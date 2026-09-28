import type { MasteryLevel } from "./mastery.js";
import type { Curriculum } from "./curriculum.js";

export interface LearningJourney {
  id: string;
  topicId: string;
  milestones: LearningMilestone[];
  currentMilestoneId: string | null;
  createdAt: string;
}

export interface LearningMilestone {
  id: string;
  level: MasteryLevel;
  title: string;
  description: string;
  capabilities: string[];
  estimatedHours: number;
  status: "not_started" | "active" | "completed";
  alternativePaths: LearningPath[];
}

export interface LearningPath {
  id: string;
  title: string;
  estimatedHours: number;
  description: string;
}

export interface LearningSession {
  id: string;
  journeyId: string;
  milestoneId: string | null;
  topicId: string;
  goal: string;
  timeBudgetMinutes: number;
  startedAt: string;
  completedAt: string | null;
  status: "active" | "completed" | "abandoned";
  curriculum: Curriculum;
  currentIndex: number;
}

/**
 * Тип события обучения.
 *
 * Делится на две группы:
 * - фазы обучения: `explain`, `recall`, `apply`, `assessment`, `synthesis`,
 *   `tutor_chat` — что именно осваивает пользователь;
 * - события жизненного цикла: `session_started`, `item_completed`,
 *   `activity_started`, `activity_answer`, `activity_step_done` — что произошло
 *   в сессии или активности.
 *
 * Зеркало `mindtree_flutter/lib/domain/models/learning.dart` (`LearningEventType`).
 * Раньше здесь были только фазы, из-за чего Flutter сводил к `explain` все
 * события жизненного цикла при записи в `learning_events`.
 */
export type LearningEventType =
  | "explain"
  | "recall"
  | "apply"
  | "assessment"
  | "synthesis"
  | "tutor_chat"
  | "session_started"
  | "item_completed"
  | "activity_started"
  | "activity_answer"
  | "activity_step_done";

export interface LearningEvent {
  id: string;
  sessionId: string;
  timestamp: string;
  type: LearningEventType;
  nodeId: string | null;
  data: Record<string, unknown>;
  durationMs: number;
}
