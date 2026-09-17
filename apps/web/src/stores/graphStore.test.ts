import { describe, expect, it } from "vitest";
import type { KnowledgeNode } from "@mindtree/types";
import {
  decorateLLMError,
  isNodeVisible,
  nodeHasHiddenChildren,
  maxVisibleLevelForTarget,
} from "./graphStore";

function node(
  id: string,
  level: number,
  parentId: string | null = null,
): KnowledgeNode {
  return {
    id,
    topicId: "t1",
    parentId,
    level,
    label: id,
    oneLiner: "",
    details: "",
    importance: 0.5,
    difficulty: 0.5,
    estimatedTimeMinutes: 5,
    state: "valid",
    contentLoaded: false,
    leaf: false,
    relations: [],
    sequences: [],
  };
}

describe("isNodeVisible", () => {
  it("показывает узлы внутри базового visibleLevel", () => {
    const root = node("root", 1);
    const child = node("child", 2, "root");
    const nodes = [root, child];
    expect(isNodeVisible(root, nodes, 2, new Set())).toBe(true);
    expect(isNodeVisible(child, nodes, 2, new Set())).toBe(true);
  });

  it("скрывает узлы глубже visibleLevel без раскрытия", () => {
    const root = node("root", 1);
    const a = node("a", 2, "root");
    const b = node("b", 3, "a");
    const nodes = [root, a, b];
    expect(isNodeVisible(b, nodes, 2, new Set())).toBe(false);
  });

  it("показывает потомков, если предок раскрыт", () => {
    const root = node("root", 1);
    const a = node("a", 2, "root");
    const b = node("b", 3, "a");
    const nodes = [root, a, b];
    expect(isNodeVisible(b, nodes, 2, new Set(["root"]))).toBe(true);
  });
});

describe("nodeHasHiddenChildren", () => {
  const root = node("root", 1);
  const l2a = node("a", 2, "root");
  const l2b = node("b", 2, "root");
  const l3 = node("l3", 3, "a");

  it("true, если есть скрытые потомки глубже visibleLevel", () => {
    const nodes = [root, l2a, l2b, l3];
    expect(nodeHasHiddenChildren(root, nodes, 2, new Set())).toBe(true);
  });

  it("false, если всё поддерево уже видно", () => {
    const nodes = [root, l2a, l2b, l3];
    // root раскрыт → l3 виден через предка.
    expect(nodeHasHiddenChildren(root, nodes, 2, new Set(["root"]))).toBe(false);
    // visibleLevel = 3 → всё видно и без раскрытия.
    expect(nodeHasHiddenChildren(root, nodes, 3, new Set())).toBe(false);
  });

  it("false, если у узла вообще нет потомков", () => {
    const nodes = [root, l2a, l2b, l3];
    expect(nodeHasHiddenChildren(l3, nodes, 2, new Set())).toBe(false);
  });

  it("корень с только видимыми детьми — нечего раскрывать", () => {
    const rootOnly = [root, l2a, l2b];
    expect(nodeHasHiddenChildren(root, rootOnly, 2, new Set())).toBe(false);
  });
});

describe("maxVisibleLevelForTarget", () => {
  it("базовые цели показывают 2 уровня", () => {
    expect(maxVisibleLevelForTarget("awareness")).toBe(2);
    expect(maxVisibleLevelForTarget("basic_understanding")).toBe(2);
  });

  it("глубокие цели показывают 3 уровня", () => {
    expect(maxVisibleLevelForTarget("solid_understanding")).toBe(3);
    expect(maxVisibleLevelForTarget("expert")).toBe(3);
  });
});

describe("decorateLLMError", () => {
  it("добавляет подсказку про ключ для 401/Incorrect API key", () => {
    const decorated = decorateLLMError("LLM API ошибка (401): Incorrect API key provided");
    expect(decorated).toContain("проверьте API-ключ в Настройках");
    expect(decorated).toContain("Incorrect API key");
  });

  it("не трогает обычные транспортные/иные ошибки", () => {
    expect(decorateLLMError("Соединение прервано: дерево не было завершено")).toBe(
      "Соединение прервано: дерево не было завершено",
    );
    expect(decorateLLMError("Таймаут соединения с сервером")).toBe("Таймаут соединения с сервером");
  });
});