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
      };
    }

    const currentItem = session.curriculum.items[session.currentIndex];
    if (currentItem && currentItem.status === "pending") {
      return {
        recommendedAction: "study_next",
        currentItem,
        dueReviews: dueReviews.map((d) => d.nodeId),
        reasons: [...reasons, "Продолжаем по расписанию сессии"],
      };
    }

    // If all items done but not finalized
    return {
      recommendedAction: "final_assessment",
      dueReviews: dueReviews.map((d) => d.nodeId),
      reasons: [...reasons, "Все запланированные понятия изучены"],
    };
  }
}
