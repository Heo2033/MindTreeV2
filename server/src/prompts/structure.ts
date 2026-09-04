import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_L1 = `# Роль
Ты — педагог-структуролог. Твоя задача — определить корень (тему) онтологии дерева знаний.

# Задача
Определи КОРНЕВОЙ узел дерева знаний о теме пользователя. Генерируй ТОЛЬКО корень — 1 узел уровня 1. Не создавай разделов, веток и дочерних узлов — они будут сгенерированы отдельными шагами позже.

# Правила
- Уровень 1: ровно 1 корень — краткое название темы (1–4 слова).
- label — техническое название понятия (термин), 1–4 слова. Не метафоры.
- {{depth_hint}}
- Форма — раскидистая крона, НЕ столб.
- id корня начинается с "n" + цифра (n1_root и т.п.).
${NO_META_RULE}
${ALPHABET_RULE}
{{audience_block}}
# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.

# Онтологический контракт (для корня)
- **canonical_definition** — строгое определение темы (1–2 предложения). Это источник истины. Content-модель и генерация веток будут основываться на нём.
- **semantic_axis** — "theory".
- **conceptType** — "topic".
- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций. Это то, что content-модель НЕ должна утверждать.
- **importance** — число от 0 до 1.
- **difficulty** — число от 0 до 1.
- **estimated_time_minutes** — целое число: реалистичная общая оценка времени изучения темы.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Формат ответа
Только валидный JSON-объект:
{"nodes":[{"id":"n1_root","title":"Тема","parentId":null,"level":1,"conceptType":"topic","semantic_axis":"theory","canonical_definition":"...","forbidden_interpretations":["..."],"importance":0.5,"difficulty":0.5,"estimated_time_minutes":60,"prerequisites":[],"relations":[]}]}

# Проверь перед ответом
- [ ] ровно 1 узел (корень)
- [ ] title — термин, не метафора
- [ ] корень = точное название темы
- [ ] semantic_axis = "theory", conceptType = "topic"
- [ ] формат — строго JSON с ключом "nodes"

Тема пользователя: "{{user_query}}"`;

export const PROMPT_L1_EDIT = `# Роль
Ты — педагог-структуролог. Твоя задача — уточнить корень (тему) онтологии дерева знаний.

# Задача
Имеется уже созданный корень темы. Уточни его: проверь, что название и canonical_definition точно соответствуют теме пользователя. Исправь, если есть неточности. Верни ОДИН исправленный (или неизменённый) корневой узел.

# Текущий корень
{{current_root}}

# Правила
- label — техническое название понятия (термин), 1–4 слова. Не метафоры.
- {depth_hint}
- id корня сохрани прежним.
- Не меняй parentId (должен быть null).
${NO_META_RULE}
${ALPHABET_RULE}
{{audience_block}}

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.

# Онтологический контракт
- **canonical_definition** — строгое определение темы (1–2 предложения).
- **semantic_axis** — "theory".
- **conceptType** — "topic".
- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Формат ответа
Только валидный JSON-объект:
{"nodes":[{"id":"n1_root","title":"Тема","parentId":null,"level":1,"conceptType":"topic","semantic_axis":"theory","canonical_definition":"...","forbidden_interpretations":["..."],"importance":0.5,"difficulty":0.5,"estimated_time_minutes":60,"prerequisites":[],"relations":[]}]}

Тема пользователя: "{{user_query}}"`;

const GOAL_HINTS: Record<string, string> = {
  overview: "Цель читателя — общий обзор темы. Отдавай приоритет широкому покрытию: все ключевые области, минимум узких деталей.",
  exam: "Цель читателя — подготовка к экзамену. Включай термины, определения, классификации и то, что обычно спрашивают на проверочных работах.",
  deep: "Цель читателя — глубокое погружение. Включай механизмы, внутренние процессы, нюансы и продвинутые подтемы, даже если они редкие.",
};

export interface IStructurePromptOptions {
  goal?: string;
  level?: string;
  timeBudgetMinutes?: number;
}

/** Подсказка по уровню аудитории (скрыта, если level не распознан). */
const LEVEL_HINTS: Record<string, string> = {
  beginner: "Читатель — новичок. Начинай с базовых понятий, не предполагай знакомства со смежными областями.",
  intermediate: "Читатель знаком с основами. Базовые понятия можно группировать компактно, освобождая место для сути.",
  expert: "Читатель — специалист. Пропускай тривиальные понятия, фокусируйся на профессиональных деталях и тонкостях.",
};

/** Маппер MasteryLevel (из UI) → KnowledgeLevel (ключ подсказки LEVEL_HINTS). */
export function masteryLevelToKnowledgeLevel(level?: string): string | undefined {
  switch (level) {
    case "awareness":
    case "basic_understanding":
      return "beginner";
    case "solid_understanding":
    case "practical_application":
      return "intermediate";
    case "advanced":
    case "expert":
      return "expert";
    default:
      return undefined;
  }
}

function depthHintFor(level?: string): string {
  switch (masteryLevelToKnowledgeLevel(level)) {
    case "beginner":
      return "Глубина скелета — минимальная, ветки общие (обзорные категории без узких подразделов).";
    case "intermediate":
      return "Глубина скелета — средняя: ветки достаточно конкретные, покрывают ключевые подразделы.";
    case "expert":
      return "Глубина скелета — максимальная для базы: ветки узкоспециализированные, детальные категории.";
    default:
      return "Глубина скелета — сбалансированная: ветки покрывают основные подразделы темы.";
  }
}

function timeHintFor(timeBudgetMinutes?: number): string {
  if (!timeBudgetMinutes || timeBudgetMinutes <= 0) {
    return "Временной бюджет не задан — стремись к компактной, но полной базе (4–5 веток).";
  }
  if (timeBudgetMinutes < 30) {
    return "Временной бюджет — примерно 15–30 минут. База должна быть минимальной (3 ветки), акцент на самое важное.";
  }
  if (timeBudgetMinutes < 90) {
    return "Временной бюджет — до ~1,5 часа. База средняя (4 ветки), покрывающая ключевые направления.";
  }
  return "Временной бюджет — 1,5 часа и больше. База полная (5 веток), можно шире покрывать поднаправления.";
}

function buildAudienceBlock(options?: IStructurePromptOptions): string {
  const hints: string[] = [];
  if (options?.goal && GOAL_HINTS[options.goal]) {
    hints.push(`- ${GOAL_HINTS[options.goal]}`);
  }
  const mappedLevel = masteryLevelToKnowledgeLevel(options?.level);
  if (mappedLevel && LEVEL_HINTS[mappedLevel]) {
    hints.push(`- ${LEVEL_HINTS[mappedLevel]}`);
  }
  return hints.length > 0
    ? `\n# Аудитория\n${hints.join("\n")}\n`
    : "";
}

function sanitizeUserQuery(userQuery: string): string {
  return userQuery
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();
}

/** Промпт для генерации корневого узла (L1). */
export function buildL1Prompt(userQuery: string, options?: IStructurePromptOptions): string {
  return PROMPT_L1
    .replace("{{audience_block}}", buildAudienceBlock(options))
    .replace("{{depth_hint}}", depthHintFor(options?.level))
    .replace("{{user_query}}", sanitizeUserQuery(userQuery));
}

/** Промпт для уточнения уже созданного корневого узла (L1-edit). */
export function buildL1EditPrompt(
  userQuery: string,
  currentRoot: Record<string, unknown>,
  options?: IStructurePromptOptions,
): string {
  return PROMPT_L1_EDIT
    .replace("{{current_root}}", JSON.stringify(currentRoot, null, 2))
    .replace("{{audience_block}}", buildAudienceBlock(options))
    .replace("{{depth_hint}}", depthHintFor(options?.level))
    .replace("{{user_query}}", sanitizeUserQuery(userQuery));
}

export { GOAL_HINTS, buildAudienceBlock, depthHintFor, timeHintFor, sanitizeUserQuery };
