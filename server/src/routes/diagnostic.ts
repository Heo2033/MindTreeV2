import type { FastifyInstance } from "fastify";
import { DiagnosticEngine } from "../domain/DiagnosticEngine.js";

export async function diagnosticRoutes(app: FastifyInstance) {
  const engine = new DiagnosticEngine();

  app.post("/:topicId/generate", async (request, reply) => {
    const { topicId } = request.params as { topicId: string };
    try {
      const questions = await engine.generate(topicId);
      return reply.send({ questions });
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  app.post("/:topicId/evaluate", async (request, reply) => {
    const { topicId } = request.params as { topicId: string };
    const { answers } = request.body as { answers: DiagnosticEngineAnswer[] };
    if (!Array.isArray(answers)) {
      return reply.status(400).send({ error: "answers array is required" });
    }
    try {
      const result = await engine.evaluate(topicId, answers);
      return reply.send(result);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });
}

interface DiagnosticEngineAnswer {
  questionId: string;
  nodeId: string;
  selectedIndex: number;
  correctIndex: number;
}
