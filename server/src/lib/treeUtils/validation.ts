import { knowledgeNodeSchema, type KnowledgeNode } from "@mindtree/types";

export function sanitizeNodes(nodes: unknown[]): KnowledgeNode[] {
  const valid: KnowledgeNode[] = [];
  const seen = new Set<string>();

  for (const raw of nodes) {
    try {
      const node = knowledgeNodeSchema.parse(raw);
      if (seen.has(node.id)) continue;
      seen.add(node.id);
      valid.push(node);
    } catch {
      // skip invalid node
    }
  }

  return valid;
}

export function validateTreeShape(nodes: KnowledgeNode[]): boolean {
  if (nodes.length === 0) return false;
  const ids = new Set(nodes.map((n) => n.id));
  const roots = nodes.filter((n) => !n.parentId);
  if (roots.length !== 1) return false;

  // every parentId must reference an existing node
  for (const n of nodes) {
    if (n.parentId && !ids.has(n.parentId)) return false;
  }

  // no cycles
  const visited = new Set<string>();
  const inStack = new Set<string>();
  const byId = new Map(nodes.map((n) => [n.id, n]));

  const dfs = (id: string): boolean => {
    if (inStack.has(id)) return false;
    if (visited.has(id)) return true;
    inStack.add(id);
    visited.add(id);
    const node = byId.get(id);
    if (node?.parentId && !dfs(node.parentId)) return false;
    inStack.delete(id);
    return true;
  };

  for (const n of nodes) {
    if (!dfs(n.id)) return false;
  }

  return true;
}
