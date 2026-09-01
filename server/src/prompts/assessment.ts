import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface AssessmentPromptContext {
  topic: string;
  goal: string;
  sessionItems: Array<{ nodeId: string; label: string; oneLiner: string; details: string }>;
  includeApplication: boolean;
}

export const PROMPT_ASSESSMENT = `# Роль
Ты — экзаменатор. Проверь, действительно ли пользователь достиг заявленного уровня понимания темы.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Изученные понятия (в рамках сессии):
{{session_items}}

# Типы вопросов
Сгенерируй финальную проверку, включающую:
- **recall** — вопросы на запоминание/воспроизведение определений и фактов
- **explanation** — вопросы, где пользователь должен объяснить механизм своими словами (structure matters)
- **application** — (если include_application=true) задачи на применение знания к новому случаю
- **transfer** — (если включено) перенос знания на смежную ситуацию

Всего {{question_count}} вопросов. Не менее одного explanation и одного recall.
Порядок: recall → explanation → application → transfer.

# Формат ответа
Строгий JSON-объект:
{"questions":[{"id":"a1","type":"recall","nodeId":"n2_a","question":"...","options":["A","B","C","D"],"correctAnswer":"A","explanation":"..."},{"id":"a2","type":"explanation","nodeId":"n2_b","question":"Объясните своими словами, как работает X (порядок шагов, причинно-следственные связи).","options":[],"correctAnswer":"","explanation":"Ключевые элементы, которые должны быть в ответе: 1) ..., 2) ..."}]}

- Для recall/recognition — укажите options и correctAnswer (индекс корректного варианта).
- Для explanation/application/transfer — options=[] и correctAnswer=""; explanation содержит рубрику (критерии) оценивания: какие элементы должны присутствовать в свободном ответе.

${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Вопросы, варианты, рубрики — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] Ровно {{question_count}} вопросов
- [ ] Не менее одного recall и одного explanation
- [ ] Application/transfer вопросы — если включены
- [ ] Explanation rubric содержит конкретные критерии оценивания
- [ ] Вопросы проверяют глубокое понимание, не поверхностную фактологию
- [ ] Формат — строго JSON с ключом "questions"`;

export function buildAssessmentPrompt(
  ctx: AssessmentPromptContext,
  questionCount: number,
): string {
  const itemsJson = JSON.stringify(
    ctx.sessionItems.map((s) => ({
      nodeId: s.nodeId,
      label: s.label,
      oneLiner: s.oneLiner,
      details: s.details?.slice(0, 400),
    })),
  );

  return PROMPT_ASSESSMENT
    .replace("{{topic}}", ctx.topic)
    .replace("{{goal}}", ctx.goal)
    .replace("{{session_items}}", itemsJson)
    .replace(/\{\{question_count\}\}/g, String(questionCount))
    .replace(
      "{{include_application}}",
      ctx.includeApplication ? "true" : "false",
    );
}

export interface AssessmentQuestionResult {
  id: string;
  type: string;
  nodeId: string;
  question: string;
  options: string[];
  correctAnswer: string;
  explanation: string;
}

export function parseAssessmentResult(data: unknown): AssessmentQuestionResult[] {
  const obj = data as Record<string, unknown>;
  if (!Array.isArray(obj.questions)) return [];
  return (obj.questions as Array<Record<string, unknown>>).map((q) => ({
    id: typeof q.id === "string" ? q.id : `a_${Math.random().toString(36).slice(2, 8)}`,
    type: typeof q.type === "string" ? q.type : "recall",
    nodeId: typeof q.nodeId === "string" ? q.nodeId : "",
    question: typeof q.question === "string" ? q.question : "",
    options: Array.isArray(q.options)
      ? (q.options as unknown[]).filter((o): o is string => typeof o === "string")
      : [],
    correctAnswer: typeof q.correctAnswer === "string" ? q.correctAnswer : "",
    explanation: typeof q.explanation === "string" ? q.explanation : "",
  }));
}
