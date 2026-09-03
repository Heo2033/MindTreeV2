import type { FastifyInstance } from "fastify";
import { KnowledgeGraphEngine, type NodeDraft } from "../domain/KnowledgeGraphEngine.js";
import { getDb } from "../db/connection.js";

export async function pipelineRoutes(app: FastifyInstance) {
  app.post("/generate", async (request, reply) => {
    const { topic_id, query, goal, level } = request.body as any;

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
      const { nodes, warnings } = await engine.generate(query, { goal, level }, (phase, message, stats) => {
        sendEvent("progress", { phase, message, stats });
      });

      // Persist nodes to DB if a topic_id was provided
      let persistCount = 0;
      try {
        persistCount = await persistNodes(topic_id, query, nodes);
      } catch (err) {
        sendEvent("error", {
          message: `Не удалось сохранить дерево: ${err instanceof Error ? err.message : String(err)}`,
        });
        reply.raw.end();
        return;
      }

      sendEvent("done", { nodes, warnings, persisted: persistCount });
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
): number {
  const db = getDb();
  if (!topicId) return 0;

  const topic = db.prepare("SELECT id FROM topics WHERE id = ?").get(topicId) as
    | { id: string }
    | undefined;
  if (!topic) return 0;

  // Derive root label from query if tree root is empty
  const rootLabel = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";

  const insert = db.prepare(
    `INSERT OR IGNORE INTO knowledge_nodes
       (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
        estimated_time_minutes, state, content_loaded, leaf, level, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
  );

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

      insert.run(
        id,
        topicId,
        parentId,
        label.trim(),
        String(n.canonical_definition ?? ""),
        n.conceptType ? String(n.conceptType) : null,
        0.5,
        0.5,
        5,
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

  return tx(nodes);
}
