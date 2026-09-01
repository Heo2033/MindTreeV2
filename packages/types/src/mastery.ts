export type MasteryLevel =
  | "awareness"
  | "basic_understanding"
  | "solid_understanding"
  | "practical_application"
  | "advanced"
  | "expert";

export const MASTERY_LEVELS: MasteryLevel[] = [
  "awareness",
  "basic_understanding",
  "solid_understanding",
  "practical_application",
  "advanced",
  "expert",
];

export interface LearnerModel {
  id: string;
  userId: string;
  topicId: string;
  overallLevel: MasteryLevel;
  conceptMasteries: ConceptMastery[];
  updatedAt: string;
}

export interface ConceptMastery {
  nodeId: string;
  understanding: number;
  recall: number;
  application: number;
  transfer: number;
  confidence: number;
  errors: Misconception[];
  lastAssessedAt: string;
}

export type MisconceptionType =
  | "unknown"
  | "confused"
  | "incomplete"
  | "definition_only"
  | "mechanism_error"
  | "application_failure"
  | "careless";

export interface Misconception {
  nodeId: string;
  type: MisconceptionType;
  description: string;
  detectedAt: string;
  resolved: boolean;
}
