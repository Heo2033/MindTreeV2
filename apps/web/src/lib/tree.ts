import type { KnowledgeNode } from "@mindtree/types";

export const MAX_DEPTH = 5;

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

export function rootsOf(nodes: KnowledgeNode[]): KnowledgeNode[] {
  return nodes.filter((n) => !n.parentId).sort((a, b) => a.level - b.level);
}

export function readingOrder(nodes: KnowledgeNode[]): KnowledgeNode[] {
  const childrenMap = buildChildrenMap(nodes);
  const result: KnowledgeNode[] = [];
  const visit = (node: KnowledgeNode) => {
    result.push(node);
    const children = childrenMap.get(node.id) ?? [];
    children.sort((a, b) => a.estimatedTimeMinutes - b.estimatedTimeMinutes);
    for (const child of children) visit(child);
  };
  for (const root of rootsOf(nodes)) visit(root);
  return result;
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

export function canDeepen(node: KnowledgeNode): boolean {
  return node.level < MAX_DEPTH && !node.leaf;
}

export function branchProgress(
  nodes: KnowledgeNode[],
  branchNodeId: string,
): { done: number; total: number } {
  const childrenMap = buildChildrenMap(nodes);
  const done = new Set<string>();
  const total = new Set<string>();
  const visit = (id: string) => {
    const children = childrenMap.get(id) ?? [];
    if (children.length === 0) {
      total.add(id);
      const node = nodes.find((n) => n.id === id);
      if (node && (node.contentLoaded || node.state === "content_generated")) done.add(id);
      return;
    }
    for (const c of children) visit(c.id);
  };
  visit(branchNodeId);
  return { done: done.size, total: total.size };
}
