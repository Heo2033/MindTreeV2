import type { KnowledgeNode, RelationType } from "@mindtree/types";

export const RELATION_COLORS: Record<RelationType, string> = {
  related: "#64748b",
  depends_on: "#3b82f6",
  requires: "#f97316",
  example_of: "#22c55e",
  similar_to: "#06b6d4",
  contrasts_with: "#ef4444",
  causes: "#a855f7",
  enables: "#14b8a6",
  used_for: "#eab308",
  alternative_to: "#ec4899",
};

const NODE_W = 200;
const NODE_H = 80;
const COMPACT_H = 34;
const NODE_GAP = 48;
const COMPACT_GAP = 16;

// Минимальный радиус кольца L2 (растёт с числом L2-веток).
const L2_RADIUS_MIN = (NODE_W + NODE_H) / 2 + 120;
// Минимальный локальный радиус раскрытия поддерева у узла (растёт с глубиной).
const SUB_R_BASE = 80;

// Ширина компактной карточки L3+ — динамически по длине label.
// Минимум достаточен для короткого названия; label растягивается на всю ширину.
function compactW(label: string): number {
  const textW = label ? label.length * 7 : 50;
  const w = 30 + textW;
  return Math.max(72, Math.min(300, w));
}

// Палитра цветов веток L2 (поддеревьев).
export const BRANCH_COLORS = [
  "#3b82f6", // blue
  "#ef4444", // red
  "#22c55e", // green
  "#f97316", // orange
  "#a855f7", // purple
  "#06b6d4", // cyan
  "#ec4899", // pink
  "#eab308", // yellow
  "#14b8a6", // teal
  "#8b5cf6", // indigo
];

// Уровневые размеры карточек: L1/L2 — полные, L3+ — компактные (ширина по label).
function nodeSize(level: number, label?: string): { w: number; h: number; gap: number } {
  return level >= 3
    ? { w: compactW(label ?? ""), h: COMPACT_H, gap: COMPACT_GAP }
    : { w: NODE_W, h: NODE_H, gap: NODE_GAP };
}

/** Экспортируемая версия для согласованности рендера (ReactFlow) с layout. */
export function cardSize(
  level: number,
  label?: string,
): { w: number; h: number } {
  const s = nodeSize(level, label);
  return { w: s.w, h: s.h };
}

export interface GraphPosition {
  x: number;
  y: number;
}

export interface GraphFlowNode {
  id: string;
  type?: string;
  position: GraphPosition;
  data: { node: KnowledgeNode; branchColor?: string };
}

export interface GraphFlowEdge {
  id: string;
  source: string;
  target: string;
  sourceHandle?: string;
  targetHandle?: string;
  data:
    | { kind: "hierarchy"; color?: string; sourceSize?: { w: number; h: number } }
    | { kind: "relation"; color: string; label: string };
}

export interface GraphFlow {
  nodes: GraphFlowNode[];
  edges: GraphFlowEdge[];
}

const TAU = Math.PI * 2;

export function getEdgeHandles(
  sx: number,
  sy: number,
  tx: number,
  ty: number,
): { sourceHandle: string; targetHandle: string } {
  const dx = tx - sx;
  const dy = ty - sy;
  const absDx = Math.abs(dx);
  const absDy = Math.abs(dy);

  // Сторона = ось максимального смещения: вертикаль только если лист дальше
  // по вертикали, чем по горизонтали (строгая доминанта). Угловой лист (~45°)
  // уходит в боковую сторону — «право корня в лево листа» для правого-верхнего.
  if (absDy > absDx) {
    if (dy > 0) {
      return { sourceHandle: "bottom", targetHandle: "top" };
    }
    return { sourceHandle: "top", targetHandle: "bottom" };
  }
  if (dx > 0) {
    return { sourceHandle: "right", targetHandle: "left" };
  }
  return { sourceHandle: "left", targetHandle: "right" };
}

/**
 * Вложенный вентиляторный layout:
 *  — корень в центре;
 *  — L2-узлы равномерно по окружности, радиус кольца растёт с их числом;
 *  — каждый узел уровня 3+ — локальный центр своей мини-карты, дети
 *    раскладываются вокруг него (вложенные радиальные вентиляторы), что
 *    устраняет «лесенку» от глобального центра;
 *  — ширина компактных карточек L3+ динамическая (по длине label).
 */

function computeRadialPositions(tree: KnowledgeNode[]): Map<string, GraphPosition> {
  const result = new Map<string, GraphPosition>();
  if (tree.length === 0) return result;

  const byId = new Map(tree.map((n) => [n.id, n]));
  const childrenOf = new Map<string, string[]>();
  for (const n of tree) {
    if (n.parentId) {
      if (!childrenOf.has(n.parentId)) childrenOf.set(n.parentId, []);
      childrenOf.get(n.parentId)!.push(n.id);
    }
  }

  const roots = tree.filter((n) => !n.parentId).map((n) => n.id);

  // Повреждённое дерево без корней: разбрасываем по уровням вокруг центра.
  if (roots.length === 0) {
    const byLevel = new Map<number, string[]>();
    for (const n of tree) {
      if (!byLevel.has(n.level)) byLevel.set(n.level, []);
      byLevel.get(n.level)!.push(n.id);
    }
    for (const [lv, ids] of byLevel) {
      const r = (lv - 1) * SUB_R_BASE * 1.6 + SUB_R_BASE;
      const total = ids.length || 1;
      ids.forEach((id, i) => {
        const theta = (i / total) * TAU;
        result.set(id, { x: r * Math.cos(theta), y: r * Math.sin(theta) });
      });
    }
    return result;
  }

  // Число детей, макс. ширина карточки и число листьев в поддереве каждого узла.
  const kidsCount = new Map<string, number>();
  const maxW = new Map<string, number>();
  const leafCount = new Map<string, number>();
  const computeSubtree = (id: string): { maxW: number; leaves: number } => {
    const node = byId.get(id)!;
    const kids = childrenOf.get(id) ?? [];
    kidsCount.set(id, kids.length);
    const own = nodeSize(node.level, node.label).w;
    if (kids.length === 0) {
      maxW.set(id, own);
      leafCount.set(id, 1);
      return { maxW: own, leaves: 1 };
    }
    let mw = own;
    let leaves = 0;
    for (const k of kids) {
      const sub = computeSubtree(k);
      mw = Math.max(mw, sub.maxW);
      leaves += sub.leaves;
    }
    maxW.set(id, mw);
    leafCount.set(id, leaves);
    return { maxW: mw, leaves };
  };
  for (const r of roots) computeSubtree(r);

  // Радиус, на котором сидят ВСЕ дети узла X (общая окружность группы).
  // Растёт с глубиной X, максимальной шириной карточки в его поддереве и
  // числом листьев — чтобы равные угловые секторы вмещали самую широкую метку.
  function groupRadius(lv: number, mw: number, leaves: number): number {
    // Запас, чтобы ближний край самой длинной карточки-потомка (полуширина mw/2)
    // не заезжал на родителя (полуширина NODE_W/2).
    const clearance = COMPACT_GAP + NODE_W / 2 + mw / 2;
    return Math.max(
      clearance,
      SUB_R_BASE + (lv - 2) * 40 + mw * 0.75 + (Math.max(leaves, 1) - 1) * 22,
    );
  }
  const radiusOf = (id: string): number => {
    const node = byId.get(id)!;
    return groupRadius(node.level, maxW.get(id) ?? 0, leafCount.get(id) ?? 1);
  };

  // Угловая потребность поддерева (радианы, видимые от родителя):
  // веер из leafCount карточек шириной до maxW на своей окружности radius(P).
  const needRad = new Map<string, number>();
  const computeNeed = (id: string): number => {
    const node = byId.get(id)!;
    const parent = node.parentId ? byId.get(node.parentId) : undefined;
    const rParent = parent ? radiusOf(parent.id) : radiusOf(id);
    const lc = leafCount.get(id) ?? 1;
    const mw = maxW.get(id) ?? 0;
    const own = nodeSize(node.level, node.label).w;
    const need = Math.max((own + COMPACT_GAP) / rParent, (lc * mw) / rParent);
    needRad.set(id, need);
    return need;
  };
  // ВАЖНО: заполняем needRad снизу вверх ДО раскладки, иначе секторы пусты
  // и все дети окажутся в одной точке.
  for (const r of roots) computeNeed(r);

  // Рекурсивная раскладка: ставит узел вокруг своего родителя и раскладывает
  // его детей равными угловыми шагами (общая окружность группы) в секторе [start, end].
  const place = (id: string, start: number, end: number): void => {
    const node = byId.get(id)!;
    const parent = node.parentId ? byId.get(node.parentId) : undefined;
    const kids = childrenOf.get(id) ?? [];
    const pp = parent ? result.get(parent.id) : undefined;

    if (pp && parent && node.level >= 3) {
      const r = radiusOf(parent.id);
      const theta = (start + end) / 2;
      // Общая окружность группы: все дети родителя — на одном радиусе.
      result.set(id, { x: pp.x + r * Math.cos(theta), y: pp.y + r * Math.sin(theta) });
    }

    if (kids.length === 0) return;
    const span = end - start;
    const K = kids.length;
    for (let i = 0; i < K; i++) {
      const cs = start + (span * i) / K;
      const ce = start + (span * (i + 1)) / K;
      place(kids[i], cs, ce);
    }
  };

  // Корень в центре.
  for (const r of roots) result.set(r, { x: 0, y: 0 });

  // L2-узлы равномерно по окружности; радиус кольца растёт с их числом.
  const l2nodes = tree
    .filter((n) => n.level === 2)
    .sort((a, b) => {
      const pa = a.parentId ?? "";
      const pb = b.parentId ?? "";
      if (pa !== pb) return pa.localeCompare(pb);
      return a.id.localeCompare(b.id);
    });

  const N = l2nodes.length;
  if (N > 0) {
    // Радиус кольца L2: минимум плюс на каждую ветку запас для карточки.
    const l2Radius = Math.max(L2_RADIUS_MIN, (N * (NODE_W + NODE_GAP)) / TAU);
    const sector = TAU / N;
    const baseTheta = (i: number) => (i + 0.5) * sector;
    // Сохраняем вычисленный L2-радиус для levelRadius(lv=2) при раскладке L3.
    l2nodes.forEach((n, i) => {
      const theta = baseTheta(i);
      const start = theta - sector / 2;
      const end = theta + sector / 2;
      // Ставим L2 явно (а не через place), т.к. его родитель — корень, радиус — l2Radius.
      result.set(n.id, {
        x: l2Radius * Math.cos(theta),
        y: l2Radius * Math.sin(theta),
      });
      place(n.id, start, end);
    });
  }

  return result;
}

export function convertTreeToGraphFlow(tree: KnowledgeNode[]): GraphFlow {
  const positions = computeRadialPositions(tree);

  // Назначаем цвет ветки каждому L2-узлу (по порядку) и наследуем его потомкам.
  const branchColor = new Map<string, string>();
  const byId = new Map(tree.map((n) => [n.id, n]));
  const childrenOf = new Map<string, string[]>();
  for (const n of tree) {
    if (n.parentId) {
      if (!childrenOf.has(n.parentId)) childrenOf.set(n.parentId, []);
      childrenOf.get(n.parentId)!.push(n.id);
    }
  }
  const l2nodes = tree
    .filter((n) => n.level === 2)
    .sort((a, b) => {
      const pa = a.parentId ?? "";
      const pb = b.parentId ?? "";
      if (pa !== pb) return pa.localeCompare(pb);
      return a.id.localeCompare(b.id);
    });
  l2nodes.forEach((n, i) => {
    const color = BRANCH_COLORS[i % BRANCH_COLORS.length];
    const stack = [n.id];
    while (stack.length) {
      const id = stack.pop()!;
      branchColor.set(id, color);
      for (const k of childrenOf.get(id) ?? []) stack.push(k);
    }
  });

  const flowNodes: GraphFlowNode[] = tree.map((node) => ({
    id: node.id,
    type: "mindNode",
    position: positions.get(node.id) ?? { x: 0, y: 0 },
    data: { node, branchColor: branchColor.get(node.id) },
  }));

  const flowEdges: GraphFlowEdge[] = [];
  const existingIds = new Set<string>();
  const nodeIds = new Set(tree.map((n) => n.id));

  for (const n of tree) {
    if (!n.parentId) continue;
    const sp = positions.get(n.parentId);
    const tp = positions.get(n.id);
    // Родитель/узел без позиции (битый parentId или сирота) — ребро пропускаем.
    if (!sp || !tp) continue;
    const parent = byId.get(n.parentId);
    const ps = parent ? nodeSize(parent.level, parent.label) : nodeSize(1);
    const handles = getEdgeHandles(sp.x, sp.y, tp.x, tp.y);
    flowEdges.push({
      id: `${n.parentId}-${n.id}`,
      source: n.parentId,
      target: n.id,
      sourceHandle: handles.sourceHandle,
      targetHandle: handles.targetHandle,
      data: {
        kind: "hierarchy",
        color: branchColor.get(n.id),
        sourceSize: { w: ps.w, h: ps.h },
      },
    });
    existingIds.add(`${n.parentId}-${n.id}`);
  }

  for (const node of tree) {
    if (!node.relations) continue;
    for (const rel of node.relations) {
      if (!nodeIds.has(rel.from) || !nodeIds.has(rel.to)) continue;
      const eid = `rel:${rel.from}-${rel.to}`;
      if (existingIds.has(eid)) continue;
      const sp = positions.get(rel.from);
      const tp = positions.get(rel.to);
      if (!sp || !tp) continue;
      existingIds.add(eid);
      const handles = getEdgeHandles(sp.x, sp.y, tp.x, tp.y);
      const color = RELATION_COLORS[rel.type] ?? "#64748b";
      flowEdges.push({
        id: eid,
        source: rel.from,
        target: rel.to,
        sourceHandle: handles.sourceHandle,
        targetHandle: handles.targetHandle,
        data: { kind: "relation", color, label: rel.label ?? rel.type },
      });
    }
  }

  return { nodes: flowNodes, edges: flowEdges };
}