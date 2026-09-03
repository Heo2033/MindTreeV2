import type { Curriculum, CurriculumItem, KnowledgeNode } from "@mindtree/types";
import { LearnerModelService } from "./LearnerModelService.js";
import { ReviewScheduler } from "./ReviewScheduler.js";
import { LearningSessionEngine } from "./LearningSessionEngine.js";
import { getDb } from "../db/connection.js";

export interface AdaptiveDecision {
  recommendedAction:
    | "study_next"
    | "review"
    | "final_assessment"
    | "deeper_milestone"
    | "complete";
  currentItem?: CurriculumItem;
  dueReviews: string[];
  nextMilestone?: string;
  reasons: string[];
  eta?: SessionEta;
}

export interface SessionEta {
  totalEstimatedMinutes: number;
  elapsedMinutes: number;
  completedItems: number;
  totalItems: number;
  remainingMinutesMin: number;
  remainingMinutesMax: number;
  pace: "faster" | "on_track" | "slower";
}

/**
 * Адаптивный движок: решает следующий шаг пользователя на основе
 * перепутанных/слабых понятий, расписания повторений и прогресса сессии.
 */
export class AdaptiveLearningEngine {
  constructor(
    private learnerModel = new LearnerModelService(),
    private reviewScheduler = new ReviewScheduler(),
    private sessionEngine = new LearningSessionEngine(),
  ) {}

  async nextStep(sessionId: string): Promise<AdaptiveDecision> {
    const session = this.sessionEngine.getSession(sessionId);
    if (!session) throw new Error("Сессия не найдена");

    const reasons: string[] = [];
    // 1. Due reviews take priority (spaced repetition)
    const dueReviews = this.reviewScheduler.upcomingReviews(session.topicId, 5);
    if (dueReviews.length > 0) {
      reasons.push(`${dueReviews.length} понятий пора повторить по расписанию`);
    }

    // 2. Weak concepts get priority for re-study
    const weak = this.learnerModel.getWeakConcepts(session.topicId, 3);
    if (weak.length > 0) {
      reasons.push("Есть слабые понятия, требующие закрепления");
    }

    // 3. Progress of session
    const remaining = session.curriculum.items.filter((i) => i.status !== "completed");
    const completed = session.curriculum.items.length - remaining.length;
    const total = session.curriculum.items.length || 1;
    const progress = completed / total;

    if (progress >= 0.85) {
      return {
        recommendedAction: "final_assessment",
        dueReviews: dueReviews.map((d) => d.nodeId),
        reasons: [...reasons, "Сессия почти завершена — пора проверить освоение"],
        eta: this.computeEta(session.id, completed, session.curriculum.items.length, session.curriculum.totalEstimatedMinutes),
      };
    }

    const currentItem = session.curriculum.items[session.currentIndex];
    if (currentItem && currentItem.status === "pending") {
      return {
        recommendedAction: "study_next",
        currentItem,
        dueReviews: dueReviews.map((d) => d.nodeId),
        reasons: [...reasons, "Продолжаем по расписанию сессии"],
        eta: this.computeEta(session.id, completed, session.curriculum.items.length, session.curriculum.totalEstimatedMinutes),
      };
    }

    // If all items done but not finalized
    return {
      recommendedAction: "final_assessment",
      dueReviews: dueReviews.map((d) => d.nodeId),
      reasons: [...reasons, "Все запланированные понятия изучены"],
      eta: this.computeEta(session.id, completed, session.curriculum.items.length, session.curriculum.totalEstimatedMinutes),
    };
  }

  /**
   * §39–40. Динамическая оценка времени (Learning ETA).
   * Считает реальный темп из learning_events и обновляет оценку оставшегося
   * времени, избегая ложной точности (отдаём диапазон).
   */
  private computeEta(
    sessionId: string,
    completedItems: number,
    totalItems: number,
    baseTotalMinutes: number,
  ): SessionEta {
    const elapsedRow = getDb()
      .prepare(
        `SELECT COALESCE(SUM(duration_ms), 0) AS ms
         FROM learning_events WHERE session_id = ? AND duration_ms > 0`,
      )
      .get(sessionId) as { ms: number } | undefined;
    const elapsedMinutes = Math.max(0, Math.round((elapsedRow?.ms ?? 0) / 60000));
    return computeEtaFrom(elapsedMinutes, completedItems, totalItems, baseTotalMinutes);
  }
}

/**
 * §39–40. Чистая функция динамической оценки времени (Learning ETA).
 * Считает реальный темп и выдаёт диапазон оставшегося времени,
 * избегая ложной точности.
 */
export function computeEtaFrom(
  elapsedMinutes: number,
  completedItems: number,
  totalItems: number,
  baseTotalMinutes: number,
): SessionEta {
  const totalItemsSafe = Math.max(1, totalItems);

  // Базовый ориентир: на весь план заложено totalEstimatedMinutes.
  // Темп = сколько минут уже потрачено на одну завершённую веху.
  const completedSafe = Math.max(1, completedItems);
  const minutesPerItem = elapsedMinutes / completedSafe;
  const remainingItems = Math.max(0, totalItems - completedItems);
  const projectedRemaining = minutesPerItem * remainingItems;

  // Сравнение с плановым темпом.
  const plannedMinutesPerItem = baseTotalMinutes / totalItemsSafe;
  const ratio = plannedMinutesPerItem > 0 ? minutesPerItem / plannedMinutesPerItem : 1;
  const pace: SessionEta["pace"] =
    ratio < 0.85 ? "faster" : ratio > 1.2 ? "slower" : "on_track";

  // Диапазон ±40% вокруг прогноза, минимум 5 минут.
  const mid = Math.max(5, Math.round(projectedRemaining));
  return {
    totalEstimatedMinutes: baseTotalMinutes,
    elapsedMinutes,
    completedItems,
    totalItems: totalItemsSafe,
    remainingMinutesMin: Math.max(0, Math.round(mid * 0.6)),
    remainingMinutesMax: Math.round(mid * 1.4),
    pace,
  };
}