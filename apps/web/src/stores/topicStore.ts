import { create } from "zustand";
import { topicsApi } from "../api";
import type { TopicRow } from "../api";

interface TopicState {
  topics: TopicRow[];
  loading: boolean;
  error: string | null;
  loadTopics: () => Promise<void>;
  createTopic: (body: {
    name: string;
    goal?: string;
    target_level?: string;
    time_budget_minutes?: number;
  }) => Promise<TopicRow>;
  removeTopic: (id: string) => Promise<void>;
}

export const useTopicStore = create<TopicState>((set, get) => ({
  topics: [],
  loading: false,
  error: null,

  async loadTopics() {
    set({ loading: true, error: null });
    try {
      const topics = await topicsApi.list();
      set({ topics, loading: false });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка загрузки тем", loading: false });
    }
  },

  async createTopic(body) {
    const topic = await topicsApi.create(body);
    set({ topics: [topic, ...get().topics] });
    return topic;
  },

  async removeTopic(id) {
    try {
      await topicsApi.remove(id);
      set({ topics: get().topics.filter((t) => t.id !== id), error: null });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка удаления темы" });
    }
  },
}));
