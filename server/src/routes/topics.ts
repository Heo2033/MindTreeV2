import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { PlannerCoordinator } from "../application/PlannerCoordinator.js";

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

  // §44: смена цели темы с перестройкой плана вокруг недостающего знания.
  app.post("/:id/goal", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { goal } = request.body as { goal?: string };
    if (!goal || String(goal).trim() === "") {
      return reply.status(400).send({ error: "goal is required" });
    }
    try {
      const planner = new PlannerCoordinator();
      const result = await planner.changeTopicGoal(id, String(goal).trim());
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  app.delete("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    app.db.prepare("DELETE FROM topics WHERE id = ?").run(id);
    return reply.send({ ok: true });
  });
}
