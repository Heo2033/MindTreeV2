import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_VALIDATE = `# Роль
Ты — эксперт по структуре знаний. Твоя задача — найти проблемы в дереве понятий.

# Задача
Проверь дерево знаний на следующие проблемы:

1. **DUPLICATE** — узлы, описывающие одно и то же понятие (разными словами или одинаково).
2. **OVERLAP** — узлы, которые слишком сильно пересекаются по содержанию.
3. **ABSTRACTION_MISMATCH** — узлы на одном уровне, находящиеся на разных уровнях абстракции.
4. **TAXONOMIC_INCONSISTENCY** — дети классифицируют родителя по разным логическим осям.
5. **COVERAGE** — пропущена крупная важная категория в рамках родителя.
6. **USELESS_CHILD** — у ребенка нет самостоятельной информационной ценности.
7. **SHOULD_BE_LEAF** — узел расширен, но дальнейшее дробление бессмысленно.
8. **LANGUAGE_VIOLATION** — label или one_liner содержат непереведенный английский текст.
9. **ONTOLOGY_VIOLATION** — узел противоречит своему canonical_definition.
10. **AXIS_MIXING** — узел смешивает semantic_axis (описывает архитектуру как процесс и т.д.).
11. **FORBIDDEN_INTERPRETATION** — узел использует запрещённую интерпретацию из forbidden_interpretations.
12. **SCOPE_ERROR** — условное утверждение превращено в абсолютное.
13. **CAUSAL_ERROR** — неверная причинно-следственная связь.
14. **MISSING_PREREQUISITE** — узел опирается (в relations/prerequisites) на понятие, которого нет в дереве, или мысль очевидно требует понятия, отсутствующего в предках.
15. **CIRCULAR_DEPENDENCY** — обнаружен цикл в связях requires/depends_on/enables.
16. **UNREALISTIC_TIMING** — суммарная оценка estimated_time_minutes одного узла или родителя с детьми выходит за разумные пределы (например, > 120 мин на узел).
17. **OVERLY_BROAD** — узел слишком глобален/расплывчат для своего уровня и его логично расширить на детей.
18. **IRRELEVANT** — узел не относится к теме/цели дерева.

${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (reason, missing_concepts) — только на русском.

# Формат ответа
Только валидный JSON-объект:
{
  "valid": true/false,
  "issues": [
    {"type": "DUPLICATE", "node_id": "id_узла", "reason": "описание проблемы"}
  ],
  "missing_concepts": [
    {"title": "название пропущенного понятия", "parent_id": "id_родительского_узла"}
  ],
  "should_expand": true/false
}

- valid = false, если есть хотя бы одна проблема из типов 1–13.
- should_expand = false, если дерево уже достаточно детализировано.
- missing_concepts — список пропущенных важных понятий.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Дерево для проверки
{{tree_json}}`;

export const DEFAULT_VALIDATE_LEAN_THRESHOLD = 100;

export function resolveLeanThreshold(): number {
  const raw = process.env.LLM_VALIDATE_LEAN_THRESHOLD;
  if (raw === undefined || raw.trim() === "") return DEFAULT_VALIDATE_LEAN_THRESHOLD;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 1 ? Math.floor(n) : DEFAULT_VALIDATE_LEAN_THRESHOLD;
}

export const VALIDATION_ISSUE_TYPES = [
  "DUPLICATE",
  "OVERLAP",
  "ABSTRACTION_MISMATCH",
  "TAXONOMIC_INCONSISTENCY",
  "COVERAGE",
  "USELESS_CHILD",
  "SHOULD_BE_LEAF",
  "LANGUAGE_VIOLATION",
  "ONTOLOGY_VIOLATION",
  "AXIS_MIXING",
  "FORBIDDEN_INTERPRETATION",
  "SCOPE_ERROR",
  "CAUSAL_ERROR",
  "MISSING_PREREQUISITE",
  "CIRCULAR_DEPENDENCY",
  "UNREALISTIC_TIMING",
  "OVERLY_BROAD",
  "IRRELEVANT",
] as const;

export type ValidationIssueType = (typeof VALIDATION_ISSUE_TYPES)[number];

export interface IValidationIssue {
  type: ValidationIssueType;
  node_id: string;
  reason: string;
}

export interface IMissingConcept {
  title: string;
  parent_id: string;
}

export interface IValidationResult {
  valid: boolean;
  issues: IValidationIssue[];
  missing_concepts: IMissingConcept[];
  should_expand: boolean;
}

export interface ValidationNode {
  id: string;
  parentId: string | null;
  level: number;
  label: string;
  one_liner: string;
  details?: string;
  conceptType?: string;
  semantic_axis?: string;
  canonical_definition?: string;
  forbidden_interpretations?: string[];
}

export function compactNodesForValidation(
  nodes: ValidationNode[],
): Array<Record<string, unknown>> {
  const lean = nodes.length > resolveLeanThreshold();
  return nodes.map((n) => ({
    id: n.id,
    parentId: n.parentId,
    level: n.level,
    label: n.label,
    one_liner: lean ? n.one_liner?.slice(0, 120) : n.one_liner,
    details: lean ? undefined : n.details?.slice(0, 300),
    conceptType: n.conceptType,
    semantic_axis: n.semantic_axis,
    canonical_definition: n.canonical_definition?.slice(0, 200),
    forbidden_interpretations: n.forbidden_interpretations,
  }));
}

export function validationNeighborhood<T extends { id: string; parentId: string | null }>(
  nodes: T[],
  focusIds: string[],
): T[] {
  if (focusIds.length === 0) return [];
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const keep = new Set<string>();
  const ctxParents = new Set<string>();
  for (const id of focusIds) {
    const node = byId.get(id);
    if (!node) continue;
    keep.add(id);
    if (node.parentId) {
      ctxParents.add(node.parentId);
      keep.add(node.parentId);
    }
  }
  for (const n of nodes) {
    if (n.parentId && ctxParents.has(n.parentId)) keep.add(n.id);
  }
  return nodes.filter((n) => keep.has(n.id));
}

export interface ValidatePromptOptions {
  focusIds?: string[];
}

export function buildValidatePrompt(
  nodes: ValidationNode[],
  opts?: ValidatePromptOptions,
): string {
  const scope =
    opts?.focusIds && opts.focusIds.length > 0
      ? validationNeighborhood(nodes, opts.focusIds)
      : nodes;
  return PROMPT_VALIDATE.replace(
    "{{tree_json}}",
    JSON.stringify(compactNodesForValidation(scope)),
  );
}

export function parseValidationResult(data: unknown): IValidationResult {
  const obj = data as Record<string, unknown>;

  const issues = Array.isArray(obj.issues)
    ? (obj.issues as Array<Record<string, unknown>>).map((i) => ({
        type: (typeof i.type === "string" ? i.type : "DUPLICATE") as ValidationIssueType,
        node_id: typeof i.node_id === "string" ? i.node_id : "",
        reason: typeof i.reason === "string" ? i.reason : "",
      }))
    : [];

  const missing = Array.isArray(obj.missing_concepts)
    ? (obj.missing_concepts as unknown[]).flatMap((c): IMissingConcept[] => {
        if (typeof c === "string") {
          return c.trim() !== "" ? [{ title: c.trim(), parent_id: "" }] : [];
        }
        if (c && typeof c === "object") {
          const rec = c as Record<string, unknown>;
          const title = typeof rec.title === "string" ? rec.title.trim() : "";
          if (title === "") return [];
          return [
            {
              title,
              parent_id: typeof rec.parent_id === "string" ? rec.parent_id : "",
            },
          ];
        }
        return [];
      })
    : [];

  return {
    valid: obj.valid === true,
    issues,
    missing_concepts: missing,
    should_expand: obj.should_expand !== false,
  };
}
