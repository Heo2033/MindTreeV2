import { beforeEach, describe, expect, it, vi } from "vitest";
import { useTopicStore } from "./topicStore";

const { topicsApi } = vi.hoisted(() => ({
  topicsApi: {
    list: vi.fn(),
    create: vi.fn(),
    remove: vi.fn(),
  },
}));

vi.mock("../api", () => ({ topicsApi }));

beforeEach(() => {
  topicsApi.remove.mockReset();
  useTopicStore.setState({
    topics: [
      { id: "t1", name: "Тема 1", goal: "overview", time_budget_minutes: 60, target_level: "basic", created_at: "2026-01-01T00:00:00.000Z" },
      { id: "t2", name: "Тема 2", goal: "deep", time_budget_minutes: 90, target_level: "advanced", created_at: "2026-01-02T00:00:00.000Z" },
    ],
    error: null,
  });
});

describe("useTopicStore.removeTopic", () => {
  it("при успехе удаляет тему из списка и очищает ошибку", async () => {
    topicsApi.remove.mockResolvedValue({ ok: true });
    await useTopicStore.getState().removeTopic("t1");
    expect(topicsApi.remove).toHaveBeenCalledWith("t1");
    expect(useTopicStore.getState().topics.map((t) => t.id)).toEqual(["t2"]);
    expect(useTopicStore.getState().error).toBeNull();
  });

  it("при ошибке не трогает список и пишет сообщение в error", async () => {
    topicsApi.remove.mockRejectedValue(new Error("LLM сервер недоступен"));
    await useTopicStore.getState().removeTopic("t1");
    expect(useTopicStore.getState().topics.map((t) => t.id)).toEqual(["t1", "t2"]);
    expect(useTopicStore.getState().error).toBe("LLM сервер недоступен");
  });
});