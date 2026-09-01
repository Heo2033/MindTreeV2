import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { MilestoneEngine } from "../domain/MilestoneEngine.js";
import { getDb } from "../db/connection.js";

export async function milestoneRoutes(app: FastifyInstance) {
  const engine = new MilestoneEngine();

  app.post("/generate", async (request, reply) => {
    const { journey_id, topic_id } = request.body as any;
    if (!journey_id || !topic_id) {
      return reply.status(400).send({ error: "journey_id and topic_id are required" });
    }
    const milestones = await engine.generate(journey_id, topic_id);
    return reply.status(201).send({ milestones });
  });

  app.get("/journey/:journeyId", async (request, reply) => {
    const { journeyId } = request.params as { journeyId: string };
    const milestones = getDb()
      .prepare(
        "SELECT * FROM learning_milestones WHERE journey_id = ? ORDER BY estimated_hours"
      )
      .all(journeyId);
    return reply.send({ milestones });
  });

  app.patch("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { status } = request.body as any;
    if (status) {
      getDb().prepare("UPDATE learning_milestones SET status = ? WHERE id = ?").run(status, id);
    }
    return reply.send({ ok: true });
  });
}
