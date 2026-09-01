import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { AssessmentEngine } from "../domain/AssessmentEngine.js";
import { MasteryEngine } from "../domain/MasteryEngine.js";
import { getDb } from "../db/connection.js";

export async function assessmentRoutes(app: FastifyInstance) {
  const assessmentEngine = new AssessmentEngine();
  const masteryEngine = new MasteryEngine();

  app.get("/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const assessment = assessmentEngine.getById(id);
    if (!assessment) return reply.status(404).send({ error: "Assessment not found" });
    const attempts = getDb()
      .prepare("SELECT * FROM assessment_attempts WHERE assessment_id = ? ORDER BY created_at")
      .all(id);
    return reply.send({ ...assessment, attempts });
  });

  app.post("/", async (request, reply) => {
    const { session_id, type, questions } = request.body as any;
    const body = request.body as Record<string, unknown>;

    if (session_id && !questions) {
      // Generate final assessment for a session
      const session = getDb()
        .prepare(`SELECT topic_id FROM learning_sessions WHERE id = ?`)
        .get(session_id) as { topic_id: string } | undefined;
      if (!session) return reply.status(404).send({ error: "Session not found" });

      const items = getDb()
        .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ? AND leaf = 1 LIMIT 10`)
        .all(session.topic_id) as Array<Record<string, unknown>>;

      const assessment = await assessmentEngine.generate(
        session_id,
        session.topic_id,
        items.map((r) => ({
          nodeId: String(r.id),
          label: String(r.label),
          oneLiner: String(r.one_liner ?? ""),
          details: String(r.details ?? ""),
        })),
        type || "final",
        Number(body.question_count || 6),
        true,
      );
      return reply.status(201).send(assessment);
    }

    const id = `assess_${crypto.randomUUID().slice(0, 8)}`;
    getDb().prepare(
      `INSERT INTO assessments (id, session_id, type, questions_json)
       VALUES (?, ?, ?, ?)`
    ).run(id, session_id || null, type || "quiz", JSON.stringify(questions || []));

    return reply.status(201).send({ id, session_id, type, questions });
  });

  app.post("/:id/submit", async (request, reply) => {
    const { id } = request.params as { id: string };
    const { attempts } = request.body as { attempts: Array<{
      question_id: string;
      answer: string;
      correct: boolean;
      time_spent_ms?: number;
      feedback?: string;
    }> };

    const insert = app.db.prepare(
      `INSERT INTO assessment_attempts (id, assessment_id, question_id, answer, correct, time_spent_ms, feedback)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );

    const insertMany = app.db.transaction((items: typeof attempts) => {
      for (const a of items) {
        insert.run(
          `attempt_${crypto.randomUUID().slice(0, 8)}`,
          id, a.question_id, a.answer,
          a.correct ? 1 : 0, a.time_spent_ms || 0, a.feedback || null
        );
      }
    });

    insertMany(attempts);

    const correct = attempts.filter((a) => a.correct).length;
    const score = attempts.length > 0 ? correct / attempts.length : 0;

    app.db.prepare(
      "UPDATE assessments SET completed_at = datetime('now'), score = ? WHERE id = ?"
    ).run(score, id);

    // Evaluate mastery if session is finalized
    const assessment = getDb().prepare("SELECT session_id, topic_id FROM assessments a LEFT JOIN learning_sessions s ON s.id = a.session_id WHERE a.id = ?").get(id) as
      | { session_id: string | null; topic_id: string | null }
      | undefined;

    let mastery = null;
    if (assessment?.session_id && assessment.topic_id) {
      const items = attempts.map((a) => ({
        nodeId: a.question_id,
        label: a.question_id,
        type: "recall" as const,
        userAnswer: a.answer,
        correct: a.correct,
      }));
      try {
        mastery = await masteryEngine.evaluate(
          assessment.topic_id,
          items,
          "solid_understanding",
        );
      } catch {
        mastery = null;
      }
    }

    return reply.send({ id, score, correct, total: attempts.length, mastery });
  });
}
