import type { FastifyInstance } from "fastify";
import { KnowledgeGraphEngine } from "../domain/KnowledgeGraphEngine.js";
import { getDb } from "../db/connection.js";

export async function treeRoutes(app: FastifyInstance) {
  const engine = new KnowledgeGraphEngine();

  // Deepen / expand a branch of the tree
  app.post("/expand", async (request, reply) => {
    const { topic_id, node_id } = (request.body ?? {}) as {
      topic_id?: string;
      node_id?: string;
    };
    if (!topic_id || !node_id) {
      return reply.status(400).send({ error: "topic_id and node_id are required" });
    }
    try {
      const added = await engine.expandNodeFromDb(topic_id, node_id);
      return reply.send({ added, count: added.length });
    } catch (err) {
      return reply.status(err instanceof Error && /не найд|лист|глубин/i.test(err.message)
        ? 404
        : 500).send({ error: err instanceof Error ? err.message : String(err) });
    }
  });

  // Lazy content generation for a node
  app.post("/content", async (request, reply) => {
    const { topic_id, node_id } = (request.body ?? {}) as {
      topic_id?: string;
      node_id?: string;
    };
    if (!topic_id || !node_id) {
      return reply.status(400).send({ error: "topic_id and node_id are required" });
    }
    try {
      const content = await engine.generateNodeContentFromDb(topic_id, node_id);
      return reply.send({ node_id, ...content });
    } catch (err) {
      return reply.status(err instanceof Error && /не найд/i.test(err.message) ? 404 : 500)
        .send({ error: err instanceof Error ? err.message : String(err) });
    }
  });

  // Fill content for all nodes without content yet (optionally constrained to a level)
  app.post("/fill-content", async (request, reply) => {
    const { topic_id, level, limit, force } = (request.body ?? {}) as {
      topic_id?: string;
      level?: string;
      limit?: number;
      force?: boolean;
    };
    if (!topic_id) return reply.status(400).send({ error: "topic_id is required" });

    const lim = typeof limit === "number" ? limit : 50;
    const rows = level
      ? getDb()
          .prepare(
            `SELECT id FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 0 AND level <= ?
             LIMIT ?`,
          )
          .all(topic_id, level, lim)
      : getDb()
          .prepare(
            `SELECT id FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 0 LIMIT ?`,
          )
          .all(topic_id, lim);

    const ids = (rows as Array<{ id: string }>).map((r) => r.id);

    // Backfill: also regenerate nodes that already have content but lost relations (bug before persistence).
    if (force) {
      const forceRows = level
        ? getDb()
            .prepare(
              `SELECT id FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 1 AND level <= ?
               AND (relations_json IS NULL OR relations_json = '[]') LIMIT ?`,
            )
            .all(topic_id, level, lim)
        : getDb()
            .prepare(
              `SELECT id FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 1
               AND (relations_json IS NULL OR relations_json = '[]') LIMIT ?`,
            )
            .all(topic_id, lim);
      for (const r of forceRows as Array<{ id: string }>) {
        if (!ids.includes(r.id)) ids.push(r.id);
      }
    }

    const results: Array<{ node_id: string; ok: boolean; error?: string }> = [];
    let completed = 0;

    for (const nodeId of ids) {
      try {
        await engine.generateNodeContentFromDb(topic_id, nodeId);
        results.push({ node_id: nodeId, ok: true });
        completed++;
      } catch (err) {
        results.push({
          node_id: nodeId,
          ok: false,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    return reply.send({ completed, results });
  });

  // Explain a term in context of the topic
  app.post("/explain-term", async (request, reply) => {
    const { topic_id, term, context } = (request.body ?? {}) as {
      topic_id?: string;
      term?: string;
      context?: string;
    };
    if (!topic_id || !term) {
      return reply.status(400).send({ error: "topic_id and term are required" });
    }
    try {
      const { getScheduler } = await import("../llm/scheduler.js");
      const { parseLLMJson } = await import("../llm/client.js");
      const topic = getDb().prepare("SELECT name FROM topics WHERE id = ?").get(topic_id) as
        | { name: string }
        | undefined;

      const prompt = buildExplainTermPrompt(topic?.name ?? "Тема", term, context);
      const res = await getScheduler().execute(
        "explain",
        () => prompt,
        (raw) => parseLLMJson<{ explanation?: string }>(raw),
      );
      return reply.send({ term, explanation: res.result.explanation ?? "" });
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });
}

function buildExplainTermPrompt(topic: string, term: string, context?: string): string {
  const ctx = context && context.trim() !== "" ? `\nКонтекст: ${context.trim()}` : "";
  return `# Роль
Ты — преподаватель, кратко объясняешь конкретный термин в контексте темы.

# Тема
${topic}

# Задача
Объясни термин "${term}" простых словами (1–3 предложения), в контексте темы.
${ctx}

# Язык
Отвечай СТРОГО на русском языке.

# Формат
Только JSON: {"explanation":"..."}`;
}
