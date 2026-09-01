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

const NODE_W = 210;
const NODE_H = 56;
const NODE_GAP = 42;
const RING_STEP = NODE_H + 42;
const MIN_RING_RADIUS = 130;

export interface GraphPosition {
  x: number;
  y: number;
}

export interface GraphFlowNode {
  id: string;
  type?: string;
  position: GraphPosition;
  data: { node: KnowledgeNode };
}

export interface GraphFlowEdge {
  id: string;
  source: string;
  target: string;
  sourceHandle?: string;
  targetHandle?: string;
  data:
    | { kind: "hierarchy" }
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

  if (absDy > absDx * 0.5) {
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
 * Радиальный (орбитальный) layout:
 *  — корень в центре;
 *  — каждый уровень — кольцо, радиус зависит от числа узлов на уровне
 *    (гарантирует, что по окружности помещаются все карточки без наложений);
 *  — каждый узел занимает угловой сектор, пропорциональный размеру своего
 *    поддерева, с минимальной шириной сектора для карточки;
 *  — ветки упорядочены по порядку детей (без «стягивания» листьев в одну точку).
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
  if (roots.length === 0) return result;

  // Уровни и их радиусы: по числу узлов на уровне, с учётом минимального роста колец.
  const levels = new Map<number, string[]>();
  for (const n of tree) {
    if (!levels.has(n.level)) levels.set(n.level, []);
    levels.get(n.level)!.push(n.id);
  }
  const sortedLevels = [...levels.keys()].sort((a, b) => a - b);

  const ringRadius = new Map<number, number>();
  let prevR = 0;
  for (const lv of sortedLevels) {
    if (lv <= 1) {
      ringRadius.set(lv, 0);
      prevR = MIN_RING_RADIUS;
      continue;
    }
    const count = levels.get(lv)!.length;
    const fit = count <= 1 ? 0 : (count * (NODE_W + NODE_GAP)) / TAU;
    const r = Math.max(prevR + RING_STEP, fit);
    ringRadius.set(lv, r);
    prevR = r;
  }

  const minArc = (lv: number): number => {
    if (lv <= 1) return 0;
    const r = ringRadius.get(lv) ?? MIN_RING_RADIUS;
    return (NODE_W + NODE_GAP) / r;
  };

  // Нижний проход: минимальная угловая ширина сектора каждой ветки (в радианах).
  const needRad = new Map<string, number>();
  const computeNeed = (id: string): number => {
    const node = byId.get(id)!;
    const kids = childrenOf.get(id) ?? [];
    const own = minArc(node.level);
    if (kids.length === 0) {
      needRad.set(id, own);
      return own;
    }
    let sum = 0;
    for (const k of kids) sum += computeNeed(k);
    const need = Math.max(own, sum);
    needRad.set(id, need);
    return need;
  };
  let totalSpan = 0;
  for (const r of roots) totalSpan += computeNeed(r);

  // Если суммарная ширина веток превышает полный круг — увеличиваем радиусы колец,
  // чтобы «сжать» минимальные секторы и уложить всё в один оборот.
  if (totalSpan > TAU) {
    const k = totalSpan / TAU;
    for (const lv of sortedLevels) {
      const r = ringRadius.get(lv) ?? 0;
      if (r > 0) ringRadius.set(lv, r * k);
    }
    needRad.clear();
    totalSpan = 0;
    for (const r of roots) totalSpan += computeNeed(r);
  }

  // Верхний проход: точные секторы [start, end] для каждого узла.
  const angle = new Map<string, { start: number; end: number }>();

  const assign = (id: string, start: number, end: number): void => {
    angle.set(id, { start, end });
    const kids = childrenOf.get(id) ?? [];
    if (kids.length === 0) return;
let sum = 0;
    for (const k of kids) sum += needRad.get(k) ?? 0;
    const span = end - start;
    const denom = sum || 1;
    let cursor = start;
    for (const k of kids) {
      const w = needRad.get(k) ?? 0;
      const childEnd = cursor + (span * w) / denom;
      assign(k, cursor, childEnd);
      cursor = childEnd;
    }
  };

  let cursor = 0;
  for (const r of roots) {
    const w = needRad.get(r) ?? 0;
    const total = totalSpan || TAU;
    const end = cursor + (2 * Math.PI * w) / total;
    assign(r, cursor, end);
    cursor = end;
  }

  // Позиции из срединных углов секторов.
  for (const [id, { start, end }] of angle) {
    const node = byId.get(id)!;
    const r = ringRadius.get(node.level) ?? 0;
    const theta = (start + end) / 2;
    result.set(id, { x: r * Math.cos(theta), y: r * Math.sin(theta) });
  }

  return result;
}

export function convertTreeToGraphFlow(tree: KnowledgeNode[]): GraphFlow {
  const positions = computeRadialPositions(tree);

  const flowNodes: GraphFlowNode[] = tree.map((node) => ({
    id: node.id,
    type: "mindNode",
    position: positions.get(node.id) ?? { x: 0, y: 0 },
    data: { node },
  }));

  const flowEdges: GraphFlowEdge[] = [];
  const existingIds = new Set<string>();
  const nodeIds = new Set(tree.map((n) => n.id));

  for (const n of tree) {
    if (!n.parentId) continue;
    const sp = positions.get(n.parentId)!;
    const tp = positions.get(n.id)!;
    const handles = getEdgeHandles(sp.x, sp.y, tp.x, tp.y);
    flowEdges.push({
      id: `${n.parentId}-${n.id}`,
      source: n.parentId,
      target: n.id,
      sourceHandle: handles.sourceHandle,
      targetHandle: handles.targetHandle,
      data: { kind: "hierarchy" },
    });
    existingIds.add(`${n.parentId}-${n.id}`);
  }

  for (const node of tree) {
    if (!node.relations) continue;
    for (const rel of node.relations) {
      if (!nodeIds.has(rel.from) || !nodeIds.has(rel.to)) continue;
      const eid = `rel:${rel.from}-${rel.to}`;
      if (existingIds.has(eid)) continue;
      existingIds.add(eid);
      const sp = positions.get(rel.from)!;
      const tp = positions.get(rel.to)!;
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