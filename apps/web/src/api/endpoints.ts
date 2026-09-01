import { request, postSSE, type SSEStream } from "./client";
import type {
  TopicRow,
  KnowledgeNodeRow,
  SessionDetailDto,
  LearningEventRow,
  QuizDto,
  ConfigEffectiveDto,
  ExplainTermDto,
  CurriculumDto,
  CurriculumItemDto,
} from "./types";

// ---------- Topics ----------

export const topicsApi = {
  list: () => request<TopicRow[]>("/api/topics"),
  get: (id: string) =>
    request<{ topic: TopicRow; nodes: KnowledgeNodeRow[] }>(`/api/topics/${id}`),
  create: (body: {
    name: string;
    goal?: string;
    target_level?: string;
    time_budget_minutes?: number;
  }) => request<TopicRow>("/api/topics", { method: "POST", json: body }),
  remove: (id: string) => request<{ ok: boolean }>(`/api/topics/${id}`, { method: "DELETE" }),
};

// ---------- Pipeline (SSE tree generation) ----------

export interface TreeGenProgress {
  phase: "structure" | "expand" | "validate" | "repair" | "content" | "done" | "error";
  level?: string;
  message: string;
  stats?: { total: number; depth: number; leaves: number };
}

export interface TreeGenDone {
  nodes: Array<Record<string, unknown>>;
  warnings: string[];
  persisted: number;
}

export const pipelineApi = {
  generate(
    body: { topic_id?: string; query: string; goal?: string; level?: string },
  ): SSEStream {
    return postSSE("/api/pipeline/generate", body);
  },
};

// ---------- Tree ----------

export const treeApi = {
  expand: (topic_id: string, node_id: string) =>
    request<{ added: Array<Record<string, unknown>>; count: number }>("/api/tree/expand", {
      method: "POST",
      json: { topic_id, node_id },
    }),
  content: (topic_id: string, node_id: string, level?: string) =>
    request<{
      node_id: string;
      one_liner: string;
      details: string;
      analogy?: string;
      relations: unknown[];
    }>("/api/tree/content", { method: "POST", json: { topic_id, node_id, level } }),
  fillContent: (topic_id: string, level?: number, limit?: number) =>
    request<{ completed: number; results: Array<{ node_id: string; ok: boolean }> }>(
      "/api/tree/fill-content",
      { method: "POST", json: { topic_id, level, limit } },
    ),
  explainTerm: (topic_id: string, term: string, context?: string) =>
    request<ExplainTermDto>("/api/tree/explain-term", {
      method: "POST",
      json: { topic_id, term, context },
    }),
};

// ---------- Sessions ----------

export interface AdaptiveDecisionDto {
  recommendedAction:
    | "study_next"
    | "review"
    | "final_assessment"
    | "deeper_milestone"
    | "complete";
  currentItem?: CurriculumItemDto;
  dueReviews: string[];
  nextMilestone?: string;
  reasons: string[];
}

export interface CurrentItemDto {
  item: CurriculumItemDto;
  index: number;
  curriculum: CurriculumDto;
}

export interface StartSessionBody {
  journey_id?: string;
  milestone_id?: string;
  topic_id: string;
  goal?: string;
  time_budget_minutes?: number;
}

export interface FinalizeResultDto {
  assessmentId: string;
  mastery: MasteryEvaluationDto | null;
}

export const sessionsApi = {
  list: () => request<Array<Record<string, unknown>>>("/api/sessions"),
  get: (id: string) =>
    request<{ session: SessionDetailDto; events: LearningEventRow[] }>(`/api/sessions/${id}`),
  create: (body: StartSessionBody) =>
    request<SessionDetailDto>("/api/sessions", { method: "POST", json: body }),
  current: (id: string) =>
    request<{ current: CurrentItemDto; adaptive: AdaptiveDecisionDto }>(
      `/api/sessions/${id}/current`,
    ),
  study: (id: string, node_id: string) =>
    request<{ content?: unknown; details?: unknown; node?: unknown }>(`/api/sessions/${id}/study`, {
      method: "POST",
      json: { node_id },
    }),
  itemComplete: (id: string, body: { item_id: string; node_id?: string; quality?: string }) =>
    request<{ ok: boolean }>(`/api/sessions/${id}/item-complete`, {
      method: "POST",
      json: body,
    }),
  finalize: (id: string) =>
    request<FinalizeResultDto>(`/api/sessions/${id}/finalize`, { method: "POST" }),
  progress: (id: string, body: { type: string; node_id?: string; data?: unknown; duration_ms?: number }) =>
    request<{ ok: boolean; eventId: string }>(`/api/sessions/${id}/progress`, {
      method: "POST",
      json: body,
    }),
  complete: (id: string) =>
    request<{ ok: boolean }>(`/api/sessions/${id}/complete`, { method: "POST" }),
};

// ---------- Assessments ----------

export interface AssessmentQuestionDto {
  id: string;
  type?: string;
  nodeId: string;
  question: string;
  options: string[];
  correctAnswer: string;
  explanation: string;
}

export interface AssessmentDto {
  id: string;
  sessionId?: string;
  type: string;
  questions: AssessmentQuestionDto[];
}

export interface SubmitAttempt {
  question_id: string;
  answer: string;
  correct: boolean;
  time_spent_ms?: number;
  feedback?: string;
}

export interface NeedLevelDto {
  label: import("@mindtree/types").MasteryLevel;
  score: number;
}

export interface PerConceptDto {
  score: number;
  misconceptionType: string | null;
}

export interface MasteryEvaluationDto {
  topicId: string;
  newLevel: NeedLevelDto;
  reachedTarget: boolean;
  perConcept: Record<string, PerConceptDto>;
  gaps: string[];
}

export interface AssessmentSubmitResult {
  id: string;
  score: number;
  correct: number;
  total: number;
  mastery: MasteryEvaluationDto | null;
}

export interface AssessmentCreateBody {
  session_id?: string;
  type?: string;
  questions?: unknown[];
  question_count?: number;
}

export const assessmentsApi = {
  get: (id: string) => request<AssessmentDto>(`/api/assessments/${id}`),
  create: (body: AssessmentCreateBody) =>
    request<AssessmentDto>("/api/assessments", { method: "POST", json: body }),
  submit: (id: string, attempts: SubmitAttempt[]) =>
    request<AssessmentSubmitResult>(
      `/api/assessments/${id}/submit`,
      { method: "POST", json: { attempts } },
    ),
};

// ---------- Quiz ----------

export const quizApi = {
  generate: (body: { topic_id: string; node_ids?: string[]; count?: number }) =>
    request<QuizDto>("/api/quiz", { method: "POST", json: body }),
  apply: (id: string, topic_id: string, results: Array<{ nodeId: string; correct: boolean }>) =>
    request<{ ok: boolean; applied: number }>(`/api/quiz/${id}/apply`, {
      method: "POST",
      json: { topic_id, results },
    }),
};

// ---------- Tutor ----------

export const tutorApi = {
  chat: (body: { topic_id: string; session_id?: string; message: string; node_id?: string }) =>
    request<{ response: string; usedFallback: boolean; context: Record<string, unknown> }>(
      "/api/tutor",
      { method: "POST", json: body },
    ),
};

// ---------- Milestones ----------

export interface MilestonePathDto {
  id: string;
  title: string;
  estimatedHours: number;
  description: string;
}

export interface MilestoneDto {
  id: string;
  level: import("@mindtree/types").MasteryLevel;
  title: string;
  description: string;
  capabilities: string[];
  estimatedHours: number;
  status: "not_started" | "active" | "completed";
  alternativePaths: MilestonePathDto[];
}

export const milestonesApi = {
  generate: (journey_id: string, topic_id: string) =>
    request<{ milestones: MilestoneDto[] }>("/api/milestones/generate", {
      method: "POST",
      json: { journey_id, topic_id },
    }),
  journey: (journeyId: string) =>
    request<{ milestones: MilestoneDto[] }>(`/api/milestones/journey/${journeyId}`),
  patch: (id: string, status: string) =>
    request<{ ok: boolean }>(`/api/milestones/${id}`, { method: "PATCH", json: { status } }),
};

// ---------- Diagnostic ----------

export interface DiagnosticQuestionDto {
  id: string;
  nodeId: string;
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}

export interface DiagnosticAnswerIn {
  questionId: string;
  nodeId: string;
  selectedIndex: number;
  correctIndex: number;
}

export interface DiagnosticResultDto {
  questions: DiagnosticQuestionDto[];
  currentLevel: import("@mindtree/types").MasteryLevel;
  knownConcepts: string[];
  unknownConcepts: string[];
  score: number;
}

export const diagnosticApi = {
  generate: (topicId: string) =>
    request<{ questions: DiagnosticQuestionDto[] }>(`/api/diagnostic/${topicId}/generate`, { method: "POST" }),
  evaluate: (topicId: string, answers: DiagnosticAnswerIn[]) =>
    request<DiagnosticResultDto>(`/api/diagnostic/${topicId}/evaluate`, {
      method: "POST",
      json: { answers },
    }),
};

// ---------- Config ----------

export interface RuntimeConfigBody {
  provider?: "ollama" | "openai" | "auto";
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  modelStrong?: string;
  modelFast?: string;
  temperature?: number;
  numCtx?: number;
}

export const configApi = {
  get: () => request<{ source: string; appliedAt: string | null; effective: ConfigEffectiveDto }>("/api/config"),
  apply: (body: { flat?: RuntimeConfigBody } | RuntimeConfigBody) =>
    request<{ ok: boolean; appliedAt: string; source: string }>("/api/config", {
      method: "POST",
      json: body,
    }),
  clear: () => request<{ ok: boolean; appliedAt: null }>("/api/config", { method: "DELETE" }),
};

// ---------- Learner Model ----------

export interface ConceptProfileDto {
  nodeId: string;
  understanding: number;
  recall: number;
  application: number;
  transfer: number;
  confidence: number;
  masteryScore: number;
  reviewCount: number;
  srsDueAt: string | null;
  errors: Array<{ type: string; description: string; detectedAt: string; resolved: boolean }>;
}

export interface LearnerModelDto {
  model: import("@mindtree/types").LearnerModel;
  profiles: ConceptProfileDto[];
  weakConcepts: string[];
  dueConcepts: string[];
}

export const learnerModelApi = {
  get: (topicId: string) =>
    request<LearnerModelDto>(`/api/learner-model/${topicId}`),
};
