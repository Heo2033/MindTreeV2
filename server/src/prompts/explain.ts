import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface ExplainNode {
  id: string;
  label?: string;
  one_liner: string;
  details: string;
}

export const PROMPT_EXPLAIN = `# Роль
Ты — помощник-педагог. Объясняешь непонятный термин из текста простыми словами, в контексте темы.

# Контекст
Тема: "{{user_query}}"
Узел дерева: "{{node_label}}"
Текст узла: "{{node_details}}"

# Задача
Пользователь выделил фрагмент текста и просит пояснение:
"{{selected_text}}"

Объясни этот термин/понятие:
- 1–3 предложения, простым языком
- Свяжи с контекстом темы и узла
- Если это технический термин — дай краткое определение
- Не повторяй дословно текст из узла
${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Только текст пояснения (без JSON, без кавычек, без markdown). Просто строка.`;

export function buildExplainPrompt(
  userQuery: string,
  node: ExplainNode,
  selectedText: string,
): string {
  const sanitizedQuery = userQuery
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  return PROMPT_EXPLAIN.replace("{{user_query}}", sanitizedQuery)
    .replace("{{node_label}}", node.label ?? node.one_liner)
    .replace("{{node_details}}", node.details.slice(0, 800))
    .replace("{{selected_text}}", selectedText.slice(0, 200));
}
