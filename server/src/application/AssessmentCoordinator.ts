import crypto from "crypto";
import { AssessmentEngine } from "../domain/AssessmentEngine.js";
import { MasteryEngine, type MasteryItem } from "../domain/MasteryEngine.js";
import { getDb } from "../db/connection.js";

export interface SubmitAttemptInput {
  question_id: string;
  answer: string;
  correct: boolean;
  time_spent_ms?: number;
  feedback?: string;
}

interface StoredQuestion {
  id: string;
  type?: string;
  nodeId?: string;
  question?: string;
  options?: string[];
  correctAnswer?: string;
  explanation?: string;
}

/**
 * Application-layer оркестратор assessment: создание, сабмит и оценка mastery.
 * Вычисляет настоящий уровень по ответам финальной проверки (без захардкоженных
 * заглушек) и завершает связанную сессию после сабмита.
 */
export class AssessmentCoordinator {
  private assessmentEngine = new AssessmentEngine();
  private masteryEngine = new MasteryEngine();

  getById(id: string) {
    const assessment = this.assessmentEngine.getById(id);
    if (!assessment) return null;
    const attempts = getDb()
      .prepare(
        "SELECT * FROM assessment_attempts WHERE assessment_id = ? ORDER BY created_at",
      )
      .all(id) as Array<Record<string, unknown>>;
    return {
      id: assessment.id,
      sessionId: assessment.sessionId,
      type: assessment.type,
      questions: assessment.questions,
      attempts: attempts.map(rowToAttempt),
    };
  }

  async create(body: {
    session_id?: string;
    type?: string;
    questions?: unknown[];
    question_count?: number;
  }) {
    if (body.session_id && !body.questions) {
      const session = getDb()
        .prepare(`SELECT topic_id FROM learning_sessions WHERE id = ?`)
        .get(body.session_id) as { topic_id: string } | undefined;
      if (!session) throw new Error("Сессия не найдена");

      const items = getDb()
        .prepare(
          "SELECT * FROM knowledge_nodes WHERE topic_id = ? AND leaf = 1 LIMIT 10",
        )
        .all(session.topic_id) as Array<Record<string, unknown>>;

      return this.assessmentEngine.generate(
        body.session_id,
        session.topic_id,
        items.map((r) => ({
          nodeId: String(r.id),
          label: String(r.label),
          oneLiner: String(r.one_liner ?? ""),
          details: String(r.details ?? ""),
        })),
        (body.type || "final") as "final" | "quiz" | "diagnostic" | "mastery",
        Number(body.question_count || 6),
        true,
      );
    }

    const id = `assess_${crypto.randomUUID().slice(0, 8)}`;
    getDb()
      .prepare(
        `INSERT INTO assessments (id, session_id, type, questions_json)
         VALUES (?, ?, ?, ?)`,
      )
      .run(
        id,
        body.session_id || null,
        body.type || "quiz",
        JSON.stringify(body.questions || []),
      );

    return { id, session_id: body.session_id, type: body.type || "quiz", questions: body.questions || [] };
  }

  async submit(id: string, attempts: SubmitAttemptInput[]) {
    const insert = getDb().prepare(
      `INSERT INTO assessment_attempts (id, assessment_id, question_id, answer, correct, time_spent_ms, feedback)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    );
    const insertMany = getDb().transaction((items: SubmitAttemptInput[]) => {
      for (const a of items) {
        insert.run(
          `attempt_${crypto.randomUUID().slice(0, 8)}`,
          id, a.question_id, a.answer,
          a.correct ? 1 : 0, a.time_spent_ms || 0, a.feedback || null,
        );
      }
    });
    insertMany(attempts);

    getDb()
      .prepare("UPDATE assessments SET completed_at = ? WHERE id = ?")
      .run(new Date().toISOString(), id);

    const row = getDb()
      .prepare(
        `SELECT a.type AS type, s.id AS session_id, s.topic_id AS topic_id,
                s.status AS session_status
         FROM assessments a
         LEFT JOIN learning_sessions s ON s.id = a.session_id
         WHERE a.id = ?`,
      )
      .get(id) as Record<string, unknown> | undefined;

    let mastery = null;
    let masteryScore: number | null = null;
    if (row?.session_id && row.topic_id) {
      const questions = parseQuestions(
        getDb()
          .prepare(`SELECT questions_json FROM assessments WHERE id = ?`)
          .get(id) as { questions_json: string | null } | undefined,
      );

      const items: MasteryItem[] = attempts.map((a) => {
        const q = questions.find((qq) => qq.id === a.question_id);
        const conceptId = q?.nodeId || a.question_id;
        return {
          nodeId: conceptId,
          label: conceptId,
          type: masteryType(q?.type ?? "recall"),
          userAnswer: a.answer,
          correct: a.correct,
          rubric: q?.explanation,
        };
      });

      if (items.length > 0) {
        const targetLevel = getTargetLevel(String(row.topic_id));
        try {
          mastery = await this.masteryEngine.evaluate(
            String(row.topic_id),
            items,
            targetLevel,
          );
          const perConcept = Object.values(mastery.perConcept);
          if (perConcept.length > 0) {
            masteryScore = perConcept.reduce((s, p) => s + p.score, 0) / perConcept.length;
          }
        } catch {
          mastery = null;
        }
      }

      // Финальная проверка по сессии завершает саму сессию.
      if (String(row.type ?? "") === "final" && String(row.session_status ?? "") === "active") {
        getDb()
          .prepare(
            "UPDATE learning_sessions SET status = 'completed', completed_at = ? WHERE id = ?",
          )
          .run(new Date().toISOString(), String(row.session_id));
      }
    }

    // Balanced score: blend MCQ exact-match ratio with mastery estimate when available.
    const rawCorrect = attempts.filter((a) => a.correct).length;
    const roasted =
      masteryScore !== null
        ? rawCorrect / Math.max(1, attempts.length) * 0.5 + masteryScore * 0.5
        : rawCorrect / Math.max(1, attempts.length);
    const finalScore = Math.max(0, Math.min(1, roasted));

    getDb()
      .prepare("UPDATE assessments SET score = ? WHERE id = ?")
      .run(finalScore, id);

    return { id, score: finalScore, correct: rawCorrect, total: attempts.length, mastery };
  }
}

function rowToAttempt(row: Record<string, unknown>) {
  return {
    id: String(row.id),
    assessmentId: String(row.assessment_id),
    questionId: String(row.question_id),
    answer: String(row.answer),
    correct: Number(row.correct) === 1,
    timeSpentMs: Number(row.time_spent_ms) || 0,
    feedback: row.feedback ? String(row.feedback) : undefined,
    createdAt: String(row.created_at),
  };
}

function parseQuestions(row: { questions_json: string | null } | undefined): StoredQuestion[] {
  if (!row?.questions_json) return [];
  try {
    const data = JSON.parse(row.questions_json);
    return Array.isArray(data) ? (data as StoredQuestion[]) : [];
  } catch {
    return [];
  }
}

function masteryType(type: string): MasteryItem["type"] {
  switch (type) {
    case "application":
      return "application";
    case "transfer":
      return "transfer";
    case "explanation":
    case "diagnosis":
      return "explanation";
    case "recognition":
    case "recall":
    default:
      return "recall";
  }
}

function getTargetLevel(topicId: string): string {
  const row = getDb()
    .prepare(`SELECT target_level FROM topics WHERE id = ?`)
    .get(topicId) as { target_level?: string } | undefined;
  return row?.target_level ?? "solid_understanding";
}