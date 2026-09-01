export function normalizeTreeResponse(nodes: Array<Record<string, unknown>>): Array<{
  id: string;
  title: string;
  parentId: string | null;
  level: number;
  canonical_definition?: string;
  semantic_axis?: string;
  conceptType?: string;
  forbidden_interpretations?: string[];
}> {
  const byLevel = new Map<string, Array<Record<string, unknown>>>();

  for (const n of nodes) {
    const level = typeof n.level === "number" ? n.level : guessLevel(n, nodes);
    const arr = byLevel.get(String(level)) ?? [];
    arr.push({ ...n, level });
    byLevel.set(String(level), arr);
  }

  // sort by level to establish parent-child relations for levels missing explicit parentId
  const sorted = [...byLevel.entries()].sort((a, b) => Number(a[0]) - Number(b[0]));
  const levels: Array<Record<string, unknown>>[] = sorted.map(([, v]) => v);

  const parentsByLevel = new Map<number, Record<string, unknown> | null>();
  parentsByLevel.set(1, null);

  const result = nodes
    .slice()
    .sort((a, b) => (Number(a.level) || 0) - (Number(b.level) || 0))
    .map((n) => {
      const level = typeof n.level === "number" ? n.level : 1;
      return {
        id: String(n.id ?? ""),
        title: String(n.title ?? n.label ?? ""),
        parentId: n.parentId !== null && n.parentId !== undefined
          ? String(n.parentId)
          : null,
        level,
        canonical_definition:
          typeof n.canonical_definition === "string" ? n.canonical_definition : undefined,
        semantic_axis: typeof n.semantic_axis === "string" ? n.semantic_axis : undefined,
        conceptType: typeof n.conceptType === "string" ? n.conceptType : undefined,
        forbidden_interpretations: Array.isArray(n.forbidden_interpretations)
          ? (n.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
          : undefined,
      };
    });

  // Fix any node missing parentId (except root) by linking to previous level
  const fixed = result.map((n) => {
    if (n.parentId) return n;
    if (n.level <= 1) return { ...n, parentId: null };
    const parent = levels[n.level - 2]?.[0];
    return parent ? { ...n, parentId: String(parent.id) } : { ...n, parentId: null };
  });

  return fixed;
}

function guessLevel(n: Record<string, unknown>, all: Array<Record<string, unknown>>): number {
  if (n.parentId === null || n.parentId === undefined) return 1;
  const parent = all.find((p) => p.id === n.parentId);
  const parentLevel = parent
    ? typeof parent.level === "number"
      ? parent.level
      : parent.parentId
        ? 2
        : 1
    : 1;
  return parentLevel + 1;
}
