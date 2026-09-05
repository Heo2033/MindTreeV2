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
  targetLevel: string | null;
  nodes: KnowledgeNode[];
  visibleLevel: number;
  /** id узлов, чьи дети принудительно показаны (поузловое раскрытие). */
  revealedNodes: Set<string>;
  loading: boolean;
  error: string | null;
  pipeline: PipelineState;
  loadTopic: (id: string) => Promise<void>;
  generateTree: (query: string, goal?: string, level?: string, timeBudgetMinutes?: number) => Promise<boolean>;
  /** Раскрыть детей (если есть) или сгенерировать следующий уровень (если лист). */
  revealNode: (nodeId: string) => Promise<boolean>;
  expandNode: (nodeId: string) => Promise<boolean>;
  generateContent: (nodeId: string) => Promise<void>;
  /** Автоматически расширить visibleLevel на 1 и сгенерировать детей для новых листьев. */
  autoExpandVisible: () => Promise<boolean>;
  setGoal: (goal: string) => void;
  resetVisibility: () => void;
  clear: () => void;
}

const idlePipeline = (): PipelineState => ({
  phase: "",
  message: "",
  stats: null,
  status: "idle",
});

/**
 * Максимальный видимый уровень узлов в зависимости от target_level.
 * Структура генерируется целиком, но пользователю показываются только уровни,
 * уместные для его целевого уровня знаний. Остальные раскрываются по запросу.
 */
export function maxVisibleLevelForTarget(targetLevel?: string | null): number {
  switch (targetLevel) {
    case "awareness":
    case "basic_understanding":
      return 2;
    case "solid_understanding":
    case "practical_application":
    case "advanced":
    case "expert":
      return 3;
    default:
      return 3;
  }
}

/**
 * Виден ли узел: его уровень ниже базовой границы ИЛИ у него есть предок,
 * который пользователь раскрыл вручную (revealedNodes).
 */
export function isNodeVisible(
  node: KnowledgeNode,
  nodes: KnowledgeNode[],
  visibleLevel: number,
  revealedNodes: Set<string>,
): boolean {
  if (node.level <= visibleLevel) return true;
  // Поднимаемся по предкам: если хоть один из них раскрыт — узел виден.
  const byId = new Map(nodes.map((n) => [n.id, n]));
  let cur: KnowledgeNode | undefined = node;
  let guard = 0;
  while (cur && guard < 50) {
    if (revealedNodes.has(cur.id)) return true;
    cur = cur.parentId ? byId.get(cur.parentId) : undefined;
    guard++;
  }
  return false;
}

export const useGraphStore = create<GraphState>((set, get) => ({
  topicId: null,
  topicName: null,
  goal: null,
  targetLevel: null,
  nodes: [],
  visibleLevel: 3,
  revealedNodes: new Set<string>(),
  loading: false,
  error: null,
  pipeline: idlePipeline(),

  async loadTopic(id) {
    set({ loading: true, error: null });
    try {
      const { topic, nodes: rows } = await topicsApi.get(id);
      const visibleLevel = maxVisibleLevelForTarget(topic.target_level);
      set({
        topicId: id,
        topicName: topic.name,
        goal: topic.goal,
        targetLevel: topic.target_level,
        visibleLevel,
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
          // Перезагружаем частичное (уже сохранённое) дерево, чтобы видеть
          // прогресс генерации по уровням.
          await get().loadTopic(topicId);
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
        } else if (ev.event === "error" || ev.event === "__error__") {
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
      // Поток завершился без явного done-фрейма (EOF/обрыв соединения).
      // Состояние pipeline ОБЯЗАНО уйти из "running", иначе экран «зависнет»
      // на оверлее построения. Если в БД уже есть узлы — считаем дерево
      // построенным (инкрементальный персист уже сохранил их), иначе — ошибка.
      const eofCheck = await topicsApi.get(topicId);
      if ((eofCheck.nodes ?? []).length === 0) {
        const msg = "Соединение прервано: дерево не было построено";
        set({
          pipeline: { ...idlePipeline(), status: "error", message: msg },
          error: msg,
        });
        return false;
      }
      set({ pipeline: { ...idlePipeline(), status: "done", message: "Дерево построено" } });
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Ошибка генерации";
      set({ pipeline: { ...idlePipeline(), status: "error", message: msg }, error: msg });
      return false;
    }
  },

  /**
   * «Углубить»:
   * - если у узла уже есть дети (в т.ч. скрытые) — раскрываем их мгновенно;
   * - если узел — настоящий лист без детей — генерируем следующий уровень через LLM.
   * Возвращает true, если что-то добавилось/раскрылось, false — если больше нечего.
   */
  async revealNode(nodeId) {
    const { nodes, revealedNodes } = get();
    const node = nodes.find((n) => n.id === nodeId);
    if (!node) return false;

    const hasChildren = nodes.some((n) => n.parentId === nodeId);

    if (hasChildren) {
      // Мгновенное раскрытие уже существующих детей.
      const next = new Set(revealedNodes);
      next.add(nodeId);
      set({ revealedNodes: next });
      return true;
    }

    // Настоящий лист — генерируем реальный следующий уровень.
    return get().expandNode(nodeId);
  },

  async expandNode(nodeId) {
    const { topicId, topicName } = get();
    if (!topicId) return false;
    set({ error: null });
    try {
      set({
        pipeline: {
          phase: "expand",
          message: "Генерирую следующий уровень…",
          stats: null,
          status: "running",
        },
      });
      const res = await treeApi.expand(topicId, nodeId);
      await get().loadTopic(topicId);
      set({ pipeline: idlePipeline() });
      void topicName;
      const count = typeof res.count === "number" ? res.count : 0;
      return count > 0;
    } catch (err) {
      set({ pipeline: idlePipeline(), error: err instanceof Error ? err.message : "Ошибка расширения узла" });
      return false;
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

  async autoExpandVisible() {
    const { topicId, nodes, visibleLevel } = get();
    if (!topicId) return false;
    const MAX_DEPTH = 5;
    if (visibleLevel >= MAX_DEPTH) return false;

    const newLevel = visibleLevel + 1;
    set({
      visibleLevel: newLevel,
      pipeline: { phase: "expand", message: "Расширяем дерево…", stats: null, status: "running" },
      error: null,
    });

    // Находим листья на новом уровне (без детей в БД)
    const leavesAtNewLevel = nodes.filter(
      (n) => n.level === newLevel && !nodes.some((c) => c.parentId === n.id),
    );

    let expanded = false;
    for (const leaf of leavesAtNewLevel.slice(0, 6)) {
      try {
        const res = await treeApi.expand(topicId, leaf.id);
        if (typeof res.count === "number" && res.count > 0) expanded = true;
      } catch {
        // пропускаем неудачные расширения
      }
    }

    await get().loadTopic(topicId);
    set({ pipeline: idlePipeline() });
    return expanded;
  },

  clear() {
    set({
      topicId: null,
      topicName: null,
      goal: null,
      targetLevel: null,
      nodes: [],
      visibleLevel: 3,
      revealedNodes: new Set<string>(),
      error: null,
      pipeline: idlePipeline(),
    });
  },

  setGoal(goal: string) {
    set({ goal });
  },

  resetVisibility() {
    const { targetLevel } = get();
    set({ visibleLevel: maxVisibleLevelForTarget(targetLevel), revealedNodes: new Set<string>() });
  },
}));
