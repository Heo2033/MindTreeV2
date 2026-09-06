import type { MasteryLevel } from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import { buildMasteryPrompt, parseMasteryResult, type MasteryResult } from "../prompts/mastery.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { getDb } from "../db/connection.js";

export interface MasteryItem {
  nodeId: string;
  label: string;
  type: "recall" | "explanation" | "application" | "transfer";
  userAnswer: string;
  correct?: boolean;
  rubric?: string;
}

export interface MasteryEvaluation {
  topicId: string;
  newLevel: MasteryLevelMeta;
  reachedTarget: boolean;
  perConcept: Record<string, { score: number; misconceptionType: string | null }>;
  gaps: string[];
}

export interface MasteryLevelMeta {
  label: string;
  score: number;
}

export class MasteryEngine {
  constructor(private learnerModel: LearnerModelService = new LearnerModelService()) {}

  /**
   * Оценивает достигнутый уровень по ответам на финальную проверку,
   * обновляет learner model и возвращает вердикт.
   */
  async evaluate(
    topicId: string,
    items: MasteryItem[],
    targetLevel: string,
  ): Promise<MasteryEvaluation> {
    const topic = this.getTopic(topicId);

    let mastery: MasteryResult | null = null;
    try {
      const prompt = buildMasteryPrompt({
        topic: topic?.name ?? "",
        targetLevel,
        items: items.map((i) => ({
          nodeId: i.nodeId,
          label: i.label,
          type: i.type,
          userAnswer: i.userAnswer,
          correct: i.correct,
          rubric: i.rubric,
        })),
      });
      const res = await getScheduler().execute(
        "mastery",
        () => prompt,
        (raw) => parseMasteryResult(parseLLMJson(raw)),
      );
      mastery = res.result;
    } catch {
      // fallback: heuristic scoring from correctness
      mastery = this.heuristic(items);
    }

    // Persist per-concept dimensions
    const perConcept: MasteryEvaluation["perConcept"] = {};
    for (const c of mastery.concepts) {
      this.learnerModel.updateMasteryDimensions(topicId, c.nodeId, {
        understanding: c.understanding,
        recall: c.recall,
        application: c.application,
        transfer: c.transfer,
      });
      if (c.misconception) {
        this.learnerModel.addMisconception(
          topicId,
          c.nodeId,
          c.misconception.type as never,
          c.misconception.description,
        );
      }
      perConcept[c.nodeId] = {
        score: c.confidence || average([c.understanding]),
        misconceptionType: c.misconception?.type ?? null,
      };
    }

    const overallScore = average(
      Object.values(perConcept).map((p) => p.score),
    );
    const newLevel = levelFromScore(overallScore);
    this.learnerModel.setOverallLevel(topicId, newLevel.label as MasteryLevel);

    const targetIndex = MASTERY_ORDER.indexOf(targetLevel);
    const reachedTarget = targetIndex >= 0 && newLevel.score >= targetIndex / (MASTERY_ORDER.length - 1) - 0.15;

    return {
      topicId,
      newLevel,
      reachedTarget: mastery.enough ?? reachedTarget,
      perConcept,
      gaps: mastery.gaps,
    };
  }

  private heuristic(items: MasteryItem[]): MasteryResult {
    const byNode = new Map<string, MasteryItem[]>();
    for (const item of items) {
      const arr = byNode.get(item.nodeId) ?? [];
      arr.push(item);
      byNode.set(item.nodeId, arr);
    }

    const concepts = [...byNode.entries()].map(([nodeId, list]) => {
      const correctCount = list.filter((i) => i.correct).length;
      const ratio = list.length > 0 ? correctCount / list.length : 0;
      return {
        nodeId,
        understanding: ratio,
        recall: ratio,
        application: ratio,
        transfer: ratio * 0.7,
        confidence: ratio,
        misconception: null,
      };
    });

    const avg = average(concepts.map((c) => c.understanding));
    return {
      concepts,
      enough: avg >= 0.6,
      overall_level: levelFromScore(avg).label,
      gaps: avg < 0.6 ? ["Требуется дополнительное закрепление ключевых понятий"] : [],
    };
  }

  private getTopic(topicId: string): { name: string; target_level: string } | undefined {
    const row = getDb()
      .prepare(`SELECT name, target_level FROM topics WHERE id = ?`)
      .get(topicId) as Record<string, unknown> | undefined;
    return row
      ? { name: String(row.name), target_level: String(row.target_level) }
      : undefined;
  }
}

const MASTERY_ORDER = [
  "awareness",
  "basic_understanding",
  "solid_understanding",
  "practical_application",
  "advanced",
  "expert",
];

export function levelFromScore(score: number): MasteryLevelMeta {
  const n = MASTERY_ORDER.length;
  let idx = 0;
  for (let i = 0; i < n; i++) {
    if (score >= i / (n - 1) - 0.08) idx = i;
  }
  return { label: MASTERY_ORDER[idx], score };
}

function average(arr: number[]): number {
  if (arr.length === 0) return 0;
  return arr.reduce((s, n) => s + n, 0) / arr.length;
}
