import { describe, it, expect, beforeEach } from "vitest";
import { buildApp, seedTopic, seedJourney } from "../../test/helpers.js";
import { getDb } from "../../db/connection.js";

describe("milestone CRUD routes", () => {
  const topicId = "top_test_ms";
  const journeyId = "jr_test_ms";

  beforeEach(() => {
    const db = getDb();
    db.prepare("DELETE FROM learning_milestones").run();
    db.prepare("DELETE FROM learning_journeys").run();
    db.prepare("DELETE FROM topics").run();
    seedTopic(topicId);
    seedJourney(journeyId, topicId);
  });

  it("создаёт веху и отдаёт её с разобранными полями", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: {
        journey_id: journeyId,
        level: "advanced",
        title: "Диагностика",
        description: "Умение ставить диагноз",
        capabilities: ["анализ", "синтез"],
        estimatedHours: 5,
      },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.milestone.id).toMatch(/^ms_/);
    expect(body.milestone.title).toBe("Диагностика");
    expect(body.milestone.level).toBe("advanced");
    expect(body.milestone.estimatedHours).toBe(5);
    expect(body.milestone.capabilities).toEqual(["анализ", "синтез"]);
    expect(body.milestone.status).toBe("not_started");
    await app.close();
  });

  it("требует journey_id и title", async () => {
    const app = await buildApp();
    const noJourney = await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: { title: "X" },
    });
    expect(noJourney.statusCode).toBe(400);
    const noTitle = await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: { journey_id: journeyId, title: "  " },
    });
    expect(noTitle.statusCode).toBe(400);
    await app.close();
  });

  it("маппит persisted JSON-колонки в объекты в GET /journey", async () => {
    const app = await buildApp();
    await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: {
        journey_id: journeyId,
        level: "advanced",
        title: "А",
        description: "d",
        capabilities: ["a", "b"],
        estimatedHours: 3,
      },
    });
    const res = await app.inject({ method: "GET", url: `/api/milestones/journey/${journeyId}` });
    expect(res.statusCode).toBe(200);
    const { milestones } = res.json();
    expect(milestones).toHaveLength(1);
    expect(milestones[0].capabilities).toEqual(["a", "b"]);
    expect(milestones[0].estimatedHours).toBe(3);
    expect(milestones[0].alternativePaths).toEqual([]);
    await app.close();
  });

  it("обновляет статус через PATCH", async () => {
    const app = await buildApp();
    const created = await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: { journey_id: journeyId, level: "advanced", title: "А" },
    });
    const mid = created.json().milestone.id;
    const patch = await app.inject({
      method: "PATCH",
      url: `/api/milestones/${mid}`,
      payload: { status: "active" },
    });
    expect(patch.statusCode).toBe(200);
    const list = await app.inject({ method: "GET", url: `/api/milestones/journey/${journeyId}` });
    expect(list.json().milestones[0].status).toBe("active");
    await app.close();
  });

  it("удаляет веху через DELETE", async () => {
    const app = await buildApp();
    const created = await app.inject({
      method: "POST",
      url: "/api/milestones/",
      payload: { journey_id: journeyId, level: "advanced", title: "А" },
    });
    const mid = created.json().milestone.id;
    const del = await app.inject({ method: "DELETE", url: `/api/milestones/${mid}` });
    expect(del.statusCode).toBe(200);
    expect(del.json().ok).toBe(true);
    const list = await app.inject({ method: "GET", url: `/api/milestones/journey/${journeyId}` });
    expect(list.json().milestones).toHaveLength(0);
    await app.close();
  });
});
