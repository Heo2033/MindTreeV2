// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

// ─── Shared constants (from rules.ts) ────────────────────────────────────────

const String noMetaRule =
    '- В значениях полей пиши только готовый контент по теме. '
    'Запрещены служебные фразы о своих действиях и решениях '
    '(«Узел помечен как…», «Переименовал узел…», «Этот узел не требует дочерних…», '
    '«Исправлено…»).';

const String alphabetRule =
    '- Используй только кириллицу, латиницу, цифры и обычную пунктуацию. '
    'Запрещены иероглифы и знаки других письменностей (китайские, японские, корейские).\n'
    '- Все label, title, one_liner, details — только на русском языке. '
    'Не используй непереведенные английские термины в текстовых полях.\n'
    '  Исключение: устоявшиеся аббревиатуры и названия моделей/алгоритмов, которые используются\n'
    '  на английском в профессиональном сообществе (U-Net, DDPM, VAE, CLIP, Stable Diffusion,\n'
    '  ControlNet, DALL-E, DiT, NeRF, DDIM, LoRA, EMA, BERT, GPT, ResNet, GAN, RAG,\n'
    '  Adam, SGD, ReLU, softmax и т.п.). Всё остальное переводи:\n'
    '    "Machine learning" → "Машинное обучение"\n'
    '    "Neural network" → "Нейронная сеть"\n'
    '    "Gradient descent" → "Градиентный спуск"\n'
    '    "Overfitting" → "Переобучение"\n'
    '    "Convolutional layers" → "Свёрточные слои"\n'
    '    "Gradient clipping" → "Обрезка градиентов"';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Replace first occurrence only (mirrors JS String.prototype.replace).
String _replaceOnce(String src, String pattern, String replacement) {
  final idx = src.indexOf(pattern);
  if (idx == -1) return src;
  return '${src.substring(0, idx)}$replacement${src.substring(idx + pattern.length)}';
}

/// Replace all occurrences.
String _replaceAll(String src, String pattern, String replacement) =>
    src.replaceAll(pattern, replacement);

String _sanitizeUserQuery(String q) => q
    .replaceAll('\r', '')
    .replaceAll(RegExp(r'^#+\s', multiLine: true), '')
    .replaceAll(RegExp(r'^[-*]\s', multiLine: true), '')
    .trim();

String _sanitizeTopic(String t) => t
    .replaceAll('\r', '')
    .replaceAll(RegExp(r'^#+\s', multiLine: true), '')
    .replaceAll(RegExp(r'^[-*]\s', multiLine: true), '')
    .trim();

// ═══════════════════════════════════════════════════════════════════════════════
// structure.ts  (L1 prompts + shared helpers)
// ═══════════════════════════════════════════════════════════════════════════════

const Map<String, String> structureGoalHints = {
  'overview':
      'Цель читателя — общий обзор темы. Отдавай приоритет широкому покрытию: '
      'все ключевые области, минимум узких деталей.',
  'exam':
      'Цель читателя — подготовка к экзамену. Включай термины, определения, '
      'классификации и то, что обычно спрашивают на проверочных работах.',
  'deep':
      'Цель читателя — глубокое погружение. Включай механизмы, внутренние процессы, '
      'нюансы и продвинутые подтемы, даже если они редкие.',
};

const Map<String, String> _levelHints = {
  'beginner':
      'Читатель — новичок. Начинай с базовых понятий, не предполагай знакомства '
      'со смежными областями.',
  'intermediate':
      'Читатель знаком с основами. Базовые понятия можно группировать компактно, '
      'освобождая место для сути.',
  'expert':
      'Читатель — специалист. Пропускай тривиальные понятия, фокусируйся на '
      'профессиональных деталях и тонкостях.',
};

String? masteryLevelToKnowledgeLevel(String? level) {
  switch (level) {
    case 'awareness':
    case 'basic_understanding':
      return 'beginner';
    case 'solid_understanding':
    case 'practical_application':
      return 'intermediate';
    case 'advanced':
    case 'expert':
      return 'expert';
    default:
      return null;
  }
}

String depthHintFor(String? level) {
  switch (masteryLevelToKnowledgeLevel(level)) {
    case 'beginner':
      return 'Глубина скелета — минимальная, ветки общие (обзорные категории '
          'без узких подразделов).';
    case 'intermediate':
      return 'Глубина скелета — средняя: ветки достаточно конкретные, покрывают '
          'ключевые подразделы.';
    case 'expert':
      return 'Глубина скелета — максимальная для базы: ветки узкоспециализированные, '
          'детальные категории.';
    default:
      return 'Глубина скелета — сбалансированная: ветки покрывают основные '
          'подразделы темы.';
  }
}

String timeHintFor(int? timeBudgetMinutes) {
  if (timeBudgetMinutes == null || timeBudgetMinutes <= 0) {
    return 'Временной бюджет не задан — стремись к компактной, но полной базе '
        '(4–5 веток).';
  }
  if (timeBudgetMinutes < 30) {
    return 'Временной бюджет — примерно 15–30 минут. База должна быть '
        'минимальной (3 ветки), акцент на самое важное.';
  }
  if (timeBudgetMinutes < 90) {
    return 'Временной бюджет — до ~1,5 часа. База средняя (4 ветки), '
        'покрывающая ключевые направления.';
  }
  return 'Временной бюджет — 1,5 часа и больше. База полная (5 веток), '
      'можно шире покрывать поднаправления.';
}

String buildAudienceBlock({
  String? goal,
  String? level,
}) {
  final hints = <String>[];
  if (goal != null && structureGoalHints.containsKey(goal)) {
    hints.add('- ${structureGoalHints[goal]}');
  }
  final mappedLevel = masteryLevelToKnowledgeLevel(level);
  if (mappedLevel != null && _levelHints.containsKey(mappedLevel)) {
    hints.add('- ${_levelHints[mappedLevel]}');
  }
  return hints.isNotEmpty ? '\n# Аудитория\n${hints.join('\n')}\n' : '';
}

// ── PROMPT_L1 ────────────────────────────────────────────────────────────────

const String promptL1 = '# Роль\n'
    'Ты — педагог-структуролог. Твоя задача — определить корень (тему) онтологии дерева знаний.\n'
    '\n'
    '# Задача\n'
    'Определи КОРНЕВОЙ узел дерева знаний о теме пользователя. Генерируй ТОЛЬКО корень — 1 узел уровня 1. Не создавай разделов, веток и дочерних узлов — они будут сгенерированы отдельными шагами позже.\n'
    '\n'
    '# Правила\n'
    '- Уровень 1: ровно 1 корень — краткое название темы (1–4 слова).\n'
    '- label — техническое название понятия (термин), 1–4 слова. Не метафоры.\n'
    '- {{depth_hint}}\n'
    '- Форма — раскидистая крона, НЕ столб.\n'
    '- id корня начинается с "n" + цифра (n1_root и т.п.).\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '{{audience_block}}'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.\n'
    '\n'
    '# Онтологический контракт (для корня)\n'
    '- **canonical_definition** — строгое определение темы (1–2 предложения). Это источник истины. Content-модель и генерация веток будут основываться на нём.\n'
    '- **semantic_axis** — "theory".\n'
    '- **conceptType** — "topic".\n'
    '- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций. Это то, что content-модель НЕ должна утверждать.\n'
    '- **importance** — число от 0 до 1.\n'
    '- **difficulty** — число от 0 до 1.\n'
    '- **estimated_time_minutes** — целое число: реалистичная общая оценка времени изучения темы.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{"nodes":[{"id":"n1_root","title":"Тема","parentId":null,"level":1,"conceptType":"topic","semantic_axis":"theory","canonical_definition":"...","forbidden_interpretations":["..."],"importance":0.5,"difficulty":0.5,"estimated_time_minutes":60,"prerequisites":[],"relations":[]}]}\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] ровно 1 узел (корень)\n'
    '- [ ] title — термин, не метафора\n'
    '- [ ] корень = точное название темы\n'
    '- [ ] semantic_axis = "theory", conceptType = "topic"\n'
    '- [ ] формат — строго JSON с ключом "nodes"\n'
    '\n'
    'Тема пользователя: "{{user_query}}"';

String buildL1Prompt(String userQuery, {String? goal, String? level}) {
  var result = _replaceOnce(promptL1, '{{audience_block}}',
      buildAudienceBlock(goal: goal, level: level));
  result = _replaceOnce(result, '{{depth_hint}}', depthHintFor(level));
  result = _replaceOnce(result, '{{user_query}}', _sanitizeUserQuery(userQuery));
  return result;
}

// ── PROMPT_L1_EDIT ───────────────────────────────────────────────────────────

const String promptL1Edit = '# Роль\n'
    'Ты — педагог-структуролог. Твоя задача — уточнить корень (тему) онтологии дерева знаний.\n'
    '\n'
    '# Задача\n'
    'Имеется уже созданный корень темы. Уточни его: проверь, что название и canonical_definition точно соответствуют теме пользователя. Исправь, если есть неточности. Верни ОДИН исправленный (или неизменённый) корневой узел.\n'
    '\n'
    '# Текущий корень\n'
    '{{current_root}}'
    '\n'
    '# Правила\n'
    '- label — техническое название понятия (термин), 1–4 слова. Не метафоры.\n'
    '- {depth_hint}\n'
    '- id корня сохрани прежним.\n'
    '- Не меняй parentId (должен быть null).\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '{{audience_block}}'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.\n'
    '\n'
    '# Онтологический контракт\n'
    '- **canonical_definition** — строгое определение темы (1–2 предложения).\n'
    '- **semantic_axis** — "theory".\n'
    '- **conceptType** — "topic".\n'
    '- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{"nodes":[{"id":"n1_root","title":"Тема","parentId":null,"level":1,"conceptType":"topic","semantic_axis":"theory","canonical_definition":"...","forbidden_interpretations":["..."],"importance":0.5,"difficulty":0.5,"estimated_time_minutes":60,"prerequisites":[],"relations":[]}]}\n'
    '\n'
    'Тема пользователя: "{{user_query}}"';

String buildL1EditPrompt(
  String userQuery,
  Map<String, dynamic> currentRoot, {
  String? goal,
  String? level,
}) {
  var result = _replaceOnce(
      promptL1Edit, '{{current_root}}', const JsonEncoder.withIndent('  ').convert(currentRoot));
  result = _replaceOnce(result, '{{audience_block}}',
      buildAudienceBlock(goal: goal, level: level));
  result = _replaceOnce(result, '{{depth_hint}}', depthHintFor(level));
  result = _replaceOnce(result, '{{user_query}}', _sanitizeUserQuery(userQuery));
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// generateL2.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptL2 = '# Роль\n'
    'Ты — педагог-структуролог. Твоя задача — построить уровень 2 (главные разделы) онтологии дерева знаний.\n'
    '\n'
    '# Контекст\n'
    'Тема пользователя: "{{user_query}}"\n'
    'Корень дерева:\n'
    '- Название: "{{root_title}}"\n'
    '- Определение: {{root_definition}}\n'
    '\n'
    '# Задача\n'
    'Сгенерируй 3–5 узлов УРОВНЯ 2 — главные части/категории темы. Это разделы первого уровня, НЕ углубляйся далее. Подразделы (уровень 3) будут сгенерированы отдельными шагами для каждого раздела позже.\n'
    'Генерируй ТОЛЬКО заголовки (titles) + канонические определения + метаданные. НЕ генерируй one_liner, details, analogy.\n'
    '\n'
    '# Правила\n'
    '- Уровень 2: 3–5 узлов — главные части/категории темы. Покрывай ВСЕ ключевые направления, не пропуская важные.\n'
    '- Порядок веток в ответе — рекомендуемый порядок изучения: сначала базовые и вводные, затем продвинутые и прикладные.\n'
    '- НЕ создавай уровень 3.\n'
    '- {{depth_hint}}\n'
    '- {{time_hint}}\n'
    '- Форма — раскидистая крона, НЕ столб.\n'
    '- Одно понятие — одно место. Нет дублей.\n'
    '- На каждом уровне — единый уровень абстракции (не смешивать общее и частное).\n'
    '- label — техническое название понятия (термин), 1–4 слова. Не метафоры.\n'
    '- Если тема содержит конкретный перечень элементов (масти, виды, типы, этапы) — перечисляй ВСЕ, не сокращай до 2–4 примеров.\n'
    '- Каждый узел уровня 2 — независимая подтема с единой внутренней логикой. Узлы L2 не должны описывать один и тот же аспект с разной детализацией.\n'
    '- Если тема содержит несколько конкурирующих подходов или архитектур (например, U-Net vs DiT vs Transformer), выдели их как отдельные узлы на одном уровне.\n'
    '- Все id начинаются с "n" + цифра (n2_, n3_...). Каждый узел обязан иметь parentId, равный id корня.\n'
    '- Родителем всех узлов уровня 2 является корень с id "{{root_id}}".\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '{{audience_block}}'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.\n'
    '\n'
    '# Онтологический контракт\n'
    'Для КАЖДОГО узла сгенерируй:\n'
    '- **canonical_definition** — строгое определение (1–2 предложения). Это источник истины. Content-модель будет основываться на нём.\n'
    '- **semantic_axis** — ось классификации. Один из: architecture, process, sampling, representation, loss, encoding, conditioning, application, theory, evaluation.\n'
    '- **forbidden_interpretations** — массив из 1–3 запрещённых интерпретаций.\n'
    '- **conceptType** — "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".\n'
    '- **importance** — число от 0 до 1.\n'
    '- **difficulty** — число от 0 до 1.\n'
    '- **estimated_time_minutes** — целое число.\n'
    '- **prerequisites** — массив id понятий в этом скелете, на которые опирается узел (может быть []).\n'
    '- **relations** — массив связей с другими узлами скелета: {"to": "id", "type": "requires"|"related"|"enables"|"used_for"|"example_of"|"similar_to"|"contrasts_with"|"causes"|"depends_on"|"alternative_to"} (может быть []).\n'
    '\n'
    'Примеры осей:\n'
    '- architecture: U-Net, DiT, VAE, CLIP — это архитектуры/модули\n'
    '- process: прямой процесс, обратный процесс, обучение — это процессы\n'
    '- sampling: DDPM, DDIM, DPM-Solver — это методы сэмплинга\n'
    '- loss: MSE, ELBO, cross-entropy — это функции потерь\n'
    '- conditioning: текстовое условие, классовая условность — это методы условия\n'
    '\n'
    'Запрет смешивания осей: нельзя делать DiT child для latent_diffusion (это оси architecture и representation).\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{"nodes":[{"id":"n2_a","title":"Категория A","parentId":"{{root_id}}","level":2,"conceptType":"concept","canonical_definition":"...","semantic_axis":"architecture","forbidden_interpretations":["..."],"importance":0.6,"difficulty":0.5,"estimated_time_minutes":15,"prerequisites":[],"relations":[]},{"id":"n2_b","title":"Категория B","parentId":"{{root_id}}","level":2,...}]}\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] 3–5 узлов уровня 2 (БЕЗ уровня 3)\n'
    '- [ ] title — термины, не метафоры\n'
    '- [ ] нет дублей: одно понятие — одно место\n'
    '- [ ] на каждом уровне единый уровень абстракции\n'
    '- [ ] ветки идут в порядке изучения: от базовых к продвинутым\n'
    '- [ ] формат — строго JSON с ключом "nodes"\n'
    '- [ ] все title и canonical_definition — на русском (кроме устоявшихся аббревиатур)\n'
    '- [ ] конкурирующие архитектуры/подходы представлены на одном уровне\n'
    '- [ ] semantic_axis консистентен с conceptType\n'
    '- [ ] у узлов заданы importance (0..1), difficulty (0..1), estimated_time_minutes, prerequisites, relations\n'
    '- [ ] у каждого узла parentId = "{{root_id}}"';

String buildL2Prompt({
  required String userQuery,
  required String rootId,
  required String rootTitle,
  String? rootCanonicalDefinition,
  String? goal,
  String? level,
  int? timeBudgetMinutes,
}) {
  final rootDef = (rootCanonicalDefinition?.trim().isNotEmpty ?? false)
      ? rootCanonicalDefinition!.trim()
      : 'Главная тема дерева знаний.';

  var result = _replaceOnce(promptL2, '{{user_query}}', userQuery);
  result = _replaceOnce(result, '{{root_title}}', rootTitle);
  result = _replaceOnce(result, '{{root_definition}}', rootDef);
  result = _replaceAll(result, '{{root_id}}', rootId);
  result = _replaceOnce(result, '{{depth_hint}}', depthHintFor(level));
  result = _replaceOnce(result, '{{time_hint}}', timeHintFor(timeBudgetMinutes));
  result = _replaceOnce(
      result, '{{audience_block}}', buildAudienceBlock(goal: goal, level: level));
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// generateL3.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptL3 = '# Роль\n'
    'Ты — педагог-структуролог. Твоя задача — построить уровень 3 (подразделы) для ОДНОГО конкретного раздела дерева знаний.\n'
    '\n'
    '# Контекст\n'
    'Тема пользователя: "{{user_query}}"\n'
    'Корень: {{root_title}}\n'
    '\n'
    '# Раздел, который ты раскрываешь\n'
    'Название: "{{parent_title}}"\n'
    'Определение: {{parent_definition}}\n'
    '\n'
    '# Остальные разделы этого же уровня (НЕ раскрывать, только контекст чтобы не дублировать)\n'
    '{{sibling_nodes}}'
    '\n'
    '# Задача\n'
    'Сгенерируй 2–4 дочерних узла УРОВНЯ 3 для раздела "{{parent_title}}". Это подразделы конкретного раздела.\n'
    'НЕ создавай уровень 4 — это задача выборочного расширения позже.\n'
    '\n'
    '# Определение конкретного ребёнка\n'
    'Каждый дочерний узел — это конкретное понятие/термин/подтема ВНУТРИ родителя "{{parent_title}}".\n'
    '- Если родитель описывает класс архитектур или подходов, дочерние узлы должны покрывать все основные варианты.\n'
    '- Если родитель — процесс/pipeline, дочерние шаги — его этапы.\n'
    '- Если родитель — набор видов/типов, дочерние — каждый конкретный вид.\n'
    '- Дети должны быть в той же semantic_axis, что и родитель, или в смежной. Не смешивай оси (архитектура ≠ процесс ≠ сэмплинг).\n'
    '\n'
    '# Критическое правило о дублях\n'
    'ВНИМАТЕЛЬНО просмотри «Остальные разделы» ({{sibling_nodes}}) и их определения.\n'
    'НЕ создавай дочерний узел, если это понятие логически является подразделом или частью ДРУГОГО раздела. Каждый дочерний узел принадлежит ТОЛЬКО своему родителю "{{parent_title}}".\n'
    '\n'
    '# Правила\n'
    '- label — техническое название понятия (термин), 1–4 слова. Не метафоры.\n'
    '- Не дублируй содержимое родителя: дочерний узел расширяет, а не переописывает родителя.\n'
    '- Не разбивай понятие, которое является естественным leaf (например, «Mean Squared Error»).\n'
    '- Одно понятие — одно место. Нет дублей.\n'
    '- На одном уровне — единый уровень абстракции.\n'
    '- Все id начинаются с "n" + цифра (n3_, n4_...). Каждый узел обязан иметь parentId, равный id родителя.\n'
    '- Для каждого ребёнка укажи semantic_axis и conceptType.\n'
    '- Для каждого ребёнка укажи метаданные: importance (0..1), difficulty (0..1), estimated_time_minutes (целое), prerequisites (массив id понятий), relations (массив {to, type} или []).\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '{{audience_block}}'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (title, canonical_definition) — только на русском.\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{"nodes":[{"id":"n3_a1","title":"Понятие A1","parentId":"{{parent_id}}","level":3,"conceptType":"mechanism","canonical_definition":"...","semantic_axis":"process","forbidden_interpretations":["..."],"importance":0.7,"difficulty":0.5,"estimated_time_minutes":12,"prerequisites":[],"relations":[]},{"id":"n3_a2","title":"Понятие A2","parentId":"{{parent_id}}","level":3,...}]}\n'
    '\n'
    'Допустимые значения conceptType: "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".\n'
    'Допустимые значения semantic_axis: "architecture", "process", "sampling", "representation", "loss", "encoding", "conditioning", "application", "theory", "evaluation".\n'
    '\n'
    'Если родитель является естественным leaf (дальнейшее разбиение бессмысленно), верни пустой массив:\n'
    '{"nodes":[]}\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] 2–4 узла уровня 3 (БЕЗ уровня 4)\n'
    '- [ ] title — термины, не метафоры\n'
    '- [ ] каждый ребёнок — конкретное понятие внутри родителя\n'
    '- [ ] нет дублей с «Остальными разделами» и внутри\n'
    '- [ ] semantic_axis консистентен с conceptType\n'
    '- [ ] у узлов заданы importance (0..1), difficulty (0..1), estimated_time_minutes\n'
    '- [ ] у каждого узла parentId = "{{parent_id}}"\n'
    '- [ ] формат — строго JSON с ключом "nodes"';

String buildL3Prompt({
  required String userQuery,
  required String rootTitle,
  required String parentId,
  required String parentTitle,
  String? parentCanonicalDefinition,
  required List<Map<String, dynamic>> siblings,
  String? goal,
  String? level,
}) {
  final parentDef = (parentCanonicalDefinition?.trim().isNotEmpty ?? false)
      ? parentCanonicalDefinition!.trim()
      : 'Подраздел темы «$rootTitle».';

  final siblingsStr = siblings.isNotEmpty
      ? siblings.map((s) {
          final def = s['canonical_definition'] != null &&
                  (s['canonical_definition'] as String).isNotEmpty
              ? ', определение: ${s['canonical_definition']}'
              : '';
          return '- id: ${s['id']}, title: "${s['title']}"$def';
        }).join('\n')
      : '- (нет других разделов того же уровня)';

  var result = _replaceOnce(promptL3, '{{user_query}}', userQuery);
  result = _replaceOnce(result, '{{root_title}}', rootTitle);
  result = _replaceOnce(result, '{{parent_title}}', parentTitle);
result = _replaceOnce(result, '{{parent_definition}}', parentDef);
  result = _replaceAll(result, '{{parent_id}}', parentId);
  result = _replaceAll(result, '{{parent_title}}', parentTitle);
  result = _replaceAll(result, '{{sibling_nodes}}', siblingsStr);
  result = _replaceOnce(
      result, '{{audience_block}}', buildAudienceBlock(goal: goal, level: level));
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// expand.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptExpand = '# Роль\n'
    'Ты — педагог, расширяешь дерево знаний. Для каждого указанного узла построй следующий уровень иерархии.\n'
    '\n'
    '# Контекст\n'
    'Тема: {{root_topic}}\n'
    'Полный путь от корня до целевых узлов:\n'
    '{{context_paths}}'
    '\n'
    '# Уже существующее дерево (НЕ дублируй эти понятия)\n'
    '{{existing_tree}}'
    '\n'
    '# Задача\n'
    'Для КАЖДОГО узла из списка «Узлы для расширения» сгенерируй 2–4 дочерних узла.\n'
    'Каждый дочерний узел — это конкретное понятие/термин внутри родителя.\n'
    'Новых тем не вводи. Не дублируй понятия, которые уже есть в дереве.\n'
    '\n'
    '# Критическое правило о размещении\n'
    'ВНИМАТЕЛЬНО изучи «Уже существующее дерево» выше.\n'
    '- Если генерируемое понятие логически является подтемой УЖЕ СУЩЕСТВУЮЩЕГО узла (а не целевого родителя), НЕ создавай его как нового ребёнка. Отметь это в поле "reparent_to" с id существующего узла.\n'
    '- Если понятие имеет смысл только как подраздел другого существующего раздела — используй reparent_to.\n'
    '- Никогда не создавай новый узел на том же уровне, где он логически был бы подразделом другого узла того же дерева.\n'
    '\n'
    '# Правила\n'
    '- id — уникальный латинский алиас (n4_a, n5_b, и т.д.).\n'
    '- parentId = id родительского узла.\n'
    '- title — техническое название понятия (термин), 1–4 слова.\n'
    '- Каждый ребенок принадлежит ТОЛЬКО своему родителю.\n'
    '- На одном уровне — единый уровень абстракции.\n'
    '- Не разбивай понятие, которое является естественным leaf (например, «Mean Squared Error»).\n'
    '- Не дублируй содержимое родителя: child-узел расширяет, а не переописывает parent.\n'
    '- Если родитель описывает класс архитектур или подходов, дочерние узлы должны покрывать все основные варианты.\n'
    '- Дети должны быть в той же semantic_axis, что и родитель, или в смежной. Не смешивай оси (архитектура ≠ процесс ≠ сэмплинг).\n'
    '- Для каждого ребенка укажи semantic_axis и conceptType.\n'
    '- Для каждого ребенка укажи метаданные: importance (0..1), difficulty (0..1), estimated_time_minutes (целое), prerequisites (массив id понятий из этого дерева, на которые опирается), relations (массив {to, type} или []).\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '{{audience_block}}'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (title) — только на русском.\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{\n'
    '  "nodes": [\n'
    '    {\n'
    '      "id": "id_родителя",\n'
    '      "children": [\n'
    '        {"id": "n_new1", "title": "Название 1", "parentId": "id_родителя", "conceptType": "concept", "semantic_axis": "architecture", "importance": 0.7, "difficulty": 0.5, "estimated_time_minutes": 12, "prerequisites": ["n2_a"], "relations": [{"to": "n2_a", "type": "requires"}]},\n'
    '        {"id": "n_new2", "title": "Название 2", "parentId": "id_родителя", "conceptType": "mechanism", "semantic_axis": "process", "importance": 0.6, "difficulty": 0.8, "estimated_time_minutes": 15, "prerequisites": ["n_new1"], "relations": [{"to": "n_new1", "type": "enables"}]}\n'
    '      ]\n'
    '    }\n'
    '  ]\n'
    '}\n'
    '\n'
    'Допустимые значения conceptType: "topic", "concept", "component", "mechanism", "process", "property", "rule", "method", "example".\n'
    'Допустимые значения semantic_axis: "architecture", "process", "sampling", "representation", "loss", "encoding", "conditioning", "application", "theory", "evaluation".\n'
    '\n'
    'Если узел является естественным leaf (дальнейшее разбиение бессмысленно), верни пустой массив children:\n'
    '{"id": "id_родителя", "children": []}\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Узлы для расширения\n'
    '{{nodes_to_expand}}'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] Для каждого узла сгенерированы 2–4 ребенка (или [] для leaf)\n'
    '- [ ] title — термины, не метафоры\n'
    '- [ ] Нет дублей с уже существующими понятиями в дереве\n'
    '- [ ] Каждый ребенок — конкретное понятие внутри родителя\n'
    '- [ ] Если понятие логически относится к существующему узлу — указан reparent_to\n'
    '- [ ] semantic_axis консистентен с conceptType\n'
    '- [ ] Формат — строго JSON с ключом "nodes"';

String buildExpandPrompt({
  required String rootTopic,
  required List<String> contextPaths,
  required List<Map<String, dynamic>> nodesToExpand,
  List<Map<String, dynamic>>? existingTree,
  String? goal,
  String? level,
}) {
  final sanitizedTopic = _sanitizeTopic(rootTopic);
  final pathsStr = contextPaths.join('\n');
  final nodesStr = nodesToExpand
      .map((n) => '- id: ${n['id']}, title: "${n['title']}", path: ${n['path']}')
      .join('\n');

  final existingStr = existingTree != null && existingTree.isNotEmpty
      ? existingTree
          .take(100)
          .map((n) =>
              '- id: ${n['id']}, title: "${n['title']}", parentId: ${n['parentId'] ?? '—'}, level: ${n['level']}')
          .join('\n')
      : '- (нет)';

  var result = _replaceOnce(promptExpand, '{{root_topic}}', sanitizedTopic);
  result = _replaceOnce(result, '{{context_paths}}', pathsStr);
  result = _replaceOnce(result, '{{existing_tree}}', existingStr);
  result = _replaceOnce(result, '{{nodes_to_expand}}', nodesStr);
  result = _replaceOnce(
      result, '{{audience_block}}', buildAudienceBlock(goal: goal, level: level));
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// content.ts
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> _criticalDomainKeywords = [
  'медицина', 'медицин', 'фармаколог', 'фармац', 'терапи', 'хирург',
  'патолог', 'анатом', 'физиолог', 'клини', 'диагност',
  'law', 'право', 'юрис', 'уголовн', 'гражданск',
  'finance', 'финанс', 'экономик', 'бухгалт', 'налог',
  'medicine', 'medical', 'pharmacolog', 'clinical', 'surgery',
  'legal', 'jurisprud',
  'exam', 'экзамен', 'сертиф', ' licens',
  'наук', 'scientific', 'исследован',
];

bool isCriticalDomain(String topicName, [List<String> nodePath = const []]) {
  final text = [topicName, ...nodePath].join(' ').toLowerCase();
  return _criticalDomainKeywords.any((kw) => text.contains(kw));
}

const Map<String, String> _contentLevelTones = {
  'beginner':
      'Пиши максимально доступно для новичка, без профессионального жаргона. '
      'Каждый специальный термин объясняй сразу простыми словами.',
  'intermediate':
      'Пиши для знакомого с основами читателя. Термины раскрывай через интуицию: '
      'сначала «как работает», затем термин.',
  'expert':
      'Пиши для специалиста, используй точную терминологию. '
      'Можно опускать базовые объяснения.',
};

const Map<String, String> _contentGoalHints = {
  'overview': 'Цель — общий обзор: опиши суть и место понятия в теме, без глубоких деталей.',
  'exam':
      'Цель — подготовка к экзамену: делай акцент на ключевых фактах, определениях и формулировках.',
  'deep':
      'Цель — глубокое изучение: кроме сути кратко обозначь механизм/устройство и подтемы, '
      'которые стоит разобрать.',
};

const String _rootGuidance = '\n# Корневой узел (обзор темы)\n'
    'Это корневой/обзорный узел. СТРОГО соблюдай:\n'
    '- ТОЛЬКО интуиция «как это работает» + краткий перечень подтем (roadmap «что разберём дальше»).\n'
    '- НЕ углубляйся в механику, математику и формулы на корневом узле — это задача дочерних узлов.\n'
    '- Для цели deep особенно: покажи «зачем» и «что дальше», а не сжатую сводку.\n'
    '- Не противоречь дочерним узлам — не опережай их content.';

const String _antiJargonRule = '\n# Антижаргон (обязательное правило)\n'
    '- КАЖДЫЙ специальный термин (например «градиент лог-плотности», «score», '
    '«марковская цепь», «максимизация правдоподобия») объясни простыми словами в ТОМ ЖЕ предложении.\n'
    '- ЗАПРЕЩЕНО использовать термин, который ты не можешь объяснить простыми словами без жаргона.\n'
    '- ЗАПРЕЩЕНО давать плотную энциклопедическую выжимку: обучай читателя, а не перечисляй термины.\n'
    '- Если термин не влияет на понимание сути — опусти его.';

const String _detailsInstruction =
    '1–2 предложения (макс. 500 символов). Факты, цифры, ключевые свойства. '
    'Если понятие включает формулу или математическое выражение, записывай его в LaTeX: '
    'инлайн — \$формула\$, блочная — \$\$формула\$\$.';

const String _twoPartDetailsBlock = '\n# Структура подробностей\n'
    'Для этой аудитории и цели (intermediate/beginner + deep) оформи details в ДВА абзаца, '
    'разделённых пустой строкой (\n\n), начинающихся со следующих заголовков:\n'
    '1. «Интуиция:» — 1–2 предложения простыми словами, БЕЗ терминов: как это работает.\n'
    '2. «Механика:» — ключевые термины/механизм, но КАЖДЫЙ термин сопровождай '
    'однострочным пояснением сразу после него.\n'
    'Не вылезай за лимит символов.';

const String _rootFormulaBan = '\n# Формулы на корневом узле\n'
    'Это корневой узел. НЕ пиши голые математические формулы. Опиши смысл словами '
    '(например: «сеть по более зашумленному кадру восстанавливает чуть менее зашумлённый»). '
    'Формулы и математика — на дочерние узлы.';

const String promptContent = '# Роль\n'
    'Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{root_topic}}"\n'
    'Путь: {{node_path}}\n'
    'Соседи: {{siblings}}\n'
    '{{audience_block}}'
    '{{goal_block}}'
    '{{root_block}}'
    '{{root_formula_ban}}'
    '{{ontology_context}}'
    '# Задача\n'
    'Опиши узел «{{node_title}}»:\n'
    '\n'
    '- one_liner — СУТЬ в одном предложении (макс. 120 символов). Без воды, без вводных фраз. Прямо к делу.\n'
    '- details — КРАТКАЯ справка. {{details_instruction}}\n'
    '- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). '
    'Если метафора не приходит в голову — верни "".\n'
    '- relations — СВЯЗИ с другими понятиями (см. формат ниже). Генерируй 2–4 связи, если они есть.\n'
    '\n'
    '{{details_structure_block}}'
    '- analogy — НЕОБЯЗАТЕЛЬНО: бытовая метафора, 1 предложение (макс. 120 символов). '
    'Если метафора не приходит в голову — верни "".\n'
    '- relations — СВЯЗИ с другими понятиями (см. формат ниже). Генерируй 2–4 связи, если они есть.\n'
    '\n'
    '# Типы связей\n'
    '- related — общая связь\n'
    '- depends_on — зависит от\n'
    '- requires — требует знания\n'
    '- example_of — является примером\n'
    '- similar_to — похоже на\n'
    '- contrasts_with — противоположно\n'
    '- causes — вызывает\n'
    '- enables — позволяет/делает возможным\n'
    '- used_for — используется для\n'
    '- alternative_to — альтернатива\n'
    '- derives_from — вытекает из\n'
    '- parameterizes — параметризует\n'
    '- approximates — аппроксимирует\n'
    '- generalizes — обобщает\n'
    '- implements — реализует\n'
    '- explains_why — объясняет почему (цепочка «зачем?»)\n'
    '\n'
    '# Антипаттерны (НЕ пиши)\n'
    '- "Данное понятие означает..."\n'
    '- "В системе Таро это..."\n'
    '- "Является важной частью..."\n'
    '- "Описывает сферу..."\n'
    '- Повторение родителя или детей\n'
    '- Общие фразы без конкретики\n'
    '\n'
    '# Правила\n'
    '- Факты > рассуждений.\n'
    '- Конкретика > абстракции.\n'
    '- Если у понятия есть компоненты — перечисли их.\n'
    '- Если понятие — конкретный объект (карта, термин) — опиши его функцию, не общую теорию.\n'
    '- В relations указывай id узлов из дерева. Если подходящего id нет — не генерируй связь.\n'
    '- Используй canonical_definition как основу для details. Не противоречь ему.\n'
    '- Не нарушай forbidden_interpretations — не утверждай то, что запрещено.\n'
    '- Не смешивай semantic_axis — не описывай архитектуру как процесс и наоборот.\n'
    '- Не противоречь parent, ancestors и siblings.\n'
    '$noMetaRule\n'
    '{{anti_jargon_block}}'
    '$alphabetRule\n'
    '{{sources_block}}'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке.\n'
    'Все термины в one_liner и details — на русском. Исключение: устоявшиеся аббревиатуры\n'
    '(U-Net, DDPM, VAE, CLIP, Stable Diffusion, ControlNet, DiT, NeRF, DDIM и т.д.).\n'
    'Всё остальное переводи.\n'
    '\n'
    '# Формат\n'
    'Только JSON:\n'
    '{"one_liner":"...","details":"...","analogy":"...","relations":[{"from":"id_этого_узла","to":"id_другого_узла","type":"requires","label":"опционально"}],"claims":[{"subject":"название_узла","predicate":"is_a","object":"категория"},{"subject":"название_узла","predicate":"alternative_to","object":"альтернатива"}],"sources":["URL_or_название_источника"]}\n'
    '\n'
    'Claims — это список утверждений, которые содержит этот узел. Они используются для валидации.\n'
    'Predicates: is_a, has_a, part_of, alternative_to, implements, requires, enables, contradicts, depends_on, related_to.\n'
    '{{sources_format_note}}'
    '\n'
    'Если analogy не нужна: "analogy": "".\n'
    'Если relations нет: "relations": [].\n'
    'Если claims нет: "claims": [].\n'
    'В поле from используй id текущего узла: "{{node_id}}".\n'
    '\n'
    'Никакого текста вне JSON.';

String buildContentPrompt({
  required String rootTopic,
  required List<String> nodePath,
  required String nodeId,
  String? nodeLabel,
  String? nodeOneLiner,
  required List<String> siblings,
  String? knowledgeLevel,
  String? goal,
  int? nodeLevel,
  bool isRoot = false,
  bool isCriticalDomain = false,
  Map<String, dynamic>? ontologyContext,
}) {
  final sanitizedTopic = _sanitizeTopic(rootTopic);

  final tone = knowledgeLevel != null && _contentLevelTones.containsKey(knowledgeLevel)
      ? '\n# Аудитория\n${_contentLevelTones[knowledgeLevel]}\n'
      : '';

  final goalBlock = goal != null && _contentGoalHints.containsKey(goal)
      ? '\n# Цель\n${_contentGoalHints[goal]}\n'
      : '';

  final rootBlock = isRoot || nodeLevel == 1 ? _rootGuidance : '';

  final antiJargon =
      knowledgeLevel != null && knowledgeLevel != 'expert' ? _antiJargonRule : '';

  final detailsInstruction = _detailsInstruction;

  final twoPartDetails =
      knowledgeLevel != null && knowledgeLevel != 'expert' && goal == 'deep'
          ? _twoPartDetailsBlock
          : '';

  final rootFormulaBan = isRoot || nodeLevel == 1 ? _rootFormulaBan : '';

  var ontologyBlock = '';
  if (ontologyContext != null) {
    final parts = <String>[];
    if (ontologyContext['canonical_definition'] != null &&
        (ontologyContext['canonical_definition'] as String).isNotEmpty) {
      parts.add('Каноническое определение: ${ontologyContext['canonical_definition']}');
    }
    if (ontologyContext['semantic_axis'] != null &&
        (ontologyContext['semantic_axis'] as String).isNotEmpty) {
      parts.add('Ось классификации: ${ontologyContext['semantic_axis']}');
    }
    if (ontologyContext['forbidden_interpretations'] != null) {
      final forbidden =
          (ontologyContext['forbidden_interpretations'] as List).cast<String>();
      if (forbidden.isNotEmpty) {
        parts.add('Запрещённые интерпретации: ${forbidden.join('; ')}');
      }
    }
    if (ontologyContext['parent_canonical_definition'] != null &&
        (ontologyContext['parent_canonical_definition'] as String).isNotEmpty) {
      parts.add(
          'Определение родителя: ${ontologyContext['parent_canonical_definition']}');
    }
    if (ontologyContext['siblings_with_axes'] != null) {
      final sibList =
          (ontologyContext['siblings_with_axes'] as List).cast<Map<String, dynamic>>();
      if (sibList.isNotEmpty) {
        final sibStr = sibList
            .map((s) => '${s['label']} (${s['axis'] ?? '?'})')
            .join(', ');
        parts.add('Соседние понятия: $sibStr');
      }
    }
    if (parts.isNotEmpty) {
      ontologyBlock = '\n# Онтологический контекст\n${parts.join('\n')}\n';
    }
  }

  var result = _replaceOnce(promptContent, '{{audience_block}}', tone);
  result = _replaceOnce(result, '{{goal_block}}', goalBlock);
  result = _replaceOnce(result, '{{root_block}}', rootBlock);
  result = _replaceOnce(result, '{{anti_jargon_block}}', antiJargon);
  result = _replaceOnce(result, '{{details_instruction}}', detailsInstruction);
  result = _replaceOnce(result, '{{details_structure_block}}', twoPartDetails);
  result = _replaceOnce(result, '{{root_formula_ban}}', rootFormulaBan);
  result = _replaceOnce(result, '{{ontology_context}}', ontologyBlock);
  result = _replaceOnce(result, '{{root_topic}}', sanitizedTopic);
  result = _replaceOnce(result, '{{node_path}}', nodePath.join(' → '));
  result = _replaceOnce(result, '{{siblings}}', siblings.join(', '));
  result = _replaceOnce(result, '{{node_id}}', nodeId);
  result = _replaceOnce(
      result, '{{node_title}}', nodeLabel ?? nodeOneLiner ?? '');

  final sourcesBlock = isCriticalDomain
      ? '# Источники (§64: factual reliability)\n'
          'Эта тема относится к критически важной области (медицина, право, финансы, наука, экзамен).\n'
          'Включи в JSON поле sources — массив из 2–4 наиболее авторитетных источников '
          '(название книги/статьи/URL или DOI), на которые опирается описание.\n'
          'Не придумывай источники — указывай только реальные, общепризнанные.\n'
          'Если достоверных источников нет — верни "sources": [].\n'
      : '';
  result = _replaceOnce(result, '{{sources_block}}', sourcesBlock);

  final sourcesFormatNote = isCriticalDomain
      ? 'Если sources запрошены: "sources": ["источник1", "источник2"].\n'
          'Если sources нет: "sources": [].'
      : 'Если sources нет: "sources": [].';
  result = _replaceOnce(result, '{{sources_format_note}}', sourcesFormatNote);

  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// explain.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptExplain = '# Роль\n'
    'Ты — помощник-педагог. Объясняешь непонятный термин из текста простыми словами, в контексте темы.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{user_query}}"\n'
    'Узел дерева: "{{node_label}}"\n'
    'Текст узла: "{{node_details}}"\n'
    '\n'
    '# Задача\n'
    'Пользователь выделил фрагмент текста и просит пояснение:\n'
    '"{{selected_text}}"\n'
    '\n'
    'Объясни этот термин/понятие:\n'
    '- 1–3 предложения, простым языком\n'
    '- Свяжи с контекстом темы и узла\n'
    '- Если это технический термин — дай краткое определение\n'
    '- Не повторяй дословно текст из узла\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Формат ответа\n'
    'Только текст пояснения (без JSON, без кавычек, без markdown). Просто строка.';

String buildExplainPrompt(
  String userQuery, {
  String? nodeLabel,
  String? nodeOneLiner,
  required String nodeDetails,
  required String selectedText,
}) {
  final sanitizedQuery = _sanitizeUserQuery(userQuery);

  var result = _replaceOnce(promptExplain, '{{user_query}}', sanitizedQuery);
  result = _replaceOnce(result, '{{node_label}}', nodeLabel ?? nodeOneLiner ?? '');
  result = _replaceOnce(
      result, '{{node_details}}', nodeDetails.length > 800
          ? nodeDetails.substring(0, 800)
          : nodeDetails);
  result = _replaceOnce(
      result, '{{selected_text}}', selectedText.length > 200
          ? selectedText.substring(0, 200)
          : selectedText);
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// activity.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptActivity = '# Роль\n'
    'Ты — AI-репетитор. Готовишь учебный материал для одного понятия внутри структурированной сессии изучения темы.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Цель сессии: "{{goal}}"\n'
    'Целевой уровень усвоения: "{{target_level}}"\n'
    'Понятие: "{{node_label}}"\n'
    'Определение: "{{node_one_liner}}"\n'
    'Подробное объяснение: "{{node_details}}"\n'
    'Тип понятия: "{{concept_type}}"\n'
    'Сложность: {{difficulty}}\n'
    '\n'
    '# Задача\n'
    'Для этого понятия подготовь три элемента учебного цикла:\n'
    '1. example — конкретный, узнаваемый пример применения данного понятия (2–4 предложения, простым языком).\n'
    '2. recall — вопрос на припоминание (multiple choice) из 4 вариантов. Вопрос проверяет понимание понятия, а не заучивание формулировок.\n'
    '3. apply — открытое задание на применение понятия в новой ситуации + эталонный ответ (reference_answer), которым репетитор сверит ответ ученика.\n'
    '\n'
    'Требования:\n'
    '- Все тексты на русском языке, простым языком, по уровню цели ученика.\n'
    '- example должен быть конкретным и новым (не из определения).\n'
    '- Один из 4 вариантов recall — правильный, остальные правдоподобные, но неверные (типичные ошибки).\n'
    '- apply формулируется как практическое микрозадание, решаемое за 1–3 минуты.\n'
    '- Не отвечайте на вопрос внутри формулировок.\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Формат ответа\n'
    'Строго JSON без markdown:\n'
    '{\n'
    '  "example": "строка",\n'
    '  "recall": { "question": "строка", "options": ["а", "б", "в", "г"], "correct_index": 0 },\n'
    '  "apply": { "instruction": "строка", "reference_answer": "строка" }\n'
    '}';

String buildActivityPrompt({
  required String topic,
  required String goal,
  required String targetLevel,
  String? label,
  required String oneLiner,
  required String details,
  String? conceptType,
  double? difficulty,
}) {
  final difficultyStr = (difficulty ?? 0.5).toString();
  final clampedDifficulty =
      difficultyStr.length > 4 ? difficultyStr.substring(0, 4) : difficultyStr;

  var result = _replaceOnce(promptActivity, '{{topic}}', topic);
  result = _replaceOnce(result, '{{goal}}', goal);
  result = _replaceOnce(result, '{{target_level}}', targetLevel);
  result = _replaceOnce(result, '{{node_label}}', label ?? oneLiner);
  result = _replaceOnce(
      result, '{{node_one_liner}}', oneLiner.length > 400
          ? oneLiner.substring(0, 400)
          : oneLiner);
  result = _replaceOnce(
      result, '{{node_details}}', details.length > 1200
          ? details.substring(0, 1200)
          : details);
  result = _replaceOnce(result, '{{concept_type}}', conceptType ?? 'концепция');
  result = _replaceOnce(result, '{{difficulty}}', clampedDifficulty);
  return result;
}

// ── Activity sanitize ─────────────────────────────────────────────────────────

Map<String, dynamic> sanitizeActivityResult(Map<String, dynamic> raw) {
  final recallMap = raw['recall'] as Map<String, dynamic>?;
  final rawOptions = recallMap != null ? recallMap['options'] : null;
  final options = rawOptions is List
      ? rawOptions.map((o) => o.toString().trim()).where((o) => o.isNotEmpty).toList()
      : <String>[];
  final safeOptions = options.length >= 2 ? options.sublist(0, 4) : <String>[];

  final correctIndexRaw = recallMap != null ? recallMap['correct_index'] : null;
  final correctIndex = correctIndexRaw is int
      ? correctIndexRaw.clamp(0, safeOptions.length - 1)
      : 0;

  final applyMap = raw['apply'] as Map<String, dynamic>?;

  return {
    'example': (raw['example'] ?? '').toString().trim(),
    'recall': {
      'question': (recallMap?['question'] ?? '').toString().trim(),
      'options': safeOptions,
      'correct_index': correctIndex,
    },
    'apply': {
      'instruction': (applyMap?['instruction'] ?? '').toString().trim(),
      'reference_answer': (applyMap?['reference_answer'] ?? '').toString().trim(),
    },
  };
}

// ── PROMPT_ACTIVITY_FEEDBACK ──────────────────────────────────────────────────

const String promptActivityFeedback = '# Роль\n'
    'Ты — AI-репетитор. Оцениваешь свободный ответ ученика на задание по конкретному понятию.\n'
    '\n'
    '# Контекст\n'
    'Понятие: "{{node_label}}"\n'
    'Определение: "{{node_one_liner}}"\n'
    'Задание: "{{instruction}}"\n'
    'Эталонный ответ: "{{reference_answer}}"\n'
    'Ответ ученика: "{{user_answer}}"\n'
    '\n'
    '# Задача\n'
    'Оцени ответ ученика:\n'
    '- correct — ответ верен по сути, демонстрирует понимание понятия\n'
    '- partial — ответ частично верен: есть верная мысль, но есть ошибки или пропущена ключевая часть\n'
    '- incorrect — ответ неверен или не относится к заданию\n'
    '\n'
    'Для partial и incorrect укажи возможное заблуждение (misconception) одной фразой, '
    'если его можно определить (null, если не определяется).\n'
    '\n'
    'Требования:\n'
    '- feedback — 1–3 предложения, по-русски, доброжелательно, конкретно: что верно, чего не хватает.\n'
    '- Не раскрывай эталонный ответ целиком в feedback (ученик должен перепроверить сам).\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Формат ответа\n'
    'Строго JSON без markdown:\n'
    '{\n'
    '  "assessment": "correct",\n'
    '  "feedback": "строка",\n'
    '  "misconception": "строка или null"\n'
    '}';

String buildActivityFeedbackPrompt({
  required String nodeLabel,
  required String nodeOneLiner,
  required String instruction,
  required String referenceAnswer,
  required String userAnswer,
}) {
  var result = _replaceOnce(promptActivityFeedback, '{{node_label}}', nodeLabel);
  result = _replaceOnce(
      result, '{{node_one_liner}}', nodeOneLiner.length > 400
          ? nodeOneLiner.substring(0, 400)
          : nodeOneLiner);
  result = _replaceOnce(
      result, '{{instruction}}', instruction.length > 600
          ? instruction.substring(0, 600)
          : instruction);
  result = _replaceOnce(
      result, '{{reference_answer}}', referenceAnswer.length > 800
          ? referenceAnswer.substring(0, 800)
          : referenceAnswer);
  result = _replaceOnce(
      result, '{{user_answer}}', userAnswer.length > 1500
          ? userAnswer.substring(0, 1500)
          : userAnswer);
  return result;
}

// ── Feedback sanitize ─────────────────────────────────────────────────────────

Map<String, dynamic> sanitizeFeedbackResult(Map<String, dynamic> raw) {
  final a = raw['assessment'];
  final assessment = (a == 'correct' || a == 'partial' || a == 'incorrect')
      ? a as String
      : 'partial';

  final mc = raw['misconception'];
  final misconception = mc != null && mc.toString().trim().isNotEmpty
      ? mc.toString().trim()
      : null;

  return {
    'assessment': assessment,
    'feedback': (raw['feedback'] ?? '').toString().trim(),
    'misconception': misconception,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// assessment.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptAssessment = '# Роль\n'
    'Ты — экзаменатор. Проверь, действительно ли пользователь достиг заявленного уровня понимания темы.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Цель пользователя: {{goal}}\n'
    'Изученные понятия (в рамках сессии):\n'
    '{{session_items}}'
    '\n'
    '# Типы вопросов (всего их 6)\n'
    'Сгенерируй финальную проверку, используя следующие типы:\n'
    '- **recognition** — узнавание: выбери корректный вариант из четырёх (формулировка, а не заучивание)\n'
    '- **recall** — припоминание: воспроизведи определение или ключевой факт (multiple choice)\n'
    '- **explanation** — объясни механизм своими словами (structure matters; rubric обязателен)\n'
    '- **diagnosis** — найди и объясни ошибку/несоответствие в приведённом утверждении (rubric обязателен)\n'
    '- **application** — примени знание к новой конкретной ситуации (rubric обязателен)\n'
    '- **transfer** — перенеси знание на смежную/нестандартную ситуацию (rubric обязателен)\n'
    '\n'
    'Всего {{question_count}} вопросов. Обеспечь разнообразие типов: это должен быть честный замер, а не только фактология.\n'
    'Для recognition/recall укажи options и correctAnswer (индекс корректного варианта, начиная с 0).\n'
    'Для explanation/diagnosis/application/transfer — options=[] и correctAnswer=""; '
    'explanation (рубрика) содержит конкретные критерии оценивания: какие элементы должны присутствовать в свободном ответе.\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект:\n'
    '{"questions":[{"id":"a1","type":"recall","nodeId":"n2_a","question":"...","options":["A","B","C","D"],"correctAnswer":"0","explanation":"..."},{"id":"a2","type":"explanation","nodeId":"n2_b","question":"Объясните своими словами, как работает X (порядок шагов, причинно-следственные связи).","options":[],"correctAnswer":"","explanation":"Ключевые элементы ответа: 1) ..., 2) ..."}]}\n'
    '\n'
    '# Примечания\n'
    '- correctAnswer для recognition/recall — ИНДЕКС правильного варианта (строка "0","1","2","3").\n'
    '- Вопросы проверяют глубокое понимание, не поверхностную фактологию.\n'
    '\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Вопросы, варианты, рубрики — на русском.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] Ровно {{question_count}} вопросов\n'
    '- [ ] Есть вопросы с options (recognition/recall) и открытые вопросы (explanation/diagnosis/application/transfer)\n'
    '- [ ] У всех открытых вопросов rubric (explanation) содержит конкретные критерии\n'
    '- [ ] Вопросы проверяют глубокое понимание, не поверхностную фактологию\n'
    '- [ ] Формат — строго JSON с ключом "questions"';

String buildAssessmentPrompt({
  required String topic,
  required String goal,
  required List<Map<String, dynamic>> sessionItems,
  bool includeApplication = false,
  required int questionCount,
}) {
  final itemsJson = jsonEncode(sessionItems.map((s) {
    final details = s['details'] != null
        ? (s['details'] as String).length > 400
            ? (s['details'] as String).substring(0, 400)
            : s['details']
        : null;
    return {
      'nodeId': s['nodeId'],
      'label': s['label'],
      'oneLiner': s['oneLiner'],
      'details': details,
    };
  }).toList());

  var result = _replaceOnce(promptAssessment, '{{topic}}', topic);
  result = _replaceOnce(result, '{{goal}}', goal);
  result = _replaceOnce(result, '{{session_items}}', itemsJson);
  result = _replaceAll(result, '{{question_count}}', questionCount.toString());
  result = _replaceOnce(
      result, '{{include_application}}', includeApplication ? 'true' : 'false');
  return result;
}

// ── Assessment parse ──────────────────────────────────────────────────────────

List<Map<String, dynamic>> parseAssessmentResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};
  final questions = obj['questions'];
  if (questions is! List) return [];
  return questions.cast<Map<String, dynamic>>().map((q) {
    final id = q['id'];
    final type = q['type'];
    final nodeId = q['nodeId'];
    final question = q['question'];
    final opts = q['options'];
    final ca = q['correctAnswer'];
    final explanation = q['explanation'];
    return {
      'id': id is String ? id : 'a_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      'type': type is String ? type : 'recall',
      'nodeId': nodeId is String ? nodeId : '',
      'question': question is String ? question : '',
      'options': opts is List
          ? opts.whereType<String>().toList()
          : <String>[],
      'correctAnswer': ca is String ? ca : '',
      'explanation': explanation is String ? explanation : '',
    };
  }).toList();
}

// ═══════════════════════════════════════════════════════════════════════════════
// curriculum.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptCurriculum = '# Роль\n'
    'Ты — curriculum-инженер. Из полного дерева знаний выбери минимальный достаточный набор понятий, '
    'которые приведут пользователя от текущего уровня к целевой цели за заданное время.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Цель пользователя: {{goal}}\n'
    'Текущий уровень: {{current_level}}\n'
    'Целевой уровень: {{target_level}}\n'
    'Доступное время: {{time_budget_minutes}} минут\n'
    '\n'
    '# Дерево знаний (полный граф)\n'
    '{{nodes_json}}'
    '\n'
    '# Задача\n'
    'Собери соответствие: из всех понятий дерева выбери минимальный достаточный список для достижения '
    'целевого уровня за доступное время.\n'
    '\n'
    '# Принципы отбора\n'
    '- **Minimum sufficient knowledge**: не включай всё дерево — только то, что необходимо для цели.\n'
    '- **Just enough prerequisites**: если достаточно краткого упоминания (например, «шум Гаусса») — '
    'не включай полный подграф Probability.\n'
    '- **Learning gain per minute**: отдавай приоритет понятиям с высокой пользой на единицу времени.\n'
    '- Учитывай importance, difficulty и estimated_time_minutes каждого узла.\n'
    '- Порядок отбора = порядок изучения (сперва базовые).\n'
    '- Если понятия уже знает пользователь (current_level достигнут) — пропусти.\n'
    '- Суммарное время не должно превышать время бюджета существенно.\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект:\n'
    '{\n'
    '  "items": [\n'
    '    {"node_id": "n3_a1", "order": 1, "estimated_minutes": 10, "why": "Почему это понятие важно для цели"},\n'
    '    {"node_id": "n2_b", "order": 2, "estimated_minutes": 15, "why": "..."}\n'
    '  ],\n'
    '  "total_estimated_minutes": 55,\n'
    '  "skipped": [\n'
    '    {"node_id": "n4_x", "reason": "why skipped (optional/deferred/advanced)"}\n'
    '  ]\n'
    '}\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Поля "why" и "reason" — на русском.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] Выбрано минимально достаточное число понятий\n'
    '- [ ] Порядок изучения от базовых к продвинутым\n'
    '- [ ] Не включено лишнее (не всё дерево)\n'
    '- [ ] Суммарное время близко к бюджету (не превышает его грубо)\n'
    '- [ ] Формат — строго JSON с ключом "items"';

String buildCurriculumPrompt({
  required String topic,
  required String goal,
  required String currentLevel,
  required String targetLevel,
  required int timeBudgetMinutes,
  required List<Map<String, dynamic>> nodes,
}) {
  final nodesJson = jsonEncode(nodes.map((n) {
    return {
      'id': n['id'],
      'label': n['label'],
      'one_liner': n['one_liner'],
      'importance': n['importance'],
      'difficulty': n['difficulty'],
      'estimated_time_minutes': n['estimated_time_minutes'],
      'prerequisites': n['prerequisites'],
    };
  }).toList());

  var result = _replaceOnce(promptCurriculum, '{{topic}}', topic);
  result = _replaceOnce(result, '{{goal}}', goal);
  result = _replaceOnce(result, '{{current_level}}', currentLevel);
  result = _replaceOnce(result, '{{target_level}}', targetLevel);
  result = _replaceOnce(
      result, '{{time_budget_minutes}}', timeBudgetMinutes.toString());
  result = _replaceOnce(result, '{{nodes_json}}', nodesJson);
  return result;
}

// ── Curriculum parse ──────────────────────────────────────────────────────────

Map<String, dynamic> parseCurriculumResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};

  final rawItems = obj['items'];
  final items = rawItems is List
      ? rawItems.cast<Map<String, dynamic>>().map((i) {
          return {
            'node_id': i['node_id'] is String ? i['node_id'] : '',
            'order': i['order'] is int ? i['order'] : 0,
            'estimated_minutes':
                i['estimated_minutes'] is int ? i['estimated_minutes'] : 5,
            'why': i['why'] is String ? i['why'] : '',
          };
        }).toList()
      : <Map<String, dynamic>>[];

  final rawSkipped = obj['skipped'];
  final skipped = rawSkipped is List
      ? rawSkipped.cast<Map<String, dynamic>>().map((s) {
          return {
            'node_id': s['node_id'] is String ? s['node_id'] : '',
            'reason': s['reason'] is String ? s['reason'] : '',
          };
        }).toList()
      : <Map<String, dynamic>>[];

  final total = obj['total_estimated_minutes'];
  final totalEst = total is int
      ? total
      : items.fold<int>(0, (s, i) => s + (i['estimated_minutes'] as int));

  return {
    'items': items,
    'total_estimated_minutes': totalEst,
    'skipped': skipped,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// diagnostic.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptDiagnostic = '# Роль\n'
    'Ты — диагностирующий педагог. Оцени текущий уровень пользователя по теме.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Цель пользователя: {{goal}}\n'
    'Целевой уровень: {{target_level}}\n'
    '\n'
    '# Ключевые понятия темы (ОБЯЗАТЕЛЬНО используй их для вопросов)\n'
    '{{nodes_json}}'
    '\n'
    '# Задача\n'
    'Составь диагностику из 3–5 вопросов. КАЖДЫЙ вопрос должен:\n'
    '1. Быть напрямую связан с конкретным понятием из списка "Ключевые понятия темы"\n'
    '2. Использовать название понятия (label) в тексте вопроса или вариантах ответа\n'
    '3. Проверять понимание именно этого понятия, а не общей темы\n'
    '\n'
    'ЗАПРЕЩЕНО задавать общие вопросы вроде "Что вы знаете о теме?" или '
    '"Что обычно показывает базовое понимание?".\n'
    'Каждый вопрос ДОЛЖЕН содержать имя конкретного понятия из списка '
    '(например, "Что такое Аркан?" или "Какова роль Старших Арканов?").\n'
    '\n'
    'Отбери 3–5 понятий из списка выше (от базовых к продвинутым) и составь по одному вопросу на каждое.\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект:\n'
    '{"questions":[{"id":"d1","nodeId":"<id из списка понятий>",'
    '"question":"Вопрос с упоминанием конкретного понятия?",'
    '"options":["Вариант A","Вариант B","Вариант C","Вариант D"],'
    '"correctIndex":0,"explanation":"..."}]}\n'
    '\n'
    '# После обработки\n'
    'На основе ответов диагностики определяется текущий уровень:\n'
    '- Если большинство правильных — current_level близок к target\n'
    '- Если большинство неправильных — current_level = awareness\n'
    '\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.';

String buildDiagnosticPrompt({
  required String topic,
  required String goal,
  required String targetLevel,
  required List<Map<String, dynamic>> nodes,
}) {
  final nodesJson = jsonEncode(
      nodes.map((n) => {'id': n['id'], 'label': n['label'], 'one_liner': n['one_liner']}).toList());

  var result = _replaceOnce(promptDiagnostic, '{{topic}}', topic);
  result = _replaceOnce(result, '{{goal}}', goal);
  result = _replaceOnce(result, '{{target_level}}', targetLevel);
  result = _replaceOnce(result, '{{nodes_json}}', nodesJson);
  return result;
}

// ── Diagnostic parse ──────────────────────────────────────────────────────────

List<Map<String, dynamic>> parseDiagnosticResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};
  final questions = obj['questions'];
  if (questions is! List) return [];
  return questions.cast<Map<String, dynamic>>().map((q) {
    final id = q['id'];
    final nodeId = q['nodeId'];
    final question = q['question'];
    final opts = q['options'];
    final ci = q['correctIndex'];
    final explanation = q['explanation'];
    return {
      'id': id is String ? id : 'd_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      'nodeId': nodeId is String ? nodeId : '',
      'question': question is String ? question : '',
      'options': opts is List
          ? opts.whereType<String>().toList()
          : <String>[],
      'correctIndex': ci is int ? ci : 0,
      'explanation': explanation is String ? explanation : '',
    };
  }).toList();
}

// ═══════════════════════════════════════════════════════════════════════════════
// mastery.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptMastery = '# Роль\n'
    'Ты — преподаватель, определяющий освоение материала. Оцени по ответам пользователя, достиг ли он целевого уровня.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Целевой уровень: {{target_level}}\n'
    '\n'
    '# Ответы пользователя на проверку\n'
    '{{items_json}}'
    '\n'
    '# Задача\n'
    'Для КАЖДОГО понятия оцени метрики освоения (0..1):\n'
    '- understanding — понимание идеи\n'
    '- recall — способность воспроизвести\n'
    '- application — способность применить\n'
    '- transfer — способность перенести на новую ситуацию\n'
    '\n'
    'Также:\n'
    '- определи misconception по каждому понятию (тип и описание), или null если нет\n'
    '- дай общий вердикт: достиг ли пользователь целевого уровня (enough: true/false)\n'
    '- если not enough — укажи, чего не хватает\n'
    '\n'
    '# Типы misconceptions\n'
    'unknown (не знал), confused (перепутал понятия), incomplete (неполная модель), '
    'definition_only (знает только определение), mechanism_error (неверный механизм), '
    'application_failure (не смог применить), careless (небрежная ошибка).\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект:\n'
    '{\n'
    '  "concepts": [\n'
    '    {"nodeId":"n2_a","understanding":0.8,"recall":0.9,"application":0.6,'
    '"transfer":0.5,"confidence":0.75,"misconception":null},\n'
    '    {"nodeId":"n2_b","understanding":0.4,"recall":0.3,"application":0.2,'
    '"transfer":0.1,"confidence":0.3,'
    '"misconception":{"type":"incomplete","description":"Не объясняет reverse diffusion как итеративный процесс"}}\n'
    '  ],\n'
    '  "enough": false,\n'
    '  "overall_level": "solid_understanding",\n'
    '  "gaps": ["Разделённые концепции: ...", "Не хватает: ..."]\n'
    '}\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Описания misconceptions и gaps — на русском.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.';

String buildMasteryPrompt({
  required String topic,
  required String targetLevel,
  required List<Map<String, dynamic>> items,
}) {
  final itemsJson = jsonEncode(items.map((i) {
    final userAnswer = i['userAnswer'] as String?;
    final rubric = i['rubric'] as String?;
    return {
      'nodeId': i['nodeId'],
      'label': i['label'],
      'type': i['type'],
      'userAnswer': userAnswer != null
          ? (userAnswer.length > 800 ? userAnswer.substring(0, 800) : userAnswer)
          : null,
      'correct': i['correct'],
      'rubric': rubric != null
          ? (rubric.length > 400 ? rubric.substring(0, 400) : rubric)
          : null,
    };
  }).toList());

  var result = _replaceOnce(promptMastery, '{{topic}}', topic);
  result = _replaceOnce(result, '{{target_level}}', targetLevel);
  result = _replaceOnce(result, '{{items_json}}', itemsJson);
  return result;
}

// ── Mastery parse ─────────────────────────────────────────────────────────────

Map<String, dynamic> parseMasteryResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};

  final rawConcepts = obj['concepts'];
  final concepts = rawConcepts is List
      ? rawConcepts.cast<Map<String, dynamic>>().map((c) {
          final mc = c['misconception'];
          final misconception = (mc is Map<String, dynamic> && mc.isNotEmpty)
              ? {
                  'type': (mc['type'] ?? 'unknown').toString(),
                  'description': (mc['description'] ?? '').toString(),
                }
              : null;
          return {
            'nodeId': c['nodeId'] is String ? c['nodeId'] : '',
            'understanding': c['understanding'] is num ? c['understanding'] : 0,
            'recall': c['recall'] is num ? c['recall'] : 0,
            'application': c['application'] is num ? c['application'] : 0,
            'transfer': c['transfer'] is num ? c['transfer'] : 0,
            'confidence': c['confidence'] is num ? c['confidence'] : 0,
            'misconception': misconception,
          };
        }).toList()
      : <Map<String, dynamic>>[];

  final rawGaps = obj['gaps'];
  final gaps = rawGaps is List
      ? rawGaps.whereType<String>().toList()
      : <String>[];

  return {
    'concepts': concepts,
    'enough': obj['enough'] == true,
    'overall_level': obj['overall_level'] is String
        ? obj['overall_level']
        : 'awareness',
    'gaps': gaps,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// milestone.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptMilestone = '# Роль\n'
    'Ты — навигатор по обучению. Составь карту уровней и направлений для темы.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Текущий уровень: {{current_level}}\n'
    'Цель пользователя: {{goal}}\n'
    '\n'
    '# Задача\n'
    'Составь последовательность milestones (уровней освоения) от текущего к более глубоким. Укажи для каждого:\n'
    '- title — понятное название уровня\n'
    '- description — что пользователь сможет делать\n'
    '- capabilities — конкретные умения (2–5)\n'
    '- estimated_hours — примерные часы\n'
    '- alternative_paths — какие направления развиваются дальше\n'
    '\n'
    'Базовая шкала уровней (адаптируй под тему):\n'
    'awareness → basic_understanding → solid_understanding → practical_application → advanced → expert\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект:\n'
    '{"milestones":[{"id":"m1","level":"solid_understanding","title":"Твёрдое понимание",'
    '"description":"...","capabilities":["...","..."],"estimated_hours":2,'
    '"alternative_paths":[{"id":"m2","title":"Применение","estimated_hours":4,"description":"..."}]}]}\n'
    '\n'
    'Отсортируй milestones от текущего к более глубоким. alternative_paths указывают ветвление после данного уровня.\n'
    '\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля — на русском.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.';

String buildMilestonePrompt({
  required String topic,
  required String currentLevel,
  required String goal,
}) {
  var result = _replaceOnce(promptMilestone, '{{topic}}', topic);
  result = _replaceOnce(result, '{{current_level}}', currentLevel);
  result = _replaceOnce(result, '{{goal}}', goal);
  return result;
}

// ── Milestone parse ───────────────────────────────────────────────────────────

Map<String, dynamic> parseMilestoneResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};

  final rawMilestones = obj['milestones'];
  final milestones = rawMilestones is List
      ? rawMilestones.cast<Map<String, dynamic>>().map((m) {
          final rawAlt = m['alternative_paths'];
          final alt = rawAlt is List
              ? rawAlt.cast<Map<String, dynamic>>().map((a) {
                  return {
                    'id': (a['id'] ?? '').toString(),
                    'title': (a['title'] ?? '').toString(),
                    'estimated_hours': a['estimated_hours'] is num
                        ? a['estimated_hours']
                        : 1,
                    'description': (a['description'] ?? '').toString(),
                  };
                }).toList()
              : <Map<String, dynamic>>[];

          final rawCaps = m['capabilities'];
          final caps = rawCaps is List
              ? rawCaps.whereType<String>().toList()
              : <String>[];

          return {
            'id': (m['id'] ?? '').toString(),
            'level': (m['level'] ?? '').toString(),
            'title': (m['title'] ?? '').toString(),
            'description': (m['description'] ?? '').toString(),
            'capabilities': caps,
            'estimated_hours': m['estimated_hours'] is num
                ? m['estimated_hours']
                : 1,
            'alternative_paths': alt,
          };
        }).toList()
      : <Map<String, dynamic>>[];

  return {'milestones': milestones};
}

// ═══════════════════════════════════════════════════════════════════════════════
// quiz.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptQuiz = '# Роль\n'
    'Ты — педагог, составляешь тест по уже изученной теме. Тест проверяет понимание ключевых концепций, связей и механизмов.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{user_query}}"\n'
    'Дерево знаний (узлы с определениями и связями):\n'
    '{{tree_nodes}}'
    '\n'
    '# Задача\n'
    'Сгенерируй {{question_count}} вопросов для теста по теме. Вопросы должны проверять:\n'
    '- Понимание ключевых терминов и их определений\n'
    '- Связи между понятиями (какие понятия зависят друг от друга, что является частью чего)\n'
    '- Порядок процессов и алгоритмов (если есть sequences)\n'
    '- Причинно-следственные связи\n'
    '- Развенчание мифов и заблуждений (misconception)\n'
    '\n'
    '# Типы вопросов\n'
    'Обычные вопросы — проверяют знание фактов и связей.\n'
    'Misconception-вопросы — содержат ложное утверждение, которое выглядит правдоподобно. '
    'Пользователь должен определить, верно оно или нет. Отметь misconception: true для таких вопросов. '
    'Хороший misconception — это распространённое заблуждение, а не абсурдное утверждение.\n'
    '\n'
    '# Правила для вопросов\n'
    '- Каждый вопрос имеет ровно 4 варианта ответа (A, B, C, D)\n'
    '- Ровно один вариант правильный\n'
    '- Неправильные варианты правдоподобны (не абсурдны), но ошибочны\n'
    '- Вопрос сформулирован ясно, без двусмысленностей\n'
    '- Объяснение правильного ответа — 1–2 предложения, пояснение почему это верно\n'
    '- Не используй "все вышеперечисленное" или "ничего из вышеперечисленного"\n'
    '- Не повторяй один и тот же концепт в разных вопросах\n'
    '- Для каждого вопроса укажи nodeId — id узла из дерева, к которому относится вопрос. '
    'Бери id ТОЛЬКО из предоставленного дерева.\n'
    '- Из {{question_count}} вопросов минимум 2 должны быть misconception\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Формат ответа\n'
    'Строгий JSON-объект. Никакого текста до или после JSON. Никаких комментариев.\n'
    'Объект содержит ключ "questions" с массивом вопросов.\n'
    '\n'
    'Пример:\n'
    '{"questions":[{"id":"q1","nodeId":"n3_a1","question":"Что делает X?",'
    '"options":["A1","A2","A3","A4"],"correctIndex":1,'
    '"explanation":"X делает Y потому что Z.","misconception":false},'
    '{"id":"q2","nodeId":"n2_b","question":"Верно ли, что X — это Y?",'
    '"options":["Да, потому что...","Нет, потому что X делает Z...",'
    '"Да, все...","Нет, но..."],'
    '"correctIndex":1,"explanation":"Неверно: X не является Y, потому что...",'
    '"misconception":true}]}\n'
    '\n'
    '# Проверь перед ответом\n'
    '- [ ] Ровно {{question_count}} вопросов\n'
    '- [ ] Каждый вопрос с 4 вариантами, один правильный\n'
    '- [ ] correctIndex от 0 до 3\n'
    '- [ ] У каждого вопроса корректный nodeId из дерева\n'
    '- [ ] Вопросы покрывают разные аспекты темы (не только определения)\n'
    '- [ ] Минимум 2 misconception-вопроса\n'
    '- [ ] Объяснения информативны, а не "Потому что A — правильный ответ"\n'
    '- [ ] Вопросы, варианты ответов и объяснения — СТРОГО на русском '
    '(кроме устоявшихся аббревиатур)';

String buildQuizPrompt(
  String userQuery,
  List<Map<String, dynamic>> nodes,
  int count,
) {
  final sanitizedQuery = _sanitizeUserQuery(userQuery);

  final compactNodes = nodes.map((n) {
    final details = n['details'] as String?;
    return {
      'id': n['id'],
      'label': n['label'],
      'one_liner': n['one_liner'],
      'details': details != null
          ? (details.length > 300 ? details.substring(0, 300) : details)
          : null,
      'conceptType': n['conceptType'],
      'relations': n['relations'],
      'sequences': n['sequences'],
    };
  }).toList();

  var result = _replaceOnce(promptQuiz, '{{user_query}}', sanitizedQuery);
  result = _replaceOnce(result, '{{tree_nodes}}', jsonEncode(compactNodes));
  result = _replaceAll(result, '{{question_count}}', count.toString());
  return result;
}

int computeQuizCount(int nodeCount) {
  if (nodeCount == 0) return 6;
  final raw = (nodeCount * 0.5).floor() + 2;
  return raw.clamp(6, 12);
}

// ═══════════════════════════════════════════════════════════════════════════════
// validate.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptValidate = '# Роль\n'
    'Ты — эксперт по структуре знаний. Твоя задача — найти проблемы в дереве понятий.\n'
    '\n'
    '# Задача\n'
    'Проверь дерево знаний на следующие проблемы:\n'
    '\n'
    '1. **DUPLICATE** — узлы, описывающие одно и то же понятие (разными словами или одинаково).\n'
    '2. **OVERLAP** — узлы, которые слишком сильно пересекаются по содержанию.\n'
    '3. **ABSTRACTION_MISMATCH** — узлы на одном уровне, находящиеся на разных уровнях абстракции.\n'
    '4. **TAXONOMIC_INCONSISTENCY** — дети классифицируют родителя по разным логическим осям.\n'
    '5. **COVERAGE** — пропущена крупная важная категория в рамках родителя.\n'
    '6. **USELESS_CHILD** — у ребенка нет самостоятельной информационной ценности.\n'
    '7. **SHOULD_BE_LEAF** — узел расширен, но дальнейшее дробление бессмысленно.\n'
    '8. **LANGUAGE_VIOLATION** — label или one_liner содержат непереведенный английский текст.\n'
    '9. **ONTOLOGY_VIOLATION** — узел противоречит своему canonical_definition.\n'
    '10. **AXIS_MIXING** — узел смешивает semantic_axis (описывает архитектуру как процесс и т.д.).\n'
    '11. **FORBIDDEN_INTERPRETATION** — узел использует запрещённую интерпретацию из forbidden_interpretations.\n'
    '12. **SCOPE_ERROR** — условное утверждение превращено в абсолютное.\n'
    '13. **CAUSAL_ERROR** — неверная причинно-следственная связь.\n'
    '14. **MISSING_PREREQUISITE** — узел опирается (в relations/prerequisites) на понятие, '
    'которого нет в дереве, или мысль очевидно требует понятия, отсутствующего в предках.\n'
    '15. **CIRCULAR_DEPENDENCY** — обнаружен цикл в связях requires/depends_on/enables.\n'
    '16. **UNREALISTIC_TIMING** — суммарная оценка estimated_time_minutes одного узла или '
    'родителя с детьми выходит за разумные пределы (например, > 120 мин на узел).\n'
    '17. **OVERLY_BROAD** — узел слишком глобален/расплывчат для своего уровня и его логично расширить на детей.\n'
    '18. **IRRELEVANT** — узел не относится к теме/цели дерева.\n'
    '\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (reason, missing_concepts) — только на русском.\n'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-объект:\n'
    '{\n'
    '  "valid": true/false,\n'
    '  "issues": [\n'
    '    {"type": "DUPLICATE", "node_id": "id_узла", "reason": "описание проблемы"}\n'
    '  ],\n'
    '  "missing_concepts": [\n'
    '    {"title": "название пропущенного понятия", "parent_id": "id_родительского_узла"}\n'
    '  ],\n'
    '  "should_expand": true/false\n'
    '}\n'
    '\n'
    '- valid = false, если есть хотя бы одна проблема из типов 1–13.\n'
    '- should_expand = false, если дерево уже достаточно детализировано.\n'
    '- missing_concepts — список пропущенных важных понятий.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Дерево для проверки\n'
    '{{tree_json}}';

const int defaultValidateLeanThreshold = 100;

int resolveLeanThreshold([String? envValue]) {
  final raw = envValue;
  if (raw == null || raw.trim().isEmpty) return defaultValidateLeanThreshold;
  final n = int.tryParse(raw);
  return (n != null && n >= 1) ? n : defaultValidateLeanThreshold;
}

const List<String> validationIssueTypes = [
  'DUPLICATE',
  'OVERLAP',
  'ABSTRACTION_MISMATCH',
  'TAXONOMIC_INCONSISTENCY',
  'COVERAGE',
  'USELESS_CHILD',
  'SHOULD_BE_LEAF',
  'LANGUAGE_VIOLATION',
  'ONTOLOGY_VIOLATION',
  'AXIS_MIXING',
  'FORBIDDEN_INTERPRETATION',
  'SCOPE_ERROR',
  'CAUSAL_ERROR',
  'MISSING_PREREQUISITE',
  'CIRCULAR_DEPENDENCY',
  'UNREALISTIC_TIMING',
  'OVERLY_BROAD',
  'IRRELEVANT',
];

List<Map<String, dynamic>> compactNodesForValidation(
  List<Map<String, dynamic>> nodes, {
  int? leanThreshold,
}) {
  final threshold = leanThreshold ?? resolveLeanThreshold();
  final lean = nodes.length > threshold;
  return nodes.map((n) {
    final oneLiner = n['one_liner'] as String?;
    final details = n['details'] as String?;
    final canonicalDef = n['canonical_definition'] as String?;
    return {
      'id': n['id'],
      'parentId': n['parentId'],
      'level': n['level'],
      'label': n['label'],
      'one_liner': lean
          ? (oneLiner != null && oneLiner.length > 120
              ? oneLiner.substring(0, 120)
              : oneLiner)
          : oneLiner,
      'details': lean ? null : (details != null && details.length > 300
          ? details.substring(0, 300)
          : details),
      'conceptType': n['conceptType'],
      'semantic_axis': n['semantic_axis'],
      'canonical_definition': canonicalDef != null && canonicalDef.length > 200
          ? canonicalDef.substring(0, 200)
          : canonicalDef,
      'forbidden_interpretations': n['forbidden_interpretations'],
    };
  }).toList();
}

List<T> validationNeighborhood<T extends Map<String, dynamic>>(
  List<T> nodes,
  List<String> focusIds,
) {
  if (focusIds.isEmpty) return [];
  final byId = <String, T>{};
  for (final n in nodes) {
    byId[n['id'] as String] = n;
  }
  final keep = <String>{};
  final ctxParents = <String>{};
  for (final id in focusIds) {
    final node = byId[id];
    if (node == null) continue;
    keep.add(id);
    final pid = node['parentId'] as String?;
    if (pid != null) {
      ctxParents.add(pid);
      keep.add(pid);
    }
  }
  for (final n in nodes) {
    final pid = n['parentId'] as String?;
    if (pid != null && ctxParents.contains(pid)) {
      keep.add(n['id'] as String);
    }
  }
  return nodes.where((n) => keep.contains(n['id'])).toList();
}

String buildValidatePrompt(
  List<Map<String, dynamic>> nodes, {
  List<String>? focusIds,
}) {
  final scope = focusIds != null && focusIds.isNotEmpty
      ? validationNeighborhood(nodes, focusIds)
      : nodes;
  return _replaceOnce(
      promptValidate, '{{tree_json}}', jsonEncode(compactNodesForValidation(scope)));
}

Map<String, dynamic> parseValidationResult(dynamic data) {
  final obj = data is Map<String, dynamic> ? data : <String, dynamic>{};

  final rawIssues = obj['issues'];
  final issues = rawIssues is List
      ? rawIssues.cast<Map<String, dynamic>>().map((i) {
          final type = i['type'];
          return {
            'type': type is String ? type : 'DUPLICATE',
            'node_id': i['node_id'] is String ? i['node_id'] : '',
            'reason': i['reason'] is String ? i['reason'] : '',
          };
        }).toList()
      : <Map<String, dynamic>>[];

  final rawMissing = obj['missing_concepts'];
  final missing = <Map<String, dynamic>>[];
  if (rawMissing is List) {
    for (final c in rawMissing) {
      if (c is String) {
        final t = c.trim();
        if (t.isNotEmpty) {
          missing.add({'title': t, 'parent_id': ''});
        }
      } else if (c is Map<String, dynamic>) {
        final title = (c['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        missing.add({
          'title': title,
          'parent_id': c['parent_id'] is String ? c['parent_id'] : '',
        });
      }
    }
  }

  return {
    'valid': obj['valid'] == true,
    'issues': issues,
    'missing_concepts': missing,
    'should_expand': obj['should_expand'] != false,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// repair.ts
// ═══════════════════════════════════════════════════════════════════════════════

const Map<String, String> _repairLevelTones = {
  'beginner': 'Пиши максимально доступно для новичка, без профессионального жаргона.',
  'intermediate': 'Пиши для знакомого с основами читателя.',
  'expert': 'Пиши для специалиста, используй точную терминологию.',
};

const String promptRepair = '# Роль\n'
    'Ты — эксперт по структуре знаний. Твоя задача — исправить конкретные проблемы в узлах дерева.\n'
    '\n'
    '# Задача\n'
    'Для каждого проблемного узла (указанного в списке «Проблемы») исправь его так, чтобы проблема была устранена.\n'
    '\n'
    '# Правила исправления\n'
    '- Если DUPLICATE: переименуй узел так, чтобы он описывал уникальное понятие, или объедини с дублем.\n'
    '- Если OVERLAP: сузь содержание узла, убери пересекающиеся тезисы.\n'
    '- Если ABSTRACTION_MISMATCH: подними или опусти уровень абстракции до соответствия с соседями.\n'
    '- Если TAXONOMIC_INCONSISTENCY: приведи классификацию к единой логической оси.\n'
    '- Если COVERAGE: добавь пропущенный узел.\n'
    '- Если USELESS_CHILD: переименуй или удали бессмысленный узел.\n'
    '- Если SHOULD_BE_LEAF: пометь узел как leaf (не генерируй детей).\n'
    '- Если LANGUAGE_VIOLATION: переведи label/one_liner на русский.\n'
    '- Если ONTOLOGY_VIOLATION: восстанови canonical_definition, приведи контент в соответствие.\n'
    '- Если AXIS_MIXING: раздели оси, приведи узел к одному semantic_axis.\n'
    '- Если FORBIDDEN_INTERPRETATION: удали запрещённую интерпретацию из контента.\n'
    '- Если SCOPE_ERROR: сделай утверждение условным, добавь оговорки.\n'
    '- Если CAUSAL_ERROR: исправь причинно-следственную связь.\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '- Не описывай произведённые исправления в текстах полей — поля должны содержать только итоговый контент.\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке. Все текстовые поля (label, one_liner, details) — только на русском.\n'
    '{{audience_block}}'
    '\n'
    '# Формат ответа\n'
    'Только валидный JSON-массив исправленных узлов:\n'
    '[\n'
    '  {"id": "id_узла", "parentId": "родитель", "level": N, "label": "Исправленное название", '
    '"one_liner": "...", "details": "...", "conceptType": "...", "semantic_axis": "...", '
    '"canonical_definition": "...", "forbidden_interpretations": ["..."]}\n'
    ']\n'
    '\n'
    'Возвращай ТОЛЬКО исправленные узлы (не все дерево). Каждый исправленный узел должен содержать все обязательные поля.\n'
    'semantic_axis, canonical_definition и forbidden_interpretations — если они изменились при исправлении.\n'
    '\n'
    'Никакого текста вне JSON. Без ```json и без пояснений.\n'
    '\n'
    '# Проблемные узлы\n'
    '{{problem_nodes}}'
    '\n'
    '# Проблемы\n'
    '{{issues}}';

String buildRepairPrompt({
  required List<Map<String, dynamic>> problemNodes,
  required List<Map<String, dynamic>> issues,
  String? level,
}) {
  final nodesStr = jsonEncode(problemNodes.map((n) {
    final details = n['details'] as String?;
    final canonicalDef = n['canonical_definition'] as String?;
    return {
      'id': n['id'],
      'parentId': n['parentId'],
      'level': n['level'],
      'label': n['label'],
      'one_liner': n['one_liner'],
      'details': details != null && details.length > 300
          ? details.substring(0, 300)
          : details,
      'conceptType': n['conceptType'],
      'semantic_axis': n['semantic_axis'],
      'canonical_definition': canonicalDef != null && canonicalDef.length > 200
          ? canonicalDef.substring(0, 200)
          : canonicalDef,
      'forbidden_interpretations': n['forbidden_interpretations'],
    };
  }).toList());

  final issuesStr = issues
      .map((i) => '- [${i['type']}] узел ${i['node_id']}: ${i['reason']}')
      .join('\n');

  final audienceBlock =
      level != null && _repairLevelTones.containsKey(level)
          ? '\n# Аудитория\n${_repairLevelTones[level]}\n'
          : '';

  var result = _replaceOnce(promptRepair, '{{audience_block}}', audienceBlock);
  result = _replaceOnce(result, '{{problem_nodes}}', nodesStr);
  result = _replaceOnce(result, '{{issues}}', issuesStr);
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// tutor.ts
// ═══════════════════════════════════════════════════════════════════════════════

const String promptTutor = '# Роль\n'
    'Ты — контекстный AI-репетитор в системе обучения. Ты знаешь тему, цель, текущий уровень, '
    'текущее понятие, ошибки и оставшееся время. Ты не «чат-болванка»: твой ответ должен помогать '
    'именно на текущем этапе обучения.\n'
    '\n'
    '# Контекст\n'
    'Тема: "{{topic}}"\n'
    'Цель пользователя: {{goal}}\n'
    'Целевой уровень: {{target_level}}\n'
    'Текущий уровень: {{current_level}}\n'
    'Текущее понятие: {{current_node}}\n'
    'Путь понятия: {{node_path}}\n'
    'Текущее освоение: {{current_mastery}}\n'
    'Известные заблуждения: {{misconceptions}}\n'
    'Оставшееся время (мин): {{time_remaining_minutes}}\n'
    'Последние ответы пользователя: {{recent_attempts}}\n'
    '\n'
    '# Правила\n'
    '- Учитывай время: если осталось мало времени (например 5 минут), НЕ давай 20-минутную лекцию. '
    'Сфокусируйся на закреплении ключевой идеи.\n'
    '- Если осталось мало времени — приоритет закреплению уже изученного (recall / краткая проверка), '
    'а не новому материалу.\n'
    '- Не начинай тему с нуля, если пользователь уже в середине.\n'
    '- Учитывай текущие ошибки и заблуждения — исправляй именно их. Ориентируйся на «Известные '
    'заблуждения» и «Последние ответы пользователя».\n'
    '- Учитывай «Текущее освоение»: если понятие уже освоено, не повторяй базовое объяснение, '
    'а углубляй или проверяй перенос (transfer/application).\n'
    '- Применяй active learning: не просто объясняй, а задавай проверочные вопросы, проси объяснить '
    'своими словами, давай применение.\n'
    '- Подстраивай сложность под текущий уровень.\n'
    '- Будь структурирован и краток.\n'
    '\n'
    '$noMetaRule\n'
    '$alphabetRule\n'
    '\n'
    '# Формат ответа\n'
    'Только текст (markdown). Структура:\n'
    '1. Краткий прямой ответ на вопрос пользователя.\n'
    '2. При необходимости — уточняющий вопрос или задание для закрепления.\n'
    '\n'
    '# Язык\n'
    'Отвечай СТРОГО на русском языке.\n'
    '\n'
    'Сообщение пользователя: "{{message}}"';

String buildTutorPrompt({
  required String topic,
  required String goal,
  required String targetLevel,
  required String currentLevel,
  String? currentNode,
  List<String>? nodePath,
  String? currentMastery,
  List<String>? misconceptions,
  int? timeRemainingMinutes,
  List<String>? recentAttempts,
  required String message,
}) {
  final nodePathStr =
      nodePath != null && nodePath.isNotEmpty ? nodePath.join(' → ') : '—';

  final misconceptionsStr =
      misconceptions != null && misconceptions.isNotEmpty
          ? misconceptions.join('; ')
          : '—';

  final timeRemainingStr =
      timeRemainingMinutes != null ? timeRemainingMinutes.toString() : '—';

  final recentAttemptsStr =
      recentAttempts != null && recentAttempts.isNotEmpty
          ? recentAttempts.join(' | ')
          : '—';

  var result = _replaceOnce(promptTutor, '{{topic}}', topic);
  result = _replaceOnce(result, '{{goal}}', goal);
  result = _replaceOnce(result, '{{target_level}}', targetLevel);
  result = _replaceOnce(result, '{{current_level}}', currentLevel);
  result = _replaceOnce(result, '{{current_node}}', currentNode ?? '—');
  result = _replaceOnce(result, '{{node_path}}', nodePathStr);
  result = _replaceOnce(result, '{{current_mastery}}', currentMastery ?? '—');
  result = _replaceOnce(result, '{{misconceptions}}', misconceptionsStr);
  result = _replaceOnce(result, '{{time_remaining_minutes}}', timeRemainingStr);
  result = _replaceOnce(result, '{{recent_attempts}}', recentAttemptsStr);
  result = _replaceOnce(result, '{{message}}', message);
  return result;
}
