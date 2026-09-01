export type LearningGoal = "overview" | "exam" | "deep";

export type KnowledgeLevel = "beginner" | "intermediate" | "expert";

export type ConceptType =
  | "topic"
  | "concept"
  | "component"
  | "mechanism"
  | "process"
  | "property"
  | "rule"
  | "method"
  | "example";

export type RelationType =
  | "related"
  | "depends_on"
  | "requires"
  | "example_of"
  | "similar_to"
  | "contrasts_with"
  | "causes"
  | "enables"
  | "used_for"
  | "alternative_to";

export interface Relation {
  from: string;
  to: string;
  type: RelationType;
  label?: string;
}

export interface SequenceStep {
  conceptId: string;
  order: number;
  label?: string;
  description?: string;
}

export interface Sequence {
  id: string;
  label: string;
  steps: SequenceStep[];
  description?: string;
}

export type NodeState =
  | "new"
  | "structure_generated"
  | "expanded"
  | "validating"
  | "valid"
  | "invalid"
  | "repairing"
  | "content_pending"
  | "content_generated"
  | "needs_review"
  | "failed";

export interface Topic {
  id: string;
  name: string;
  goal: LearningGoal;
  targetLevel: MasteryLevel;
  timeBudgetMinutes: number;
  createdAt: string;
}

export interface KnowledgeGraph {
  topicId: string;
  nodes: KnowledgeNode[];
}

export interface KnowledgeNode {
  id: string;
  topicId: string;
  parentId: string | null;
  level: number;
  label: string;
  oneLiner: string;
  details: string;
  analogy?: string;
  conceptType?: ConceptType;
  importance: number;
  difficulty: number;
  estimatedTimeMinutes: number;
  state: NodeState;
  contentLoaded: boolean;
  leaf: boolean;
  relations: Relation[];
  sequences: Sequence[];
}

import type { MasteryLevel } from "./mastery.js";
