import { LearningSessionEngine } from "../domain/LearningSessionEngine.js";
import { CurriculumEngine } from "../domain/CurriculumEngine.js";
import { LearnerModelService } from "../domain/LearnerModelService.js";
import { getDb } from "../db/connection.js";
import { readingOrder } from "../lib/treeUtils/reading.js";
import type { KnowledgeNode } from "@mindtree/types";

export interface PlanItem {
  itemId: string;
  nodeId: string;
  label: string;
  order: number;
  type: string;
  estimatedMinutes: number;
  priority: number;
  status: string;
  reason?: string;
}

export interface SessionPlan {
  sessionId: string;
  topicName: string;
  items: PlanItem[];
  totalEstimatedMinutes: number;
  skipped: Array<{ node_id: string; reason: string }>;
}

/**
 * Результат смены цели (§44): обновлённая тема + план, построенный только
 * вокруг недостающего знания (уже освоенные узлы пропущены).
 */
export interface ChangeGoalResult {
  goal: string;
  topicName: string;
  plan: SessionPlan;
  alreadyKnown: string[];
}

/**
 * Application-layer: формирует план сессии для UI перед её началом
 * (см. спецификацию §18, §66). Содержимое skipped наполняется
 * CurriculumEngine из LLM-результата.
 */
export class PlannerCoordinator {
  private engine = new LearningSessionEngine();

  getSessionPlan(sessionId: string): SessionPlan {
    const session = this.engine.getSession(sessionId);
    if (!session) {
      return { sessionId, topicName: "", items: [], totalEstimatedMinutes: 0, skipped: [] };
    }

    const labels = this.nodeLabels(session.topicId);
    const items: PlanItem[] = session.curriculum.items.map((it) => ({
      itemId: it.id,
      nodeId: it.nodeId,
      label: labels.get(it.nodeId) ?? "",
      order: it.order,
      type: it.type,
      estimatedMinutes: it.estimatedMinutes,
      priority: it.priority,
      status: it.status,
      reason: it.reason,
    }));

    return {
      sessionId,
      topicName: this.topicName(session.topicId),
      items,
      totalEstimatedMinutes: session.curriculum.totalEstimatedMinutes,
      skipped: [],
    };
  }

  /**
   * §44: смена цели темы. Обновляет goal на тему, затем перестраивает план,
   * не начиная с нуля: уже освоенные узлы (из learner model) помечаются как
   * known и исключаются, а новый curriculum строится вокруг недостающего знания.
   */
  async changeTopicGoal(topicId: string, newGoal: string): Promise<ChangeGoalResult> {
    const topic = getDb().prepare("SELECT * FROM topics WHERE id = ?").get(topicId) as
      | { id: string; name: string; goal: string; time_budget_minutes: number; target_level: string }
      | undefined;
    if (!topic) throw new Error("Тема не найдена");

    getDb()
      .prepare("UPDATE topics SET goal = ? WHERE id = ?")
      .run(newGoal, topicId);

    const nodeRows = getDb()
      .prepare("SELECT * FROM knowledge_nodes WHERE topic_id = ?")
      .all(topicId) as Record<string, unknown>[];
    const nodes: KnowledgeNode[] = nodeRows.map(rowToNode);
    const ordered = readingOrder(nodes);

    const engine = new CurriculumEngine();
    const learnerModel = new LearnerModelService();
    const result = await engine.planForGoal(
      {
        topicId,
        topicName: topic.name,
        goal: newGoal,
        targetLevel: topic.target_level || "basic_understanding",
        currentLevel: learnerModel.getCurrentLevel(topicId),
        timeBudgetMinutes: topic.time_budget_minutes || 60,
        nodes: ordered,
      },
      learnerModel,
    );

    const labels = new Map(nodes.map((n) => [n.id, n.label]));
    const items: PlanItem[] = result.curriculum.items.map((it) => ({
      itemId: it.id,
      nodeId: it.nodeId,
      label: labels.get(it.nodeId) ?? "",
      order: it.order,
      type: it.type,
      estimatedMinutes: it.estimatedMinutes,
      priority: it.priority,
      status: it.status,
      reason: it.reason,
    }));

    const plan: SessionPlan = {
      sessionId: result.curriculum.sessionId,
      topicName: topic.name,
      items,
      totalEstimatedMinutes: result.curriculum.totalEstimatedMinutes,
      skipped: result.alreadyKnown.map((nodeId) => ({
        node_id: nodeId,
        reason: "Уже освоено — пропущено при смене цели",
      })),
    };

    return {
      goal: newGoal,
      topicName: topic.name,
      plan,
      alreadyKnown: result.alreadyKnown,
    };
  }

  private nodeLabels(topicId: string): Map<string, string> {
    const rows = getDb()
      .prepare(`SELECT id, label FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<{ id: string; label: string }>;
    return new Map(rows.map((r) => [r.id, r.label]));
  }

  private topicName(topicId: string): string {
    const row = getDb()
      .prepare(`SELECT name FROM topics WHERE id = ?`)
      .get(topicId) as { name?: string } | undefined;
    return row?.name ?? "";
  }
}

function rowToNode(row: Record<string, unknown>): KnowledgeNode {
  let relations: KnowledgeNode["relations"] = [];
  let sequences: KnowledgeNode["sequences"] = [];
  try {
    relations = JSON.parse(String(row.relations_json ?? "[]"));
  } catch {
    relations = [];
  }
  try {
    sequences = JSON.parse(String(row.sequences_json ?? "[]"));
  } catch {
    sequences = [];
  }
  let sources: string[] = [];
  try {
    sources = JSON.parse(String(row.sources_json ?? "[]"));
  } catch {
    sources = [];
  }
  return {
    id: String(row.id),
    topicId: String(row.topic_id),
    parentId: row.parent_id ? String(row.parent_id) : null,
    level: Number(row.level),
    label: String(row.label),
    oneLiner: String(row.one_liner ?? ""),
    details: String(row.details ?? ""),
    analogy: row.analogy ? String(row.analogy) : undefined,
    sources,
    conceptType: row.concept_type
      ? (String(row.concept_type) as KnowledgeNode["conceptType"])
      : undefined,
    importance: Number(row.importance ?? 0.5),
    difficulty: Number(row.difficulty ?? 0.5),
    estimatedTimeMinutes: Number(row.estimated_time_minutes ?? 5),
    state: String(row.state ?? "new") as KnowledgeNode["state"],
    contentLoaded: Number(row.content_loaded) === 1,
    leaf: Number(row.leaf) === 1,
    relations,
    sequences,
  };
}