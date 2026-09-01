import type { FastifyInstance } from "fastify";
import crypto from "crypto";

export async function topicRoutes(app: FastifyInstance) {
  app.get("/", async (_request, reply) => {
    const topics = app.db.prepare("SELECT * FROM topics ORDER BY created_at DESC").all();
    return reply.send(topics);
  });

  app.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const topic = app.db.prepare("SELECT * FROM topics WHERE id = ?").get(id);
    if (!topic) return reply.status(404).send({ error: "Topic not found" });

    const nodes = app.db.prepare("SELECT * FROM knowledge_nodes WHERE topic_id = ?").all(id);
    return reply.send({ topic, nodes });
  });

  app.post("/", async (request, reply) => {
    const { name, goal, target_level, time_budget_minutes } = request.body as any;
    const id = `topic_${crypto.randomUUID().slice(0, 8)}`;

    app.db.prepare(
      "INSERT INTO topics (id, name, goal, target_level, time_budget_minutes) VALUES (?, ?, ?, ?, ?)"
    ).run(id, name, goal || "overview", target_level || "basic_understanding", time_budget_minutes || 60);

    const topic = app.db.prepare("SELECT * FROM topics WHERE id = ?").get(id);
    return reply.status(201).send(topic);
  });

  app.delete("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    app.db.prepare("DELETE FROM topics WHERE id = ?").run(id);
    return reply.send({ ok: true });
  });
}
