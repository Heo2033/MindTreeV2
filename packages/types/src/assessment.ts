export type AssessmentType = "diagnostic" | "quiz" | "final" | "milestone";

export type QuestionType =
  | "recognition"
  | "recall"
  | "explanation"
  | "application"
  | "diagnosis"
  | "transfer";

export interface Assessment {
  id: string;
  sessionId: string | null;
  type: AssessmentType;
  questions: AssessmentQuestion[];
  startedAt: string;
  completedAt: string | null;
  score: number | null;
}

export interface AssessmentQuestion {
  id: string;
  type: QuestionType;
  nodeId: string;
  question: string;
  options?: string[];
  correctAnswer?: string;
  explanation?: string;
}

export interface Attempt {
  id: string;
  assessmentId: string;
  questionId: string;
  answer: string;
  correct: boolean;
  timeSpentMs: number;
  feedback?: string;
}
