import type { FastifyInstance } from "fastify";
import { AssessmentCoordinator } from "../application/AssessmentCoordinator.js";

export async function assessmentRoutes(app: FastifyInstance) {
  const coordinator = new AssessmentCoordinator();

  app.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const assessment = coordinator.getById(id);
    if (!assessment) return reply.status(404).send({ error: "Assessment not found" });
    return reply.send(assessment);
  });

  app.post("/", async (request, reply) => {
    const { session_id, type, questions, question_count } = request.body as {
      session_id?: string;
      type?: string;
      questions?: unknown[];
      question_count?: number;
    };

    try {
      const assessment = await coordinator.create({
        session_id,
        type,
        questions,
        question_count,
      });
      return reply.status(201).send(assessment);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  app.post("/:id/submit", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { attempts } = request.body as { attempts?: unknown[] };
    if (!Array.isArray(attempts) || attempts.length === 0) {
      return reply.status(400).send({ error: "attempts is required" });
    }

    const normalized = attempts.map((a) => {
      const t = (a ?? {}) as Record<string, unknown>;
      return {
        question_id: String(t.question_id ?? ""),
        answer: String(t.answer ?? ""),
        correct: t.correct === true,
        time_spent_ms: typeof t.time_spent_ms === "number" ? t.time_spent_ms : undefined,
        feedback: typeof t.feedback === "string" ? t.feedback : undefined,
      };
    });

    const result = await coordinator.submit(id, normalized);
    return reply.send(result);
  });
}