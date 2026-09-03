export interface Curriculum {
  sessionId: string;
  items: CurriculumItem[];
  totalEstimatedMinutes: number;
}

export interface CurriculumItem {
  id: string;
  nodeId: string;
  order: number;
  type: "explain" | "example" | "recall" | "apply" | "assessment" | "synthesis";
  estimatedMinutes: number;
  priority: number;
  status: "pending" | "active" | "completed" | "skipped";
  content?: string;
  reason?: string;
}
