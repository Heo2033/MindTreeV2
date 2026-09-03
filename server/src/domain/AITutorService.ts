import { getScheduler } from "../llm/scheduler.js";
import { buildTutorPrompt } from "../prompts/tutor.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { getDb } from "../db/connection.js";

export interface TutorReply {
  text: string;
  usedFallback: boolean;
  timeRemainingMinutes?: number;
}

interface TutorContext {
  topic?: { name: string; goal: string; target_level: string };
  currentLevel: string;
  targetLevel: string;
  currentNode?: { id: string; label: string; path?: string[] };
  currentMastery?: string;
  misconceptions: string[];
  recentAttempts: string[];
  timeRemainingMinutes?: number;
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
    const ctx = this.buildContext(topicId, opts);
    const prompt = this.buildPrompt(ctx, message);

    try {
      const res = await getScheduler().execute(
        "tutor",
        () => prompt,
        (raw) => raw,
      );
      return {
        text: res.result,
        usedFallback: false,
        timeRemainingMinutes: ctx.timeRemainingMinutes,
      };
    } catch (err) {
      return {
        text: this.fallbackText(ctx, message, err),
        usedFallback: true,
        timeRemainingMinutes: ctx.timeRemainingMinutes,
      };
    }
  }

  /**
   * Потоковая версия: отдаёт токены ответа по мере генерации (SSE).
   * При сбое модели возвращает fallback-текст посимвольно и сигнализирует
   * usedFallback в конце. Возвращает async-итератор объектов:
   * { kind: "token", text } | { kind: "done", usedFallback, timeRemainingMinutes }
   */
  async *streamReply(
    topicId: string,
    message: string,
    opts: { sessionId?: string; nodeId?: string; signal?: AbortSignal } = {},
  ): AsyncIterableIterator<
    | { kind: "token"; text: string }
    | { kind: "done"; usedFallback: boolean; timeRemainingMinutes?: number }
  > {
    const ctx = this.buildContext(topicId, opts);
    const prompt = this.buildPrompt(ctx, message);

    try {
      const stream = getScheduler().executeStream("tutor", () => prompt, {
        signal: opts.signal,
      });
      let any = false;
      for await (const token of stream) {
        if (token.length > 0) {
          any = true;
          yield { kind: "token", text: token };
        }
      }
      if (!any) throw new Error("LLM API вернул пустой ответ");
    } catch (err) {
      const text = this.fallbackText(ctx, message, err);
      // Отдаём fallback порциями, чтобы клиент видел прогресс заполнения.
      const chunk = 64;
      for (let i = 0; i < text.length; i += chunk) {
        yield { kind: "token", text: text.slice(i, i + chunk) };
      }
      yield { kind: "done", usedFallback: true, timeRemainingMinutes: ctx.timeRemainingMinutes };
      return;
    }

    yield { kind: "done", usedFallback: false, timeRemainingMinutes: ctx.timeRemainingMinutes };
  }

  private buildContext(
    topicId: string,
    opts: { sessionId?: string; nodeId?: string },
  ): TutorContext {
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
    const currentNodeProfile = currentNode?.id
      ? this.learnerModel.getConceptProfile(currentNode.id, topicId)
      : undefined;
    const currentMastery = currentNodeProfile
      ? `освоение ${Math.round(currentNodeProfile.masteryScore * 100)}%`
      : undefined;
    const recentAttempts = this.recentAttempts(topicId);

    return {
      topic,
      currentLevel,
      targetLevel: targetLevel ?? "basic_understanding",
      currentNode,
      currentMastery,
      misconceptions,
      recentAttempts,
      timeRemainingMinutes: timeLeft,
    };
  }

  private buildPrompt(ctx: TutorContext, message: string): string {
    return buildTutorPrompt({
      topic: ctx.topic?.name ?? "",
      goal: ctx.topic?.goal ?? "",
      targetLevel: ctx.targetLevel,
      currentLevel: ctx.currentLevel,
      currentNode: ctx.currentNode?.label,
      nodePath: ctx.currentNode?.path,
      currentMastery: ctx.currentMastery,
      misconceptions: ctx.misconceptions,
      recentAttempts: ctx.recentAttempts,
      timeRemainingMinutes: ctx.timeRemainingMinutes,
      message,
    });
  }

  private fallbackText(ctx: TutorContext, message: string, err: unknown): string {
    return (
      `Не удалось получить ответ от модели. ` +
      `Тема: ${ctx.topic?.name ?? ""}. Ваш вопрос: ${message}. ` +
      `(Ошибка: ${err instanceof Error ? err.message : String(err)})`
    );
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

  /**
   * Последние ошибки/слабые понятия с описанием заблуждения — история обучения
   * для репетитора (§35), чтобы тот исправлял именно известные проблемы.
   */
  private recentAttempts(topicId: string, limit = 4): string[] {
    const profiles = this.learnerModel.getConceptProfiles(topicId);
    const withErrors = profiles.filter((p) => p.errors && p.errors.length > 0);
    const items: string[] = [];
    for (const p of withErrors) {
      for (const err of p.errors) {
        items.push(
          `${p.nodeId}: ${err.description || err.type || "ошибка"}`,
        );
        if (items.length >= limit) break;
      }
      if (items.length >= limit) break;
    }
    if (items.length < limit) {
      for (const p of profiles) {
        if (items.length >= limit) break;
        if (p.masteryScore < 0.6) {
          items.push(`${p.nodeId}: слабое освоение (${Math.round(p.masteryScore * 100)}%)`);
        }
      }
    }
    return items.slice(0, limit);
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
