import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface MilestonePromptContext {
  topic: string;
  currentLevel: string;
  goal: string;
}

export const PROMPT_MILESTONE = `# Роль
Ты — навигатор по обучению. Составь карту уровней и направлений для темы.

# Контекст
Тема: "{{topic}}"
Текущий уровень: {{current_level}}
Цель пользователя: {{goal}}

# Задача
Составь последовательность milestones (уровней освоения) от текущего к более глубоким. Укажи для каждого:
- title — понятное название уровня
- description — что пользователь сможет делать
- capabilities — конкретные умения (2–5)
- estimated_hours — примерные часы
- alternative_paths — какие направления развиваются дальше

Базовая шкала уровней (адаптируй под тему):
awareness → basic_understanding → solid_understanding → practical_application → advanced → expert

# Формат ответа
Строгий JSON-объект:
{"milestones":[{"id":"m1","level":"solid_understanding","title":"Твёрдое понимание","description":"...","capabilities":["...","..."],"estimated_hours":2,"alternative_paths":[{"id":"m2","title":"Применение","estimated_hours":4,"description":"..."}]}]}

Отсортируй milestones от текущего к более глубоким. alternative_paths указывают ветвление после данного уровня.

${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.`;

export function buildMilestonePrompt(ctx: MilestonePromptContext): string {
  return PROMPT_MILESTONE
    .replace("{{topic}}", ctx.topic)
    .replace("{{current_level}}", ctx.currentLevel)
    .replace("{{goal}}", ctx.goal);
}

export interface MilestoneResult {
  milestones: Array<{
    id: string;
    level: string;
    title: string;
    description: string;
    capabilities: string[];
    estimated_hours: number;
    alternative_paths: Array<{
      id: string;
      title: string;
      estimated_hours: number;
      description: string;
    }>;
  }>;
}

export function parseMilestoneResult(data: unknown): MilestoneResult {
  const obj = (data ?? {}) as Record<string, unknown>;
  const milestones = Array.isArray(obj.milestones)
    ? (obj.milestones as Array<Record<string, unknown>>).map((m) => {
        const alt = Array.isArray(m.alternative_paths)
          ? (m.alternative_paths as Array<Record<string, unknown>>).map((a) => ({
              id: String(a.id ?? ""),
              title: String(a.title ?? ""),
              estimated_hours: typeof a.estimated_hours === "number" ? a.estimated_hours : 1,
              description: String(a.description ?? ""),
            }))
          : [];
        return {
          id: String(m.id ?? ""),
          level: String(m.level ?? ""),
          title: String(m.title ?? ""),
          description: String(m.description ?? ""),
          capabilities: Array.isArray(m.capabilities)
            ? (m.capabilities as unknown[]).filter((c): c is string => typeof c === "string")
            : [],
          estimated_hours: typeof m.estimated_hours === "number" ? m.estimated_hours : 1,
          alternative_paths: alt,
        };
      })
    : [];

  return { milestones };
}
