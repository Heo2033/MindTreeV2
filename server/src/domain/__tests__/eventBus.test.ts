import { describe, it, expect, beforeEach } from "vitest";
import { EventBus } from "../EventBus.js";
import { getDb } from "../../db/connection.js";
import { seedTopic, seedJourney } from "../../test/helpers.js";

/**
 * Регрессии на `learning_events`:
 * - `id` обязан писаться явно (колонка `TEXT PRIMARY KEY` без NOT NULL, и
 *   SQLite молча подставлял NULL, если её не указать в INSERT);
 * - вид события (`type`) не должен теряться — сервер пишет `kind` как есть,
 *   в отличие от Flutter-версии, где он сначала проходил через enum.
 */
describe("EventBus learning_events", () => {
  const topicId = "top_test_ev";
  const sessionId = "ss_test_ev";

  beforeEach(() => {
    const db = getDb();
    db.prepare("DELETE FROM learning_events").run();
    db.prepare("DELETE FROM learning_sessions").run();
    db.prepare("DELETE FROM learning_journeys").run();
    db.prepare("DELETE FROM topics").run();
    seedTopic(topicId, "Events Topic");
    seedJourney("jr_test_ev", topicId);
    db.prepare(
      `INSERT INTO learning_sessions (id, journey_id, topic_id, started_at)
       VALUES (?, ?, ?, ?)`,
    ).run(sessionId, "jr_test_ev", topicId, new Date().toISOString());
  });

  const stored = (): Array<Record<string, unknown>> =>
    getDb().prepare(`SELECT * FROM learning_events WHERE session_id = ?`).all(sessionId) as Array<
      Record<string, unknown>
    >;

  it("emit пишет id события, а не NULL", () => {
    const id = EventBus.emit({ sessionId, topicId, kind: "explain" });
    expect(id).toBeTruthy();
    expect(id).toMatch(/^ev_/);

    const rows = stored();
    expect(rows).toHaveLength(1);
    expect(rows[0]!.id).toBe(id);
  });

  it("несколько событий подряд получают разные id", () => {
    const ids = new Set<string>();
    for (let i = 0; i < 50; i++) {
      ids.add(EventBus.emit({ sessionId, topicId, kind: "activity_answer" }));
    }
    expect(ids.size).toBe(50);
    expect(stored()).toHaveLength(50);
  });

  it("вид события сохраняется как есть, без схлопывания в explain", () => {
    const kinds = [
      "session_started",
      "explain",
      "item_completed",
      "assessment",
      "activity_started",
      "activity_answer",
      "activity_step_done",
    ] as const;
    for (const kind of kinds) EventBus.emit({ sessionId, topicId, kind });

    const storedKinds = new Set(stored().map((r) => r.type));
    expect([...storedKinds].sort()).toEqual([...kinds].sort());
  });

  it("recent фильтрует по виду события и не смешивает", () => {
    for (const kind of ["explain", "session_started", "activity_answer"] as const) {
      EventBus.emit({ sessionId, topicId, kind });
    }

    expect(EventBus.recent(topicId, ["explain"]).map((e) => e.type)).toEqual(["explain"]);
    expect(EventBus.recent(topicId, ["session_started"]).map((e) => e.type)).toEqual([
      "session_started",
    ]);
    expect(EventBus.recent(topicId, ["activity_answer"]).map((e) => e.type)).toEqual([
      "activity_answer",
    ]);
  });
});
