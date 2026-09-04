import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";
import { buildAudienceBlock, depthHintFor, timeHintFor, type IStructurePromptOptions } from "./structure.js";

export const PROMPT_L2 = `# Роль
Ты — педагог-структуролог. Твоя задача — построить уровень 2 (главные разделы) онтологии дерева знаний.

# Контекст
Тема пользователя: "{{user_query}}"
Корень дерева:
- Название: "{{root_title}}"
- Определение: {{root_definition}}

# Задача
Сгенерируй 3–5 узлов УРОВНЯ 2 — главные части/категории темы. Это разделы первого уровня, НЕ углубляйся далее. Подразделы (уровень 3) будут сгенерированы отдельными шагами для каждого раздела позже.
Генерируй ТОЛЬКО заголовки (titles) + канонические определения + метаданные. НЕ генерируй one_liner, details, analogy.

# Правила
- Уровень 2: 3–5 узлов — главные части/категории темы. Покрывай ВСЕ ключевые направления, не пропуская важные.
- Порядок веток в ответе — рекомендуемый порядок изучения: сначала базовые и вводные, затем продвинутые и прикладные.
- НЕ создавай уровень 3.
- {{depth_hint}}
- {{time_hint}}
- Форма — раскидистая крона, НЕ столб.
- Одно понятие — одно место. Нет дублей.
- На каждом уровне — единый уровень абстракции (не смешивать общее и частное).
- label — техническое название понятия (термин), 1–4 слова. Не метафоры.
- Если тема содержит конкретный перечень элементов (масти, виды, типы, этапы) — перечисляй ВСЕ, не сокращай до 2–4 примеров.
- Каждый узел уровня 2 — независимая подтема с единой внутренней логикой. Узлы L2 не должны описывать один и тот же аспект с разной детализацией.
- Если тема содержит несколько конкурирующих подходов или архитектур (например, U-Net vs DiT vs Transformer), выдели их как отдельные узлы на одном уровне.
- Все id начинаются с "n" + цифра (n2_, n3_...). Каждый узел обязан иметь parentId, равный id корня.
- Родителем всех узлов уровня 2 является корень с id "{{root_id}}".
${NO_META_RULE}
${ALPHABET_RULE}
{{audience_block}}
# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.

# Онтологический контракт
Для КАЖДОГО узла сгенерируй:
- **canonical_definition** — строгое определение (1–2 предложения). Это источник истины. Content-модель будет основываться на нём.
- **semantic_axis** — ось классификации. Один из: architecture, process, sampling, representation, loss, encoding, conditioning, application, theory, evaluation.
- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций.
- **conceptType** — "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".
- **importance** — число от 0 до 1.
- **difficulty** — число от 0 до 1.
- **estimated_time_minutes** — целое число.
- **prerequisites** — массив id понятий в этом скелете, на которые опирается узел (может быть []).
- **relations** — массив связей с другими узлами скелета: {"to": "id", "type": "requires"|"related"|"enables"|"used_for"|"example_of"|"similar_to"|"contrasts_with"|"causes"|"depends_on"|"alternative_to"} (может быть []).

Примеры осей:
- architecture: U-Net, DiT, VAE, CLIP — это архитектуры/модули
- process: прямой процесс, обратный процесс, обучение — это процессы
- sampling: DDPM, DDIM, DPM-Solver — это методы сэмплинга
- loss: MSE, ELBO, cross-entropy — это функции потерь
- conditioning: текстовое условие, классовая условность — это методы условия

Запрет смешивания осей: нельзя делать DiT child для latent_diffusion (это оси architecture и representation).

# Формат ответа
Только валидный JSON-объект:
{"nodes":[{"id":"n2_a","title":"Категория A","parentId":"{{root_id}}","level":2,"conceptType":"concept","canonical_definition":"...","semantic_axis":"architecture","forbidden_interpretations":["..."],"importance":0.6,"difficulty":0.5,"estimated_time_minutes":15,"prerequisites":[],"relations":[]},{"id":"n2_b","title":"Категория B","parentId":"{{root_id}}","level":2,...}]}

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] 3–5 узлов уровня 2 (БЕЗ уровня 3)
- [ ] title — термины, не метафоры
- [ ] нет дублей: одно понятие — одно место
- [ ] на каждом уровне единый уровень абстракции
- [ ] ветки идут в порядке изучения: от базовых к продвинутым
- [ ] формат — строго JSON с ключом "nodes"
- [ ] все title и canonical_definition — на русском (кроме устоявшихся аббревиатур)
- [ ] конкурирующие архитектуры/подходы представлены на одном уровне
- [ ] semantic_axis консистентен с conceptType
- [ ] у узлов заданы importance (0..1), difficulty (0..1), estimated_time_minutes, prerequisites, relations
- [ ] у каждого узла parentId = "{{root_id}}"`;

export interface IGenerateL2Context {
  userQuery: string;
  root: { id: string; title: string; canonical_definition?: string };
  options?: IStructurePromptOptions;
}

export function buildL2Prompt(ctx: IGenerateL2Context): string {
  const rootDef =
    ctx.root.canonical_definition?.trim() ||
    `Главная тема дерева знаний.`;

  const audience = buildAudienceBlock(ctx.options);

  return PROMPT_L2
    .replace("{{user_query}}", ctx.userQuery)
    .replace("{{root_title}}", ctx.root.title)
    .replace("{{root_definition}}", rootDef)
    .replaceAll("{{root_id}}", ctx.root.id)
    .replace("{{depth_hint}}", depthHintFor(ctx.options?.level))
    .replace("{{time_hint}}", timeHintFor(ctx.options?.timeBudgetMinutes))
    .replace("{{audience_block}}", audience);
}
