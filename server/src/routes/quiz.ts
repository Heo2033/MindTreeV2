import type { FastifyInstance } from "fastify";
import crypto from "crypto";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import { buildQuizPrompt, computeQuizCount } from "../prompts/quiz.js";
import { getDb } from "../db/connection.js";
import { ReviewScheduler } from "../domain/ReviewScheduler.js";

export interface QuizQuestion {
  id: string;
  nodeId: string;
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  misconception?: boolean;
}

export interface QuizResult {
  id: string;
  topicId: string;
  title: string;
  questions: QuizQuestion[];
}

export async function quizRoutes(app: FastifyInstance) {
  const reviewScheduler = new ReviewScheduler();

  // Generate a quiz for a topic (or subset of node ids)
  app.post("/", async (request, reply) => {
    const { topic_id, node_ids, count } = (request.body ?? {}) as {
      topic_id?: string;
      node_ids?: unknown[];
      count?: number;
    };
    if (!topic_id) return reply.status(400).send({ error: "topic_id is required" });

    const topic = getDb().prepare("SELECT id, name FROM topics WHERE id = ?").get(topic_id) as
      | { id: string; name: string }
      | undefined;
    if (!topic) return reply.status(404).send({ error: "Topic not found" });

    let rows: Array<Record<string, unknown>>;
    if (Array.isArray(node_ids) && node_ids.length > 0) {
      const marks = node_ids.map(() => "?").join(",");
      rows = getDb()
        .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ? AND id IN (${marks})`)
        .all(topic_id, ...node_ids) as Array<Record<string, unknown>>;
    } else {
      rows = getDb()
        .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 1 LIMIT 20`)
        .all(topic_id) as Array<Record<string, unknown>>;
    }

    const nodes = rows.map((r) => ({
      id: String(r.id),
      label: String(r.label),
      one_liner: String(r.one_liner ?? ""),
      details: String(r.details ?? ""),
      conceptType: r.concept_type ? String(r.concept_type) : undefined,
    }));

    if (nodes.length === 0) {
      return reply.status(400).send({ error: "Нет узлов с контентом для теста" });
    }

    const questionCount = typeof count === "number"
      ? Math.max(4, Math.min(count, 12))
      : computeQuizCount(nodes.length);

    const prompt = buildQuizPrompt(topic.name, nodes, questionCount);

    let questions: QuizQuestion[] = [];
    try {
      const res = await getScheduler().execute(
        "quiz",
        () => prompt,
        (raw) => {
          const data = parseLLMJson<{ questions?: unknown[] }>(raw);
          if (!Array.isArray(data?.questions)) return [];
          return (data.questions as Array<Record<string, unknown>>)
            .map((q, i) => ({
              id: typeof q.id === "string" ? q.id : `q${i}`,
              nodeId: typeof q.nodeId === "string" ? q.nodeId : "",
              question: typeof q.question === "string" ? q.question : "",
              options: Array.isArray(q.options)
                ? (q.options as unknown[]).filter((o): o is string => typeof o === "string")
                : [],
              correctIndex:
                typeof q.correctIndex === "number" ? (q.correctIndex as number) : 0,
              explanation: typeof q.explanation === "string" ? q.explanation : "",
              misconception: q.misconception === true,
            }))
            .filter((q) => q.question !== "" && q.options.length >= 2);
        },
      );
      questions = res.result.slice(0, questionCount);
    } catch (err) {
      return reply.status(500).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }

    const id = `quiz_${crypto.randomUUID().slice(0, 8)}`;
    return reply.status(201).send({ id, topicId: topic_id, title: topic.name, questions });
  });

  // Apply quiz results back to learner model (SRS update per node)
  app.post("/:id/apply", async (request, reply) => {
    const { topic_id, results } = (request.body ?? {}) as {
      topic_id?: string;
      results?: Array<{ nodeId?: string; correct?: boolean }>;
    };
    if (!topic_id || !Array.isArray(results)) {
      return reply.status(400).send({ error: "topic_id and results array are required" });
    }

    for (const r of results) {
      if (!r?.nodeId) continue;
      const correct = r.correct === true;
      reviewScheduler.onAnswered(topic_id, r.nodeId, correct ? "correct" : "incorrect");
    }

    return reply.send({ ok: true, applied: results.length });
  });
}
