import type { FastifyInstance } from "fastify";
import { SessionCoordinator } from "../application/SessionCoordinator.js";
import { PlannerCoordinator } from "../application/PlannerCoordinator.js";
import { LearningActivityService } from "../domain/LearningActivityService.js";

export async function sessionRoutes(app: FastifyInstance) {
  const sessions = new SessionCoordinator();
  const planner = new PlannerCoordinator();
  const activities = new LearningActivityService();

  app.get("/", async (_request, reply) => {
    return reply.send(sessions.list());
  });

  app.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const detail = sessions.getDetail(id);
    if (!detail) return reply.status(404).send({ error: "Session not found" });
    const plan = planner.getSessionPlan(id);
    return reply.send({ ...detail, plan });
  });

  app.post("/", async (request, reply) => {
    const { journey_id, milestone_id, topic_id, goal, time_budget_minutes } = request.body as {
      journey_id?: string;
      milestone_id?: string;
      topic_id?: string;
      goal?: string;
      time_budget_minutes?: number;
    };
    if (!topic_id) return reply.status(400).send({ error: "topic_id is required" });

    try {
      const session = await sessions.create({
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
    const result = await sessions.current(id);
    if (!result) return reply.status(404).send({ error: "Session or item not found" });
    return reply.send(result);
  });

  // Study a node (lazy content generation)
  app.post("/:id/study", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { node_id } = request.body as { node_id?: string };
    if (!node_id) return reply.status(400).send({ error: "node_id is required" });

    try {
      const result = await sessions.study(id, node_id);
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  // Mark a curriculum item complete (advances curriculum position)
  app.post("/:id/item-complete", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { item_id, node_id, quality } = request.body as {
      item_id?: string;
      node_id?: string;
      quality?: string;
    };
    if (!item_id) return reply.status(400).send({ error: "item_id is required" });

    const qualityNorm =
      quality === "incorrect" || quality === "again" ? quality : "correct";
    return reply.send(
      await sessions.completeItem(id, item_id, node_id, qualityNorm),
    );
  });

  // Prepare the final assessment for a session (idempotent).
  // Session status flips to "completed" after the assessment is submitted.
  app.post("/:id/finalize", async (request, reply) => {
    const { id } = request.params as { id: string };
    try {
      const result = await sessions.prepareFinalAssessment(id);
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  // Records a learning event only; does not advance curriculum position.
  app.post("/:id/progress", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { type, node_id, data, duration_ms } = request.body as {
      type?: string;
      node_id?: string;
      data?: Record<string, unknown>;
      duration_ms?: number;
    };
    if (!type) return reply.status(400).send({ error: "type is required" });

    const eventId = sessions.recordProgress(id, {
      type,
      nodeId: node_id,
      data,
      durationMs: duration_ms,
    });
    return reply.send({ ok: true, eventId });
  });

  // Ensure current activity exists and return it (steps of the learning loop).
  app.post("/:id/activity", async (request, reply) => {
    const { id } = request.params as { id: string };
    try {
      const activity = await activities.ensureActivity(id);
      return reply.send(activity);
    } catch (err) {
      return reply.status(404).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  // Answer a step of the current activity. Returns the updated activity.
  app.post("/:id/activity/answer", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { step_index, answer } = request.body as {
      step_index?: number;
      answer?: string;
    };
    if (!Number.isInteger(step_index)) {
      return reply.status(400).send({ error: "step_index is required" });
    }
    try {
      const activity = await activities.answer(id, Number(step_index), String(answer ?? ""));
      return reply.send(activity);
    } catch (err) {
      return reply.status(400).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  app.post("/:id/complete", async (request, reply) => {
    const { id } = request.params as { id: string };
    return reply.send(sessions.completeSession(id));
  });
}