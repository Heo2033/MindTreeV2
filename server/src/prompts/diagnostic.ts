import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export interface DiagnosticPromptContext {
  topic: string;
  goal: string;
  targetLevel: string;
  nodes: Array<{ id: string; label: string; one_liner: string }>;
}

export const PROMPT_DIAGNOSTIC = `# Роль
Ты — диагностирующий педагог. Оцени текущий уровень пользователя по теме.

# Контекст
Тема: "{{topic}}"
Цель пользователя: {{goal}}
Целевой уровень: {{target_level}}

# Ключевые понятия темы
{{nodes_json}}

# Задача
Составь короткую диагностику из 3–5 вопросов, которые проверяют, что пользователь уже знает, а что нет. Вопросы покрывают ключевые понятия темы в порядке от базовых к продвинутым.

Каждый вопрос относится к конкретному понятию (node_id) и проверяет понимание на уровне Awareness/Basic Understanding.

# Формат ответа
Строгий JSON-объект:
{"questions":[{"id":"d1","nodeId":"n2_a","question":"Что вы знаете о X?","options":["Вариант A","Вариант B","Вариант C","Вариант D"],"correctIndex":0,"explanation":"..."}]}

# После обработки
На основе ответов диагностики определяется текущий уровень:
- Если большинство правильных — current_level близок к target
- Если большинство неправильных — current_level = awareness

${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.

Никакого текста вне JSON. Без \`\`\`json и без пояснений.`;

export function buildDiagnosticPrompt(ctx: DiagnosticPromptContext): string {
  const nodesJson = JSON.stringify(
    ctx.nodes.map((n) => ({ id: n.id, label: n.label, one_liner: n.one_liner })),
  );

  return PROMPT_DIAGNOSTIC
    .replace("{{topic}}", ctx.topic)
    .replace("{{goal}}", ctx.goal)
    .replace("{{target_level}}", ctx.targetLevel)
    .replace("{{nodes_json}}", nodesJson);
}

export function parseDiagnosticResult(data: unknown): Array<{
  id: string;
  nodeId: string;
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}> {
  const obj = data as Record<string, unknown>;
  if (!Array.isArray(obj.questions)) return [];
  return (obj.questions as Array<Record<string, unknown>>).map((q) => ({
    id: typeof q.id === "string" ? q.id : `d_${Math.random().toString(36).slice(2, 8)}`,
    nodeId: typeof q.nodeId === "string" ? q.nodeId : "",
    question: typeof q.question === "string" ? q.question : "",
    options: Array.isArray(q.options)
      ? (q.options as unknown[]).filter((o): o is string => typeof o === "string")
      : [],
    correctIndex: typeof q.correctIndex === "number" ? q.correctIndex : 0,
    explanation: typeof q.explanation === "string" ? q.explanation : "",
  }));
}
