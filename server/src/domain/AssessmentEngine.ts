import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import crypto from "crypto";
import {
  buildAssessmentPrompt,
  parseAssessmentResult,
  type AssessmentQuestionResult,
} from "../prompts/assessment.js";
import { getDb } from "../db/connection.js";

export interface AssessmentItem {
  nodeId: string;
  label: string;
  oneLiner: string;
  details: string;
}

export interface Assessment {
  id: string;
  sessionId: string | null;
  type: "quiz" | "final" | "diagnostic" | "mastery";
  questions: AssessmentQuestionResult[];
}

export class AssessmentEngine {
  async generate(
    sessionId: string,
    topicId: string,
    items: AssessmentItem[],
    type: Assessment["type"] = "final",
    questionCount = 6,
    includeApplication = true,
  ): Promise<Assessment> {
    const topic = this.getTopic(topicId);

    const prompt = buildAssessmentPrompt(
      {
        topic: topic?.name ?? "",
        goal: topic?.goal ?? "",
        sessionItems: items.map((i) => ({
          nodeId: i.nodeId,
          label: i.label,
          oneLiner: i.oneLiner,
          details: i.details,
        })),
        includeApplication,
      },
      questionCount,
    );

    let questions: AssessmentQuestionResult[] = [];
    try {
      const res = await getScheduler().execute(
        "assessment",
        () => prompt,
        (raw) => parseAssessmentResult(parseLLMJson(raw)),
      );
      questions = res.result.slice(0, questionCount);
    } catch {
      // fallback minimal quiz
      questions = items.slice(0, questionCount).map((i, idx) => ({
        id: `fa_${idx}`,
        type: "recall",
        nodeId: i.nodeId,
        question: `Что такое "${i.label}"?`,
        options: [],
        correctAnswer: "",
        explanation: i.oneLiner,
      }));
    }

    const id = `asmt_${crypto.randomUUID().slice(0, 8)}`;
    getDb()
      .prepare(
        `INSERT INTO assessments (id, session_id, type, questions_json, started_at)
         VALUES (?,?,?,?,?)`,
      )
      .run(id, sessionId, type, JSON.stringify(questions), new Date().toISOString());

    return { id, sessionId, type, questions };
  }

  recordAttempt(
    assessmentId: string,
    questionId: string,
    answer: string,
    correct: boolean,
    timeMs: number,
    feedback?: string,
  ) {
    getDb()
      .prepare(
        `INSERT INTO assessment_attempts
           (id, assessment_id, question_id, answer, correct, time_spent_ms, feedback)
         VALUES (?,?,?,?,?,?,?)`,
      )
      .run(
        `att_${crypto.randomUUID().slice(0, 8)}`,
        assessmentId,
        questionId,
        answer,
        correct ? 1 : 0,
        timeMs,
        feedback ?? null,
      );
  }

  finalize(assessmentId: string, score: number) {
    getDb()
      .prepare(`UPDATE assessments SET score = ?, completed_at = ? WHERE id = ?`)
      .run(score, new Date().toISOString(), assessmentId);
  }

  getById(assessmentId: string): Assessment | undefined {
    const row = getDb()
      .prepare(`SELECT * FROM assessments WHERE id = ?`)
      .get(assessmentId) as Record<string, unknown> | undefined;
    if (!row) return undefined;
    let questions: AssessmentQuestionResult[] = [];
    try {
      questions = JSON.parse(String(row.questions_json)) as AssessmentQuestionResult[];
    } catch {
      questions = [];
    }
    return {
      id: String(row.id),
      sessionId: row.session_id ? String(row.session_id) : null,
      type: String(row.type) as Assessment["type"],
      questions,
    };
  }

  private getTopic(topicId: string): { name: string; goal: string } | undefined {
    const row = getDb()
      .prepare(`SELECT name, goal FROM topics WHERE id = ?`)
      .get(topicId) as Record<string, unknown> | undefined;
    return row
      ? { name: String(row.name), goal: String(row.goal) }
      : undefined;
  }
}
