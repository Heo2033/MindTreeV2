import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { LearningSessionEngine } from "../LearningSessionEngine.js";
import { getDb } from "../../db/connection.js";
import { seedTopic, seedJourney } from "../../test/helpers.js";
import { LLMCache } from "../../llm/cache.js";
import { TreeScheduler } from "../../llm/scheduler.js";

vi.mock("../../llm/client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../llm/client.js")>();
  return { ...actual, callLLM: vi.fn() };
});

import { callLLM } from "../../llm/client.js";

const mockedCallLLM = vi.mocked(callLLM);

type GlobalStore = {
  __mindtree_scheduler__?: TreeScheduler;
  __mindtree_llm_cache__?: LLMCache;
};

beforeAll(() => {
  // Без ключа readLLMConfig() бросает «LLM_API_KEY не задан», а он вызывается
  // из getModelsForTier() на каждый execute. LLM_MOCK=1 — штатный офлайн-режим.
  vi.stubEnv("LLM_MOCK", "1");

  // LearningSessionEngine ходит в глобальный scheduler (getScheduler()). Подменяем
  // синглтон на экземпляр с высокими лимитами и maxRetries: 0, иначе тест упирается
  // в rate-limit и ждёт backoff.
  const store = globalThis as unknown as GlobalStore;
  store.__mindtree_llm_cache__ = new LLMCache({ persistDir: null });
  store.__mindtree_scheduler__ = new TreeScheduler(
    {
      maxRPM: 100000,
      maxRPD: 1000000,
      maxConcurrency: 1,
      maxRetries: 0,
      opDeadlineMs: 0,
    },
    store.__mindtree_llm_cache__,
  );
});

afterAll(() => {
  const store = globalThis as unknown as GlobalStore;
  delete store.__mindtree_scheduler__;
  delete store.__mindtree_llm_cache__;
  vi.unstubAllEnvs();
});

function seedNode(id: string, topicId: string, label: string): void {
  getDb()
    .prepare(
      `INSERT INTO knowledge_nodes (id, topic_id, label, one_liner, state, content_loaded, leaf, level)
       VALUES (?, ?, ?, ?, 'contentGenerated', 1, 1, 1)`,
    )
    .run(id, topicId, label, `${label}: короткое описание`);
}

function journeysFor(topicId: string): { id: string }[] {
  return getDb()
    .prepare(`SELECT id FROM learning_journeys WHERE topic_id = ? ORDER BY created_at DESC`)
    .all(topicId) as { id: string }[];
}

describe("LearningSessionEngine.create: journey на тему единственный", () => {
  const topicId = "top_jr_uniq";

  beforeEach(() => {
    const db = getDb();
    db.prepare("DELETE FROM learning_sessions").run();
    db.prepare("DELETE FROM learning_milestones").run();
    db.prepare("DELETE FROM learning_journeys").run();
    db.prepare("DELETE FROM knowledge_nodes").run();
    db.prepare("DELETE FROM topics").run();
    mockedCallLLM.mockReset();
    // Пустой список items — детерминированный curriculum без сетевых вызовов.
    mockedCallLLM.mockResolvedValue({
      text: JSON.stringify({ items: [] }),
      usage: { input_tokens: 10, output_tokens: 10 },
    });
  });

  // Раньше journey создавался безусловно при journeyId = null, поэтому каждая
  // сессия добавляла строку в learning_journeys. После двух сессий выбор journey
  // по topic_id отдавал две строки — в Flutter это роняло экран «Прогресс»
  // с «Bad state: Too many elements».
  it("РЕГРЕСС: две сессии одной темы не плодят две journey", async () => {
    seedTopic(topicId, "Journey Topic");
    seedNode("kn_jr_uniq_1", topicId, "Узел один");

    const engine = new LearningSessionEngine();
    const first = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
    });
    const second = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
    });

    const journeys = journeysFor(topicId);
    expect(journeys).toHaveLength(1);
    expect(second.journeyId).toBe(first.journeyId);
    // Сессии при этом остаются разными — потеря прогресса быть не должно.
    expect(second.id).not.toBe(first.id);
  });

  it("РЕГРЕСС: явный journeyId не создаёт journey", async () => {
    seedTopic(topicId, "Journey Topic");
    seedNode("kn_jr_uniq_2", topicId, "Узел два");
    seedJourney("jr_explicit", topicId);

    const engine = new LearningSessionEngine();
    const session = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
      journeyId: "jr_explicit",
    });

    // Ни новой journey, ни второй строки — явный id просто используется.
    expect(journeysFor(topicId).map((j) => j.id)).toEqual(["jr_explicit"]);
    expect(session.journeyId).toBe("jr_explicit");
  });

  it("РЕГРЕСС: journeyId из пустой строки считается отсутствующим", async () => {
    seedTopic(topicId, "Journey Topic");
    seedNode("kn_jr_uniq_3", topicId, "Узел три");

    const engine = new LearningSessionEngine();
    const first = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
      journeyId: "",
    });
    const second = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
      journeyId: "",
    });

    expect(journeysFor(topicId)).toHaveLength(1);
    expect(second.journeyId).toBe(first.journeyId);
  });

  it("разные темы получают разные journey", async () => {
    seedTopic(topicId, "Тема A");
    seedTopic("top_jr_uniq_2", "Тема B");
    seedNode("kn_jr_uniq_4", topicId, "Узел четыре");
    seedNode("kn_jr_uniq_5", "top_jr_uniq_2", "Узел пять");

    const engine = new LearningSessionEngine();
    const a = await engine.create({ topicId, goal: "overview", timeBudgetMinutes: 25 });
    const b = await engine.create({
      topicId: "top_jr_uniq_2",
      goal: "overview",
      timeBudgetMinutes: 25,
    });

    expect(a.journeyId).not.toBe(b.journeyId);
    expect(journeysFor(topicId)).toHaveLength(1);
    expect(journeysFor("top_jr_uniq_2")).toHaveLength(1);
  });

  it("существующая journey темы переиспользуется, а не создаётся заново", async () => {
    seedTopic(topicId, "Journey Topic");
    seedNode("kn_jr_uniq_6", topicId, "Узел шесть");
    getDb()
      .prepare(`INSERT INTO learning_journeys (id, topic_id) VALUES (?, ?)`)
      .run("jr_preexisting", topicId);

    const engine = new LearningSessionEngine();
    const session = await engine.create({
      topicId,
      goal: "overview",
      timeBudgetMinutes: 25,
    });

    expect(session.journeyId).toBe("jr_preexisting");
    expect(journeysFor(topicId).map((j) => j.id)).toEqual(["jr_preexisting"]);
  });
});
