import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_VALIDATE = `# Роль
Ты — эксперт по структуре знаний. Твоя задача — найти проблемы в дереве понятий.

# Задача
Проверь дерево знаний на следующие проблемы.

## Критичные — дерево реально неверно
Если найдена хотя бы одна, поставь "valid": false.
1. **DUPLICATE** — узлы, описывающие одно и то же понятие (разными словами или одинаково).
2. **OVERLAP** — узлы, которые слишком сильно пересекаются по содержанию.
3. **ABSTRACTION_MISMATCH** — узлы на одном уровне, находящиеся на разных уровнях абстракции.
4. **TAXONOMIC_INCONSISTENCY** — дети классифицируют родителя по разным логическим осям.
5. **AXIS_MIXING** — узел смешивает semantic_axis (описывает архитектуру как процесс и т.д.).
6. **LANGUAGE_VIOLATION** — label или one_liner содержат непереведенный английский текст.
7. **ONTOLOGY_VIOLATION** — узел прямо противоречит своему canonical_definition.
8. **CAUSAL_ERROR** — неверная причинно-следственная связь.

## Что проверяет код, а не ты
MISSING_PREREQUISITE, CIRCULAR_DEPENDENCY и UNREALISTIC_TIMING вычисляются
детерминированной проверкой по relations/prerequisites/estimated_minutes.
В nodes тебе этих полей нет, поэтому проверить их ты не можешь, а repair
связи всё равно не чинит. НЕ сообщай эти типы: находка окажется выдуманной
и зря запустит полный ремонт на здоровом дереве.

## Некритичные — стилистика и соображения
Найденные проблемы из этого списка НЕ делают дерево невалидным: перечисли их в "issues", но поставь "valid": true.
9. **COVERAGE** — можно было бы добавить ещё одну категорию.
10. **USELESS_CHILD** — у ребёнка слабая самостоятельная ценность.
11. **SHOULD_BE_LEAF** — узел логично было бы не дробить дальше.
12. **FORBIDDEN_INTERPRETATION** — узел использует запрещённую интерпретацию.
13. **SCOPE_ERROR** — условное утверждение можно ужесточить до абсолютного.
14. **OVERLY_BROAD** — узел слишком глобален и его можно расширить.
15. **IRRELEVANT** — узел слабо относится к теме.

${NO_META_RULE}
${ALPHABET_RULE}

# Главное правило
Отвечай за консервативность. Дерево, у которого есть критичных проблем, должно быть признано невалидным; дерево без критичных проблем — валидным.
НЕ выдумывай проблемы, чтобы выглядеть внимательным. Если структура рабочая, верни "valid": true и "issues": [] — это правильный и полезный ответ, а не отсутствие работы.
Не считай критичной ситуацию «можно было бы сделать лучше» — это некритичный пункт.

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

- valid = false, если и только если есть хотя бы одна КРИТИЧНАЯ проблема (типы 1–8).
- Некритичные находки (типы 9–15) перечисляй в issues, но valid оставляй true.
- MISSING_PREREQUISITE, CIRCULAR_DEPENDENCY и UNREALISTIC_TIMING не сообщай: их считает код.
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

/**
 * Типы находок, из-за которых дерево действительно считается невалидным и
 * запускается ремонт. Остальные — стилистика и соображения: докладываются,
 * но дерево не переписывается.
 *
 * Замер на живом провайдере показал, что до разделения валидатор отвергал
 * дерево в 2 прогонах из 2, хотя все детерминированные проверки проходили и
 * ремонт не оставлял ни одной warning. Причина — 18 обязательных проверок и
 * правило «valid = false при любой находке». Теперь решение принимается по типу
 * находки: ремонт идёт тогда и только тогда, когда есть блокирующий тип.
 */
export const VALIDATION_BLOCKING_ISSUE_TYPES: ReadonlySet<string> = new Set([
  "DUPLICATE",
  "OVERLAP",
  "ABSTRACTION_MISMATCH",
  "TAXONOMIC_INCONSISTENCY",
  "AXIS_MIXING",
  "LANGUAGE_VIOLATION",
  "ONTOLOGY_VIOLATION",
  "CAUSAL_ERROR",
  // MISSING_PREREQUISITE и CIRCULAR_DEPENDENCY сознательно НЕ блокирующие,
  // хотя формально относятся к ошибкам дерева. В промпт `validate` эти поля
  // вообще не передаются (`relations`/`prerequisites` в ValidationNodeRef
  // отсутствуют), то есть модель проверить их физически не может и выдумывает
  // находку вместо настоящей. Настоящие циклы и висячие ссылки ловит
  // детерминированный пре-пасс, а циклы к тому же разрываются кодом
  // (`breakDependencyCycles`), поэтому объявлять их блокирующими значило
  // запускать дорогой repair на здоровом дереве.
]);

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
