import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

/**
 * §64: domain detection for factual reliability.
 * Topics in these domains require source citations — AI-generated content
 * must not be automatically considered reliable.
 */
const CRITICAL_DOMAIN_KEYWORDS = [
  "медицина", "медицин", "фармаколог", "фармац", "терапи", "хирург",
  "патолог", "анатом", "физиолог", "клини", "диагност",
  "law", "право", "юрис", "уголовн", "гражданск",
  "finance", "финанс", "экономик", "бухгалт", "налог",
  "medicine", "medical", "pharmacolog", "clinical", "surgery",
  "legal", "jurisprud",
  "exam", "экзамен", "сертиф", " licens",
  "наук", "scientific", "исследован",
];

export function isCriticalDomain(topicName: string, nodePath: string[] = []): boolean {
  const text = [topicName, ...nodePath].join(" ").toLowerCase();
  return CRITICAL_DOMAIN_KEYWORDS.some((kw) => text.includes(kw));
}

export const PROMPT_CONTENT = `# Роль
Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.

# Контекст
Тема: "{{root_topic}}"
Путь: {{node_path}}
Соседи: {{siblings}}
{{audience_block}}
{{goal_block}}
{{root_block}}
{{root_formula_ban}}
{{ontology_context}}
# Задача
Опиши узел «{{node_title}}»:

- one_liner — СУТЬ в одном предложении (макс. 120 символов). Без воды, без вводных фраз. Прямо к делу.
- details — КРАТКАЯ справка. {{details_instruction}}
- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). Если метафора не приходит в голову — верни "".

{{details_structure_block}}
{{complexity_block}}
{{factual_discipline_block}}

# Связи
Связи в этом ответе НЕ генерируются: всегда "relations": [].
Связи уже заданы на структурной стадии, где известны настоящие id узлов, и при генерации контента их нельзя переписать или выдумать заново.

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
- Используй canonical_definition как основу для details. Не противоречь ему.
- Не нарушай forbidden_interpretations — не утверждай то, что запрещено.
- Не смешивай semantic_axis — не описывай архитектуру как процесс и наоборот.
- Не противоречь parent, ancestors и siblings.
${NO_META_RULE}
{{anti_jargon_block}}
${ALPHABET_RULE}
{{sources_block}}
# Язык
Отвечай СТРОГО на русском языке.
Все термины в one_liner и details — на русском. Исключение: устоявшиеся аббревиатуры
(U-Net, DDPM, VAE, CLIP, Stable Diffusion, ControlNet, DiT, NeRF, DDIM и т.д.).
Всё остальное переводи.

# Формат
Только JSON:
{"one_liner":"...","details":"...","analogy":"...","relations":[],"claims":[{"subject":"название_узла","predicate":"is_a","object":"категория"},{"subject":"название_узла","predicate":"alternative_to","object":"альтернатива"}],"sources":["URL_or_название_источника"]}

Claims — это список утверждений, которые содержит этот узел. Они используются для валидации.
Predicates: is_a, has_a, part_of, alternative_to, implements, requires, enables, contradicts, depends_on, related_to.
{{sources_format_note}}

Если analogy не нужна: "analogy": "".
Всегда: "relations": [] (связи заданы на структурной стадии).
Если claims нет: "claims": [].

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
  /** KnowledgeLevel аудитории (beginner|intermediate|expert) — от уровня цели темы. */
  knowledgeLevel?: string;
  /** Цель изучения темы (overview|exam|deep). */
  goal?: string;
  /** Уровень узла в дереве (1 = корень). */
  nodeLevel?: number;
  isRoot?: boolean;
  /** §64: when true, LLM is asked to include source citations. */
  isCriticalDomain?: boolean;
  ontologyContext?: {
    canonical_definition?: string;
    semantic_axis?: string;
    forbidden_interpretations?: string[];
    parent_canonical_definition?: string;
    siblings_with_axes?: Array<{ id: string; label: string; axis?: string }>;
  };
}

const LEVEL_TONES: Record<string, string> = {
  beginner: "Пиши максимально доступно для новичка, без профессионального жаргона. Каждый специальный термин объясняй сразу простыми словами.",
  intermediate: "Пиши для знакомого с основами читателя. Термины раскрывай через интуицию: сначала «как работает», затем термин.",
  expert: "Пиши для специалиста, используй точную терминологию. Можно опускать базовые объяснения.",
};

const GOAL_HINTS: Record<string, string> = {
  overview: "Цель — общий обзор: опиши суть и место понятия в теме, без глубоких деталей.",
  exam: "Цель — подготовка к экзамену: делай акцент на ключевых фактах, определениях и формулировках.",
  deep: "Цель — глубокое изучение: кроме сути кратко обозначь механизм/устройство и подтемы, которые стоит разобрать.",
};

const ROOT_GUIDANCE = `\n# Корневой узел (обзор темы)
Это корневой/обзорный узел. СТРОГО соблюдай:
- ТОЛЬКО интуиция «как это работает» + краткий перечень подтем (roadmap «что разберём дальше»).
- НЕ углубляйся в механику, математику и формулы на корневом узле — это задача дочерних узлов.
- Для цели deep особенно: покажи «зачем» и «что дальше», а не сжатую сводку.
- Не противоречь дочерним узлам — не опережай их content.`;

const ANTI_JARGON_RULE = `\n# Антижаргон (обязательное правило)
- КАЖДЫЙ специальный термин (например «градиент лог-плотности», «score», «марковская цепь», «максимизация правдоподобия») объясни простыми словами в ТОМ ЖЕ предложении.
- ЗАПРЕЩЕНО использовать термин, который ты не можешь объяснить простыми словами без жаргона.
- ЗАПРЕЩЕНО давать плотную энциклопедическую выжимку: обучай читателя, а не перечисляй термины.
- Если термин не влияет на понимание сути — опусти его.`;

const DETAILS_INSTRUCTION = `1–2 предложения (ЖЁСТКИЙ лимит 500 символов: если не укладываешься — сокращай, лимит важнее полноты). Факты, цифры, ключевые свойства. Если понятие включает формулу или математическое выражение, записывай его в LaTeX: инлайн — $формула$, блочная — $$формула$$. ЗАПРЕЩЕНО оборачивать формулу в обратные кавычки или ограждения \`\`\`кода\`\`\` — рендерер не понимает markdown и ломает вывод. Только $формула$ без кавычек.`;

/** Двухчастная структура details для non-expert + цель deep: «Интуиция» + «Механика». */
const TWO_PART_DETAILS_BLOCK = `\n# Структура подробностей
Для этой аудитории и цели (intermediate/beginner + deep) оформи details в РОВНО ДВА абзаца, разделённых пустой строкой (\n\n), в точности с этими заголовками и по одному разу:
1. «Интуиция:» — 1–2 предложения простыми словами, БЕЗ терминов: как это работает.
2. «Механика:» — ключевые термины/механизм, но КАЖДЫЙ термин сопровождай однострочным пояснением сразу после него.
Третьего абзаца и повторных заголовков быть не должно. Не вылезай за лимит символов.`;

/** Запрет голых формул в корневом узле. */
const ROOT_FORMULA_BAN = `\n# Формулы на корневом узле
Это корневой узел. НЕ пиши голые математические формулы. Опиши смысл словами (например: «сеть по более зашумленному кадру восстанавливает чуть менее зашумлённый»). Формулы и математика — на дочерние узлы.`;

/** Зеркало `_factualDisciplineBlock` в prompts.dart (flutter), от 02.10.2026. */
const FACTUAL_DISCIPLINE_BLOCK = `\n# Фактическая дисциплина (обязательно)
- НЕ приписывай авторам, статьям и годам то, чего не знаешь наверняка. Если авторство или год не уверены — не пиши их вообще.
- НЕ отождествляй разные понятия. Проверь каждое утверждение вида «X — это Y» и «X даёт Y»: если это лишь похожее или связанное, пиши точнее.
- Утверждай только то, что следует из общепринятых фактов; сомневаешься — не утверждай.
- Не называй быстрый метод медленным и наоборот: оценивай свойства по самому методу.`;

/** Зеркало `_complexityBlock` в prompts.dart (flutter), от 02.10.2026. */
const COMPLEXITY_BLOCK = `\n# Сложность (обязательно)
- Одно предложение — одна мысль. Не строй длинные цепочки с придаточными.
- Каждую аббревиатуру при первом появлении расшифруй: DDIM (denoising diffusion implicit model, неявная диффузионная модель).
- Термин, который не можешь объяснить в одном простом предложении, — не используй.
- Если без термина нельзя обойтись — сначала смысл обычными словами, потом термин.
- Не перечисляй формулы и методы списком: объясни, зачем они нужны.`;

export function buildContentPrompt(ctx: IContentPromptContext): string {
  const sanitizedTopic = ctx.rootTopic
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  const tone =
    ctx.knowledgeLevel && LEVEL_TONES[ctx.knowledgeLevel]
      ? `\n# Аудитория\n${LEVEL_TONES[ctx.knowledgeLevel]}\n`
      : "";

  const goalBlock = ctx.goal && GOAL_HINTS[ctx.goal] ? `\n# Цель\n${GOAL_HINTS[ctx.goal]}\n` : "";

  const rootBlock = ctx.isRoot || ctx.nodeLevel === 1 ? ROOT_GUIDANCE : "";

  const antiJargon =
    ctx.knowledgeLevel && ctx.knowledgeLevel !== "expert" ? ANTI_JARGON_RULE : "";

  const detailsInstruction = DETAILS_INSTRUCTION;

  // Двухчастная структура «Интуиция + Механика» — для non-expert + цель deep
  const twoPartDetails =
    ctx.knowledgeLevel && ctx.knowledgeLevel !== "expert" && ctx.goal === "deep"
      ? TWO_PART_DETAILS_BLOCK
      : "";

  // На корневом узле голые формулы запрещены
  const rootFormulaBan = ctx.isRoot || ctx.nodeLevel === 1 ? ROOT_FORMULA_BAN : "";

  // Блок сложности — только не-expert: у эксперта жаргон уместен.
  // Фактическая дисциплина нужна всем уровням.
  const complexity =
    ctx.knowledgeLevel && ctx.knowledgeLevel !== "expert" ? COMPLEXITY_BLOCK : "";

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
    .replace("{{goal_block}}", goalBlock)
    .replace("{{root_block}}", rootBlock)
    .replace("{{anti_jargon_block}}", antiJargon)
    .replace("{{details_instruction}}", detailsInstruction)
    .replace("{{details_structure_block}}", twoPartDetails)
    .replace("{{complexity_block}}", complexity)
    .replace("{{factual_discipline_block}}", FACTUAL_DISCIPLINE_BLOCK)
    .replace("{{root_formula_ban}}", rootFormulaBan)
    .replace("{{ontology_context}}", ontologyBlock)
    .replace("{{root_topic}}", sanitizedTopic)
    .replace("{{node_path}}", ctx.nodePath.join(" → "))
    .replace("{{siblings}}", ctx.siblings.join(", "))
    .replace("{{node_id}}", ctx.node.id)
    .replace("{{node_title}}", ctx.node.label ?? ctx.node.oneLiner ?? "")
    .replace(
      "{{sources_block}}",
      ctx.isCriticalDomain
        ? `# Источники (§64: factual reliability)\nЭта тема относится к критически важной области (медицина, право, финансы, наука, экзамен).\nВключи в JSON поле sources — массив из 2–4 наиболее авторитетных источников (название книги/статьи/URL или DOI), на которые опирается описание.\nНе придумывай источники — указывай только реальные, общепризнанные.\nЕсли достоверных источников нет — верни "sources": [].\n`
        : "",
    )
    .replace(
      "{{sources_format_note}}",
      ctx.isCriticalDomain
        ? 'Если sources запрошены: "sources": ["источник1", "источник2"].\nЕсли sources нет: "sources": [].'
        : 'Если sources нет: "sources": [].',
    );
}
