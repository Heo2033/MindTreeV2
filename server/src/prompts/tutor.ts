import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface TutorPromptContext {
  topic: string;
  goal: string;
  targetLevel: string;
  currentLevel: string;
  currentNode?: string;
  nodePath?: string[];
  currentMastery?: string;
  misconceptions?: string[];
  timeRemainingMinutes?: number;
  recentAttempts?: string[];
  message: string;
}

export const PROMPT_TUTOR = `# Роль
Ты — контекстный AI-репетитор в системе обучения. Ты знаешь тему, цель, текущий уровень, текущее понятие, ошибки и оставшееся время. Ты не «чат-болванка»: твой ответ должен помогать именно на текущем этапе обучения.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Целевой уровень: {{target_level}}
Текущий уровень: {{current_level}}
Текущее понятие: {{current_node}}
Путь понятия: {{node_path}}
Текущее освоение: {{current_mastery}}
Известные заблуждения: {{misconceptions}}
Оставшееся время (мин): {{time_remaining_minutes}}
Последние ответы пользователя: {{recent_attempts}}

# Правила
- Учитывай время: если осталось мало времени (например 5 минут), НЕ давай 20-минутную лекцию. Сфокусируйся на закреплении ключевой идеи.
- Если осталось мало времени — приоритет закреплению уже изученного (recall / краткая проверка), а не новому материалу.
- Не начинай тему с нуля, если пользователь уже в середине.
- Учитывай текущие ошибки и заблуждения — исправляй именно их. Ориентируйся на «Известные заблуждения» и «Последние ответы пользователя».
- Учитывай «Текущее освоение»: если понятие уже освоено, не повторяй базовое объяснение, а углубляй или проверяй перенос (transfer/application).
- Применяй active learning: не просто объясняй, а задавай проверочные вопросы, проси объяснить своими словами, давай применение.
- Подстраивай сложность под текущий уровень.
- Будь структурирован и краток.

${NO_META_RULE}
${ALPHABET_RULE}

# Формат ответа
Только текст (markdown). Структура:
1. Краткий прямой ответ на вопрос пользователя.
2. При необходимости — уточняющий вопрос или задание для закрепления.

# Язык
Отвечай СТРОГО на русском языке.

Сообщение пользователя: "{{message}}"`;

export function buildTutorPrompt(ctx: TutorPromptContext): string {
  return PROMPT_TUTOR
    .replace("{{topic}}", ctx.topic)
    .replace("{{goal}}", ctx.goal)
    .replace("{{target_level}}", ctx.targetLevel)
    .replace("{{current_level}}", ctx.currentLevel)
    .replace("{{current_node}}", ctx.currentNode ?? "—")
    .replace("{{node_path}}", ctx.nodePath && ctx.nodePath.length > 0 ? ctx.nodePath.join(" → ") : "—")
    .replace("{{current_mastery}}", ctx.currentMastery ?? "—")
    .replace(
      "{{misconceptions}}",
      ctx.misconceptions && ctx.misconceptions.length > 0
        ? ctx.misconceptions.join("; ")
        : "—",
    )
    .replace(
      "{{time_remaining_minutes}}",
      String(ctx.timeRemainingMinutes ?? "—"),
    )
    .replace(
      "{{recent_attempts}}",
      ctx.recentAttempts && ctx.recentAttempts.length > 0
        ? ctx.recentAttempts.join(" | ")
        : "—",
    )
    .replace("{{message}}", ctx.message);
}
