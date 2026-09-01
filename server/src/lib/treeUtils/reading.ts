import type { KnowledgeNode } from "@mindtree/types";

export function buildChildrenMap(nodes: KnowledgeNode[]): Map<string, KnowledgeNode[]> {
  const map = new Map<string, KnowledgeNode[]>();
  for (const node of nodes) {
    if (!node.parentId) continue;
    const arr = map.get(node.parentId) ?? [];
    arr.push(node);
    map.set(node.parentId, arr);
  }
  return map;
}

export function readingOrder(nodes: KnowledgeNode[]): KnowledgeNode[] {
  const childrenMap = buildChildrenMap(nodes);
  const roots = nodes
    .filter((n) => !n.parentId)
    .sort((a, b) => a.level - b.level);

  const result: KnowledgeNode[] = [];
  const visit = (node: KnowledgeNode) => {
    result.push(node);
    const children = childrenMap.get(node.id) ?? [];
    children.sort((a, b) => a.estimatedTimeMinutes - b.estimatedTimeMinutes);
    for (const child of children) visit(child);
  };

  for (const root of roots) visit(root);
  return result;
}

export function buildToc(nodes: KnowledgeNode[]): Array<{ id: string; label: string; level: number; children: string[] }> {
  const childrenMap = buildChildrenMap(nodes);
  return nodes
    .filter((n) => n.level === 1 || n.level === 2)
    .map((n) => ({
      id: n.id,
      label: n.label,
      level: n.level,
      children: (childrenMap.get(n.id) ?? []).map((c) => c.id),
    }));
}

export function branchProgress(nodes: KnowledgeNode[]): Map<string, number> {
  const childrenMap = buildChildrenMap(nodes);
  const progress = new Map<string, number>();
  const leafCounts = new Map<string, number>();
  const masteredCounts = new Map<string, number>();

  const count = (nodeId: string): { total: number; mastered: number } => {
    if (leafCounts.has(nodeId)) {
      return {
        total: leafCounts.get(nodeId)!,
        mastered: masteredCounts.get(nodeId)!,
      };
    }
    const node = nodes.find((n) => n.id === nodeId)!;
    const children = childrenMap.get(nodeId) ?? [];

    if (children.length === 0) {
      const total = node.importance > 0 ? 1 : 0;
      const mastered = node.state === "content_generated" ? 1 : 0;
      leafCounts.set(nodeId, total);
      masteredCounts.set(nodeId, mastered);
      return { total, mastered };
    }

    let total = 0;
    let mastered = 0;
    for (const child of children) {
      const c = count(child.id);
      total += c.total;
      mastered += c.mastered;
    }
    leafCounts.set(nodeId, total);
    masteredCounts.set(nodeId, mastered);
    return { total, mastered };
  };

  for (const node of nodes) {
    const c = count(node.id);
    progress.set(node.id, c.total > 0 ? c.mastered / c.total : 0);
  }
  return progress;
}

export function nodePath(nodes: KnowledgeNode[], nodeId: string): string[] {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const path: string[] = [];
  let current = byId.get(nodeId);
  let guard = 0;
  while (current && guard < 50) {
    path.unshift(current.label);
    current = current.parentId ? byId.get(current.parentId) : undefined;
    guard++;
  }
  return path;
}

export function collectDescendantIds(nodes: KnowledgeNode[], nodeId: string): string[] {
  const childrenMap = buildChildrenMap(nodes);
  const result: string[] = [];
  const stack = [...(childrenMap.get(nodeId) ?? [])];
  while (stack.length > 0) {
    const node = stack.pop()!;
    result.push(node.id);
    stack.push(...(childrenMap.get(node.id) ?? []));
  }
  return result;
}
