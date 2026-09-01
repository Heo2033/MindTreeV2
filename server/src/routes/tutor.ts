import type { FastifyInstance } from "fastify";
import { AITutorService } from "../domain/AITutorService.js";

export async function tutorRoutes(app: FastifyInstance) {
  app.post("/", async (request, reply) => {
    const { topic_id, session_id, message, node_id } = request.body as any;

    if (!topic_id || !message) {
      return reply.status(400).send({ error: "topic_id and message are required" });
    }

    const tutor = new AITutorService();
    const result = await tutor.reply(topic_id, message, {
      sessionId: session_id,
      nodeId: node_id,
    });

    return reply.send({
      response: result.text,
      usedFallback: result.usedFallback,
      context: { topic_id, session_id, node_id },
    });
  });
}
