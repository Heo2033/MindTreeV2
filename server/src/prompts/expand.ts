import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_EXPAND = `# Роль
Ты — педагог, расширяешь дерево знаний. Для каждого указанного узла построй следующий уровень иерархии.

# Контекст
Тема: {{root_topic}}
Полный путь от корня до целевых узлов:
{{context_paths}}

# Задача
Для КАЖДОГО узла из списка «Узлы для расширения» сгенерируй 2–4 дочерних узла.
Каждый дочерний узел — это конкретное понятие/термин внутри родителя.
Новых тем не вводи. Не дублируй понятия, которые уже есть в дереве.

# Правила
- id — уникальный латинский алиас (n4_a, n5_b, и т.д.).
- parentId = id родительского узла.
- title — техническое название понятия (термин), 1–4 слова.
- Каждый ребенок принадлежит ТОЛЬКО своему родителю.
- На одном уровне — единый уровень абстракции.
- Не разбивай понятие, которое является естественным leaf (например, «Mean Squared Error»).
- Не дублируй содержимое родителя: child-узел расширяет, а не переописывает parent.
- Если родитель описывает класс архитектур или подходов, дочерние узлы должны покрывать все основные варианты.
- Дети должны быть в той же semantic_axis, что и родитель, или в смежной. Не смешивай оси (архитектура ≠ процесс ≠ сэмплинг).
- Для каждого ребенка укажи semantic_axis и conceptType.
- Для каждого ребенка укажи метаданные: importance (0..1), difficulty (0..1), estimated_time_minutes (целое), prerequisites (массив id понятий из этого дерева, на которые опирается), relations (массив {to, type} или []).
${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title) — только на русском.

# Формат ответа
Только валидный JSON-объект:
{
  "nodes": [
    {
      "id": "id_родителя",
      "children": [
        {"id": "n_new1", "title": "Название 1", "parentId": "id_родителя", "conceptType": "concept", "semantic_axis": "architecture", "importance": 0.7, "difficulty": 0.5, "estimated_time_minutes": 12, "prerequisites": ["n2_a"], "relations": [{"to": "n2_a", "type": "requires"}]},
        {"id": "n_new2", "title": "Название 2", "parentId": "id_родителя", "conceptType": "mechanism", "semantic_axis": "process", "importance": 0.6, "difficulty": 0.8, "estimated_time_minutes": 15, "prerequisites": ["n_new1"], "relations": [{"to": "n_new1", "type": "enables"}]}
      ]
    }
  ]
}

Допустимые значения conceptType: "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".
Допустимые значения semantic_axis: "architecture", "process", "sampling", "representation", "loss", "encoding", "conditioning", "application", "theory", "evaluation".

Если узел является естественным leaf (дальнейшее разбиение бессмысленно), верни пустой массив children:
{"id": "id_родителя", "children": []}

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Узлы для расширения
{{nodes_to_expand}}

# Проверь перед ответом
- [ ] Для каждого узла сгенерированы 2–4 ребенка (или [] для leaf)
- [ ] title — термины, не метафоры
- [ ] Нет дублей с уже существующими понятиями в дереве
- [ ] Каждый ребенок — конкретное понятие внутри родителя
- [ ] semantic_axis консистентен с conceptType
- [ ] Формат — строго JSON с ключом "nodes"`;

export interface IExpandPromptContext {
  rootTopic: string;
  contextPaths: string[];
  nodesToExpand: Array<{ id: string; title: string; path: string }>;
}

export function buildExpandPrompt(ctx: IExpandPromptContext): string {
  const sanitizedTopic = ctx.rootTopic
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  const pathsStr = ctx.contextPaths.join("\n");
  const nodesStr = ctx.nodesToExpand
    .map((n) => `- id: ${n.id}, title: "${n.title}", path: ${n.path}`)
    .join("\n");

  return PROMPT_EXPAND.replace("{{root_topic}}", sanitizedTopic)
    .replace("{{context_paths}}", pathsStr)
    .replace("{{nodes_to_expand}}", nodesStr);
}
