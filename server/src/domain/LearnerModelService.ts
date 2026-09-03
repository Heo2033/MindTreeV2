import type { ConceptMastery, LearnerModel, Misconception, MisconceptionType, MasteryLevel } from "@mindtree/types";
import { getDb } from "../db/connection.js";

export interface ConceptProfile extends ConceptMastery {
  nodeId: string;
  masteryScore: number;
  lastReviewedAt: string | null;
  reviewCount: number;
  srsInterval: number;
  srsEase: number;
  srsDueAt: string | null;
}

export type SkillDimension = "understanding" | "recall" | "application" | "transfer";

export class LearnerModelService {
  private db = getDb();

  private getRow(topicId: string): Record<string, unknown> | undefined {
    return this.db
      .prepare(
        `SELECT * FROM learner_models
         WHERE user_id = 'default' AND topic_id = ? LIMIT 1`,
      )
      .get(topicId) as Record<string, unknown> | undefined;
  }

  private ensureRow(topicId: string): void {
    const exists = this.db
      .prepare(
        `SELECT id FROM learner_models
         WHERE user_id = 'default' AND topic_id = ? LIMIT 1`,
      )
      .get(topicId);
    if (!exists) {
      this.db
        .prepare(
          `INSERT INTO learner_models (user_id, topic_id, concept_masteries_json, initial_overall_level, updated_at)
           VALUES ('default', ?, '[]', 'awareness', ?)`,
        )
        .run(topicId, new Date().toISOString());
    }
  }

  getInitialLevel(topicId: string): MasteryLevel {
    const row = this.getRow(topicId);
    if (!row?.initial_overall_level) return "awareness";
    return String(row.initial_overall_level) as MasteryLevel;
  }

  private conceptMasteries(topicId: string): ConceptMastery[] {
    const row = this.getRow(topicId);
    if (!row || !row.concept_masteries_json) return [];
    try {
      return JSON.parse(String(row.concept_masteries_json)) as ConceptMastery[];
    } catch {
      return [];
    }
  }

  private save(topicId: string, masteries: ConceptMastery[]) {
    this.ensureRow(topicId);
    this.db
      .prepare(
        `UPDATE learner_models SET concept_masteries_json = ?, updated_at = ?
         WHERE user_id = 'default' AND topic_id = ?`,
      )
      .run(JSON.stringify(masteries), new Date().toISOString(), topicId);
  }

  getCurrentLevel(topicId: string): MasteryLevel {
    const row = this.getRow(topicId);
    if (!row?.overall_level) return "awareness";
    return String(row.overall_level) as MasteryLevel;
  }

  getModel(topicId: string): LearnerModel {
    const row = this.getRow(topicId) ?? {};
    return {
      id: String(row.id ?? ""),
      userId: String(row.user_id ?? "default"),
      topicId,
      overallLevel: this.getCurrentLevel(topicId),
      conceptMasteries: this.conceptMasteries(topicId),
      updatedAt: String(row.updated_at ?? ""),
    };
  }

  getConceptProfiles(topicId: string): ConceptProfile[] {
    return this.conceptMasteries(topicId).map((c) => conceptProfileFromMastery(c));
  }

  setOverallLevel(topicId: string, level: MasteryLevel) {
    this.ensureRow(topicId);
    this.db
      .prepare(
        `UPDATE learner_models SET overall_level = ?, updated_at = ?
         WHERE user_id = 'default' AND topic_id = ?`,
      )
      .run(level, new Date().toISOString(), topicId);
  }

  getConceptProfile(nodeId: string, topicId: string): ConceptProfile | null {
    const cm = this.conceptMasteries(topicId).find((c) => c.nodeId === nodeId);
    if (!cm) return null;
    return conceptProfileFromMastery(cm);
  }

  updateMasteryDimensions(
    topicId: string,
    nodeId: string,
    dims: Partial<Record<SkillDimension, number>>,
  ) {
    const masteries = this.conceptMasteries(topicId);
    let cm = masteries.find((c) => c.nodeId === nodeId);
    if (!cm) {
      cm = {
        nodeId,
        understanding: 0,
        recall: 0,
        application: 0,
        transfer: 0,
        confidence: 0,
        errors: [],
        lastAssessedAt: new Date().toISOString(),
      };
      masteries.push(cm);
    }
    for (const dim of Object.keys(dims) as SkillDimension[]) {
      const v = dims[dim];
      if (v !== undefined) cm[dim] = clamp01(v);
    }
    cm.lastAssessedAt = new Date().toISOString();
    const profile = conceptProfileFromMastery(cm);
    cm.confidence = profile.masteryScore;
    this.save(topicId, masteries);
  }

  addMisconception(topicId: string, nodeId: string, type: MisconceptionType, description: string) {
    const masteries = this.conceptMasteries(topicId);
    let cm = masteries.find((c) => c.nodeId === nodeId);
    if (!cm) {
      cm = {
        nodeId,
        understanding: 0,
        recall: 0,
        application: 0,
        transfer: 0,
        confidence: 0,
        errors: [],
        lastAssessedAt: new Date().toISOString(),
      };
      masteries.push(cm);
    }
    cm.errors.push({
      nodeId,
      type,
      description,
      detectedAt: new Date().toISOString(),
      resolved: false,
    });
    this.save(topicId, masteries);
  }

  updateMisconception(
    topicId: string,
    nodeId: string,
    type: MisconceptionType | null,
    description: string | null,
  ) {
    const masteries = this.conceptMasteries(topicId);
    const cm = masteries.find((c) => c.nodeId === nodeId);
    if (!cm) return;
    if (type === null) {
      cm.errors = [];
    } else {
      cm.errors.push({
        nodeId,
        type,
        description: description ?? "",
        detectedAt: new Date().toISOString(),
        resolved: false,
      });
    }
    this.save(topicId, masteries);
  }

  updateSrs(
    topicId: string,
    nodeId: string,
    srs: { interval: number; ease: number; dueAt: string },
  ) {
    // SRS dimensions are stored flattened into the concept mastery record.
    const masteries = this.conceptMasteries(topicId);
    let cm = masteries.find((c) => c.nodeId === nodeId);
    if (!cm) {
      cm = {
        nodeId,
        understanding: 0,
        recall: 0,
        application: 0,
        transfer: 0,
        confidence: 0,
        errors: [],
        lastAssessedAt: new Date().toISOString(),
      };
      masteries.push(cm);
    }
    const target = cm as unknown as Record<string, unknown>;
    target["reviewCount"] = (Number(target["reviewCount"]) || 0) + 1;
    target["lastReviewedAt"] = new Date().toISOString();
    target["srsInterval"] = srs.interval;
    target["srsEase"] = srs.ease;
    target["srsDueAt"] = srs.dueAt;
    this.save(topicId, masteries);
  }

  getWeakConcepts(topicId: string, limit = 10): string[] {
    return this.conceptMasteries(topicId)
      .map((c) => conceptProfileFromMastery(c))
      .filter((p) => p.masteryScore < 0.6)
      .sort((a, b) => a.masteryScore - b.masteryScore)
      .slice(0, limit)
      .map((p) => p.nodeId);
  }

  getDueConcepts(topicId: string, limit = 10): string[] {
    const now = Date.now();
    return this.conceptMasteries(topicId)
      .map((c) => conceptProfileFromMastery(c))
      .filter((p) => !p.srsDueAt || new Date(p.srsDueAt).getTime() <= now)
      .sort((a, b) =>
        (a.srsDueAt ?? "0").localeCompare(b.srsDueAt ?? "0"),
      )
      .slice(0, limit)
      .map((p) => p.nodeId);
  }
}

function conceptProfileFromMastery(cm: ConceptMastery): ConceptProfile {
  const target = cm as unknown as Record<string, unknown>;
  const reviewCount = Number(target["reviewCount"]) || 0;
  const srsInterval = Number(target["srsInterval"]) || 0;
  const srsEase = Number(target["srsEase"]) || 2.5;
  const srsDueAt = target["srsDueAt"] ? String(target["srsDueAt"]) : null;
  const lastReviewedAt =
    target["lastReviewedAt"] !== undefined && target["lastReviewedAt"] !== null
      ? String(target["lastReviewedAt"])
      : null;

  const masteryScore = average([
    cm.understanding,
    cm.recall,
    cm.application,
    cm.transfer,
  ]);

  return {
    nodeId: cm.nodeId,
    understanding: cm.understanding,
    recall: cm.recall,
    application: cm.application,
    transfer: cm.transfer,
    confidence: cm.confidence,
    errors: cm.errors,
    lastAssessedAt: cm.lastAssessedAt,
    masteryScore,
    lastReviewedAt,
    reviewCount,
    srsInterval,
    srsEase,
    srsDueAt,
  };
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function average(arr: number[]): number {
  if (arr.length === 0) return 0;
  return arr.reduce((s, n) => s + n, 0) / arr.length;
}
