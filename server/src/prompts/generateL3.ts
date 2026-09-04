import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";
import { buildAudienceBlock, type IStructurePromptOptions } from "./structure.js";

export const PROMPT_L3 = `# Роль
Ты — педагог-структуролог. Твоя задача — построить уровень 3 (подразделы) для ОДНОГО конкретного раздела дерева знаний.

# Контекст
Тема пользователя: "{{user_query}}"
Корень: {{root_title}}

# Раздел, который ты раскрываешь
Название: "{{parent_title}}"
Определение: {{parent_definition}}

# Остальные разделы этого же уровня (НЕ раскрывать, только контекст чтобы не дублировать)
{{sibling_nodes}}

# Задача
Сгенерируй 2–4 дочерних узла УРОВНЯ 3 для раздела "{{parent_title}}". Это подразделы конкретного раздела.
НЕ создавай уровень 4 — это задача выборочного расширения позже.

# Определение конкретного ребёнка
Каждый дочерний узел — это конкретное понятие/термин/подтема ВНУТРИ родителя "{{parent_title}}".
- Если родитель описывает класс архитектур или подходов, дочерние узлы должны покрывать все основные варианты.
- Если родитель — процесс/pipeline, дочерние шаги — его этапы.
- Если родитель — набор видов/типов, дочерние — каждый конкретный вид.
- Дети должны быть в той же semantic_axis, что и родитель, или в смежной. Не смешивай оси (архитектура ≠ процесс ≠ сэмплинг).

# Критическое правило о дублях
ВНИМАТЕЛЬНО просмотри «Остальные разделы» ({{sibling_nodes}}) и их определения.
НЕ создавай дочерний узел, если это понятие логически является подразделом или частью ДРУГОГО раздела. Каждый дочерний узел принадлежит ТОЛЬКО своему родителю "{{parent_title}}".

# Правила
- label — техническое название понятия (термин), 1–4 слова. Не метафоры.
- Не дублируй содержимое родителя: дочерний узел расширяет, а не переописывает родителя.
- Не разбивай понятие, которое является естественным leaf (например, «Mean Squared Error»).
- Одно понятие — одно место. Нет дублей.
- На одном уровне — единый уровень абстракции.
- Все id начинаются с "n" + цифра (n3_, n4_...). Каждый узел обязан иметь parentId, равный id родителя.
- Для каждого ребёнка укажи semantic_axis и conceptType.
- Для каждого ребёнка укажи метаданные: importance (0..1), difficulty (0..1), estimated_time_minutes (целое), prerequisites (массив id понятий), relations (массив {to, type} или []).
${NO_META_RULE}
${ALPHABET_RULE}
{{audience_block}}
# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.

# Формат ответа
Только валидный JSON-объект:
{"nodes":[{"id":"n3_a1","title":"Понятие A1","parentId":"{{parent_id}}","level":3,"conceptType":"mechanism","canonical_definition":"...","semantic_axis":"process","forbidden_interpretations":["..."],"importance":0.7,"difficulty":0.5,"estimated_time_minutes":12,"prerequisites":[],"relations":[]},{"id":"n3_a2","title":"Понятие A2","parentId":"{{parent_id}}","level":3,...}]}

Допустимые значения conceptType: "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".
Допустимые значения semantic_axis: "architecture", "process", "sampling", "representation", "loss", "encoding", "conditioning", "application", "theory", "evaluation".

Если родитель является естественным leaf (дальнейшее разбиение бессмысленно), верни пустой массив:
{"nodes":[]}

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] 2–4 узла уровня 3 (БЕЗ уровня 4)
- [ ] title — термины, не метафоры
- [ ] каждый ребёнок — конкретное понятие внутри родителя
- [ ] нет дублей с «Остальными разделами» и внутри
- [ ] semantic_axis консистентен с conceptType
- [ ] у узлов заданы importance (0..1), difficulty (0..1), estimated_time_minutes
- [ ] у каждого узла parentId = "{{parent_id}}"
- [ ] формат — строго JSON с ключом "nodes"`;

export interface IGenerateL3Context {
  userQuery: string;
  rootTitle: string;
  parent: { id: string; title: string; canonical_definition?: string; semantic_axis?: string };
  siblings: Array<{ id: string; title: string; canonical_definition?: string }>;
  options?: IStructurePromptOptions;
}

export function buildL3Prompt(ctx: IGenerateL3Context): string {
  const parentDef =
    ctx.parent.canonical_definition?.trim() ||
    `Подраздел темы «${ctx.rootTitle}».`;

  const siblingsStr =
    ctx.siblings.length > 0
      ? ctx.siblings
          .map(
            (s) =>
              `- id: ${s.id}, title: "${s.title}"${
                s.canonical_definition ? `, определение: ${s.canonical_definition}` : ""
              }`,
          )
          .join("\n")
      : "- (нет других разделов того же уровня)";

  return PROMPT_L3
    .replace("{{user_query}}", ctx.userQuery)
    .replace("{{root_title}}", ctx.rootTitle)
    .replace("{{parent_title}}", ctx.parent.title)
    .replace("{{parent_definition}}", parentDef)
    .replaceAll("{{parent_id}}", ctx.parent.id)
    .replace("{{sibling_nodes}}", siblingsStr)
    .replace("{{audience_block}}", buildAudienceBlock(ctx.options));
}
