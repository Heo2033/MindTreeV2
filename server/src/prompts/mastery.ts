import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface MasteryPromptContext {
  topic: string;
  targetLevel: string;
  items: Array<{
    nodeId: string;
    label: string;
    type: string;
    userAnswer: string;
    correct?: boolean;
    rubric?: string;
  }>;
}

export const PROMPT_MASTERY = `# Роль
Ты — преподаватель, определяющий освоение материала. Оцени по ответам пользователя, достиг ли он целевого уровня.

# Контекст
Тема: "{{topic}}"
Целевой уровень: {{target_level}}

# Ответы пользователя на проверку
{{items_json}}

# Задача
Для КАЖДОГО понятия оцени метрики освоения (0..1):
- understanding — понимание идеи
- recall — способность воспроизвести
- application — способность применить
- transfer — способность перенести на новую ситуацию

Также:
- определи misconception по каждому понятию (тип и описание), или null если нет
- дай общий вердикт: достиг ли пользователь целевого уровня (enough: true/false)
- если not enough — укажи, чего не хватает

# Типы misconceptions
unknown (не знал), confused (перепутал понятия), incomplete (неполная модель), definition_only (знает только определение), mechanism_error (неверный механизм), application_failure (не смог применить), careless (небрежная ошибка).

# Формат ответа
Строгий JSON-объект:
{
  "concepts": [
    {"nodeId":"n2_a","understanding":0.8,"recall":0.9,"application":0.6,"transfer":0.5,"confidence":0.75,"misconception":null},
    {"nodeId":"n2_b","understanding":0.4,"recall":0.3,"application":0.2,"transfer":0.1,"confidence":0.3,"misconception":{"type":"incomplete","description":"Не объясняет reverse diffusion как итеративный процесс"}}
  ],
  "enough": false,
  "overall_level": "solid_understanding",
  "gaps": ["Разделённые концепции: ...", "Не хватает: ..."]
}
${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Описания misconceptions и gaps — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.`;

export function buildMasteryPrompt(ctx: MasteryPromptContext): string {
  const itemsJson = JSON.stringify(
    ctx.items.map((i) => ({
      nodeId: i.nodeId,
      label: i.label,
      type: i.type,
      userAnswer: i.userAnswer?.slice(0, 800),
      correct: i.correct,
      rubric: i.rubric?.slice(0, 400),
    })),
  );

  return PROMPT_MASTERY
    .replace("{{topic}}", ctx.topic)
    .replace("{{target_level}}", ctx.targetLevel)
    .replace("{{items_json}}", itemsJson);
}

export interface MasteryResult {
  concepts: Array<{
    nodeId: string;
    understanding: number;
    recall: number;
    application: number;
    transfer: number;
    confidence: number;
    misconception: { type: string; description: string } | null;
  }>;
  enough: boolean;
  overall_level: string;
  gaps: string[];
}

export function parseMasteryResult(data: unknown): MasteryResult {
  const obj = (data ?? {}) as Record<string, unknown>;
  const concepts = Array.isArray(obj.concepts)
    ? (obj.concepts as Array<Record<string, unknown>>).map((c) => ({
        nodeId: typeof c.nodeId === "string" ? c.nodeId : "",
        understanding: typeof c.understanding === "number" ? c.understanding : 0,
        recall: typeof c.recall === "number" ? c.recall : 0,
        application: typeof c.application === "number" ? c.application : 0,
        transfer: typeof c.transfer === "number" ? c.transfer : 0,
        confidence: typeof c.confidence === "number" ? c.confidence : 0,
        misconception:
          c.misconception && typeof c.misconception === "object"
            ? {
                type: String((c.misconception as Record<string, unknown>).type ?? "unknown"),
                description: String((c.misconception as Record<string, unknown>).description ?? ""),
              }
            : null,
      }))
    : [];

  return {
    concepts,
    enough: obj.enough === true,
    overall_level: typeof obj.overall_level === "string" ? obj.overall_level : "awareness",
    gaps: Array.isArray(obj.gaps)
      ? (obj.gaps as unknown[]).filter((g): g is string => typeof g === "string")
      : [],
  };
}
