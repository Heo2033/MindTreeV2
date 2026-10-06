import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";
import { resolveCorrectAnswerIndex } from "../lib/optionMatching.js";
import { shortIdWith } from "../domain/shortIds.js";

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

# Типы вопросов (всего их 6)
Сгенерируй финальную проверку, используя следующие типы:
- **recognition** — узнавание: выбери корректный вариант из четырёх (формулировка, а не заучивание)
- **recall** — припоминание: воспроизведи определение или ключевой факт (multiple choice)
- **explanation** — объясни механизм своими словами (structure matters; rubric обязателен)
- **diagnosis** — найди и объясни ошибку/несоответствие в приведённом утверждении (rubric обязателен)
- **application** — примени знание к новой конкретной ситуации (rubric обязателен)
- **transfer** — перенеси знание на смежную/нестандартную ситуацию (rubric обязателен)

Всего {{question_count}} вопросов. Обеспечь разнообразие типов: это должен быть честный замер, а не только фактология.
Для recognition/recall укажи options и correctAnswer (индекс корректного варианта, начиная с 0).
Для explanation/diagnosis/application/transfer — options=[] и correctAnswer=""; explanation (рубрика) содержит конкретные критерии оценивания: какие элементы должны присутствовать в свободном ответе.

# Формат ответа
Строгий JSON-объект:
{"questions":[{"id":"a1","type":"recall","nodeId":"n2_a","question":"...","options":["A","B","C","D"],"correctAnswer":"0","explanation":"..."},{"id":"a2","type":"explanation","nodeId":"n2_b","question":"Объясните своими словами, как работает X (порядок шагов, причинно-следственные связи).","options":[],"correctAnswer":"","explanation":"Ключевые элементы ответа: 1) ..., 2) ..."}]}

# Примечания
- correctAnswer для recognition/recall — ИНДЕКС правильного варианта (строка "0","1","2","3").
- Вопросы проверяют глубокое понимание, не поверхностную фактологию.

${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Вопросы, варианты, рубрики — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] Ровно {{question_count}} вопросов
- [ ] Есть вопросы с options (recognition/recall) и открытые вопросы (explanation/diagnosis/application/transfer)
- [ ] У всех открытых вопросов rubric (explanation) содержит конкретные критерии
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
  const obj = (data ?? {}) as Record<string, unknown>;
  if (!Array.isArray(obj.questions)) return [];

  const parsed: AssessmentQuestionResult[] = [];
  for (const raw of obj.questions as unknown[]) {
    const q = (raw ?? {}) as Record<string, unknown>;

    const type = typeof q.type === "string" ? q.type : "recall";
    const options = Array.isArray(q.options)
      ? (q.options as unknown[]).filter((o): o is string => typeof o === "string")
      : [];

    // Вариантный вопрос обязан быть проверяемым: резолвим index/текст варианта
    // через общий резолвер (см. lib/optionMatching). Если индекс не разрешить,
    // ответить на такой вопрос честно нельзя — выбрасываем, чтобы не портить
    // замер неверной автоматической проверкой.
    const correctAnswer =
      options.length > 0
        ? resolveCorrectAnswerIndex(options, typeof q.correctAnswer === "string" ? q.correctAnswer : "")
        : typeof q.correctAnswer === "string"
          ? q.correctAnswer
          : "";
    if (options.length > 0 && correctAnswer === "") continue;

    parsed.push({
      id: typeof q.id === "string" && q.id.length > 0 ? q.id : shortIdWith("q_"),
      type,
      nodeId: typeof q.nodeId === "string" ? q.nodeId : "",
      question: typeof q.question === "string" ? q.question : "",
      options,
      correctAnswer,
      explanation: typeof q.explanation === "string" ? q.explanation : "",
    });
  }

  return parsed;
}
