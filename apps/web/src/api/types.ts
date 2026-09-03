// DTO types matching the raw shapes returned by the backend (snake_case DB rows).

export interface TopicRow {
  id: string;
  name: string;
  goal: string;
  target_level: string;
  time_budget_minutes: number;
  created_at: string;
}

export interface KnowledgeNodeRow {
  id: string;
  topic_id: string;
  parent_id: string | null;
  label: string;
  one_liner: string;
  details: string;
  analogy: string | null;
  concept_type: string | null;
  importance: number;
  difficulty: number;
  estimated_time_minutes: number;
  state: string;
  content_loaded: number;
  leaf: number;
  level: number;
  relations_json: string;
  sources_json?: string | null;
  created_at: string;
}

export interface SessionRow {
  id: string;
  journey_id: string | null;
  milestone_id: string | null;
  topic_id: string;
  goal: string;
  time_budget_minutes: number;
  started_at: string;
  completed_at: string | null;
  status: "active" | "completed" | "abandoned";
  curriculum_json: string | null;
  current_index: number;
}

export interface LearningEventRow {
  id: string;
  session_id: string;
  timestamp: string;
  type: string;
  node_id: string | null;
  data_json: string | null;
  duration_ms: number;
}

export interface CurriculumItemDto {
  id: string;
  nodeId: string;
  label?: string;
  order: number;
  type:
    | "explain"
    | "example"
    | "recall"
    | "apply"
    | "assessment"
    | "synthesis";
  estimatedMinutes: number;
  priority: number;
  status: "pending" | "active" | "completed" | "skipped";
  content?: string;
  reason?: string;
}

export interface CurriculumDto {
  sessionId: string;
  items: CurriculumItemDto[];
  totalEstimatedMinutes: number;
}

export interface SessionDetailDto {
  id: string;
  journeyId: string | null;
  milestoneId: string | null;
  topicId: string;
  goal: string;
  timeBudgetMinutes: number;
  startedAt: string;
  completedAt: string | null;
  status: "active" | "completed" | "abandoned";
  curriculum: CurriculumDto;
  currentIndex: number;
}

export interface QuizQuestionDto {
  id: string;
  nodeId: string;
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  misconception?: boolean;
}

export interface QuizDto {
  id: string;
  topicId: string;
  title: string;
  questions: QuizQuestionDto[];
}

export interface MasteryDto {
  overallLevel: string;
  conceptMasteries: Array<Record<string, unknown>>;
}

export interface ConfigEffectiveDto {
  model?: string;
  modelStrong?: string;
  modelFast?: string;
  runtimeConfigured: boolean;
}

export interface ExplainTermDto {
  term: string;
  explanation: string;
}
