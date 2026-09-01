import { z } from "zod";
import type {
  KnowledgeNode,
  RelationType,
  ConceptType,
  NodeState,
} from "./topic.js";
import type { LearningSession } from "./learning.js";
import type { Curriculum, CurriculumItem } from "./curriculum.js";

export const relationSchema = z.object({
  from: z.string(),
  to: z.string(),
  type: z.string(),
  label: z.string().optional(),
});

export const sequenceStepSchema = z.object({
  conceptId: z.string(),
  order: z.number(),
  label: z.string().optional(),
  description: z.string().optional(),
});

export const sequenceSchema = z.object({
  id: z.string(),
  label: z.string(),
  steps: z.array(sequenceStepSchema),
  description: z.string().optional(),
});

export const knowledgeNodeSchema: z.ZodType<KnowledgeNode> = z.object({
  id: z.string(),
  topicId: z.string(),
  parentId: z.string().nullable(),
  level: z.number(),
  label: z.string(),
  oneLiner: z.string(),
  details: z.string(),
  analogy: z.string().optional(),
  conceptType: z.string().optional() as z.ZodType<ConceptType | undefined>,
  importance: z.number(),
  difficulty: z.number(),
  estimatedTimeMinutes: z.number(),
  state: z.string() as z.ZodType<NodeState>,
  contentLoaded: z.boolean(),
  leaf: z.boolean(),
  relations: z.array(relationSchema) as z.ZodType<KnowledgeNode["relations"]>,
  sequences: z.array(sequenceSchema),
});

export const topicSchema = z.object({
  id: z.string(),
  name: z.string(),
  goal: z.string(),
  targetLevel: z.string(),
  timeBudgetMinutes: z.number(),
  createdAt: z.string(),
});

export const curriculumItemSchema: z.ZodType<CurriculumItem> = z.object({
  id: z.string(),
  nodeId: z.string(),
  order: z.number(),
  type: z.string(),
  estimatedMinutes: z.number(),
  priority: z.number(),
  status: z.string(),
  content: z.string().optional(),
}) as z.ZodType<CurriculumItem>;

export const curriculumSchema: z.ZodType<Curriculum> = z.object({
  sessionId: z.string(),
  items: z.array(curriculumItemSchema),
  totalEstimatedMinutes: z.number(),
});

export const learningSessionSchema: z.ZodType<LearningSession> = z.object({
  id: z.string(),
  journeyId: z.string(),
  milestoneId: z.string().nullable(),
  topicId: z.string(),
  goal: z.string(),
  timeBudgetMinutes: z.number(),
  startedAt: z.string(),
  completedAt: z.string().nullable(),
  status: z.string() as z.ZodType<LearningSession["status"]>,
  curriculum: curriculumSchema,
  currentIndex: z.number(),
});
