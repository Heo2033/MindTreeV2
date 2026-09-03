import { describe, it, expect } from "vitest";
import type { KnowledgeNode } from "@mindtree/types";
import { convertTreeToGraphFlow } from "./layout.js";

function node(
  partial: Partial<Omit<KnowledgeNode, "parentId">> & { id: string } & {
    parentId?: string | null;
  },
): KnowledgeNode {
  return {
    id: partial.id,
    topicId: "topic_t",
    parentId: partial.parentId ?? null,
    level: partial.level ?? 2,
    label: partial.label ?? partial.id,
    oneLiner: partial.oneLiner ?? "",
    details: partial.details ?? "",
    importance: partial.importance ?? 0.5,
    difficulty: partial.difficulty ?? 0.5,
    estimatedTimeMinutes: partial.estimatedTimeMinutes ?? 5,
    state: partial.state ?? "new",
    contentLoaded: false,
    leaf: partial.leaf ?? false,
    relations: partial.relations ?? [],
    sequences: partial.sequences ?? [],
  };
}

describe("convertTreeToGraphFlow", () => {
  it("не бросает исключение на дереве без корней (все узлы-сироты)", () => {
    // Все узлы ссылаются на отсутствующий parentId n1_root — корней нет.
    const tree: KnowledgeNode[] = [
      node({ id: "n2_periods", parentId: "n1_root", level: 2 }),
      node({ id: "n3_directions", parentId: "n1_root", level: 2 }),
      node({ id: "n4_consequences", parentId: "n1_root", level: 2 }),
    ];
    let flow;
    expect(() => {
      flow = convertTreeToGraphFlow(tree);
    }).not.toThrow();
    expect(flow!.nodes.length).toBe(3);
    // Рёбра иерархии к отсутствующему родителю пропускаются (не крашат).
    expect(flow!.edges.length).toBe(0);
  });

  it("возвращает позиции для каждого узла на повреждённом дереве", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "a", parentId: "missing", level: 2 }),
      node({ id: "b", parentId: "missing", level: 2 }),
      node({ id: "c", parentId: "missing", level: 3 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    for (const n of flow.nodes) {
      expect(typeof n.position.x).toBe("number");
      expect(typeof n.position.y).toBe("number");
    }
  });

  it("корректно строит рёбра на корректном дереве с корнем", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "child1", parentId: "root", level: 2 }),
      node({ id: "child2", parentId: "root", level: 2 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    expect(flow.nodes.length).toBe(3);
    const hierarchy = flow.edges.filter((e) => e.data.kind === "hierarchy");
    expect(hierarchy.length).toBe(2);
  });
});
