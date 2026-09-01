export interface ApiResponse<T> {
  data: T;
  error?: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface SSEProgressEvent {
  phase: "structure" | "expand" | "validate" | "repair" | "content" | "done" | "error";
  level?: string;
  message: string;
  stats?: {
    total: number;
    depth: number;
    leaves: number;
  };
}

export interface GenerateTreeRequest {
  query: string;
  goal?: string;
  level?: string;
  timeBudgetMinutes?: number;
}

export interface StartSessionRequest {
  topicId: string;
  journeyId?: string;
  milestoneId?: string;
  goal?: string;
  timeBudgetMinutes?: number;
}

export interface ProgressSessionRequest {
  type: string;
  nodeId?: string;
  data?: Record<string, unknown>;
  durationMs?: number;
}

export interface TutorChatRequest {
  topicId: string;
  sessionId?: string;
  message: string;
  context?: Record<string, unknown>;
}
