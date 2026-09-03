import type { FastifyInstance } from "fastify";
import { KnowledgeGraphEngine, type NodeDraft } from "../domain/KnowledgeGraphEngine.js";
import { getDb } from "../db/connection.js";

export async function pipelineRoutes(app: FastifyInstance) {
  app.post("/generate", async (request, reply) => {
    const { topic_id, query, goal, level, time_budget_minutes } = request.body as any;

    if (!query) {
      return reply.status(400).send({ error: "query is required" });
    }

    // SSE headers
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    const sendEvent = (event: string, data: any) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    const engine = new KnowledgeGraphEngine();

    try {
      const { nodes, warnings } = await engine.generate(
        query,
        {
          goal,
          level,
          timeBudgetMinutes:
            typeof time_budget_minutes === "number" && time_budget_minutes > 0
              ? time_budget_minutes
              : undefined,
        },
        (phase, message, stats) => {
          sendEvent("progress", { phase, message, stats });
        },
      );

      // Persist nodes to DB if a topic_id was provided
      let persistCount = 0;
      let skippedOrphans: string[] = [];
      try {
        const result = await persistNodes(topic_id, query, nodes);
        persistCount = result.count;
        skippedOrphans = result.skippedOrphans;
      } catch (err) {
        sendEvent("error", {
          message: `Не удалось сохранить дерево: ${err instanceof Error ? err.message : String(err)}`,
        });
        reply.raw.end();
        return;
      }

      // Фоновое, тихое заполнение контента листьев после успешного persist.
      // Не блокирует SSE-ответ: запускается fire-and-forget и не зависит от
      // того, останется ли клиент открытым.
      if (topic_id && persistCount > 0) {
        scheduleBackgroundFill(topic_id, engine);
      }

      sendEvent("done", { nodes, warnings, persisted: persistCount, skippedOrphans });
    } catch (err) {
      sendEvent("error", {
        message: err instanceof Error ? err.message : String(err),
      });
    }

    reply.raw.end();
  });
}

function persistNodes(
  topicId: string | undefined,
  query: string,
  nodes: NodeDraft[],
): { count: number; skippedOrphans: string[] } {
  const db = getDb();
  if (!topicId) return { count: 0, skippedOrphans: [] };

  const topic = db.prepare("SELECT id FROM topics WHERE id = ?").get(topicId) as
    | { id: string }
    | undefined;
  if (!topic) return { count: 0, skippedOrphans: [] };

  // Derive root label from query if tree root is empty
  const rootLabel = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";

  const insert = db.prepare(
    `INSERT OR IGNORE INTO knowledge_nodes
       (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
        estimated_time_minutes, relations_json, state, content_loaded, leaf, level, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
  );

  // Защита от «сирот»: до персиста собираем все id партии; узел с parentId,
  // указывающим на id, которого нет в сохраняемом дереве, НЕ записываем,
  // чтобы в БД не появлялись дети без родителя (белый граф/повисшие листья).
  const persistedIds = new Set(nodes.filter((n) => String(n.id ?? "") !== "").map((n) => String(n.id)));
  const skippedOrphans: string[] = [];
  const validItems = nodes.filter((n) => {
    const id = String(n.id ?? "");
    if (!id) return false;
    const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
    if (parentId && !persistedIds.has(parentId) && !nodes.some((x) => String(x.id) === parentId)) {
      skippedOrphans.push(id);
      return false;
    }
    return true;
  });

  const tx = db.transaction((items: NodeDraft[]) => {
    let count = 0;
    for (const n of items) {
      const id = String(n.id ?? "");
      if (!id) continue;
      const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
      // level-1 root node uses query as label if empty
      const label = n.level === 1
        ? (String((n as { title?: string }).title ?? "") || rootLabel)
        : String((n as { title?: string }).title ?? "");
      if (!label.trim()) continue;

      const existingChildren = items.filter((c) => c.parentId === id);
      const leaf = existingChildren.length === 0 ? 1 : Number((n as { leaf?: unknown }).leaf ?? 0);
      const relations = Array.isArray((n as { relations?: unknown[] }).relations)
        ? (n as { relations: unknown[] }).relations
        : [];

      insert.run(
        id,
        topicId,
        parentId,
        label.trim(),
        String(n.canonical_definition ?? ""),
        n.conceptType ? String(n.conceptType) : null,
        typeof n.importance === "number" ? n.importance : 0.5,
        typeof n.difficulty === "number" ? n.difficulty : 0.5,
        typeof n.estimatedMinutes === "number" ? n.estimatedMinutes : 5,
        JSON.stringify(relations),
        "skeleton",
        0,
        leaf,
        Number(n.level ?? 1),
        new Date().toISOString(),
      );
      count++;
    }
    return count;
  });

  return { count: tx(validItems), skippedOrphans };
}

// Множество topicId, для которых фоновое заполнение уже запущено и не завершено.
// Предотвращает накопление нескольких фоновых циклов для одной темы.
const backgroundFillInFlight = new Set<string>();

/**
 * Запускает тихое фоновое заполнение контента всех узлов темы, у которых
 * content_loaded = 0 (листья L1–L2 после первой генерации). Выполняется
 * fire-and-forget: не блокирует ответ, не привязан к открытой вкладке.
 * Узлы, не заполнившиеся (ошибка LLM и т.п.), остаются для ленивой подгрузки.
 * Идемпотентен: повторный запуск дозаполняет только оставшиеся узлы.
 */
function scheduleBackgroundFill(topicId: string, engine: KnowledgeGraphEngine): void {
  if (backgroundFillInFlight.has(topicId)) return;
  backgroundFillInFlight.add(topicId);

  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  void (async () => {
    const db = getDb();
    try {
      const rows = db
        .prepare(
          `SELECT id FROM knowledge_nodes
           WHERE topic_id = ? AND content_loaded = 0
           ORDER BY level ASC, created_at ASC`,
        )
        .all(topicId) as Array<{ id: string }>;

      for (const { id } of rows) {
        // Технический узел уже заполнен к моменту обработки (например,
        // пользователь сам подгрузил контент) — пропускаем.
        const stillPending = db
          .prepare(`SELECT content_loaded FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
          .get(id, topicId) as { content_loaded: number } | undefined;
        if (!stillPending || stillPending.content_loaded === 1) continue;

        try {
          await engine.generateNodeContentFromDb(topicId, id);
        } catch {
          // Ошибка конкретного узла не останавливает фоновую заливку остальных.
        }
      }
    } finally {
      backgroundFillInFlight.delete(topicId);
    }
  })();
}
