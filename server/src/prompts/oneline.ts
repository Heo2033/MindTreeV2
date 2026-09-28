import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

/**
 * Максимальная длина `one_liner` — инвариант AGENTS.md.
 * Зеркало: `oneLinerMaxChars` в `mindtree_flutter/lib/domain/engines/
 * knowledge_graph_engine.dart` (единый источник для Flutter-стека).
 */
export const ONELINER_MAX_CHARS = 120;

export const PROMPT_ONELINE_REWRITE = `# Роль
Ты — редактор учебных материалов. Ты сокращаешь слишком длинное однострочное описание понятия (one_liner), сохраняя точность и ключевую идею.

# Задача
Дано понятие и его слишком длинное однострочное описание. Перепиши описание так, чтобы оно занимало не более {{limit}} символов.

# Контекст
Понятие: "{{label}}"
Текущее описание (длинное): {{one_liner}}

# Правила
- Новая версия должна быть не длиннее {{limit}} символов (длина строки).
- Сохрани ключевую идею; не добавляй новых фактов и не меняй смысл.
- Это одно короткое предложение или фраза, а не статья.
- Не используй жаргон и канцелярит; пиши просто и понятно.
${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Только валидный JSON-объект:
{"one_liner": "сокращённое описание"}

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Язык
Ответ строго на русском языке.`;

export interface IOnelineRewriteContext {
  label: string;
  currentOneLiner: string;
}

export function buildOnelineRewritePrompt(ctx: IOnelineRewriteContext): string {
  return PROMPT_ONELINE_REWRITE.replace("{{limit}}", String(ONELINER_MAX_CHARS))
    .replace("{{label}}", ctx.label)
    .replace("{{one_liner}}", ctx.currentOneLiner);
}