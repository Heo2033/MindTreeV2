import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";

export const PROMPT_STRUCTURE = `# Роль
Ты — педагог-структуролог. Твоя задача — построить онтологию (скелет) дерева знаний о теме.

# Задача
Построй иерархическую структуру понятий по теме: от сути к деталям.
Генерируй ТОЛЬКО заголовки (titles) + канонические определения. НЕ генерируй one_liner, details, analogy.

# Правила
- Уровень 1: 1 корень — краткое название темы (1–4 слова).
- Уровень 2: 3–5 узлов — главные части/категории темы.
- Порядок веток уровня 2 в ответе — рекомендуемый порядок изучения: сначала базовые и вводные, затем продвинутые и прикладные.
- Уровень 3: у каждого узла уровня 2 — по 3–7 дочерних. Покрывай ВСЕ основные подкатегории, не пропуская важные.
- Не углубляй глубже уровня 3.
- Форма — раскидистая крона, НЕ столб.
- Одно понятие — одно место. Нет дублей.
- На каждом уровне — единый уровень абстракции (не смешивать общее и частное).
- label — техническое название понятия (термин), 1–4 слова. Не метафоры.
- Если тема содержит конкретный перечень элементов (масти, виды, типы, этапы) — перечисляй ВСЕ, не сокращай до 2–4 примеров.
- Каждый узел уровня 2 — независимая подтема с единой внутренней логикой. Узлы L2 не должны описывать один и тот же аспект с разной детализацией.
- Если тема содержит несколько конкурирующих подходов или архитектур (например, U-Net vs DiT vs Transformer), выдели их как отдельные узлы на одном уровне.
- Дочерние узлы (L3+) не должны повторять определение родителя (L2) другими словами. Ребенок расширяет parent, а не переописывает его.
- Все id начинаются с "n" + цифра (n1_, n2_, n3_...). Запрещены nc_*, random_* и другие форматы. Каждый узел (кроме корня) обязан иметь parentId.
${NO_META_RULE}
${ALPHABET_RULE}
{{audience_block}}
# Язык
Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.

# Онтологический контракт
Для КАЖДОГО узла (включая корень) сгенерируй:
- **canonical_definition** — строгое определение (1–2 предложения). Это источник истины. Content-модель будет основываться на нём.
- **semantic_axis** — ось классификации. Один из: architecture, process, sampling, representation, loss, encoding, conditioning, application, theory, evaluation.
- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций. Это то, что content-модель НЕ должна утверждать.

Примеры осей:
- architecture: U-Net, DiT, VAE, CLIP — это архитектуры/модули
- process: прямой процесс, обратный процесс, обучение — это процессы
- sampling: DDPM, DDIM, DPM-Solver — это методы сэмплинга
- loss: MSE, ELBO, cross-entropy — это функции потерь
- conditioning: текстовое условие, классовая условность — это методы условия

Запрет смешивания осей: нельзя делать DiT child для latent_diffusion (это оси architecture и representation).

# Формат ответа
Только валидный JSON-объект:
{"nodes":[{"id":"n1_root","title":"Тема","canonical_definition":"...","semantic_axis":"theory","forbidden_interpretations":["..."]},{"id":"n2_a","title":"Категория A","parentId":"n1_root","conceptType":"concept","canonical_definition":"...","semantic_axis":"architecture"},{"id":"n3_a1","title":"Понятие A1","parentId":"n2_a","conceptType":"mechanism","canonical_definition":"...","semantic_axis":"process","forbidden_interpretations":["..."]}]}

Допустимые значения conceptType: "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".
- topic — корень дерева или крупная область
- concept — абстрактное понятие, теория
- component — часть системы, модуль, блок
- mechanism — внутреннее устройство, как что-то работает
- process — последовательность шагов, алгоритм, pipeline
- property — характеристика, параметр, качество
- rule — закон, принцип, ограничение
- method — подход, техника, способ решения
- example — конкретный пример, кейс

Допустимые значения semantic_axis: "architecture", "process", "sampling", "representation", "loss", "encoding", "conditioning", "application", "theory", "evaluation".

Узлы L2 и L3 должны иметь conceptType и semantic_axis. У корня (L1) — conceptType="topic", semantic_axis="theory".

Никакого текста вне JSON. Без \`\`\`json и без пояснений.

# Проверь перед ответом
- [ ] 7–12 узлов, 3–5 веток на уровне 2
- [ ] title — термины, не метафоры
- [ ] корень = точное название темы
- [ ] нет дублей: одно понятие — одно место
- [ ] на каждом уровне единый уровень абстракции
- [ ] ветки уровня 2 идут в порядке изучения: от базовых к продвинутым
- [ ] формат — строго JSON с ключом "nodes"
- [ ] все title и canonical_definition — на русском (кроме устоявшихся аббревиатур)
- [ ] нет дублирования: child не повторяет parent
- [ ] конкурирующие архитектуры/подходы представлены на одном уровне
- [ ] semantic_axis консистентен с conceptType
- [ ] forbidden_interpretations реалистичны и предотвращают галлюцинации

Тема пользователя: "{{user_query}}"`;

const GOAL_HINTS: Record<string, string> = {
  overview: "Цель читателя — общий обзор темы. Отдавай приоритет широкому покрытию: все ключевые области, минимум узких деталей.",
  exam: "Цель читателя — подготовка к экзамену. Включай термины, определения, классификации и то, что обычно спрашивают на проверочных работах.",
  deep: "Цель читателя — глубокое погружение. Включай механизмы, внутренние процессы, нюансы и продвинутые подтемы, даже если они редкие.",
};

const LEVEL_HINTS: Record<string, string> = {
  beginner: "Читатель — новичок. Начинай с базовых понятий, не предполагай знакомства со смежными областями.",
  intermediate: "Читатель знаком с основами. Базовые понятия можно группировать компактно, освобождая место для сути.",
  expert: "Читатель — специалист. Пропускай тривиальные понятия, фокусируйся на профессиональных деталях и тонкостях.",
};

export interface IStructurePromptOptions {
  goal?: string;
  level?: string;
}

export function buildStructurePrompt(
  userQuery: string,
  options?: IStructurePromptOptions,
): string {
  const sanitized = userQuery
    .replace(/\r/g, "")
    .replace(/^#+\s/gm, "")
    .replace(/^[-*]\s/gm, "")
    .trim();

  const hints: string[] = [];
  if (options?.goal && GOAL_HINTS[options.goal]) {
    hints.push(`- ${GOAL_HINTS[options.goal]}`);
  }
  if (options?.level && LEVEL_HINTS[options.level]) {
    hints.push(`- ${LEVEL_HINTS[options.level]}`);
  }
  const audienceBlock = hints.length > 0
    ? `\n# Аудитория\n${hints.join("\n")}\n`
    : "";

  return PROMPT_STRUCTURE.replace("{{audience_block}}", audienceBlock).replace(
    "{{user_query}}",
    sanitized,
  );
}
