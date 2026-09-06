import { describe, it, expect, beforeEach } from "vitest";
import { AnalyticsService } from "../AnalyticsService.js";
import { LearnerModelService } from "../LearnerModelService.js";
import { getDb } from "../../db/connection.js";
import { seedTopic, seedJourney } from "../../test/helpers.js";

describe("AnalyticsService", () => {
  const topicId = "top_test_an";
  const journeyId = "jr_test_an";
  const sessionId = "ss_test_an";

  beforeEach(() => {
    const db = getDb();
    db.prepare("DELETE FROM assessment_attempts").run();
    db.prepare("DELETE FROM assessments").run();
    db.prepare("DELETE FROM learner_models").run();
    db.prepare("DELETE FROM learning_events").run();
    db.prepare("DELETE FROM learning_sessions").run();
    db.prepare("DELETE FROM learning_milestones").run();
    db.prepare("DELETE FROM learning_journeys").run();
    db.prepare("DELETE FROM topics").run();
    seedTopic(topicId, "Analytics Topic", { target_level: "solid_understanding" });
    seedJourney(journeyId, topicId);
  });

  it("возвращает нулевые метрики для темы без данных", () => {
    const svc = new AnalyticsService();
    const m = svc.topicMetrics(topicId);
    expect(m).not.toBeNull();
    expect(m!.masteryReached).toBe(false);
    expect(m!.learningGain).toBe(0);
    expect(m!.conceptCount).toBe(0);
    expect(m!.meanMastery).toBe(0);
    expect(m!.sessionCompletion).toBe(0);
  });

  it("корректно считает learning gain от уровня до цели", () => {
    const learner = new LearnerModelService();
    learner.setOverallLevel(topicId, "expert");
    // initial level по умолчанию awareness
    const svc = new AnalyticsService();
    const m = svc.topicMetrics(topicId);
    expect(m!.currentLevel).toBe("expert");
    expect(m!.masteryReached).toBe(true);
    // expert=5, awareness=0 → gain 5 (clamped ≥0)
    expect(m!.learningGain).toBe(5);
  });

  it("считает точность по типам из assessment_attempts и session completion", () => {
    const db = getDb();

    db.prepare(
      `INSERT INTO learning_sessions
         (id, journey_id, topic_id, goal, status)
       VALUES (?, ?, ?, 'overview', 'completed')`,
    ).run(sessionId, journeyId, topicId);

    db.prepare(
      `INSERT INTO assessments (id, session_id, type, questions_json, score)
       VALUES ('as1', ?, 'final', ?, 1)`,
    ).run(
      sessionId,
      JSON.stringify([
        { id: "q1", type: "recall" },
        { id: "q2", type: "application" },
        { id: "q3", type: "transfer" },
      ]),
    );

    db.prepare(
      `INSERT INTO assessment_attempts (id, assessment_id, question_id, answer, correct)
       VALUES ('t1', 'as1', 'q1', '', 1), ('t2', 'as1', 'q2', '', 0), ('t3', 'as1', 'q3', '', 1)`,
    ).run();

    const svc = new AnalyticsService();
    const m = svc.topicMetrics(topicId);
    expect(m!.immediateRecall).toBe(1);
    expect(m!.applicationAccuracy).toBe(0);
    expect(m!.transferAccuracy).toBe(1);
    expect(m!.sessionCompletion).toBe(1);
  });

  it("сводка агрегирует по всем темам", () => {
    const svc = new AnalyticsService();
    const s = svc.summary();
    expect(s.topics.some((t) => t.topicId === topicId)).toBe(true);
    expect(s.totals.totalMilestones).toBe(0);
    expect(s.totals.totalSessions).toBe(0);
  });
});
