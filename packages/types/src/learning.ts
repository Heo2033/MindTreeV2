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

export interface LearningEvent {
  id: string;
  sessionId: string;
  timestamp: string;
  type: "explain" | "recall" | "apply" | "assessment" | "synthesis" | "tutor_chat";
  nodeId: string | null;
  data: Record<string, unknown>;
  durationMs: number;
}
