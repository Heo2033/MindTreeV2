// Детерминированный LLM для headless-прогона.
//
// Транспорт подменяется на уровне `TreeScheduler.llmCall`, поэтому rate-limit,
// retry, кэш и телеметрия остаются настоящими — меняется только сам ответ.
// Никаких `Random()`/`DateTime.now()` в контенте: один и тот же промпт всегда
// даёт побайтово один и тот же ответ.
//
// Маркеры для `classifyPrompt` — первые строки ролей из
// `lib/data/prompts/prompts.dart` (см. константу `_roleMarkers`).
import 'dart:convert';

import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';

/// Промпт не распознан ни одним из известных шаблонов `prompts.dart`.
///
/// Это ошибка маршрутизации, а не «пустой ответ»: молча отдавать дефолтный
/// JSON нельзя — тогда отчёт будет правдоподобным, но бессмысленным.
class UnknownPromptKind implements Exception {
  /// Первые 200 символов промпта — достаточно, чтобы найти источник.
  final String promptHead;

  UnknownPromptKind(this.promptHead);

  @override
  String toString() => 'UnknownPromptKind: промпт не совпал ни с одним из '
      'известных шаблонов prompts.dart.\n--- начало промпта ---\n$promptHead';
}

/// Все виды промптов, которые умеет обслуживать [classifyPrompt].
///
/// 18 основных билдеров + `L1_EDIT` (тот же шаблон L1 с уточнением корня).
enum PromptKind {
  l1('L1', 'structure'),
  l1Edit('L1_EDIT', 'structure'),
  l2('L2', 'structure-l2'),
  l3('L3', 'structure-l3'),
  expand('expand', 'expand'),
  validate('validate', 'validate'),
  repair('repair', 'repair'),
  onelineRewrite('oneline-rewrite', 'oneline-rewrite'),
  content('content', 'content'),
  explain('explain', 'explain'),
  activity('activity', 'activity'),
  activityFeedback('activityFeedback', 'feedback'),
  assessment('assessment', 'assessment'),
  curriculum('curriculum', 'curriculum'),
  diagnostic('diagnostic', 'diagnostic'),
  mastery('mastery', 'mastery'),
  milestone('milestone', 'milestone'),
  quiz('quiz', 'quiz'),
  tutor('tutor', 'tutor');

  const PromptKind(this.label, this.schedulerOperation);

  /// Короткое имя для отчёта.
  final String label;

  /// Операция в `TreeScheduler.execute`, которой соответствует промпт.
  final String schedulerOperation;
}

/// Однозначные литеральные маркеры из `lib/data/prompts/prompts.dart`.
///
/// Берём строку роли (`# Роль\n<роль>`): в шаблонах она уникальна, в отличие от
/// общих кусков вроде `$noMetaRule`. Порядок важен только для читаемости —
/// маркеры между собой не пересекаются.
const Map<PromptKind, String> _roleMarkers = {
  PromptKind.l1: 'Ты — педагог-структуролог. Твоя задача — определить корень (тему) онтологии дерева знаний.',
  PromptKind.l1Edit: 'Ты — педагог-структуролог. Твоя задача — уточнить корень (тему) онтологии дерева знаний.',
  PromptKind.l2: 'построить уровень 2 (главные разделы) онтологии дерева знаний.',
  PromptKind.l3: 'построить уровень 3 (подразделы) для ОДНОГО конкретного раздела дерева знаний.',
  PromptKind.expand: 'Ты — педагог, расширяешь дерево знаний. Для каждого указанного узла построй следующий уровень иерархии.',
  PromptKind.validate: 'Ты — эксперт по структуре знаний. Твоя задача — найти проблемы в дереве понятий.',
  PromptKind.repair: 'Ты — эксперт по структуре знаний. Твоя задача — исправить конкретные проблемы в узлах дерева.',
  PromptKind.onelineRewrite: 'Ты — редактор учебных материалов. Ты сокращаешь слишком длинное однострочное',
  PromptKind.content: 'Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.',
  PromptKind.explain: 'Ты — помощник-педагог. Объясняешь непонятный термин из текста простыми словами, в контексте темы.',
  PromptKind.activity: 'Ты — AI-репетитор. Готовишь учебный материал для одного понятия внутри структурированной сессии изучения темы.',
  PromptKind.activityFeedback: 'Ты — AI-репетитор. Оцениваешь свободный ответ ученика на задание по конкретному понятию.',
  PromptKind.assessment: 'Ты — экзаменатор. Проверь, действительно ли пользователь достиг заявленного уровня понимания темы.',
  PromptKind.curriculum: 'Ты — curriculum-инженер.',
  PromptKind.diagnostic: 'Ты — диагностирующий педагог. Оцени текущий уровень пользователя по теме.',
  PromptKind.mastery: 'Ты — преподаватель, определяющий освоение материала. Оцени по ответам пользователя, достиг ли он целевого уровня.',
  PromptKind.milestone: 'Ты — навигатор по обучению. Составь карту уровней и направлений для темы.',
  PromptKind.quiz: 'Ты — педагог, составляешь тест по уже изученной теме.',
  PromptKind.tutor: 'Ты — контекстный AI-репетитор в системе обучения.',
};

/// Определяет вид промпта по литеральным маркерам.
///
/// Бросает [UnknownPromptKind], если совпадений нет или их больше одного
/// (неоднозначность маршрутизации — это дефект, а не повод угадывать).
PromptKind classifyPrompt(String prompt) {
  final matched = <PromptKind>[];
  for (final entry in _roleMarkers.entries) {
    if (prompt.contains(entry.value)) matched.add(entry.key);
  }
  if (matched.length == 1) return matched.single;
  final head = prompt.length > 200 ? prompt.substring(0, 200) : prompt;
  if (matched.isEmpty) {
    throw UnknownPromptKind(head);
  }
  throw UnknownPromptKind(
      'Неоднозначная маршрутизация: ${matched.map((k) => k.label).join(', ')}.\n'
      '--- начало промпта ---\n$head');
}

/// Один зарегистрированный вызов fake-LLM.
class FakeLlmCall {
  final PromptKind kind;
  final int promptChars;

  const FakeLlmCall({required this.kind, required this.promptChars});
}

/// Детерминированный транспорт для [TreeScheduler].
///
/// Использование: `buildEngines(..., llmCall: fake.invoke)`.
class FakeLlm {
  final List<FakeLlmCall> calls = [];

  /// Сколько раз вызывался каждый вид промпта.
  Map<String, int> get callsByKind {
    final out = <String, int>{};
    for (final c in calls) {
      out[c.kind.label] = (out[c.kind.label] ?? 0) + 1;
    }
    return out;
  }

  /// Функция того же вида, что и глобальный `callLLM`.
  Future<LLMResult> invoke(
    LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) async {
    final kind = classifyPrompt(prompt);
    final text = respondTo(kind, prompt);
    calls.add(FakeLlmCall(kind: kind, promptChars: prompt.length));
    // Токены считаем по длине текста: детерминированно и достаточно точно
    // для отчёта об объёме/стоимости.
    return LLMResult(
      text: text,
      usage: LLMUsage(
        inputTokens: prompt.length ~/ 4,
        outputTokens: text.length ~/ 4,
      ),
    );
  }

  /// Ответ на промпт заданного вида (без обёртки в [LLMResult]).
  String respondTo(PromptKind kind, String prompt) => switch (kind) {
        PromptKind.l1 => _structure(rootOnly: true, prompt: prompt),
        PromptKind.l1Edit => _structure(rootOnly: true, prompt: prompt),
        PromptKind.l2 => _structure(rootOnly: false, prompt: prompt),
        PromptKind.l3 => _structure(rootOnly: false, prompt: prompt),
        PromptKind.expand => _expand(prompt),
        PromptKind.validate => _validate(),
        PromptKind.repair => _repair(),
        PromptKind.onelineRewrite => _onelineRewrite(prompt),
        PromptKind.content => _content(prompt),
        PromptKind.explain => _explain(prompt),
        PromptKind.activity => _activity(prompt),
        PromptKind.activityFeedback => _activityFeedback(prompt),
        PromptKind.assessment => _assessment(prompt),
        PromptKind.curriculum => _curriculum(prompt),
        PromptKind.diagnostic => _diagnostic(prompt),
        PromptKind.mastery => _mastery(prompt),
        PromptKind.milestone => _milestone(prompt),
        PromptKind.quiz => _quiz(prompt),
        PromptKind.tutor => _tutor(prompt),
      };
}

// ─── Детерминированные тексты и id ───────────────────────────────────────────

/// Названия разделов второго уровня (термины, не метафоры, попарно различны).
const List<String> _sectionTitles = [
  'Основные понятия',
  'Устройство и процессы',
  'Практическое применение',
  'Типичные ошибки',
];

/// Названия для уровня 3+; к ним добавляется префикс родителя, поэтому подписи
/// уникальны по всему дереву (проверка `no_duplicate_labels`).
const List<String> _deepTitles = [
  'ключевые свойства',
  'порядок работы',
  'живой пример',
  'сравнение с альтернативами',
  'ограничения и границы',
];

const List<String> _aspects = [
  'что это такое и зачем это нужно знать',
  'как это устроено изнутри',
  'где это применяется на практике',
  'какие ошибки встречаются чаще всего',
  'как это связано с соседними разделами',
];

/// `n1_root` → `root`: уникальный короткий суффикс для id потомков.
String _slugOf(String rawId) {
  final stripped = rawId.replaceFirst(RegExp(r'^n\d+_'), '');
  final cleaned = stripped.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  if (trimmed.isEmpty) return 'node';
  return trimmed.length > 12 ? trimmed.substring(0, 12) : trimmed;
}

/// Детерминированный «сырой» id ребёнка: `n3_root_1_1`.
String _childRawId(String parentRawId, int level, int index) {
  return 'n${level}_${_slugOf(parentRawId)}_$index';
}

String _clip(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1).trimRight()}…';
}

double _clampNum(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);

// ─── Извлечение контекста из промпта ─────────────────────────────────────────

final RegExp _reQuoted = RegExp(r'"([^"\n]*)"');

/// Значение в кавычках, стоящее сразу после `anchor` (`anchor` — без кавычек).
String _quotedAfter(String prompt, String anchor) {
  final idx = prompt.indexOf(anchor);
  if (idx < 0) return '';
  final m = _reQuoted.firstMatch(prompt.substring(idx + anchor.length));
  return m == null ? '' : m.group(1)!.trim();
}

/// Значение до конца строки после `anchor` — для полей без кавычек
/// (`Тема: {{root_topic}}`, `Текущее понятие: {{current_node}}`).
String _lineValue(String prompt, String anchor) {
  final idx = prompt.indexOf(anchor);
  if (idx < 0) return '';
  final tail = prompt.substring(idx + anchor.length);
  final nl = tail.indexOf('\n');
  return (nl < 0 ? tail : tail.substring(0, nl)).trim();
}

/// Тема пользователя: `Тема пользователя: "..."` (структура) либо `Тема: "..."`.
String _userQuery(String prompt) {
  final byUser = _quotedAfter(prompt, 'Тема пользователя:');
  if (byUser.isNotEmpty) return byUser;
  final quoted = _quotedAfter(prompt, 'Тема:');
  if (quoted.isNotEmpty) return quoted;
  return _lineValue(prompt, 'Тема:').isEmpty ? 'Новая тема' : _lineValue(prompt, 'Тема:');
}

/// Короткое имя корня (L2) или раскрываемого раздела (L3).
String _rootTitle(String prompt) {
  final named = _quotedAfter(prompt, 'Название:');
  if (named.isNotEmpty) return named;
  return _userQuery(prompt);
}

/// Id родителя, подставляемого в шаблон ответа.
String _parentId(String prompt) {
  final m = RegExp(r'"parentId"\s*:\s*"([^"]+)"').firstMatch(prompt);
  if (m != null) return m.group(1)!;
  final root = RegExp(r'с id "([^"]+)"').firstMatch(prompt);
  if (root != null) return root.group(1)!;
  return 'n1_root';
}

/// `n1_root`, `n2_root_1~1a2b3c4d` — уровень из самого id.
int _levelOf(String rawId) {
  final m = RegExp(r'^n(\d+)_').firstMatch(rawId);
  return m == null ? 2 : int.parse(m.group(1)!);
}

/// Маркеры секций, после которых билдер вставляет ровно один JSON-массив
/// с реальными данными. Формат-примеры в конце шаблона сюда не попадают:
/// они отделены заголовком `# ` и содержат выдуманные `n2_a`/`n2_b`.
const List<String> _dataBlockMarkers = <String>[
  'Изученные понятия (в рамках сессии):\n', // assessment
  '# Дерево знаний (полный граф)\n', // curriculum
  '# Ключевые понятия темы (ОБЯЗАТЕЛЬНО используй их для вопросов)\n', // diagnostic
  '# Ответы пользователя на проверку\n', // mastery
  'Дерево знаний (узлы с определениями и связями):\n', // quiz
];

/// Первый непустой блок данных, реально подставленный в промпт.
List<Map<String, dynamic>> _dataBlock(String prompt) {
  for (final marker in _dataBlockMarkers) {
    final block = _jsonBlockAfter(prompt, marker);
    if (block.isNotEmpty) return block;
  }
  return const [];
}

/// Id узлов из блока данных — в порядке появления и без дублей.
List<String> _dataIds(String prompt) {
  final out = <String>[];
  for (final m in _dataBlock(prompt)) {
    final id = m['nodeId'] ?? m['id'];
    if (id is String && id.isNotEmpty && !out.contains(id)) out.add(id);
  }
  return out;
}

/// `label` из блока данных — параллельно [_dataIds].
List<String> _dataLabels(String prompt) {
  final out = <String>[];
  for (final m in _dataBlock(prompt)) {
    final label = m['label'];
    if (label is String && label.isNotEmpty) out.add(label);
  }
  return out;
}

/// Заголовок текущего узла в content-промпте: `Опиши узел «X»:`.
String _nodeTitle(String prompt) {
  final m = RegExp(r'Опиши узел «([^»]+)»').firstMatch(prompt);
  if (m != null) return m.group(1)!.trim();
  final quoted = _quotedAfter(prompt, 'Понятие:');
  return quoted.isEmpty ? _quotedAfter(prompt, 'Узел дерева:') : quoted;
}

/// Путь к узлу: `Путь: A → B → C` (разделитель — стрелка из `prompts.dart`).
List<String> _nodePath(String prompt) {
  final line = RegExp(r'^Путь: (.+)$', multiLine: true).firstMatch(prompt);
  if (line == null) return const [];
  return line
      .group(1)!
      .split('→')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Все id узлов из массива, реально вставленного в промпт (а не из примера
/// формата в конце шаблона — там лежат фиктивные `n2_a`/`n2_b`).
///
/// Между маркером секции и следующим заголовком `# ` лежит ровно один
/// JSON-массив, который подставил билдер.
List<Map<String, dynamic>> _jsonBlockAfter(String prompt, String marker) {
  final idx = prompt.indexOf(marker);
  if (idx < 0) return const [];
  var tail = prompt.substring(idx + marker.length);
  final heading = RegExp(r'\n# ', multiLine: true).firstMatch(tail);
  if (heading != null) tail = tail.substring(0, heading.start);
  final start = tail.indexOf('[');
  final end = tail.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  try {
    final decoded = jsonDecode(tail.substring(start, end + 1));
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList()
        : const [];
  } on FormatException {
    return const [];
  }
}

/// Узлы, перечисленные в секции «Узлы для расширения» (только эта секция,
/// а не «Уже существующее дерево» — там формат строки другой).
List<({String id, String title})> _expandTargets(String prompt) {
  final idx = prompt.indexOf('# Узлы для расширения');
  if (idx < 0) return const [];
  final out = <({String id, String title})>[];
  for (final m in RegExp(r'^- id: ([^,]+), title: "([^"]+)"',
          multiLine: true)
      .allMatches(prompt.substring(idx))) {
    out.add((id: m.group(1)!.trim(), title: m.group(2)!.trim()));
  }
  return out;
}

// ─── Ответы по видам промптов ────────────────────────────────────────────────

String _nodeJson({
  required String id,
  required String title,
  required String? parentId,
  required int level,
  required String topic,
  required int index,
  String semanticAxis = 'representation',
  String conceptType = 'concept',
}) {
  return jsonEncode({
    'id': id,
    'title': title,
    'parentId': parentId,
    'level': level,
    'conceptType': conceptType,
    'canonical_definition':
        '«$title» — часть темы «$topic», раскрывающая ${_aspects[index % _aspects.length]}.',
    'semantic_axis': semanticAxis,
    'forbidden_interpretations': [
      '«$title» — не то же самое, что соседние разделы темы «$topic»'
    ],
    'importance': _clampNum(0.9 - index * 0.1, 0.3, 1.0),
    'difficulty': _clampNum(0.3 + index * 0.1, 0.0, 1.0),
    'estimated_time_minutes': 12 - (index % 4) * 2,
    'prerequisites': <String>[],
    'relations': <Map<String, dynamic>>[],
  });
}

/// L1 (корень) / L2 / L3.
String _structure({required bool rootOnly, required String prompt}) {
  if (rootOnly) {
    final title = _clip(_userQuery(prompt), 48);
    return jsonEncode({
      'nodes': [
        {
          'id': 'n1_root',
          'title': title,
          'parentId': null,
          'level': 1,
          'conceptType': 'topic',
          'canonical_definition':
              '«$title» — тема, основные части которой разбираются в разделах ниже.',
          'semantic_axis': 'theory',
          'forbidden_interpretations': [
            '«$title» — не перечисление фактов, а связанная система понятий'
          ],
          'importance': 1.0,
          'difficulty': 0.4,
          'estimated_time_minutes': 60,
          'prerequisites': <String>[],
          'relations': <Map<String, dynamic>>[],
        }
      ]
    });
  }

  final parentId = _parentId(prompt);
  final level = _levelOf(parentId) + 1;
  final isSectionLevel = level == 2;
  final count = isSectionLevel ? _sectionTitles.length : 3;

  final nodes = <Map<String, dynamic>>[];
  for (var i = 1; i <= count; i++) {
    // Префикс родителя на уровне 3+ гарантирует уникальность подписей
    // (проверка `no_duplicate_labels`).
    final title = isSectionLevel
        ? _sectionTitles[(i - 1) % _sectionTitles.length]
        : '${_rootTitle(prompt)}: ${_deepTitles[(i - 1) % _deepTitles.length]}';
    final raw = jsonDecode(_nodeJson(
      id: _childRawId(parentId, level, i),
      title: title,
      parentId: parentId,
      level: level,
      topic: _userQuery(prompt),
      index: i - 1,
      semanticAxis: isSectionLevel ? 'representation' : 'process',
      conceptType: isSectionLevel ? 'concept' : 'mechanism',
    )) as Map<String, dynamic>;
    nodes.add(raw);
  }
  return jsonEncode({'nodes': nodes});
}

/// Expand (уровень 4+): по 3 ребёнка на каждый целевой узел.
String _expand(String prompt) {
  final targets = _expandTargets(prompt);
  final topic = _lineValue(prompt, 'Тема:');
  final nodes = <Map<String, dynamic>>[];
  for (final t in targets) {
    final level = _levelOf(t.id) + 1;
    final children = <Map<String, dynamic>>[];
    for (var i = 1; i <= 3; i++) {
      children.add(jsonDecode(_nodeJson(
        id: _childRawId(t.id, level, i),
        title: '${t.title}: ${_deepTitles[(i - 1) % _deepTitles.length]}',
        parentId: t.id,
        level: level,
        topic: topic.isEmpty ? t.title : topic,
        index: i - 1,
        semanticAxis: 'process',
        conceptType: 'component',
      )) as Map<String, dynamic>);
    }
    nodes.add({'id': t.id, 'children': children});
  }
  return jsonEncode({'nodes': nodes});
}

/// Валидация: mock всегда подтверждает корректность структуры.
///
/// Так путь `repair` не загрязняет прогон, а сам вид промпта покрыт тестом
/// `fake_llm_routing_test.dart` (вызов билдера напрямую).
String _validate() => jsonEncode({
      'valid': true,
      'issues': <Map<String, dynamic>>[],
      'missing_concepts': <Map<String, dynamic>>[],
      'should_expand': false,
    });

/// Repair: пустой массив — исправлять нечего.
String _repair() => jsonEncode(<Map<String, dynamic>>[]);

/// Переспрос one_liner: детерминированный короткий вариант для понятия.
String _onelineRewrite(String prompt) {
  final label = _quotedAfter(prompt, 'Понятие:');
  return jsonEncode({
    'one_liner': _clip('Краткое описание понятия «$label»: суть и назначение.', 119),
  });
}

/// Контент узла (one_liner / details / analogy / relations / claims).
String _content(String prompt) {
  final label = _nodeTitle(prompt);
  final topic = _userQuery(prompt);
  final path = _nodePath(prompt);
  final level = path.isEmpty ? 2 : path.length;
  final parent = path.length >= 2 ? path[path.length - 2] : topic;

  final oneLiner = _clip(switch (level) {
    1 => '«$label» — обзорная тема: что это такое и из чего состоит.',
    2 => '«$label» — главный раздел темы «$topic»: что он объясняет и зачем нужен.',
    _ => '«$label» — часть раздела «$parent» темы «$topic».',
  }, 120);

  final details = _clip(
    'Интуиция: проще всего представить как «$label» в теме «$topic» — сразу '
    'видно, где это понятие стоит и с чем оно связано.\n\n'
    'Механика: понятие раскрывается в трёх шагах: (1) что это и зачем нужно, '
    '(2) как связано с соседними разделами, (3) где применяется на практике. '
    'На разбор раздела уходит около 10 минут.',
    500,
  );

  final analogy = _clip(
    'Похоже на бытовой пример: как «$label» в теме «$topic» — работает по '
    'тому же принципу, только проще.',
    120,
  );

  // Связи — только на id, реально переданные в промпте. В content-промпте
  // соседи подставляются как ПОДПИСИ (`{{siblings}}` = labels.join(', ')),
  // поэтому единственный известный id — сам узел. Честный ответ здесь —
  // пустой массив: выдумывать `to` нельзя, иначе связь повиснет в БД.
  //
  // Это наблюдение для отчёта probe: промпт просит `relations` с id, но не
  // даёт соседних id, так что связи на этом шаге недостижимы для LLM.
  const relations = <Map<String, dynamic>>[];

  return jsonEncode({
    'one_liner': oneLiner,
    'details': details,
    'analogy': analogy,
    'relations': relations,
    'claims': [
      {
        'subject': label,
        'predicate': 'part_of',
        'object': parent.isEmpty ? topic : parent,
      }
    ],
    'sources': <String>[],
  });
}

/// Explain: обычный текст, без JSON.
String _explain(String prompt) {
  final label = _quotedAfter(prompt, 'Узел дерева:');
  final selected = _quotedAfter(prompt, 'просит пояснение:');
  final subject = selected.isEmpty ? label : selected;
  return '«$subject» — это часть понятия «${label.isEmpty ? 'темы' : label}». '
      'Проще говоря: здесь речь о том, где понятие применяется и почему это '
      'важно. Если коротко — это упрощает понимание всей темы целиком.';
}

/// Activity: example + recall (4 варианта) + apply.
String _activity(String prompt) {
  final label = _quotedAfter(prompt, 'Понятие:');
  final topic = _quotedAfter(prompt, 'Тема:');
  final nodeName = label.isEmpty ? 'понятие' : label;
  return jsonEncode({
    'example': 'Представь, что ты объясняешь «$nodeName» другу из темы '
        '«$topic». Проще всего начать с одного бытового примера, а затем '
        'показать, где этот пример перестаёт работать и нужно уточнение.',
    'recall': {
      'question': 'Что раскрывает понятие «$nodeName»?',
      'options': [
        'Главную роль понятия в теме «$topic»',
        'Только список терминов без пояснений',
        'Историю появления темы в науке',
        'Список литературы по теме',
      ],
      'correct_index': 0,
    },
    'apply': {
      'instruction':
          'Опиши ситуацию из «$topic», где понятие «$nodeName» помогает принять решение, и объясни ход мысли.',
      'reference_answer':
          'Нужно назвать конкретную ситуацию, показать, что без «$nodeName» решение не получается, и объяснить, какой шаг именно его применяет.',
    }
  });
}

/// Activity feedback: детерминированно «частично верно» + мисконцепция.
String _activityFeedback(String prompt) {
  final label = _quotedAfter(prompt, 'Понятие:');
  return jsonEncode({
    'assessment': 'partial',
    'feedback': 'Ход мысли верный, но не хватает конкретики: назовите «$label» '
        'своими словами и покажите, где именно он применяется в вашем примере.',
    'misconception':
        'Ответ опирается на знание определения, но не показывает применения «$label» на практике',
  });
}

/// Assessment: вопросы, чередуя открытые типы и типы с вариантами.
String _assessment(String prompt) {
  final countMatch = RegExp(r'Всего (\d+) вопросов').firstMatch(prompt);
  final count = countMatch == null ? 6 : int.parse(countMatch.group(1)!);
  final ids = _dataIds(prompt);
  final labels = _dataLabels(prompt);
  final nodes = ids.isEmpty ? ['n1_root'] : ids;

  // 6 типов из спеки: recognition/recall — с вариантами, остальные открытые.
  const openTypes = ['explanation', 'diagnosis', 'application', 'transfer'];
  const closedTypes = ['recognition', 'recall'];
  final questions = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final nodeId = nodes[i % nodes.length];
    final label = i < labels.length ? labels[i] : 'тема';
    final isOpen = i % 3 == 2;
    final type = isOpen
        ? openTypes[i % openTypes.length]
        : closedTypes[i % closedTypes.length];
    questions.add({
      'id': 'a${i + 1}',
      'type': type,
      'nodeId': nodeId,
      'question': isOpen
          ? 'Объясните своими словами, как «$label» связан с остальными разделами, и приведите пример.'
          : 'Что верно о понятии «$label»?',
      'options': isOpen
          ? <String>[]
          : [
              '«$label» раскрывает свою роль в теме и связывается с другими разделами',
              '«$label» — это отдельная тема, не связанная с остальными',
              '«$label» упоминается только в исторической справке',
              '«$label» не требует пояснений и используется как готовое название раздела',
            ],
      'correctAnswer': isOpen ? '' : '0',
      'explanation': isOpen
          ? 'Рубрика: 1) названо, что такое «$label»; 2) названа связь с другим разделом; 3) приведён пример.'
          : 'Верно первый вариант: он описывает содержание понятия, остальные либо подменяют тему, либо ничего не объясняют.',
    });
  }
  return jsonEncode({'questions': questions});
}

/// Curriculum: 6 понятий из дерева с оценкой времени.
String _curriculum(String prompt) {
  final ids = _dataIds(prompt);
  final labels = _dataLabels(prompt);
  if (ids.isEmpty) {
    return jsonEncode({
      'items': <Map<String, dynamic>>[],
      'total_estimated_minutes': 0,
      'skipped': <Map<String, dynamic>>[],
    });
  }
  final items = <Map<String, dynamic>>[];
  var total = 0;
  final count = ids.length < 6 ? ids.length : 6;
  for (var i = 0; i < count; i++) {
    final minutes = 10 - (i % 3) * 2;
    total += minutes;
    items.add({
      'node_id': ids[i],
      'order': i + 1,
      'estimated_minutes': minutes,
      'why': i < labels.length
          ? '«${labels[i]}» нужен, чтобы понять следующий раздел плана.'
          : 'Понятие закрывает обязательный минимум по цели.',
    });
  }
  return jsonEncode({
    'items': items,
    'total_estimated_minutes': total,
    'skipped': <Map<String, dynamic>>[],
  });
}

/// Diagnostic: 3–4 вопроса с вариантами по первым понятиям дерева.
String _diagnostic(String prompt) {
  final ids = _dataIds(prompt);
  final labels = _dataLabels(prompt);
  if (ids.isEmpty) {
    return jsonEncode({'questions': <Map<String, dynamic>>[]});
  }
  final count = ids.length < 4 ? ids.length : 4;
  final questions = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final label = i < labels.length ? labels[i] : 'понятие';
    questions.add({
      'id': 'd${i + 1}',
      'nodeId': ids[i],
      'question': 'Как связано понятие «$label» с остальными разделами темы?',
      'options': [
        '«$label» показывает, как понятие применяется на практике',
        '«$label» — это отдельная дисциплина без связи с темой',
        '«$label» нужно только для исторической справки',
        '«$label» не требует изучения',
      ],
      'correctIndex': 0,
      'explanation':
          'Правильный первый вариант: понятие объясняет применение темы, остальные не описывают содержание.',
    });
  }
  return jsonEncode({'questions': questions});
}

/// Mastery: фиксированные неидеальные метрики + мисконцепция.
String _mastery(String prompt) {
  final ids = _dataIds(prompt);
  final concepts = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length && i < 12; i++) {
    final understanding = _clampNum(0.85 - i * 0.05, 0.3, 1.0);
    concepts.add({
      'nodeId': ids[i],
      'understanding': understanding,
      'recall': _clampNum(understanding - 0.1, 0.2, 1.0),
      'application': _clampNum(understanding - 0.25, 0.1, 1.0),
      'transfer': _clampNum(understanding - 0.4, 0.05, 1.0),
      'confidence': _clampNum(understanding - 0.2, 0.1, 1.0),
      'misconception': i == 1
          ? {
              'type': 'incomplete',
              'description':
                  'Понятие названо верно, но не объяснено, как оно применяется на практике'
            }
          : null,
    });
  }
  return jsonEncode({
    'concepts': concepts,
    'enough': false,
    'overall_level': 'basic_understanding',
    'gaps': [
      'Ответы верны по смыслу, но почти без примеров применения.',
      'Нужно отдельно отработать перенос знания на смежную ситуацию.',
    ],
  });
}

/// Milestone: карта уровней awareness → expert.
String _milestone(String prompt) {
  final topic = _quotedAfter(prompt, 'Тема:');
  const levels = [
    'awareness',
    'basic_understanding',
    'solid_understanding',
    'practical_application',
    'advanced',
    'expert',
  ];
  const titles = [
    'Знакомство с темой',
    'Базовое понимание',
    'Твёрдое понимание',
    'Практическое применение',
    'Продвинутый уровень',
    'Экспертный уровень',
  ];
  final milestones = <Map<String, dynamic>>[];
  for (var i = 0; i < levels.length; i++) {
    milestones.add({
      'id': 'm${i + 1}',
      'level': levels[i],
      'title': titles[i],
      'description':
          'Уровень «${titles[i]}» по теме «$topic»: следующий шаг после предыдущего.',
      'capabilities': [
        'Разобрать основные понятия темы «$topic»',
        'Объяснить понятие своими словами',
        'Применить понятие к новой ситуации',
      ],
      'estimated_hours': 1 + i,
      'alternative_paths': i + 1 < levels.length
          ? [
              {
                'id': 'm${i + 2}',
                'title': titles[i + 1],
                'estimated_hours': 2 + i,
                'description': 'Дальнейшее углубление по теме «$topic».',
              }
            ]
          : <Map<String, dynamic>>[],
    });
  }
  return jsonEncode({'milestones': milestones});
}

/// Quiz: вопросов — сколько попросили, минимум два misconception-вопроса.
String _quiz(String prompt) {
  final countMatch = RegExp(r'Сгенерируй (\d+) вопросов').firstMatch(prompt);
  final count = countMatch == null ? 6 : int.parse(countMatch.group(1)!);
  final ids = _dataIds(prompt);
  final labels = _dataLabels(prompt);
  final nodes = ids.isEmpty ? ['n1_root'] : ids;
  final questions = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final label = i < labels.length ? labels[i] : 'понятие';
    final isMisconception = i >= count - 2;
    questions.add({
      'id': 'q${i + 1}',
      'nodeId': nodes[i % nodes.length],
      'question': isMisconception
          ? 'Верно ли, что «$label» не нужно связывать с остальными разделами темы?'
          : 'Что даёт понимание «$label» при изучении темы?',
      'options': isMisconception
          ? [
              'Да, это верно: понятие изучается изолированно',
              'Нет: понятие раскрывается через связь с соседними разделами',
              'Да, если остальные разделы уже пройдены',
              'Да, но только в письменных работах',
            ]
          : [
              'Понимание, где понятие применяется и с чем оно связано',
              'Только запоминание названия раздела',
              'Только умение пересказать определение',
              'Ничего: определение уже есть в учебнике',
            ],
      'correctIndex': 1,
      'explanation': isMisconception
          ? 'Утверждение ложно: понятие раскрывается через связь с соседними разделами, изоляция приводит к формальному запоминанию.'
          : 'Верно: понимание связей даёт применимость, а не запоминание определения.',
      'misconception': isMisconception,
    });
  }
  return jsonEncode({'questions': questions});
}

/// Tutor: короткий ответ обычным текстом.
String _tutor(String prompt) {
  final message = _quotedAfter(prompt, 'Сообщение пользователя:');
  final current = _lineValue(prompt, 'Текущее понятие:');
  final subject = current.isEmpty || current == '-' ? 'текущим' : current;
  return 'Коротко по вопросу «${_clip(message, 80)}».\n\n'
      'Сейчас вы работаете с понятием «$subject». Стоит зафиксировать главное: '
      'сначала скажите своими словами, что это понятие делает, затем приведите '
      'один пример из жизни или работы. Если получится — задайте себе вопрос '
      '«а что будет, если этого не будет?».';
}
