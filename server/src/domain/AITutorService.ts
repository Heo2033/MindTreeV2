import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import { buildTutorPrompt } from "../prompts/tutor.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { getDb } from "../db/connection.js";

export interface TutorReply {
  text: string;
  usedFallback: boolean;
}

export class AITutorService {
  constructor(private learnerModel = new LearnerModelService()) {}

  /**
   * Контекстный ответ репетитора: учитывает тему, уровень, текущее понятие,
   * ошибки и оставшееся время.
   */
  async reply(
    topicId: string,
    message: string,
    opts: { sessionId?: string; nodeId?: string } = {},
  ): Promise<TutorReply> {
    const topic = this.getTopic(topicId);
    const currentLevel = this.learnerModel.getCurrentLevel(topicId);
    const targetLevel = topic?.target_level;
    const currentNode = opts.sessionId
      ? this.currentNodeOfSession(opts.sessionId)
      : opts.nodeId
        ? this.nodeOfId(opts.nodeId)
        : undefined;
    const misconceptions = this.recentMisconceptions(topicId);
    const timeLeft = opts.sessionId ? this.remainingMinutes(opts.sessionId) : undefined;

    const prompt = buildTutorPrompt({
      topic: topic?.name ?? "",
      goal: topic?.goal ?? "",
      targetLevel: targetLevel ?? "basic_understanding",
      currentLevel,
      currentNode: currentNode?.label,
      nodePath: currentNode?.path,
      misconceptions,
      timeRemainingMinutes: timeLeft,
      message,
    });

    try {
      const res = await getScheduler().execute(
        "tutor",
        () => prompt,
        (raw) => raw,
      );
      return { text: res.result, usedFallback: false };
    } catch (err) {
      return {
        text:
          `Не удалось получить ответ от модели. ` +
          `Тема: ${topic?.name ?? ""}. Ваш вопрос: ${message}. ` +
          `(Ошибка: ${err instanceof Error ? err.message : String(err)})`,
        usedFallback: true,
      };
    }
  }

  private nodeOfId(nodeId: string): { id: string; label: string; path?: string[] } | undefined {
    const node = getDb()
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ?`)
      .get(nodeId) as Record<string, unknown> | undefined;
    if (!node) return undefined;

    const allRows = getDb()
      .prepare(`SELECT id, label, parent_id FROM knowledge_nodes WHERE topic_id = ?`)
      .all(String(node.topic_id)) as Array<Record<string, unknown>>;
    const byId = new Map(allRows.map((r) => [String(r.id), r]));
    const path: string[] = [];
    let current = String(nodeId);
    let guard = 0;
    while (byId.has(current) && guard < 50) {
      const row = byId.get(current)!;
      path.unshift(String(row.label));
      const parentId = row.parent_id ? String(row.parent_id) : null;
      if (!parentId) break;
      current = parentId;
      guard++;
    }
    return { id: String(node.id), label: String(node.label), path };
  }

  private currentNodeOfSession(sessionId: string): { id: string; label: string; path?: string[] } | undefined {
    const session = getDb()
      .prepare(`SELECT curriculum_json, current_index, topic_id FROM learning_sessions WHERE id = ?`)
      .get(sessionId) as Record<string, unknown> | undefined;
    if (!session) return undefined;
    let curriculum;
    try {
      curriculum = JSON.parse(String(session.curriculum_json ?? "{}"));
    } catch {
      return undefined;
    }
    const idx = Number(session.current_index);
    const item = curriculum?.items?.[idx];
    if (!item?.nodeId) return undefined;
    const node = getDb()
      .prepare(`SELECT id, label FROM knowledge_nodes WHERE id = ?`)
      .get(item.nodeId) as { id: string; label: string } | undefined;
    if (!node) return undefined;
    const withPath = this.nodeOfId(node.id);
    return withPath ?? node;
  }

  private recentMisconceptions(topicId: string, limit = 3): string[] {
    const masteries = this.learnerModel.getWeakConcepts(topicId, limit);
    return masteries;
  }

  private remainingMinutes(sessionId: string): number | undefined {
    const session = getDb()
      .prepare(`SELECT time_budget_minutes, started_at FROM learning_sessions WHERE id = ?`)
      .get(sessionId) as Record<string, unknown> | undefined;
    if (!session) return undefined;
    const budget = Number(session.time_budget_minutes);
    const elapsed = (Date.now() - new Date(String(session.started_at)).getTime()) / 60000;
    return Math.max(0, Math.round(budget - elapsed));
  }

  private getTopic(topicId: string): { name: string; goal: string; target_level: string } | undefined {
    const row = getDb()
      .prepare(`SELECT name, goal, target_level FROM topics WHERE id = ?`)
      .get(topicId) as Record<string, unknown> | undefined;
    return row
      ? {
          name: String(row.name),
          goal: String(row.goal),
          target_level: String(row.target_level),
        }
      : undefined;
  }
}
