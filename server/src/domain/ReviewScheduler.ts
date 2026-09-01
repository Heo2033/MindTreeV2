import { scheduleReview, isDue } from "../lib/srs.js";
import { LearnerModelService, type ConceptProfile } from "./LearnerModelService.js";
import { getDb } from "../db/connection.js";

export class ReviewScheduler {
  constructor(private learnerModel = new LearnerModelService()) {}

  onAnswered(topicId: string, nodeId: string, quality: "correct" | "incorrect" | "again") {
    const profile = this.learnerModel.getConceptProfile(nodeId, topicId);
    const prev =
      profile
        ? {
            interval: profile.srsInterval,
            ease: profile.srsEase,
            reps: profile.reviewCount,
            dueAt: profile.srsDueAt ?? new Date().toISOString(),
          }
        : null;

    const next = scheduleReview(prev, quality);
    this.learnerModel.updateSrs(topicId, nodeId, next);

    // quality also nudges mastery dimensions
    if (quality === "correct") {
      const p = this.learnerModel.getConceptProfile(nodeId, topicId);
      if (p) {
        this.learnerModel.updateMasteryDimensions(topicId, nodeId, {
          recall: Math.min(1, p.recall + 0.15),
          understanding: Math.min(1, p.understanding + 0.1),
        });
      }
    } else {
      this.learnerModel.addMisconception(
        topicId,
        nodeId,
        "careless",
        "Ответ был неверным при повторении",
      );
    }
  }

  isDueNode(nodeId: string, topicId: string): boolean {
    const p = this.learnerModel.getConceptProfile(nodeId, topicId);
    if (!p) return true;
    return isDue({
      interval: p.srsInterval,
      ease: p.srsEase,
      reps: p.reviewCount,
      dueAt: p.srsDueAt ?? new Date().toISOString(),
    });
  }

  /** Понятия, которые пора повторить (due) по SRS. */
  upcomingReviews(topicId: string, limit = 10): Array<{ nodeId: string; dueAt: string | null }> {
    const nodes = getDb()
      .prepare(`SELECT id FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<{ id: string }>;
    const due: Array<{ nodeId: string; dueAt: string | null }> = [];
    for (const n of nodes) {
      if (this.isDueNode(n.id, topicId)) {
        const p = this.learnerModel.getConceptProfile(n.id, topicId);
        due.push({ nodeId: n.id, dueAt: p?.srsDueAt ?? null });
      }
    }
    return due
      .sort((a, b) => (a.dueAt ?? "0").localeCompare(b.dueAt ?? "0"))
      .slice(0, limit);
  }
}
