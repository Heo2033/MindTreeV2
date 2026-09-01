import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_CONTENT = `# Роль
Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.

# Контекст
Тема: "{{root_topic}}"
Путь: {{node_path}}
Соседи: {{siblings}}
{{audience_block}}
{{ontology_context}}
# Задача
Опиши узел «{{node_title}}»:

- one_liner — СУТЬ в одном предложении (макс. 120 символов). Без воды, без вводных фраз. Прямо к делу.
- details — КРАТКАЯ справка: 1–2 предложения (макс. 500 символов). Факты, цифры, ключевые свойства. Никаких рассуждений. Если понятие включает формулу или математическое выражение, записывай его в LaTeX: инлайн — $формула$, блочная — $$формула$$.
- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). Если метафора не приходит в голову — верни "".
- relations — СВЯЗИ с другими понятиями (см. формат ниже). Генерируй 2–4 связи, если они есть.

# Типы связей
- related — общая связь
- depends_on — зависит от
- requires — требует знания
- example_of — является примером
- similar_to — похоже на
- contrasts_with — противоположно
- causes — вызывает
- enables — позволяет/делает возможным
- used_for — используется для
- alternative_to — альтернатива
- derives_from — вытекает из
- parameterizes — параметризует
- approximates — аппроксимирует
- generalizes — обобщает
- implements — реализует
- explains_why — объясняет почему (цепочка «зачем?»)

# Антипаттерны (НЕ пиши)
- "Данное понятие означает..."
- "В системе Таро это..."
- "Является важной частью..."
- "Описывает сферу..."
- Повторение родителя или детей
- Общие фразы без конкретики

# Правила
- Факты > рассуждений.
- Конкретика > абстракции.
- Если у понятия есть компоненты — перечисли их.
- Если понятие — конкретный объект (карта, термин) — опиши его функцию, не общую теорию.
- В relations указывай id узлов из дерева. Если подходящего id нет — не генерируй связь.
- Используй canonical_definition как основу для details. Не противоречь ему.
- Не нарушай forbidden_interpretations — не утверждай то, что запрещено.
- Не смешивай semantic_axis — не описывай архитектуру как процесс и наоборот.
- Не противоречь parent, ancestors и siblings.
${NO_META_RULE}
${ALPHABET_RULE}

# Язык
Отвечай СТРОГО на русском языке.
Все термины в one_liner и details — на русском. Исключение: устоявшиеся аббревиатуры
(U-Net, DDPM, VAE, CLIP, Stable Diffusion, ControlNet, DiT, NeRF, DDIM и т.д.).
Всё остальное переводи.

# Формат
Только JSON:
{"one_liner":"...","details":"...","analogy":"...","relations":[{"from":"id_этого_узла","to":"id_другого_узла","type":"requires","label":"опционально"}],"claims":[{"subject":"название_узла","predicate":"is_a","object":"категория"},{"subject":"название_узла","predicate":"alternative_to","object":"альтернатива"}]}

Claims — это список утверждений, которые содержит этот узел. Они используются для валидации.
Predicates: is_a, has_a, part_of, alternative_to, implements, requires, enables, contradicts, depends_on, related_to.

Если analogy не нужна: "analogy": "".
Если relations нет: "relations": [].
Если claims нет: "claims": [].
В поле from используй id текущего узла: "{{node_id}}".

Никакого текста вне JSON.`;

export interface IContentPromptContext {
  rootTopic: string;
  nodePath: string[];
  node: {
    id: string;
    label?: string;
    oneLiner?: string;
  };
  siblings: string[];
  level?: string;
  ontologyContext?: {
    canonical_definition?: string;
    semantic_axis?: string;
    forbidden_interpretations?: string[];
    parent_canonical_definition?: string;
    siblings_with_axes?: Array<{ id: string; label: string; axis?: string }>;
  };
}

const LEVEL_TONES: Record<string, string> = {
  beginner: "Пиши максимально доступно для новичка, без профессионального жаргона.",
  intermediate: "Пиши для знакомого с основами читателя.",
  expert: "Пиши для специалиста, используй точную терминологию.",
};

export function buildContentPrompt(ctx: IContentPromptContext): string {
  const sanitizedTopic = ctx.rootTopic
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  const tone =
    ctx.level && LEVEL_TONES[ctx.level]
      ? `\n# Аудитория\n${LEVEL_TONES[ctx.level]}\n`
      : "";

  let ontologyBlock = "";
  if (ctx.ontologyContext) {
    const parts: string[] = [];
    if (ctx.ontologyContext.canonical_definition) {
      parts.push(`Каноническое определение: ${ctx.ontologyContext.canonical_definition}`);
    }
    if (ctx.ontologyContext.semantic_axis) {
      parts.push(`Ось классификации: ${ctx.ontologyContext.semantic_axis}`);
    }
    if (ctx.ontologyContext.forbidden_interpretations && ctx.ontologyContext.forbidden_interpretations.length > 0) {
      parts.push(`Запрещённые интерпретации: ${ctx.ontologyContext.forbidden_interpretations.join("; ")}`);
    }
    if (ctx.ontologyContext.parent_canonical_definition) {
      parts.push(`Определение родителя: ${ctx.ontologyContext.parent_canonical_definition}`);
    }
    if (ctx.ontologyContext.siblings_with_axes && ctx.ontologyContext.siblings_with_axes.length > 0) {
      const sibStr = ctx.ontologyContext.siblings_with_axes
        .map((s) => `${s.label} (${s.axis ?? "?"})`)
        .join(", ");
      parts.push(`Соседние понятия: ${sibStr}`);
    }
    if (parts.length > 0) {
      ontologyBlock = `\n# Онтологический контекст\n${parts.join("\n")}\n`;
    }
  }

  return PROMPT_CONTENT
    .replace("{{audience_block}}", tone)
    .replace("{{ontology_context}}", ontologyBlock)
    .replace("{{root_topic}}", sanitizedTopic)
    .replace("{{node_path}}", ctx.nodePath.join(" → "))
    .replace("{{siblings}}", ctx.siblings.join(", "))
    .replace("{{node_id}}", ctx.node.id)
    .replace("{{node_title}}", ctx.node.label ?? ctx.node.oneLiner ?? "");
}
