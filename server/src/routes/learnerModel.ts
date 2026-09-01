import type { FastifyInstance } from "fastify";
import { LearnerModelService } from "../domain/LearnerModelService.js";

export async function learnerModelRoutes(app: FastifyInstance) {
  const service = new LearnerModelService();

  app.get("/:topicId", async (request, reply) => {
    const { topicId } = request.params as { topicId: string };
    if (!topicId) return reply.status(400).send({ error: "topicId required" });
    const model = service.getModel(topicId);
    const profiles = service.getConceptProfiles(topicId);
    return reply.send({
      model,
      profiles,
      weakConcepts: service.getWeakConcepts(topicId),
      dueConcepts: service.getDueConcepts(topicId),
    });
  });
}
