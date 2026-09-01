import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface CurriculumNodeInput {
  id: string;
  label: string;
  one_liner: string;
  importance: number;
  difficulty: number;
  estimated_time_minutes: number;
  prerequisites: string[];
}

export interface CurriculumPromptContext {
  topic: string;
  goal: string;
  targetLevel: string;
  currentLevel: string;
  timeBudgetMinutes: number;
  nodes: CurriculumNodeInput[];
}

export const PROMPT_CURRICULUM = `# Роль
Ты — curriculum-инженер. Из полного дерева знаний выбери минимальный достаточный набор понятий, которые приведут пользователя от текущего уровня к целевой цели за заданное время.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Текущий уровень: {{current_level}}
Целевой уровень: {{target_level}}
Доступное время: {{time_budget_minutes}} минут

# Дерево знаний (полный граф)
{{nodes_json}}

# Задача
Собери соответствие: из всех понятий дерева выбери минимальный достаточный список для достижения целевого уровня за доступное время.

# Принципы отбора
- **Minimum sufficient knowledge**: не включай всё дерево — только то, что необходимо для цели.
- **Just enough prerequisites**: если достаточно краткого упоминания (например, «шум Гаусса») — не включай полный подграф Probability.
- **Learning gain per minute**: отдавай приоритет понятиям с высокой пользой на единицу времени.
- Учитывай importance, difficulty и estimated_time_minutes каждого узла.
- Порядок отбора = порядок изучения (сперва базовые).
- Если понятия уже знает пользователь (current_level достигнут) — пропусти.
- Суммарное время не должно превышать время бюджета существенно.

# Формат ответа
Строгий JSON-объект:
{
  "items": [
    {"node_id": "n3_a1", "order": 1, "estimated_minutes": 10, "why": "Почему это понятие важно для цели"},
    {"node_id": "n2_b", "order": 2, "estimated_minutes": 15, "why": "..."}
  ],
  "total_estimated_minutes": 55,
  "skipped": [
    {"node_id": "n4_x", "reason": "why skipped (optional/deferred/advanced)"}
  ]
}
${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Поля "why" и "reason" — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] Выбрано минимально достаточное число понятий
- [ ] Порядок изучения от базовых к продвинутым
- [ ] Не включено лишнее (не всё дерево)
- [ ] Суммарное время близко к бюджету (не превышает его грубо)
- [ ] Формат — строго JSON с ключом "items"`;

export function buildCurriculumPrompt(ctx: CurriculumPromptContext): string {
  const nodesJson = JSON.stringify(
    ctx.nodes.map((n) => ({
      id: n.id,
      label: n.label,
      one_liner: n.one_liner,
      importance: n.importance,
      difficulty: n.difficulty,
      estimated_time_minutes: n.estimated_time_minutes,
      prerequisites: n.prerequisites,
    })),
  );

  return PROMPT_CURRICULUM
    .replace("{{topic}}", ctx.topic)
    .replace("{{goal}}", ctx.goal)
    .replace("{{current_level}}", ctx.currentLevel)
    .replace("{{target_level}}", ctx.targetLevel)
    .replace("{{time_budget_minutes}}", String(ctx.timeBudgetMinutes))
    .replace("{{nodes_json}}", nodesJson);
}

export interface CurriculumItemResult {
  node_id: string;
  order: number;
  estimated_minutes: number;
  why: string;
}

export function parseCurriculumResult(data: unknown): {
  items: CurriculumItemResult[];
  total_estimated_minutes: number;
  skipped: Array<{ node_id: string; reason: string }>;
} {
  const obj = data as Record<string, unknown>;
  const items = Array.isArray(obj.items)
    ? (obj.items as Array<Record<string, unknown>>).map((i) => ({
        node_id: typeof i.node_id === "string" ? i.node_id : "",
        order: typeof i.order === "number" ? i.order : 0,
        estimated_minutes: typeof i.estimated_minutes === "number" ? i.estimated_minutes : 5,
        why: typeof i.why === "string" ? i.why : "",
      }))
    : [];

  const skipped = Array.isArray(obj.skipped)
    ? (obj.skipped as Array<Record<string, unknown>>).map((s) => ({
        node_id: typeof s.node_id === "string" ? s.node_id : "",
        reason: typeof s.reason === "string" ? s.reason : "",
      }))
    : [];

  return {
    items,
    total_estimated_minutes: typeof obj.total_estimated_minutes === "number"
      ? obj.total_estimated_minutes
      : items.reduce((s, i) => s + i.estimated_minutes, 0),
    skipped,
  };
}
