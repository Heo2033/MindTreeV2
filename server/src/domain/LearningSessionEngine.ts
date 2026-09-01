import type {
  LearningSession,
  CurriculumItem,
  Curriculum,
  KnowledgeNode,
  MasteryLevel,
} from "@mindtree/types";
import crypto from "crypto";
import { getDb } from "../db/connection.js";
import { CurriculumEngine } from "./CurriculumEngine.js";
import { AssessmentEngine } from "./AssessmentEngine.js";
import { MasteryEngine } from "./MasteryEngine.js";
import { ReviewScheduler } from "./ReviewScheduler.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { EventBus } from "./EventBus.js";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import { buildContentPrompt } from "../prompts/content.js";
import { readingOrder } from "../lib/treeUtils/reading.js";

export interface CreateSessionInput {
  journeyId?: string;
  topicId: string;
  goal: string;
  timeBudgetMinutes: number;
  milestoneId?: string | null;
}

export class LearningSessionEngine {
  constructor(
    private curriculumEngine = new CurriculumEngine(),
    private assessmentEngine = new AssessmentEngine(),
    private masteryEngine = new MasteryEngine(),
    private reviewScheduler = new ReviewScheduler(),
    private learnerModel = new LearnerModelService(),
  ) {}

  async create(input: CreateSessionInput): Promise<LearningSession> {
    let journeyId = input.journeyId;
    if (!journeyId) {
      journeyId = `journey_${crypto.randomUUID().slice(0, 8)}`;
      getDb()
        .prepare(`INSERT INTO learning_journeys (id, topic_id) VALUES (?,?)`)
        .run(journeyId, input.topicId);
    }

    const nodeRows = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(input.topicId) as Record<string, unknown>[];

    const nodes: KnowledgeNode[] = nodeRows.map(rowToNode);
    const ordered = readingOrder(nodes);
    const targetLevel = this.getTargetLevel(input.topicId);

    // Diagnostic current level comes from learner model; use it for curriculum
    const curriculum = await this.curriculumEngine.generate({
      topicId: input.topicId,
      topicName: this.getTopicName(input.topicId),
      goal: input.goal,
      targetLevel,
      currentLevel: this.learnerModel.getCurrentLevel(input.topicId),
      timeBudgetMinutes: input.timeBudgetMinutes,
      nodes: ordered,
    });
    // re-key curriculum with actual session id placeholder
    curriculum.sessionId = "";

    const sessionId = `session_${crypto.randomUUID().slice(0, 8)}`;
    curriculum.sessionId = sessionId;

    getDb()
      .prepare(
        `INSERT INTO learning_sessions
           (id, journey_id, milestone_id, topic_id, goal, time_budget_minutes, status, curriculum_json, current_index)
         VALUES (?,?,?,?,?,?,?,?,?)`,
      )
      .run(
        sessionId,
        journeyId,
        input.milestoneId ?? null,
        input.topicId,
        input.goal,
        input.timeBudgetMinutes,
        "active",
        JSON.stringify(curriculum),
        0,
      );

    EventBus.emit({
      sessionId,
      topicId: input.topicId,
      kind: "session_started",
      payload: { goal: input.goal },
    });

    return this.getSession(sessionId)!;
  }

  getSession(sessionId: string): LearningSession | undefined {
    const row = getDb()
      .prepare(`SELECT * FROM learning_sessions WHERE id = ?`)
      .get(sessionId) as Record<string, unknown> | undefined;
    if (!row) return undefined;
    let curriculum: Curriculum = { sessionId, items: [], totalEstimatedMinutes: 0 };
    try {
      curriculum = JSON.parse(String(row.curriculum_json ?? "{}")) as Curriculum;
    } catch {
      curriculum = { sessionId, items: [], totalEstimatedMinutes: 0 };
    }
    return {
      id: String(row.id),
      journeyId: String(row.journey_id),
      milestoneId: row.milestone_id ? String(row.milestone_id) : null,
      topicId: String(row.topic_id),
      goal: String(row.goal),
      timeBudgetMinutes: Number(row.time_budget_minutes),
      startedAt: String(row.started_at),
      completedAt: row.completed_at ? String(row.completed_at) : null,
      status: String(row.status) as LearningSession["status"],
      curriculum: {
        ...curriculum,
        sessionId: String(row.id),
      },
      currentIndex: Number(row.current_index),
    };
  }

  getCurrentItem(sessionId: string): { item: CurriculumItem; index: number; curriculum: Curriculum } | null {
    const session = this.getSession(sessionId);
    if (!session) return null;
    const item = session.curriculum.items[session.currentIndex];
    if (!item) return null;
    return { item, index: session.currentIndex, curriculum: session.curriculum };
  }

  /**
   * Изучение конкретного понятия: генерирует/возвращает контент узла.
   * Контент генерируется just-in-time (лениво) и кэшируется в knowledge_nodes.
   */
  async studyNode(
    sessionId: string,
    nodeId: string,
  ): Promise<{ content: { one_liner: string; details: string; analogy?: string }; node: KnowledgeNode }> {
    const session = this.getSession(sessionId);
    if (!session) throw new Error("Сессия не найдена");

    let nodeRow = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, session.topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    let node = rowToNode(nodeRow);
    const contentLoaded = Number(nodeRow.content_loaded) === 1;

    if (!contentLoaded) {
      // Lazy content generation
      const path = this.nodePath(session.topicId, nodeId);
      const siblings = this.siblings(session.topicId, node.parentId ?? "");
      const topicName = this.getTopicName(session.topicId);

      const prompt = buildContentPrompt({
        rootTopic: topicName,
        nodePath: path,
        siblings,
        level: this.learnerModel.getCurrentLevel(session.topicId),
        ontologyContext: {
          canonical_definition: node.oneLiner,
          semantic_axis: node.conceptType,
        },
        node: { id: node.id, label: node.label },
      });

      let content: { one_liner: string; details: string; analogy?: string; relations: unknown[] };
      try {
        const res = await getScheduler().execute(
          "content",
          () => prompt,
          (raw) =>
            parseLLMJson<{ one_liner?: string; details?: string; analogy?: string; relations?: unknown[] }>(raw),
        );
        content = {
          one_liner: String(res.result.one_liner ?? node.oneLiner),
          details: String(res.result.details ?? node.details),
          analogy:
            res.result.analogy && String(res.result.analogy) !== ""
              ? String(res.result.analogy)
              : undefined,
          relations: Array.isArray(res.result.relations) ? res.result.relations : [],
        };
      } catch {
        content = { one_liner: node.oneLiner, details: node.details, relations: [] };
      }

      getDb()
        .prepare(
          `UPDATE knowledge_nodes SET one_liner = ?, details = ?, analogy = ?, relations_json = ?, content_loaded = 1, state = 'content_generated' WHERE id = ?`,
        )
        .run(content.one_liner, content.details, content.analogy ?? null, JSON.stringify(content.relations), nodeId);
      node = { ...node, oneLiner: content.one_liner, details: content.details, analogy: content.analogy, relations: content.relations as KnowledgeNode["relations"] };
      nodeRow = getDb().prepare(`SELECT * FROM knowledge_nodes WHERE id = ?`).get(nodeId) as Record<string, unknown>;
    } else {
      const content = {
        one_liner: node.oneLiner,
        details: node.details,
        analogy: node.analogy,
      };
      EventBus.emit({
        sessionId,
        topicId: session.topicId,
        kind: "explain",
        nodeId,
        payload: { label: node.label },
      });
      return { content, node };
    }

    EventBus.emit({
      sessionId,
      topicId: session.topicId,
      kind: "explain",
      nodeId,
      payload: { label: node.label },
    });

    return {
      content: {
        one_liner: node.oneLiner,
        details: node.details,
        analogy: node.analogy,
      },
      node,
    };
  }

  markItemCompleted(sessionId: string, itemId: string, nodeId?: string, quality: "correct" | "incorrect" | "again" = "correct") {
    const session = this.getSession(sessionId);
    if (!session) return;

    const items = session.curriculum.items.map((it) =>
      it.id === itemId ? { ...it, status: "completed" as const } : it,
    );
    const nextIdx = Math.min(session.currentIndex + 1, items.length);
    const completed = items.filter((i) => i.status === "completed").length;
    const progress = items.length > 0 ? completed / items.length : 0;

    getDb()
      .prepare(
        `UPDATE learning_sessions SET curriculum_json = ?, current_index = ? WHERE id = ?`,
      )
      .run(JSON.stringify({ ...session.curriculum, items }), nextIdx, sessionId);

    // If nodeId provided, schedule review + update mastery
    if (nodeId) {
      this.reviewScheduler.onAnswered(session.topicId, nodeId, quality);
    }

    EventBus.emit({
      sessionId,
      topicId: session.topicId,
      kind: "item_completed",
      nodeId,
      payload: { itemId, progress },
    });
  }

  /**
   * Финализация сессии: генерация финальной проверки и оценка освоения.
   */
  async finalize(sessionId: string): Promise<{
    assessmentId: string;
    mastery: Awaited<ReturnType<MasteryEngine["evaluate"]>>;
  }> {
    const session = this.getSession(sessionId);
    if (!session) throw new Error("Сессия не найдена");

    const studiedNodeIds = session.curriculum.items
      .filter((i) => i.status === "completed" && i.nodeId)
      .map((i) => i.nodeId);

    const items = studiedNodeIds.length
      ? studiedNodeIds.map((nid) => this.nodeBrief(session.topicId, nid))
      : this.allNodeBriefs(session.topicId);

    const assessment = await this.assessmentEngine.generate(
      sessionId,
      session.topicId,
      items,
      "final",
      6,
      true,
    );

    getDb()
      .prepare(
        `UPDATE learning_sessions SET status = 'completed', completed_at = ? WHERE id = ?`,
      )
      .run(new Date().toISOString(), sessionId);

    EventBus.emit({
      sessionId,
      topicId: session.topicId,
      kind: "assessment",
      payload: { assessmentId: assessment.id },
    });

    return { assessmentId: assessment.id, mastery: { topicId: session.topicId, newLevel: { label: "solid_understanding" as MasteryLevel, score: 0.5 }, reachedTarget: false, perConcept: {}, gaps: [] } };
  }

  private nodeBrief(topicId: string, nodeId: string): { nodeId: string; label: string; oneLiner: string; details: string } {
    const row = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!row) return { nodeId, label: "", oneLiner: "", details: "" };
    return {
      nodeId: String(row.id),
      label: String(row.label),
      oneLiner: String(row.one_liner ?? ""),
      details: String(row.details ?? ""),
    };
  }

  private allNodeBriefs(topicId: string) {
    const rows = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ? AND leaf = 1 LIMIT 12`)
      .all(topicId) as Record<string, unknown>[];
    return rows.map((r) => ({
      nodeId: String(r.id),
      label: String(r.label),
      oneLiner: String(r.one_liner ?? ""),
      details: String(r.details ?? ""),
    }));
  }

  private nodePath(topicId: string, nodeId: string): string[] {
    const nodes = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Record<string, unknown>[];
    const byId = new Map(nodes.map((n) => [String(n.id), n]));
    const path: string[] = [];
    let current = byId.get(nodeId);
    let guard = 0;
    while (current && guard < 50) {
      path.unshift(String(current.label));
      current = current.parent_id ? byId.get(String(current.parent_id)) : undefined;
      guard++;
    }
    return path;
  }

  private siblings(topicId: string, parentId: string): string[] {
    const rows = getDb()
      .prepare(
        `SELECT label FROM knowledge_nodes WHERE topic_id = ? AND parent_id = ? AND id != ?`,
      )
      .all(topicId, parentId || null, parentId) as Array<{ label: string }>;
    return rows.map((r) => r.label).slice(0, 8);
  }

  private getTopicName(topicId: string): string {
    const row = getDb().prepare(`SELECT name FROM topics WHERE id = ?`).get(topicId) as
      | { name: string }
      | undefined;
    return row?.name ?? "";
  }

  private getTargetLevel(topicId: string): string {
    const row = getDb()
      .prepare(`SELECT target_level FROM topics WHERE id = ?`)
      .get(topicId) as { target_level: string } | undefined;
    return row?.target_level ?? "basic_understanding";
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
  return {
    id: String(row.id),
    topicId: String(row.topic_id),
    parentId: row.parent_id ? String(row.parent_id) : null,
    level: Number(row.level),
    label: String(row.label),
    oneLiner: String(row.one_liner ?? ""),
    details: String(row.details ?? ""),
    analogy: row.analogy ? String(row.analogy) : undefined,
    conceptType: row.concept_type ? (String(row.concept_type) as KnowledgeNode["conceptType"]) : undefined,
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
