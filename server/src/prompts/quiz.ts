import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface QuizNode {
  id: string;
  label?: string;
  one_liner: string;
  details: string;
  conceptType?: string;
  relations?: unknown[];
  sequences?: unknown[];
}

export const PROMPT_QUIZ = `# Роль
Ты — педагог, составляешь тест по уже изученной теме. Тест проверяет понимание ключевых концепций, связей и механизмов.

# Контекст
Тема: "{{user_query}}"
Дерево знаний (узлы с определениями и связями):
{{tree_nodes}}

# Задача
Сгенерируй {{question_count}} вопросов для теста по теме. Вопросы должны проверять:
- Понимание ключевых терминов и их определений
- Связи между понятиями (какие понятия зависят друг от друга, что является частью чего)
- Порядок процессов и алгоритмов (если есть sequences)
- Причинно-следственные связи
- Развенчание мифов и заблуждений (misconception)

# Типы вопросов
Обычные вопросы — проверяют знание фактов и связей.
Misconception-вопросы — содержат ложное утверждение, которое выглядит правдоподобно. Пользователь должен определить, верно оно или нет. Отметь misconception: true для таких вопросов. Хороший misconception — это распространённое заблуждение, а не абсурдное утверждение.

# Правила для вопросов
- Каждый вопрос имеет ровно 4 варианта ответа (A, B, C, D)
- Ровно один вариант правильный
- Неправильные варианты правдоподобны (не абсурдны), но ошибочны
- Вопрос сформулирован ясно, без двусмысленностей
- Объяснение правильного ответа — 1–2 предложения, пояснение почему это верно
- Не используй "все вышеперечисленное" или "ничего из вышеперечисленного"
- Не повторяй один и тот же концепт в разных вопросах
- Для каждого вопроса укажи nodeId — id узла из дерева, к которому относится вопрос. Бери id ТОЛЬКО из предоставленного дерева.
- Из {{question_count}} вопросов минимум 2 должны быть misconception
${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Строгий JSON-объект. Никакого текста до или после JSON. Никаких комментариев.
Объект содержит ключ "questions" с массивом вопросов.

Пример:
{"questions":[{"id":"q1","nodeId":"n3_a1","question":"Что делает X?","options":["A1","A2","A3","A4"],"correctIndex":1,"explanation":"X делает Y потому что Z.","misconception":false},{"id":"q2","nodeId":"n2_b","question":"Верно ли, что X — это Y?","options":["Да, потому что...","Нет, потому что X делает Z...","Да, все...","Нет, но..."],"correctIndex":1,"explanation":"Неверно: X не является Y, потому что...","misconception":true}]}

# Проверь перед ответом
- [ ] Ровно {{question_count}} вопросов
- [ ] Каждый вопрос с 4 вариантами, один правильный
- [ ] correctIndex от 0 до 3
- [ ] У каждого вопроса корректный nodeId из дерева
- [ ] Вопросы покрывают разные аспекты темы (не только определения)
- [ ] Минимум 2 misconception-вопроса
- [ ] Объяснения информативны, а не "Потому что A — правильный ответ"
- [ ] Вопросы, варианты ответов и объяснения — СТРОГО на русском (кроме устоявшихся аббревиатур)`;

export function buildQuizPrompt(
  userQuery: string,
  nodes: QuizNode[],
  count: number,
): string {
  const sanitizedQuery = userQuery
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  const compactNodes = nodes.map((n) => ({
    id: n.id,
    label: n.label,
    one_liner: n.one_liner,
    details: n.details?.slice(0, 300),
    conceptType: n.conceptType,
    relations: n.relations,
    sequences: n.sequences,
  }));

  return PROMPT_QUIZ.replace("{{user_query}}", sanitizedQuery)
    .replace("{{tree_nodes}}", JSON.stringify(compactNodes))
    .replace(/\{\{question_count\}\}/g, String(count));
}

export function computeQuizCount(nodeCount: number): number {
  if (nodeCount === 0) return 6;
  const raw = Math.floor(nodeCount * 0.5) + 2;
  return Math.max(6, Math.min(raw, 12));
}
