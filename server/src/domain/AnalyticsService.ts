import { getDb } from "../db/connection.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { MASTERY_LEVELS, type MasteryLevel } from "@mindtree/types";

/**
 * §71: продуктовые метрики.
 * Основные метрики (см. спецификацию) оценивают реальный учебный прогресс,
 * а не активность (клики, сообщения, время в приложении).
 */
export interface TopicMetrics {
  topicId: string;
  topicName: string;
  currentLevel: MasteryLevel;
  targetLevel: MasteryLevel;
  goal: string;
  masteryReached: boolean;
  /** Learning Gain: уровень достигнутый относительно начального. 0..1 */
  learningGain: number;
  /** Learning Gain / Minute — прирост уровня на минуту полезного времени. */
  learningGainPerMinute: number;
  /** Mean mastery across studied concepts. */
  meanMastery: number;
  /** Immediate recall: точность по recall-вопросам финальных assessment. */
  immediateRecall: number;
  /** Delayed recall: точность по recall-вопросам, заданным после завершения сессии. */
  delayedRecall: number;
  /** Application accuracy: точность по application-вопросам. */
  applicationAccuracy: number;
  /** Transfer accuracy: точность по transfer-вопросам. */
  transferAccuracy: number;
  sessionCompletion: number;
  milestoneProgression: number;
  /** Time to Target Mastery (minutes), null если ещё не достигнуто. */
  timeToTargetMinutes: number | null;
  studyMinutes: number;
  conceptCount: number;
}

export interface AnalyticsSummary {
  topics: TopicMetrics[];
  totals: {
    completedSessions: number;
    totalSessions: number;
    sessionCompletion: number;
    milestonesCompleted: number;
    totalMilestones: number;
    milestoneProgression: number;
    studyMinutes: number;
    meanLearningGain: number;
  };
}

interface QuestionMeta {
  id: string;
  type?: string;
}

const LEVEL_INDEX = Object.fromEntries(MASTERY_LEVELS.map((l, i) => [l, i]));

export class AnalyticsService {
  private learnerModel = new LearnerModelService();

  topicMetrics(topicId: string): TopicMetrics | null {
    const db = getDb();
    const topic = db
      .prepare(`SELECT * FROM topics WHERE id = ?`)
      .get(topicId) as
      | { id: string; name: string; goal: string; target_level: string }
      | undefined;
    if (!topic) return null;

    const targetLevel = (topic.target_level || "basic_understanding") as MasteryLevel;
    const currentLevel = this.learnerModel.getCurrentLevel(topicId);
    const initialLevel = this.learnerModel.getInitialLevel(topicId);
    const profiles = this.learnerModel.getConceptProfiles(topicId);

    const meanMastery =
      profiles.length > 0
        ? profiles.reduce((s, p) => s + p.masteryScore, 0) / profiles.length
        : 0;

    const learningGain = LEVEL_INDEX[currentLevel] - LEVEL_INDEX[initialLevel];

    const studyMinutes = this.studyMinutesForTopic(topicId);
    const learningGainPerMinute =
      studyMinutes > 0 ? Math.max(0, learningGain) / (studyMinutes / 60) : 0;

    const accuracy = this.accuracyByType(topicId);
    const immediateRecall = accuracy.find((a) => a.type === "recall")?.accuracy ?? 0;
    const applicationAccuracy =
      accuracy.find((a) => a.type === "application")?.accuracy ?? 0;
    const transferAccuracy = accuracy.find((a) => a.type === "transfer")?.accuracy ?? 0;
    const delayedRecall = this.delayedRecall(topicId);

    const sessionCompletion = this.sessionCompletionForTopic(topicId);
    const milestoneProgression = this.milestoneProgressionForTopic(topicId);

    const timeToTargetMinutes = this.timeToTarget(topicId, targetLevel);

    return {
      topicId,
      topicName: topic.name,
      currentLevel,
      targetLevel,
      goal: topic.goal,
      masteryReached: LEVEL_INDEX[currentLevel] >= LEVEL_INDEX[targetLevel],
      learningGain: Math.max(0, learningGain),
      learningGainPerMinute,
      meanMastery,
      immediateRecall,
      delayedRecall,
      applicationAccuracy,
      transferAccuracy,
      sessionCompletion,
      milestoneProgression,
      timeToTargetMinutes,
      studyMinutes,
      conceptCount: profiles.length,
    };
  }

  summary(): AnalyticsSummary {
    const db = getDb();
    const topicIds = (
      db.prepare(`SELECT id FROM topics ORDER BY created_at DESC`).all() as Array<{ id: string }>
    ).map((r) => r.id);

    const topics = topicIds
      .map((id) => this.topicMetrics(id))
      .filter((t): t is TopicMetrics => t !== null);

    const sessions = db
      .prepare(`SELECT COUNT(*) AS total, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) AS completed FROM learning_sessions`)
      .get() as { total: number; completed: number };
    const milestones = db
      .prepare(
        `SELECT COUNT(*) AS total, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) AS completed FROM learning_milestones`,
      )
      .get() as { total: number; completed: number };

    const studyMinutes = topics.reduce((s, t) => s + t.studyMinutes, 0);

    return {
      topics,
      totals: {
        completedSessions: Number(sessions.completed || 0),
        totalSessions: Number(sessions.total || 0),
        sessionCompletion:
          Number(sessions.total || 0) > 0
            ? Number(sessions.completed || 0) / Number(sessions.total)
            : 0,
        milestonesCompleted: Number(milestones.completed || 0),
        totalMilestones: Number(milestones.total || 0),
        milestoneProgression:
          Number(milestones.total || 0) > 0
            ? Number(milestones.completed || 0) / Number(milestones.total)
            : 0,
        studyMinutes,
        meanLearningGain:
          topics.length > 0
            ? topics.reduce((s, t) => s + t.learningGain, 0) / topics.length
            : 0,
      },
    };
  }

  private studyMinutesForTopic(topicId: string): number {
    const db = getDb();
    const topicStart = db
      .prepare(
        `SELECT MIN(started_at) AS first FROM learning_sessions WHERE topic_id = ?`,
      )
      .get(topicId) as { first?: string };

    const events = db
      .prepare(
        `SELECT SUM(duration_ms) AS total
           FROM learning_events e
           JOIN learning_sessions s ON s.id = e.session_id
          WHERE s.topic_id = ?`,
      )
      .get(topicId) as { total?: number };
    let minutes = Math.round((Number(events.total || 0) / 60000) * 10) / 10;

    // If no duration events, approximate from session span (capped).
    if (minutes === 0 && topicStart?.first) {
      const now = Date.now();
      const start = new Date(topicStart.first).getTime();
      minutes = Math.round(((now - start) / 60000) / 10) / 10;
      const sessions = db
        .prepare(`SELECT COUNT(*) AS n FROM learning_sessions WHERE topic_id = ?`)
        .get(topicId) as { n: number };
      minutes = Math.min(minutes, Number(sessions.n || 1) * 60);
    }
    return minutes;
  }

  /**
   * Immediate accuracy by question type across assessments (final + quiz + diagnostic).
   */
  private accuracyByType(topicId: string): Array<{ type: string; accuracy: number }> {
    const db = getDb();
    const assessments = db
      .prepare(
        `SELECT a.id, a.questions_json, a.type AS atype
           FROM assessments a
           LEFT JOIN learning_sessions s ON s.id = a.session_id
          WHERE s.topic_id = ? OR a.type IS NOT NULL`,
      )
      .all(topicId) as Array<{ id: string; questions_json: string; atype: string }>;

    const byType: Record<string, { correct: number; total: number }> = {};

    for (const a of assessments) {
      const questions = this.parseQuestions(a.questions_json);
      const attempts = db
        .prepare(`SELECT question_id, correct FROM assessment_attempts WHERE assessment_id = ?`)
        .all(a.id) as Array<{ question_id: string; correct: number }>;

      for (const att of attempts) {
        const q = questions.find((qq) => qq.id === att.question_id);
        const type = q?.type ?? "recall";
        const bucket = byType[type] ?? { correct: 0, total: 0 };
        bucket.correct += att.correct === 1 ? 1 : 0;
        bucket.total += 1;
        byType[type] = bucket;
      }
    }

    return Object.entries(byType).map(([type, v]) => ({
      type,
      accuracy: v.total > 0 ? v.correct / v.total : 0,
    }));
  }

  /**
   * Delayed recall: accuracy of recall questions that were asked via quiz/review
   * after the study session's final assessment was completed.
   */
  private delayedRecall(topicId: string): number {
    const db = getDb();
    // Approximate: use quiz assessments (type != 'final') recall accuracy.
    const rows = db
      .prepare(
        `SELECT a.id, a.type, a.questions_json
           FROM assessments a
           LEFT JOIN learning_sessions s ON s.id = a.session_id
          WHERE s.topic_id = ?`,
      )
      .all(topicId) as Array<{ id: string; type: string; questions_json: string }>;

    let correct = 0;
    let total = 0;
    for (const a of rows) {
      if (a.type === "final") continue;
      const questions = this.parseQuestions(a.questions_json);
      const attempts = db
        .prepare(`SELECT question_id, correct FROM assessment_attempts WHERE assessment_id = ?`)
        .all(a.id) as Array<{ question_id: string; correct: number }>;
      for (const att of attempts) {
        const q = questions.find((qq) => qq.id === att.question_id);
        if ((q?.type ?? "recall") !== "recall") continue;
        correct += att.correct === 1 ? 1 : 0;
        total += 1;
      }
    }
    return total > 0 ? correct / total : 0;
  }

  private sessionCompletionForTopic(topicId: string): number {
    const db = getDb();
    const row = db
      .prepare(
        `SELECT COUNT(*) AS total, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) AS completed
           FROM learning_sessions WHERE topic_id = ?`,
      )
      .get(topicId) as { total: number; completed: number };
    return Number(row.total || 0) > 0 ? Number(row.completed || 0) / Number(row.total) : 0;
  }

  private milestoneProgressionForTopic(topicId: string): number {
    const db = getDb();
    const row = db
      .prepare(
        `SELECT COUNT(*) AS total, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) AS completed
           FROM learning_milestones
          WHERE journey_id IN (SELECT id FROM learning_journeys WHERE topic_id = ?)`,
      )
      .get(topicId) as { total: number; completed: number };
    return Number(row.total || 0) > 0 ? Number(row.completed || 0) / Number(row.total) : 0;
  }

  private timeToTarget(topicId: string, target: MasteryLevel): number | null {
    const db = getDb();
    const current = this.learnerModel.getCurrentLevel(topicId);
    if (LEVEL_INDEX[current] < LEVEL_INDEX[target]) return null;

    const first = db
      .prepare(
        `SELECT MIN(started_at) AS first, MIN(completed_at) AS completed
           FROM learning_sessions WHERE topic_id = ?`,
      )
      .get(topicId) as { first?: string; completed?: string };

    const anchor = first?.first ? new Date(first.first).getTime() : Date.now();
    const end = first?.completed ? new Date(first.completed).getTime() : Date.now();
    return Math.max(0, Math.round((end - anchor) / 60000));
  }

  private parseQuestions(json: string): QuestionMeta[] {
    try {
      const data = JSON.parse(json);
      return Array.isArray(data) ? (data as QuestionMeta[]) : [];
    } catch {
      return [];
    }
  }
}
