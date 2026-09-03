import crypto from "crypto";
import type { LearningSession } from "@mindtree/types";
import {
  LearningSessionEngine,
  type CreateSessionInput,
} from "../domain/LearningSessionEngine.js";
import {
  AdaptiveLearningEngine,
  type AdaptiveDecision,
} from "../domain/AdaptiveLearningEngine.js";
import { getDb } from "../db/connection.js";

export interface ProgressInput {
  type: string;
  nodeId?: string;
  data?: Record<string, unknown>;
  durationMs?: number;
}

export type Quality = "correct" | "incorrect" | "again";

const DEFAULT_ADAPTIVE: AdaptiveDecision = {
  recommendedAction: "study_next",
  dueReviews: [],
  reasons: [],
};

/**
 * Application-layer оркестратор жизненного цикла сессии.
 * Связывает UI-роуты с доменными движками (LearningSessionEngine,
 * AdaptiveLearningEngine) без UI-специфичной логики.
 */
export class SessionCoordinator {
  private engine = new LearningSessionEngine();
  private adaptive = new AdaptiveLearningEngine();

  create(input: CreateSessionInput): Promise<LearningSession> {
    return this.engine.create(input);
  }

  list(): Array<LearningSession> {
    const rows = getDb()
      .prepare("SELECT id FROM learning_sessions ORDER BY started_at DESC LIMIT 100")
      .all() as Array<{ id: string }>;
    return rows
      .map((r) => this.engine.getSession(r.id))
      .filter((s): s is LearningSession => Boolean(s));
  }

  getDetail(id: string) {
    const session = this.engine.getSession(id);
    if (!session) return null;
    const events = getDb()
      .prepare("SELECT * FROM learning_events WHERE session_id = ? ORDER BY timestamp")
      .all(id);
    return { session, events };
  }

  async current(id: string) {
    const current = this.engine.getCurrentItem(id);
    if (!current) return null;
    let adaptiveDecision = DEFAULT_ADAPTIVE;
    try {
      adaptiveDecision = await this.adaptive.nextStep(id);
    } catch {
      // keep default decision
    }
    return { current, adaptive: adaptiveDecision };
  }

  study(id: string, nodeId: string) {
    return this.engine.studyNode(id, nodeId);
  }

  async completeItem(
    id: string,
    itemId: string,
    nodeId?: string,
    quality: Quality = "correct",
  ) {
    this.engine.markItemCompleted(id, itemId, nodeId, quality);
    const current = this.engine.getCurrentItem(id);
    let adaptiveDecision = DEFAULT_ADAPTIVE;
    try {
      adaptiveDecision = await this.adaptive.nextStep(id);
    } catch {
      // keep default decision
    }
    return { ok: true, current, adaptive: adaptiveDecision };
  }

  /**
   * Запись learning event без изменения позиции curriculum.
   * Продвижение по curriculum происходит только через item-complete.
   */
  recordProgress(id: string, input: ProgressInput): string {
    const eventId = `evt_${crypto.randomUUID().slice(0, 8)}`;
    getDb()
      .prepare(
        `INSERT INTO learning_events (id, session_id, type, node_id, data_json, duration_ms)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        eventId,
        id,
        input.type,
        input.nodeId || null,
        JSON.stringify(input.data || {}),
        input.durationMs || 0,
      );
    return eventId;
  }

  /**
   * Идемпотентная подготовка финального assessment сессии.
   * Повторный вызов возвращает уже созданную проверку.
   * Сессия помечается завершённой после сабмита assessment (см. AssessmentCoordinator).
   */
  async prepareFinalAssessment(id: string): Promise<{ assessmentId: string; mastery: null }> {
    const session = this.engine.getSession(id);
    if (!session) throw new Error("Сессия не найдена");

    const existing = getDb()
      .prepare(
        `SELECT id FROM assessments WHERE session_id = ? AND type = 'final'
         ORDER BY started_at DESC LIMIT 1`,
      )
      .get(id) as { id: string } | undefined;
    if (existing) return { assessmentId: existing.id, mastery: null };

    const assessment = await this.engine.generateFinalAssessment(id);
    return { assessmentId: assessment.assessmentId, mastery: null };
  }

  completeSession(id: string): { ok: boolean } {
    getDb()
      .prepare(
        "UPDATE learning_sessions SET status = 'completed', completed_at = ? WHERE id = ?",
      )
      .run(new Date().toISOString(), id);
    return { ok: true };
  }
}