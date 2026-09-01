import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";
import type { IValidationIssue } from "./validate.js";

const LEVEL_TONES: Record<string, string> = {
  beginner: "Пиши максимально доступно для новичка, без профессионального жаргона.",
  intermediate: "Пиши для знакомого с основами читателя.",
  expert: "Пиши для специалиста, используй точную терминологию.",
};

export const PROMPT_REPAIR = `# Роль
Ты — эксперт по структуре знаний. Твоя задача — исправить конкретные проблемы в узлах дерева.

# Задача
Для каждого проблемного узла (указанного в списке «Проблемы») исправь его так, чтобы проблема была устранена.

# Правила исправления
- Если DUPLICATE: переименуй узел так, чтобы он описывал уникальное понятие, или объедини с дублем.
- Если OVERLAP: сузь содержание узла, убери пересекающиеся тезисы.
- Если ABSTRACTION_MISMATCH: подними или опусти уровень абстракции до соответствия с соседями.
- Если TAXONOMIC_INCONSISTENCY: приведи классификацию к единой логической оси.
- Если COVERAGE: добавь пропущенный узел.
- Если USELESS_CHILD: переименуй или удали бессмысленный узел.
- Если SHOULD_BE_LEAF: пометь узел как leaf (не генерируй детей).
- Если LANGUAGE_VIOLATION: переведи label/one_liner на русский.
- Если ONTOLOGY_VIOLATION: восстанови canonical_definition, приведи контент в соответствие.
- Если AXIS_MIXING: раздели оси, приведи узел к одному semantic_axis.
- Если FORBIDDEN_INTERPRETATION: удали запрещённую интерпретацию из контента.
- Если SCOPE_ERROR: сделай утверждение условным, добавь оговорки.
- Если CAUSAL_ERROR: исправь причинно-следственную связь.
${NO_META_RULE}
${ALPHABET_RULE}
- Не описывай произведённые исправления в текстах полей — поля должны содержать только итоговый контент.

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (label, one_liner, details) — только на русском.
{{audience_block}}

# Формат ответа
Только валидный JSON-массив исправленных узлов:
[
  {"id": "id_узла", "parentId": "родитель", "level": N, "label": "Исправленное название", "one_liner": "...", "details": "...", "conceptType": "...", "semantic_axis": "...", "canonical_definition": "...", "forbidden_interpretations": ["..."]}
]

Возвращай ТОЛЬКО исправленные узлы (не все дерево). Каждый исправленный узел должен содержать все обязательные поля.
semantic_axis, canonical_definition и forbidden_interpretations — если они изменились при исправлении.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проблемные узлы
{{problem_nodes}}

# Проблемы
{{issues}}`;

export interface ProblemNode {
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

export interface IRepairPromptContext {
  problemNodes: ProblemNode[];
  issues: IValidationIssue[];
  level?: string;
}

export function buildRepairPrompt(ctx: IRepairPromptContext): string {
  const nodesStr = JSON.stringify(
    ctx.problemNodes.map((n) => ({
      id: n.id,
      parentId: n.parentId,
      level: n.level,
      label: n.label,
      one_liner: n.one_liner,
      details: n.details?.slice(0, 300),
      conceptType: n.conceptType,
      semantic_axis: n.semantic_axis,
      canonical_definition: n.canonical_definition?.slice(0, 200),
      forbidden_interpretations: n.forbidden_interpretations,
    })),
  );

  const issuesStr = ctx.issues
    .map((i) => `- [${i.type}] узел ${i.node_id}: ${i.reason}`)
    .join("\n");

  const audienceBlock =
    ctx.level && LEVEL_TONES[ctx.level]
      ? `\n# Аудитория\n${LEVEL_TONES[ctx.level]}\n`
      : "";

  return PROMPT_REPAIR
    .replace("{{audience_block}}", audienceBlock)
    .replace("{{problem_nodes}}", nodesStr)
    .replace("{{issues}}", issuesStr);
}
