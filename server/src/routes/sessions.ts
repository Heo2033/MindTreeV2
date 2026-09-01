import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { LearningSessionEngine } from "../domain/LearningSessionEngine.js";
import { AdaptiveLearningEngine } from "../domain/AdaptiveLearningEngine.js";

export async function sessionRoutes(app: FastifyInstance) {
  const engine = new LearningSessionEngine();
  const adaptive = new AdaptiveLearningEngine();

  app.get("/", async (_request, reply) => {
    const sessions = app.db.prepare(
      "SELECT * FROM learning_sessions ORDER BY started_at DESC"
    ).all();
    return reply.send(sessions);
  });

  app.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const session = engine.getSession(id);
    if (!session) return reply.status(404).send({ error: "Session not found" });

    const events = app.db.prepare(
      "SELECT * FROM learning_events WHERE session_id = ? ORDER BY timestamp"
    ).all(id);

    return reply.send({ session, events });
  });

  app.post("/", async (request, reply) => {
    const { journey_id, milestone_id, topic_id, goal, time_budget_minutes } = request.body as any;
    if (!topic_id) return reply.status(400).send({ error: "topic_id is required" });

    try {
      const session = await engine.create({
        journeyId: journey_id,
        milestoneId: milestone_id,
        topicId: topic_id,
        goal: goal || "overview",
        timeBudgetMinutes: time_budget_minutes || 60,
      });
      return reply.status(201).send(session);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  // Current item + adaptive next step
  app.get("/:id/current", async (request, reply) => {
    const { id } = request.params as { id: string };
    const current = engine.getCurrentItem(id);
    if (!current) return reply.status(404).send({ error: "Session or item not found" });

    let adaptiveDecision;
    try {
      adaptiveDecision = await adaptive.nextStep(id);
    } catch (err) {
      adaptiveDecision = { recommendedAction: "study_next" as const, dueReviews: [], reasons: [] };
    }

    return reply.send({ current, adaptive: adaptiveDecision });
  });

  // Study a node (lazy content generation)
  app.post("/:id/study", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { node_id } = request.body as any;
    if (!node_id) return reply.status(400).send({ error: "node_id is required" });

    try {
      const result = await engine.studyNode(id, node_id);
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  // Mark a curriculum item complete
  app.post("/:id/item-complete", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { item_id, node_id, quality } = request.body as any;
    engine.markItemCompleted(id, item_id, node_id, quality || "correct");
    return reply.send({ ok: true });
  });

  // Finalize session: generate final assessment
  app.post("/:id/finalize", async (request, reply) => {
    const { id } = request.params as { id: string };
    try {
      const result = await engine.finalize(id);
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  app.post("/:id/progress", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { type, node_id, data, duration_ms } = request.body as any;
    const eventId = `evt_${crypto.randomUUID().slice(0, 8)}`;

    app.db.prepare(
      `INSERT INTO learning_events (id, session_id, type, node_id, data_json, duration_ms)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(eventId, id, type, node_id || null, JSON.stringify(data || {}), duration_ms || 0);

    app.db.prepare(
      "UPDATE learning_sessions SET current_index = current_index + 1 WHERE id = ?"
    ).run(id);

    return reply.send({ ok: true, eventId });
  });

  app.post("/:id/complete", async (request, reply) => {
    const { id } = request.params as { id: string };
    app.db.prepare(
      "UPDATE learning_sessions SET status = 'completed', completed_at = datetime('now') WHERE id = ?"
    ).run(id);
    return reply.send({ ok: true });
  });
}
