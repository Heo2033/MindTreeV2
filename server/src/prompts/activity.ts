import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface ActivityNodeContext {
  id: string;
  label?: string;
  one_liner: string;
  details: string;
  concept_type?: string;
  difficulty?: number;
}

export interface ActivitySessionContext {
  topic: string;
  goal: string;
  targetLevel: string;
}

export const PROMPT_ACTIVITY = `# Роль
Ты — AI-репетитор. Готовишь учебный материал для одного понятия внутри структурированной сессии изучения темы.

# Контекст
Тема: "{{topic}}"
Цель сессии: "{{goal}}"
Целевой уровень усвоения: "{{target_level}}"
Понятие: "{{node_label}}"
Определение: "{{node_one_liner}}"
Подробное объяснение: "{{node_details}}"
Тип понятия: "{{concept_type}}"
Сложность: {{difficulty}}

# Задача
Для этого понятия подготовь три элемента учебного цикла. Не смешивай их роли:
example — то, что ученик ЧИТАЕТ; apply.instruction — то, что ученик ДЕЛАЕТ.
1. example — готовый разобранный пример от третьего лица (2–4 предложения): конкретная ситуация, как понятие в ней работает, и почему это важно. Это НЕ задание ученику: не начинай с «Приведите…», «Рассмотрите…», «Опишите…» и не заканчивай вопросом.
2. recall — вопрос на припоминание (multiple choice) из 4 вариантов. Вопрос проверяет понимание понятия, а не заучивание формулировок.
3. apply — задание ученику от второго лица (императив: «Объясните…», «Приведите…»), решаемое за 1–3 минуты, + reference_answer — развёрнутый образец того, как ученик должен ответить: где применяется понятие и как именно.

Требования:
- Все тексты на русском языке, простым языком, по уровню цели ученика.
- example — новый пример, не повторяющий определение и не являющийся заданием.
- reference_answer — это НЕ определение и не пересказ one_liner: он отвечает на задание про применение (конкретная область или ситуация + как это работает). Определение может быть упомянуто только вскользь.
- Один из 4 вариантов recall — правильный, остальные правдоподобные, но неверные (типичные ошибки).
- Не отвечайте на вопрос внутри формулировок.
${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Строго JSON без markdown:
{
  "example": "строка",
  "recall": { "question": "строка", "options": ["а", "б", "в", "г"], "correct_index": 0 },
  "apply": { "instruction": "строка", "reference_answer": "строка" }
}`;

export interface ActivityGenResult {
  example: string;
  recall: {
    question: string;
    options: string[];
    correct_index: number;
  };
  apply: {
    instruction: string;
    reference_answer: string;
  };
}

export function buildActivityPrompt(ctx: ActivitySessionContext & ActivityNodeContext): string {
  return PROMPT_ACTIVITY.replace("{{topic}}", ctx.topic)
    .replace("{{goal}}", ctx.goal)
    .replace("{{target_level}}", ctx.targetLevel)
    .replace("{{node_label}}", ctx.label ?? ctx.one_liner)
    .replace("{{node_one_liner}}", ctx.one_liner.slice(0, 400))
    .replace("{{node_details}}", ctx.details.slice(0, 1200))
    .replace("{{concept_type}}", ctx.concept_type ?? "концепция")
    .replace("{{difficulty}}", String(ctx.difficulty ?? 0.5).slice(0, 4));
}

export function sanitizeActivityResult(raw: ActivityGenResult): ActivityGenResult {
  const options = Array.isArray(raw.recall?.options)
    ? raw.recall.options.map((o) => String(o).trim()).filter((o) => o !== "")
    : [];
  const safeOptions = options.length >= 2 ? options.slice(0, 4) : [];
  return {
    example: String(raw.example ?? "").trim(),
    recall: {
      question: String(raw.recall?.question ?? "").trim(),
      options: safeOptions,
      correct_index: Number.isInteger(raw.recall?.correct_index)
        ? Math.min(Math.max(Number(raw.recall.correct_index), 0), safeOptions.length - 1)
        : 0,
    },
    apply: {
      instruction: String(raw.apply?.instruction ?? "").trim(),
      reference_answer: String(raw.apply?.reference_answer ?? "").trim(),
    },
  };
}

export const PROMPT_ACTIVITY_FEEDBACK = `# Роль
Ты — AI-репетитор. Оцениваешь свободный ответ ученика на задание по конкретному понятию.

# Контекст
Понятие: "{{node_label}}"
Определение: "{{node_one_liner}}"
Задание: "{{instruction}}"
Эталонный ответ: "{{reference_answer}}"
Ответ ученика: "{{user_answer}}"

# Задача
Оцени ответ ученика:
- correct — ответ верен по сути, демонстрирует понимание понятия
- partial — ответ частично верен: есть верная мысль, но есть ошибки или пропущена ключевая часть
- incorrect — ответ неверен или не относится к заданию

Для partial и incorrect укажи возможное заблуждение (misconception) одной фразой, если его можно определить (null, если не определяется).

Требования:
- feedback — 1–3 предложения, по-русски, доброжелательно, конкретно: что верно, чего не хватает.
- Не раскрывай эталонный ответ целиком в feedback (ученик должен перепроверить сам).
${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Строго JSON без markdown:
{
  "assessment": "correct",
  "feedback": "строка",
  "misconception": "строка или null"
}`;

export interface FeedbackResult {
  assessment: "correct" | "partial" | "incorrect";
  feedback: string;
  misconception: string | null;
}

export function buildActivityFeedbackPrompt(ctx: {
  nodeLabel: string;
  nodeOneLiner: string;
  instruction: string;
  referenceAnswer: string;
  userAnswer: string;
}): string {
  return PROMPT_ACTIVITY_FEEDBACK.replace("{{node_label}}", ctx.nodeLabel)
    .replace("{{node_one_liner}}", ctx.nodeOneLiner.slice(0, 400))
    .replace("{{instruction}}", ctx.instruction.slice(0, 600))
    .replace("{{reference_answer}}", ctx.referenceAnswer.slice(0, 800))
    .replace("{{user_answer}}", ctx.userAnswer.slice(0, 1500));
}

export function sanitizeFeedbackResult(raw: FeedbackResult): FeedbackResult {
  const assessment =
    raw.assessment === "correct" || raw.assessment === "partial" || raw.assessment === "incorrect"
      ? raw.assessment
      : "partial";
  return {
    assessment,
    feedback: String(raw.feedback ?? "").trim(),
    misconception:
      raw.misconception && String(raw.misconception).trim() !== ""
        ? String(raw.misconception).trim()
        : null,
  };
}