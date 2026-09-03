import { create } from "zustand";
import type { KnowledgeNode } from "@mindtree/types";
import { topicsApi, treeApi, pipelineApi } from "../api";
import type { KnowledgeNodeRow, TreeGenProgress } from "../api";
import { rowsToKnowledgeNodes } from "../graph/mapping";

interface PipelineState {
  phase: string;
  message: string;
  stats: { total: number; depth: number; leaves: number } | null;
  status: "idle" | "running" | "done" | "error";
}

interface GraphState {
  topicId: string | null;
  topicName: string | null;
  goal: string | null;
  nodes: KnowledgeNode[];
  loading: boolean;
  error: string | null;
  pipeline: PipelineState;
  loadTopic: (id: string) => Promise<void>;
  generateTree: (query: string, goal?: string, level?: string, timeBudgetMinutes?: number) => Promise<boolean>;
  expandNode: (nodeId: string) => Promise<void>;
  generateContent: (nodeId: string) => Promise<void>;
  setGoal: (goal: string) => void;
  clear: () => void;
}

const idlePipeline = (): PipelineState => ({
  phase: "",
  message: "",
  stats: null,
  status: "idle",
});

export const useGraphStore = create<GraphState>((set, get) => ({
  topicId: null,
  topicName: null,
  goal: null,
  nodes: [],
  loading: false,
  error: null,
  pipeline: idlePipeline(),

  async loadTopic(id) {
    set({ loading: true, error: null });
    try {
      const { topic, nodes: rows } = await topicsApi.get(id);
      set({
        topicId: id,
        topicName: topic.name,
        goal: topic.goal,
        nodes: rowsToKnowledgeNodes(rows as KnowledgeNodeRow[]),
        loading: false,
      });
    } catch (err) {
      set({
        error: err instanceof Error ? err.message : "Ошибка загрузки темы",
        loading: false,
      });
    }
  },

  async generateTree(query, goal, level, timeBudgetMinutes) {
    const { topicId } = get();
    if (!topicId) return false;
    set({
      pipeline: { ...idlePipeline(), status: "running", message: "Начинаю построение дерева…" },
      error: null,
    });

    const stream = pipelineApi.generate({
      topic_id: topicId,
      query,
      goal,
      level,
      time_budget_minutes: timeBudgetMinutes,
    });
    try {
      for await (const ev of stream.events) {
        if (ev.event === "progress") {
          const p = ev.data as TreeGenProgress;
          set({
            pipeline: {
              phase: p.phase,
              message: p.message,
              stats: p.stats ?? null,
              status: "running",
            },
          });
        } else if (ev.event === "done") {
          set({
            pipeline: { phase: "done", message: "Дерево построено", stats: null, status: "done" },
          });
          await get().loadTopic(topicId);
          return true;
        } else if (ev.event === "error") {
          const msg =
            typeof ev.data === "object" && ev.data && "message" in (ev.data as object)
              ? String((ev.data as { message: unknown }).message)
              : "Ошибка генерации";
          set({
            pipeline: { ...idlePipeline(), status: "error", message: msg },
            error: msg,
          });
          return false;
        }
      }
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Ошибка генерации";
      set({ pipeline: { ...idlePipeline(), status: "error", message: msg }, error: msg });
      return false;
    }
  },

  async expandNode(nodeId) {
    const { topicId, topicName } = get();
    if (!topicId) return;
    set({ error: null });
    try {
      set({
        pipeline: {
          phase: "expand",
          message: "Углубляю узел — строю поддерево…",
          stats: null,
          status: "running",
        },
      });
      await treeApi.expand(topicId, nodeId);
      await get().loadTopic(topicId);
      set({ pipeline: idlePipeline() });
      void topicName;
    } catch (err) {
      set({ pipeline: idlePipeline(), error: err instanceof Error ? err.message : "Ошибка расширения узла" });
    }
  },

  async generateContent(nodeId) {
    const { topicId } = get();
    if (!topicId) return;
    set({ error: null });
    try {
      set({
        pipeline: {
          phase: "content",
          message: "Генерирую контент узла…",
          stats: null,
          status: "running",
        },
      });
      await treeApi.content(topicId, nodeId);
      await get().loadTopic(topicId);
      set({ pipeline: idlePipeline() });
    } catch (err) {
      set({ pipeline: idlePipeline(), error: err instanceof Error ? err.message : "Ошибка генерации контента" });
    }
  },

  clear() {
    set({
      topicId: null,
      topicName: null,
      goal: null,
      nodes: [],
      error: null,
      pipeline: idlePipeline(),
    });
  },

  setGoal(goal: string) {
    set({ goal });
  },
}));
