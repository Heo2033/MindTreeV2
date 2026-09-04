import { describe, it, expect } from "vitest";
import type { KnowledgeNode } from "@mindtree/types";
import { convertTreeToGraphFlow, cardSize, getEdgeHandles } from "./layout.js";

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

  it("назначает L2-узлам цвета веток и наследует их потомкам", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "b", parentId: "root", level: 2 }),
      node({ id: "a1", parentId: "a", level: 3 }),
      node({ id: "a2", parentId: "a", level: 3 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    const colorOf = (id: string) =>
      (flow.nodes.find((n) => n.id === id)!.data as { branchColor?: string })
        .branchColor;
    const colorA = colorOf("a");
    const colorB = colorOf("b");
    expect(colorA).toBeTruthy();
    expect(colorB).toBeTruthy();
    expect(colorA).not.toBe(colorB);
    // Потомки наследуют цвет своего L2-предка.
    expect(colorOf("a1")).toBe(colorA);
    expect(colorOf("a2")).toBe(colorA);
  });

  it("компактные L3+ получают позиции (не крашат layout)", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "x1", parentId: "a", level: 3 }),
      node({ id: "x2", parentId: "a", level: 3 }),
      node({ id: "x3", parentId: "a", level: 3 }),
      node({ id: "x4", parentId: "a", level: 3 }),
      node({ id: "x5", parentId: "a", level: 3 }),
      node({ id: "x6", parentId: "a", level: 3 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    expect(flow.edges.filter((e) => e.data.kind === "hierarchy").length).toBe(7);
    for (const id of ["root", "a", "x1", "x2", "x3", "x4", "x5", "x6"]) {
      const n = flow.nodes.find((n) => n.id === id)!;
      expect(typeof n.position.x).toBe("number");
      expect(typeof n.position.y).toBe("number");
    }
  });

  it("корень в центре, L3 раскладываются вокруг своего L2 (локальный центр)", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "b", parentId: "root", level: 2 }),
      node({ id: "a1", parentId: "a", level: 3 }),
      node({ id: "a2", parentId: "a", level: 3 }),
      node({ id: "a3", parentId: "a", level: 3 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    const pos = (id: string) => flow.nodes.find((n) => n.id === id)!.position;
    // Корень в центре.
    expect(pos("root").x).toBe(0);
    expect(pos("root").y).toBe(0);
    // L2 на одинаковом радиус-расстоянии от центра (равномерный круг).
    const ra = Math.hypot(pos("a").x, pos("a").y);
    const rb = Math.hypot(pos("b").x, pos("b").y);
    expect(Math.abs(ra - rb)).toBeLessThan(1);
    // Регрессия: L3 листья одного L2 НЕ в одной точке (разные углы/позиции).
    expect(pos("a1").x).not.toBe(pos("a2").x);
    expect(pos("a2").x).not.toBe(pos("a3").x);
    // L3 рядом со своим L2 (много ближе, чем к глобальному центру).
    const distToA = Math.hypot(pos("a1").x - pos("a").x, pos("a1").y - pos("a").y);
    const distToRoot = Math.hypot(pos("a1").x, pos("a1").y);
    expect(distToA).toBeLessThan(distToRoot);
  });

  it("L2 равномерно распределены по всей окружности (не в одном полукруге)", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
    ];
    for (let i = 0; i < 8; i++) {
      tree.push(node({ id: `l2_${i}`, parentId: "root", level: 2 }));
    }
    const flow = convertTreeToGraphFlow(tree);
    const angles = flow.nodes
      .filter((n) => n.id !== "root")
      .map((n) => Math.atan2(n.position.y, n.position.x));
    // Сортируем углы и проверяем, что они покрывают весь круг равномерно.
    angles.sort((p, q) => p - q);
    const gaps: number[] = [];
    for (let i = 0; i < angles.length; i++) {
      const next = angles[(i + 1) % angles.length] + (i === angles.length - 1 ? Math.PI * 2 : 0);
      gaps.push(next - angles[i]);
    }
    const maxGap = Math.max(...gaps);
    // Равномерное распределение без образования полукруговой плотности.
    expect(maxGap).toBeLessThan(Math.PI * 0.5);
  });

  it("радиус кольца L2 растёт с числом веток", () => {
    const build = (n: number) => {
      const t: KnowledgeNode[] = [node({ id: "root", parentId: undefined, level: 1 })];
      for (let i = 0; i < n; i++) t.push(node({ id: `l2_${i}`, parentId: "root", level: 2 }));
      return t;
    };
    const small = convertTreeToGraphFlow(build(3));
    const big = convertTreeToGraphFlow(build(11));
    const rSmall = Math.hypot(
      small.nodes.find((n) => n.id === "l2_0")!.position.x,
      small.nodes.find((n) => n.id === "l2_0")!.position.y,
    );
    const rBig = Math.hypot(
      big.nodes.find((n) => n.id === "l2_0")!.position.x,
      big.nodes.find((n) => n.id === "l2_0")!.position.y,
    );
    expect(rBig).toBeGreaterThan(rSmall);
  });

  it("максимум 12 L2-направлений: не крашится при большом числе L2", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
    ];
    for (let i = 0; i < 14; i++) {
      tree.push(node({ id: `l2_${i}`, parentId: "root", level: 2 }));
    }
    const flow = convertTreeToGraphFlow(tree);
    expect(flow.nodes.length).toBe(15);
    for (const n of flow.nodes) {
      expect(typeof n.position.x).toBe("number");
    }
    // Все L2 расходятся от центра (ненулевой радиус).
    for (let i = 0; i < 14; i++) {
      const p = flow.nodes.find((n) => n.id === `l2_${i}`)!.position;
      expect(Math.hypot(p.x, p.y)).toBeGreaterThan(100);
    }
  });

  it("L3-листья одного L2 разнесены (не в одной точке и не дублируют позиции)", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "a1", parentId: "a", level: 3 }),
      node({ id: "a2", parentId: "a", level: 3 }),
      node({ id: "a3", parentId: "a", level: 3 }),
      node({ id: "a4", parentId: "a", level: 3 }),
      node({ id: "a5", parentId: "a", level: 3 }),
      node({ id: "a6", parentId: "a", level: 3 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    const pos = (id: string) => flow.nodes.find((n) => n.id === id)!.position;
    const keys = ["a1", "a2", "a3", "a4", "a5", "a6"];
    const sig = new Set(keys.map((k) => `${pos(k).x.toFixed(2)},${pos(k).y.toFixed(2)}`));
    // Все позиции уникальны — листья разведены.
    expect(sig.size).toBe(keys.length);
    // Листья не наложены друг на друга (попарное расстояние > минимум).
    for (let i = 0; i < keys.length; i++) {
      for (let j = i + 1; j < keys.length; j++) {
        const d = Math.hypot(
          pos(keys[i]).x - pos(keys[j]).x,
          pos(keys[i]).y - pos(keys[j]).y,
        );
        expect(d).toBeGreaterThan(30);
      }
    }
  });

  it("ширина компактной карточки растёт с длиной label", () => {
    expect(cardSize(3, "короткое")).toEqual(cardSize(3, "короткое"));
    const short = cardSize(3, "Ток").w;
    const long = cardSize(3, "Очень длинное название понятия").w;
    expect(long).toBeGreaterThan(short);
    // Одинаковый label даёт одинаковый размер (layout предсказуем).
  });

  it("L3-листья одного L2 лежат на одной окружности (общий радиус) с равными шагами", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "a1", parentId: "a", level: 3, label: "Альфа" }),
      node({ id: "a2", parentId: "a", level: 3, label: "Бета длинная" }),
      node({ id: "a3", parentId: "a", level: 3, label: "Гамма" }),
      node({ id: "a4", parentId: "a", level: 3, label: "Дельта длиннее" }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    const pos = (id: string) => flow.nodes.find((n) => n.id === id)!.position;
    const a = pos("a");
    const keys = ["a1", "a2", "a3", "a4"];
    const radii = keys.map((k) => Math.hypot(pos(k).x - a.x, pos(k).y - a.y));
    // Один и тот же радиус — общая окружность группы (разброс < 0.01).
    const minR = Math.min(...radii);
    const maxR = Math.max(...radii);
    expect(maxR - minR).toBeLessThan(0.01);
    // Равные угловые шаги между соседними листьями.
    const angles = keys
      .map((k) => Math.atan2(pos(k).y - a.y, pos(k).x - a.x))
      .sort((x, y) => x - y);
    // Соседние разности углов (учитывая переход через ±π) близки к 2π/4.
    let prev = angles[angles.length - 1] - Math.PI * 2;
    for (const th of angles) {
      const gap = th - prev;
      expect(gap).toBeGreaterThan(0.9 * (Math.PI * 2) / keys.length);
      expect(gap).toBeLessThan(1.1 * (Math.PI * 2) / keys.length);
      prev = th;
    }
  });

  it("равномерный веер применяется и на глубине (L4 вокруг L3)", () => {
    const tree: KnowledgeNode[] = [
      node({ id: "root", parentId: undefined, level: 1 }),
      node({ id: "a", parentId: "root", level: 2 }),
      node({ id: "b", parentId: "a", level: 3 }),
      node({ id: "b1", parentId: "b", level: 4 }),
      node({ id: "b2", parentId: "b", level: 4 }),
      node({ id: "b3", parentId: "b", level: 4 }),
    ];
    const flow = convertTreeToGraphFlow(tree);
    const pos = (id: string) => flow.nodes.find((n) => n.id === id)!.position;
    const b = pos("b");
    const keys = ["b1", "b2", "b3"];
    const radii = keys.map((k) => Math.hypot(pos(k).x - b.x, pos(k).y - b.y));
    const minR = Math.min(...radii);
    const maxR = Math.max(...radii);
    expect(maxR - minR).toBeLessThan(0.01);
    const angles = keys
      .map((k) => Math.atan2(pos(k).y - b.y, pos(k).x - b.x))
      .sort((x, y) => x - y);
    let prev = angles[angles.length - 1] - Math.PI * 2;
    for (const th of angles) {
      const gap = th - prev;
      expect(gap).toBeGreaterThan(0.9 * (Math.PI * 2) / keys.length);
      expect(gap).toBeLessThan(1.1 * (Math.PI * 2) / keys.length);
      prev = th;
    }
  });
});

describe("getEdgeHandles", () => {
  it("угловой лист (в сторону больше, чем вверх) идёт в боковую сторону", () => {
    // Лист справа-вверх, но смещение по X больше Y → right (из левого в правое).
    expect(getEdgeHandles(0, 0, 200, -100)).toEqual({
      sourceHandle: "right",
      targetHandle: "left",
    });
    // Слева-вверх, смещение по X больше → left.
    expect(getEdgeHandles(0, 0, -200, -100)).toEqual({
      sourceHandle: "left",
      targetHandle: "right",
    });
  });

  it("диагональ ровно 45° (|dx|≈|dy|) — горизонталь, а не вертикаль", () => {
    expect(getEdgeHandles(0, 0, 100, -100)).toEqual({
      sourceHandle: "right",
      targetHandle: "left",
    });
  });

  it("лист строго над корнем (по вертикали дальше) — верхняя сторона", () => {
    expect(getEdgeHandles(0, 0, 30, -200)).toEqual({
      sourceHandle: "top",
      targetHandle: "bottom",
    });
    expect(getEdgeHandles(0, 0, 30, 200)).toEqual({
      sourceHandle: "bottom",
      targetHandle: "top",
    });
  });
});
