import { describe, it, expect } from "vitest";
import { CurriculumEngine, scorePriority } from "../CurriculumEngine.js";
import type { CurriculumItem, KnowledgeNode } from "@mindtree/types";

describe("scorePriority (§20: goal_relevance × prerequisite_value × importance ÷ time)", () => {
  it("растёт при большей важности и падает при большем времени", () => {
    const low = scorePriority(0.5, 0.5, 0.3, 20);
    const high = scorePriority(0.5, 0.5, 0.9, 5);
    expect(high).toBeGreaterThan(low);
  });

  it("приоритет выше у понятия, от которого зависят другие", () => {
    const withPrePrereq = scorePriority(0.5, 1, 0.5, 10);
    const withoutPrereq = scorePriority(0.5, 0, 0.5, 10);
    expect(withPrePrereq).toBeGreaterThan(withoutPrereq);
  });

  it("всегда >= 1 (не нулевой, чтобы никого не исключать случайно)", () => {
    expect(scorePriority(0, 0, 0, 200)).toBeGreaterThanOrEqual(1);
  });
});

describe("CurriculumEngine.validate (§63: prereq → dependent ordering)", () => {
  function node(id: string, label: string, rels: Array<{ type: string; from: string; to: string }>): KnowledgeNode {
    return {
      id,
      label,
      relations: rels,
    } as unknown as KnowledgeNode;
  }

  const nodes: KnowledgeNode[] = [
    node("a", "A", []),
    node("b", "B", [{ type: "depends_on", from: "b", to: "a" }]),
    node("c", "C", [{ type: "requires", from: "c", to: "b" }]),
  ];

  function item(nodeId: string, order: number): CurriculumItem {
    return {
      id: `ci_${nodeId}`,
      nodeId,
      order,
      type: "explain",
      estimatedMinutes: 5,
      priority: 1,
      status: "pending",
    } as CurriculumItem;
  }

  it("не находит проблем, когда порядок корректный (a → b → c)", () => {
    const engine = new CurriculumEngine({} as never);
    const issues = engine.validate(
      [item("a", 0), item("b", 1), item("c", 2)],
      nodes,
    );
    expect(issues).toEqual([]);
  });

  it("находит проблему, когда dependent идёт раньше prerequisite", () => {
    const engine = new CurriculumEngine({} as never);
    const issues = engine.validate(
      [item("c", 0), item("b", 1), item("a", 2)],
      nodes,
    );
    expect(issues.length).toBeGreaterThan(0);
  });
});
