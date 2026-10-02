// Детерминированные проверки качества ЭКСПОРТИРОВАННОГО дерева темы
// (`mindtree-*.json`, модель `lib/data/io/topic_file.dart`).
//
// Это НЕ дубликат `tool/probe/quality_checks.dart`: probe смотрит на живой
// прогон пайплайна (драфты до сохранения, активности, вопросы), а здесь вход —
// уже сохранённый и экспортированный файл. Поэтому проверки другие: ревью
// интересуют дефекты, которые пережили запись в БД и экспорт:
//
//  * битые ссылки `relations[].to` (в `to` модель часто пишет ПОДПИСЬ узла
//    вместо id — после импорта связь молча провисает);
//  * подделанные `~`-суффиксы id (LLM любит дописать «правдоподобный» хеш);
//  * формат `details` для двухсекционного режима (цель `deep` + не expert);
//  * необъяснённые аббревиатуры (ELBO без «вариационного нижнего предела»);
//  * дубли `one_liner` у соседних веток;
//  * расхождение сумм `estimatedTimeMinutes` с бюджетом темы.
//
// ВСЕ функции чистые: ни IO, ни LLM, ни «сейчас», ни случайности. Один и тот
// же файл → один и тот же список находок в одном и том же порядке.

import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart'
    show masteryLevelToKnowledgeLevel, maxMinutesPerNode;
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/mastery.dart' show MasteryLevel;
import 'package:mindtree_flutter/domain/models/primitives.dart'
    show ConceptType, LearningGoal, RelationType;

import '../probe/jargon.dart' show findJargon, kDetailsMaxLength;
import 'finding.dart';

/// Стабильные коды проверок дерева. Значения — часть контракта отчёта.
abstract final class TreeCheckCode {
  /// `relations[].to`/`from` не найден среди id узлов файла.
  static const relationTargetExists = 'relation_target_exists';

  /// `~`-суффикс id/цели не равен `scopedSuffix(sourceTopicId)`.
  static const relationScopeHash = 'relation_scope_hash';

  /// Связь ведёт на саму себя или на «тёзку» узла (тот же префикс до `~`).
  static const relationSelfLoop = 'relation_self_loop';

  /// Тип связи вне множества, которое понимает движок (`RelationType`).
  static const relationTypeValid = 'relation_type_valid';

  /// Промпт обещает больше типов связей, чем понимает модель-зеркало.
  static const relationTypePromptMismatch = 'relation_type_prompt_mismatch';

  /// Цикл по dependency-связям (`requires`/`depends_on`/`enables`).
  static const relationDependencyCycle = 'relation_dependency_cycle';

  /// `details` не в двухсекционном формате («Интуиция:» + «Механика:»).
  static const detailsSectionShape = 'details_section_shape';

  /// `details` длиннее `kDetailsMaxLength`.
  static const detailsLength = 'details_length';

  /// Аббревиатура есть, а расшифровки в этом же узле нет.
  static const abbreviationGlossed = 'abbreviation_glossed';

  /// Необъяснённый жаргон (переиспользует словарь probe).
  static const jargonFree = 'jargon_free';

  /// Доля узлов с аналогией.
  static const analogyCoverage = 'analogy_coverage';

  /// `difficulty` выше потолка для не-advanced уровня.
  static const difficultyFit = 'difficulty_fit';

  /// Сумма `estimatedTimeMinutes` не вписывается в бюджет темы.
  static const timeBudgetFit = 'time_budget_fit';

  /// Один узел оценён дольше `maxMinutesPerNode`.
  static const nodeTimeFit = 'node_time_fit';

  /// `one_liner` двух узлов детерминированно близки (без эмбеддингов).
  static const nearDuplicateContent = 'near_duplicate_content';

  /// Последовательностей нет / их мало.
  static const sequencesEmpty = 'sequences_empty';

  /// Один и тот же источник у несвязанных узлов — вероятная ошибка атрибуции.
  static const sourcesSanity = 'sources_sanity';

  /// Эвристика «поверхностного» дерева: нет ветки про применение или сравнение.
  static const goalCoverageGap = 'goal_coverage_gap';

  /// `conceptType` не из множества `ConceptType` (или не задан).
  static const conceptTypePlausible = 'concept_type_plausible';
}

/// Сырые строки `relations[].type` из исходного JSON: `nodeId → типы по
/// порядку relations`.
///
/// Нужны потому, что `Relation.fromJson` СХЛОПЫВАЕТ неизвестный тип в
/// `related` (`RelationType.fromString`), и после разбора файла отличить
/// «модель написал derives_from» от «модель написал related» невозможно.
/// Загрузчик может подставить сюда сырой JSON — проверка останется чистой.
typedef RawRelationTypes = Map<String, List<String>>;

/// Сырые строки `conceptType` из исходного JSON: `nodeId → значение`.
/// Та же причина: `ConceptType.fromString` возвращает `null` на неизвестном
/// значении, теряя сам факт, что значение было.
typedef RawConceptTypes = Map<String, String>;

// ─── Пороги и словари ────────────────────────────────────────────────────────

/// Типы связей, которые образуют граф зависимостей (совпадает с
/// `_dependencyRelationTypes` в `knowledge_graph_engine.dart`).
const List<String> kDependencyRelationTypes = <String>[
  'requires',
  'depends_on',
  'enables',
];

/// Типы связей, обещанные промптом контента (`promptContent`,
/// `data/prompts/prompts.dart`). Держим списком, а не вычисляем из кода:
/// сверка с промптом — ровно то, ради чего существует `relation_type_prompt_mismatch`.
const List<String> kPromptRelationTypes = <String>[
  'related',
  'depends_on',
  'requires',
  'example_of',
  'similar_to',
  'contrasts_with',
  'causes',
  'enables',
  'used_for',
  'alternative_to',
  'derives_from',
  'parameterizes',
  'approximates',
  'generalizes',
  'implements',
  'explains_why',
];

/// Потолок `difficulty` для уровней не выше `solid_understanding`.
const double kMaxDifficultyForBasicLevel = 0.7;

/// Индексы `MasteryLevel.order`, где `difficulty`/`analogy` ещё терпимы:
/// `awareness`, `basic_understanding`, `solid_understanding`.
const int kLastLenientLevelIndex = 2;

/// Порог доли аналогий для цели `deep`.
const double kMinAnalogyCoverageForDeep = 0.5;

/// Множители превышения бюджета: от [kTimeBudgetWarnRatio] — warn,
/// от [kTimeBudgetFailRatio] — fail.
const double kTimeBudgetWarnRatio = 1.5;
const double kTimeBudgetFailRatio = 3.0;

/// Пороги «близкого дубликата» `one_liner`.
const double kNearDuplicateJaccard = 0.75;
const double kNearDuplicateOverlap = 0.8;
const int kNearDuplicateMinWords = 4;
const double kNearDuplicatePrefixShare = 0.6;

/// Ключи подписи раздела `details` в двухсекционном режиме.
const String kIntuitionHeader = 'Интуиция:';
const String kMechanicsHeader = 'Механика:';

/// Разделители для «сжатого» текста (для поиска расшифровок).
final RegExp _nonAlphaNum = RegExp('[^0-9a-zа-я]+');

/// Паразиты в «значащих словах» — иначе Jaccard наполняется служебными
/// словами и любые два `one_liner` выглядят похожими.
const Set<String> kStopWords = <String>{
  'это',
  'как',
  'для',
  'при',
  'если',
  'чтобы',
  'который',
  'которая',
  'которые',
  'которое',
  'также',
  'очень',
  'более',
  'менее',
  'чем',
  'либо',
  'здесь',
  'там',
  'где',
  'когда',
  'после',
  'перед',
  'через',
  'без',
  'над',
  'под',
  'надм',
  'этом',
  'этого',
  'этих',
  'свои',
  'своих',
  'свой',
  'его',
  'ее',
  'её',
  'снаружи',
  'внутри',
};

/// Словарь аббревиатур: сокращение → варианты расшифровки.
///
/// Расшифровка считается найденной, если в тексте узла (one_liner + details +
/// analogy) встречается ЛЮБАЯ из форм: русская, транслитерация или
/// английский полный термин. Смысл проверки — не «буква есть», а «нечем
/// пользователю понять это место».
class AbbreviationGloss {
  /// Сокращение в том виде, в каком его пишут (регистр не важен).
  final String abbreviation;

  /// Формы расшифровки; сравнение — по «сжатому» тексту.
  final List<String> glosses;

  const AbbreviationGloss(this.abbreviation, this.glosses);
}

const List<AbbreviationGloss> kAbbreviationDictionary = <AbbreviationGloss>[
  AbbreviationGloss('ELBO', <String>[
    'evidence lower bound',
    'вариационный нижний предел',
    'вариационная нижняя граница',
    'нижняя граница доказательства',
  ]),
  AbbreviationGloss('MSE', <String>[
    'mean squared error',
    'среднеквадратичная ошибка',
    'средне квадратичная ошибка',
  ]),
  AbbreviationGloss('SDE', <String>[
    'stochastic differential equation',
    'стохастическое дифференциальное уравнение',
  ]),
  AbbreviationGloss('ODE', <String>[
    'ordinary differential equation',
    'обыкновенное дифференциальное уравнение',
  ]),
  AbbreviationGloss('DDPM', <String>[
    'denoising diffusion probabilistic model',
    'диффузионная вероятностная модель',
    'диффузионная вероятностная модель со шумоподавлением',
    'деноизинг диффузионная вероятностная модель',
  ]),
  AbbreviationGloss('DDIM', <String>[
    'denoising diffusion implicit model',
    'диффузионная неявная модель',
    'неявная диффузионная модель',
    'деноизинг диффузионная неявная модель',
  ]),
  AbbreviationGloss('U-Net', <String>[
    'convolutional neural network',
    'сверточная нейросеть',
    'сверточная нейронная сеть',
    'u-shaped network',
    'u образная сеть',
    'сеть u образной формы',
  ]),
  AbbreviationGloss('DiT', <String>[
    'diffusion transformer',
    'диффузионный трансформер',
    'трансформер для диффузии',
  ]),
  AbbreviationGloss('GAN', <String>[
    'generative adversarial network',
    'генеративно состязательная сеть',
    'генеративная состязательная сеть',
  ]),
  AbbreviationGloss('CLIP', <String>[
    'contrastive language image pretraining',
    'контрастивное предобучение языка и изображений',
    'контрастивное обучение на парах текст и изображение',
    'языково визуальное контрастивное обучение',
  ]),
  AbbreviationGloss('LDM', <String>[
    'latent diffusion model',
    'латентная диффузионная модель',
    'диффузионная модель в латентном пространстве',
  ]),
  AbbreviationGloss('CFG', <String>[
    'classifier free guidance',
    'направление без классификатора',
    'гайд без классификатора',
  ]),
  AbbreviationGloss('EMA', <String>[
    'exponential moving average',
    'экспоненциальное скользящее среднее',
    'экспоненциальное среднее',
  ]),
];

/// Ключи подписей L1/L2, по которым ищем ветку про применение.
const List<String> kApplicationKeywords = <String>[
  'примен',
  'пример',
  'практик',
  'приклад',
  'кейс',
  'задач',
  'решен',
  'упражнен',
  'использован',
];

/// Ключи подписей L1/L2, по которым ищем ветку про сравнение.
const List<String> kComparisonKeywords = <String>[
  'сравн',
  'альтернатив',
  'отлич',
  'противополож',
  'в отличие',
  'сопостав',
  'аналог',
  'versus',
];

// ─── Общие хелперы ───────────────────────────────────────────────────────────

/// Нормализация для сравнения подписей и текстов: регистр, ё/е, пробелы.
String _normalize(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// «Сжатый» текст для поиска расшифровок: только буквы/цифры, одиночные
/// пробелы. Так «диффузионная, вероятностная модель» и «диффузионная
/// вероятностная модель (DDPM)» сравниваются одинаково.
String _squeeze(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_nonAlphaNum, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Значащие слова текста — основа для Jaccard/пересечения.
Set<String> _significantWords(String text) => <String>{
      for (final token in _normalize(text).split(_nonAlphaNum))
        if (token.length >= 4 && !kStopWords.contains(token)) token,
    };

/// Префикс id до `~` — «голое» имя узла.
String _baseId(String id) {
  final at = id.indexOf('~');
  return at < 0 ? id : id.substring(0, at);
}

/// Суффикс после `~` вместе с самим `~` (как его отдаёт `scopedSuffix`) либо
/// `null`, если его нет.
String? _scopeSuffixOf(String id) {
  final at = id.indexOf('~');
  return at < 0 ? null : id.substring(at);
}

/// Индекс уровня знаний для словаря антижарона: 1 — beginner, 2 —
/// intermediate, 3 — expert. Тот же порядок, что у probe (`level` 1..3).
int _jargonLevel(MasteryLevel level) => switch (
    masteryLevelToKnowledgeLevel(level.raw)) {
  'intermediate' => 2,
  'expert' => 3,
  _ => 1,
};

/// Подпись уровня аудитории для сообщений.
String _levelLabel(MasteryLevel level) {
  final key = masteryLevelToKnowledgeLevel(level.raw);
  return '${level.raw} (${key ?? 'уровень не задан'})';
}

/// Список id для сообщения: сортировка + ограничение длины.
String _idList(Iterable<String> ids, {int limit = 8}) {
  final sorted = [...ids]..sort();
  if (sorted.length <= limit) return sorted.join(', ');
  final head = sorted.take(limit).join(', ');
  return '$head и ещё ${sorted.length - limit}';
}

/// Процент «как есть» (0..100) одним знаком после запятой — для отчёта.
double _percent(int part, int total) =>
    total == 0 ? 0 : part * 100 / total;

/// Работает ли аналогия у узла.
bool _hasAnalogy(KnowledgeNode n) => (n.analogy ?? '').trim().isNotEmpty;

/// Содержит ли [text] сокращение [abbr] как отдельный токен.
///
/// Токенайзер режет по не-алфавиту, но сохраняет дефис ВНУТРИ токена, а
/// соседние слова дополнительно склеиваются с дефисом: это нужно для `U-Net`.
bool _containsAbbreviation(String text, String abbr) {
  final parts = _squeeze(text).split(' ');
  final wanted = abbr.toLowerCase();
  if (wanted.contains('-')) {
    for (var i = 0; i + 1 < parts.length; i++) {
      if ('${parts[i]}-${parts[i + 1]}' == wanted) return true;
    }
    return false;
  }
  return parts.contains(wanted);
}

/// Есть ли хотя бы одна форма расшифровки в «сжатом» тексте.
bool _containsGloss(String squeezedText, List<String> glosses) =>
    glosses.any((g) => squeezedText.contains(_squeeze(g)));

// ─── Проверки связей ─────────────────────────────────────────────────────────

/// `relations[].to` / `.from` ссылаются на существующие id узлов файла.
///
/// Типичный дефект после экспорта: в `to` стоит ПОДПИСЬ узла («Диффузионная
/// модель»), потому что модель видела только label. Такая связь не чинится
/// ничем и просто провисает — поэтому в сообщение обязательно попадает
/// подпись-кандидат.
List<Finding> checkRelationTargetsExist(TopicFile file) {
  final ids = <String>{for (final n in file.nodes) n.id};
  final idsByLabel = <String, List<String>>{};
  for (final n in file.nodes) {
    final key = _normalize(n.label);
    if (key.isEmpty) continue;
    (idsByLabel[key] ??= <String>[]).add(n.id);
  }
  final expected = file.sourceTopicId.trim().isEmpty
      ? null
      : scopedSuffix(file.sourceTopicId);
  final hexSuffix = RegExp(r'^[0-9a-f]{8}$');

  final out = <Finding>[];
  for (final n in file.nodes) {
    for (var i = 0; i < n.relations.length; i++) {
      final r = n.relations[i];
      for (final field in <(String, String)>[('from', r.from), ('to', r.to)]) {
        final ref = field.$2.trim();
        if (ref.isEmpty || ids.contains(ref)) continue;
        final labelHit = idsByLabel[_normalize(ref)] ?? const <String>[];
        final hint = labelHit.isEmpty
            ? 'в поле «${field.$1}» не id и не подпись узла'
            : 'в поле «${field.$1}» стоит подпись узла '
                '(id: ${_idList(labelHit)})';
        // Отдельной находки «выглядит как выдуманный id» не делаем: она
        // дублировала бы эту же связь. Признак добавляем в текст — по нему
        // видно, что цель не «потерялась», а была придумана моделью.
        final synthetic = _looksSynthetic(ref, expected, hexSuffix);
        out.add(Finding(
          code: TreeCheckCode.relationTargetExists,
          severity: FindingSeverity.fail,
          nodeId: n.id,
          message: 'relations[$i].${field.$1} = «$ref» не найден среди '
              '${ids.length} id узлов файла; $hint'
              '${synthetic ? '; выглядит как выдуманный id: суффикс не 8-hex либо не совпадает с ${expected ?? '~'}-суффиксом темы' : ''}',
          data: {
            'index': i,
            'field': field.$1,
            'ref': ref,
            'type': r.type.raw,
            'labelMatchIds': labelHit,
            'looksSynthetic': synthetic,
            'expectedSuffix': expected,
          },
        ));
      }
    }
  }
  return out;
}

/// `~`-суффикс id равен `scopedSuffix(sourceTopicId)`.
///
/// Инвариант `AGENTS.md`: id узлов — scoped, иначе две темы делят `n1_root`.
/// Экспорт может прийти с чужим или дописанным хешем — тогда связи «теряют»
/// смысл при переносе в другую тему.
List<Finding> checkRelationScopeHash(TopicFile file) {
  if (file.sourceTopicId.trim().isEmpty) {
    return const [
      Finding(
        code: TreeCheckCode.relationScopeHash,
        severity: FindingSeverity.info,
        message: 'В файле нет source.topicId — сверить ~-суффиксы не с чем',
      ),
    ];
  }
  final expected = scopedSuffix(file.sourceTopicId);
  final out = <Finding>[];
  for (final n in file.nodes) {
    final actual = _scopeSuffixOf(n.id);
    if (actual == expected) continue;
    out.add(Finding(
      code: TreeCheckCode.relationScopeHash,
      severity: FindingSeverity.fail,
      nodeId: n.id,
      message: actual == null
          ? 'id «${n.id}» без ~-суффикса; ожидается «$expected» '
              '(scopedSuffix(${file.sourceTopicId}))'
          : '~-суффикс id «${n.id}» = «$actual», ожидается «$expected» '
              '(scopedSuffix(${file.sourceTopicId}))',
      data: {'expected': expected, 'actual': actual},
    ));
  }
  return out;
}

/// Признак «придуманного» id: без `~`, с не-hex суффиксом или с хешем,
/// отличным от scoped-суффикса файла. Используется как подсказка внутри
/// [TreeCheckCode.relationTargetExists].
bool _looksSynthetic(String ref, String? expectedSuffix, RegExp hexSuffix) {
  final at = ref.indexOf('~');
  if (at < 0) return true;
  final suffix = ref.substring(at + 1);
  if (!hexSuffix.hasMatch(suffix)) return true;
  if (expectedSuffix != null && suffix != expectedSuffix.substring(1)) return true;
  return false;
}

/// Связь ведёт на саму себя или на «тёзку» — узел с тем же именем до `~`,
/// но другим суффиксом (типично при пере-скоупинге части дерева).
List<Finding> checkRelationSelfLoops(TopicFile file) {
  final out = <Finding>[];
  for (final n in file.nodes) {
    for (var i = 0; i < n.relations.length; i++) {
      final r = n.relations[i];
      if (r.from.trim() == r.to.trim()) {
        out.add(Finding(
          code: TreeCheckCode.relationSelfLoop,
          severity: FindingSeverity.warn,
          nodeId: n.id,
          message: 'relations[$i]: from == to == «${r.from}» — связь ведёт '
              'на сам узел',
          data: {'index': i},
        ));
        continue;
      }
      final ownBase = _baseId(n.id);
      final toBase = _baseId(r.to.trim());
      final fromBase = _baseId(r.from.trim());
      if (toBase == ownBase || fromBase == toBase) {
        out.add(Finding(
          code: TreeCheckCode.relationSelfLoop,
          severity: FindingSeverity.warn,
          nodeId: n.id,
          message: 'relations[$i]: цель «${r.to}» — тёзка узла «${n.id}» '
              '(одинаковое имя до ~, разный суффикс); связь бессмысленна',
          data: {'index': i, 'to': r.to},
        ));
      }
    }
  }
  return out;
}

/// Типы связей из множества, которое реально понимает движок (`RelationType`).
///
/// Работает по СЫРЫМ строкам: разбор файла схлопывает неизвестный тип в
/// `related`. Если загрузчик сырой JSON не дал — проверка молчит (не выдумывает
/// нарушений), и это видно по отсутствию кода в отчёте.
List<Finding> checkRelationTypeValid(
  List<KnowledgeNode> nodes,
  RawRelationTypes rawTypes,
) {
  if (rawTypes.isEmpty) return const [];
  final supported = <String>{
    for (final t in RelationType.values) t.raw,
  };
  final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};
  final out = <Finding>[];

  for (final nodeId in rawTypes.keys.toList()..sort()) {
    final raw = rawTypes[nodeId] ?? const <String>[];
    for (var i = 0; i < raw.length; i++) {
      final value = raw[i].trim();
      if (value.isEmpty || supported.contains(value)) continue;
      out.add(Finding(
        code: TreeCheckCode.relationTypeValid,
        severity: FindingSeverity.warn,
        nodeId: nodeId,
        message: 'relations[$i].type = «$value» не понимается движком: '
            'RelationType.fromString молча превратит его в «related». '
            'Допустимы: ${(supported.toList()..sort()).join(', ')}',
        data: {
          'index': i,
          'rawType': value,
          'label': byId[nodeId]?.label,
        },
      ));
    }
  }
  return out;
}

/// Промпт обещает типов связей больше, чем понимает модель-зеркало.
///
/// Не дефект конкретного файла, а расхождение промпта и `RelationType`: модель
/// честно пишет `generalizes`, а движок читает это как `related`. Отмечаем
/// один раз, чтобы дыра была видна в каждом ревью.
List<Finding> checkRelationTypePromptMismatch() {
  final supported = <String>{for (final t in RelationType.values) t.raw};
  final extra = <String>[
    for (final t in kPromptRelationTypes)
      if (!supported.contains(t)) t,
  ];
  if (extra.isEmpty) return const [];
  return [
    Finding(
      code: TreeCheckCode.relationTypePromptMismatch,
      severity: FindingSeverity.info,
      message: 'Промпт контента обещает типы связей, которых нет в '
          'RelationType: ${extra.join(', ')} — они молча читаются как «related». '
          'Либо расширить enum, либо убрать их из промпта.',
      data: {'unsupported': extra},
    ),
  ];
}

/// Цикл в графе зависимостей (`requires`/`depends_on`/`enables`).
///
/// Считаем только РАЗРЕШИМЫЕ связи: висящие цели — забота
/// `relation_target_exists`, иначе они давали бы фантомные циклы.
List<Finding> checkRelationDependencyCycles(TopicFile file) {
  final ids = <String>{for (final n in file.nodes) n.id};
  final edges = <String, Set<String>>{};
  for (final n in file.nodes) {
    for (final r in n.relations) {
      if (!kDependencyRelationTypes.contains(r.type.raw)) continue;
      final to = r.to.trim();
      if (to.isEmpty || !ids.contains(to)) continue;
      (edges[n.id] ??= <String>{}).add(to);
    }
  }

  // Трёхцветный DFS: 0 — не посещён, 1 — в стеке, 2 — обработан.
  // Узлы входа и порядок целей — по отсортированным id, поэтому результат
  // не зависит от порядка связей в файле.
  final color = <String, int>{};
  final inCycle = <String>{};
  final startIds = edges.keys.toList()..sort();

  void visit(String id, List<String> stack) {
    color[id] = 1;
    stack.add(id);
    final next = (edges[id] ?? const <String>{}).toList()..sort();
    for (final to in next) {
      final c = color[to] ?? 0;
      if (c == 1) {
        final at = stack.indexOf(to);
        if (at >= 0) inCycle.addAll(stack.sublist(at));
      } else if (c == 0) {
        visit(to, stack);
      }
    }
    stack.removeLast();
    color[id] = 2;
  }

  for (final id in startIds) {
    if ((color[id] ?? 0) == 0) visit(id, <String>[]);
  }

  return [
    for (final id in inCycle.toList()..sort())
      Finding(
        code: TreeCheckCode.relationDependencyCycle,
        severity: FindingSeverity.fail,
        nodeId: id,
        message: 'Узел участвует в цикле по связям '
            'requires/depends_on/enables: ${_idList(inCycle)}',
        data: {'cycleNodes': inCycle.toList()..sort()},
      ),
  ];
}

// ─── Проверки контента ───────────────────────────────────────────────────────

/// Нужен ли двухсекционный формат `details` для этой темы.
///
/// Ровно то же условие, что у промпта (`_twoPartDetailsBlock`): цель `deep`
/// и аудитория не expert. Дальше формат обязателен: один «Интуиция:», один
/// «Механика:», ровно два абзаца.
bool _requiresTwoPartDetails(TopicFile file) =>
    file.topic.goal == LearningGoal.deep &&
    masteryLevelToKnowledgeLevel(file.topic.targetLevel.raw) != 'expert';

/// Заголовок «Интуиция:» в любом написании («интуиция :», «Интуиция:»).
///
/// Класс букв задан ЯВНО: `\w` в Dart — это только `[A-Za-z0-9_]`, кириллицу
/// он не покрывает, и регулярка молча перестала бы находить заголовок.
final RegExp _intuitionHeaderRe =
    RegExp('интуици[а-яё]*\\s*:', caseSensitive: false);

/// Заголовок «Механика:» в любом написании.
final RegExp _mechanicsHeaderRe =
    RegExp('механик[а-яё]*\\s*:', caseSensitive: false);

/// `details` в двухсекционном формате: «Интуиция:» + «Механика:», два абзаца.
List<Finding> checkDetailsSectionShape(TopicFile file) {
  if (!_requiresTwoPartDetails(file)) return const [];
  final paragraphSplit = RegExp(r'\n\s*\n');

  final out = <Finding>[];
  for (final n in file.nodes) {
    final details = n.details.trim();
    if (details.isEmpty) {
      if (n.contentLoaded) {
        out.add(Finding(
          code: TreeCheckCode.detailsSectionShape,
          severity: FindingSeverity.warn,
          nodeId: n.id,
          message: 'details пуст, а цель «deep» требует двух абзацев '
              '(«$kIntuitionHeader» + «$kMechanicsHeader»); уровень '
              '${_levelLabel(file.topic.targetLevel)}',
        ));
      }
      continue;
    }

    final intuitions = _intuitionHeaderRe.allMatches(details).length;
    final mechanics = _mechanicsHeaderRe.allMatches(details).length;
    final paragraphs = details
        .split(paragraphSplit)
        .where((p) => p.trim().isNotEmpty)
        .length;

    final why = <String>[];
    if (intuitions != 1) {
      why.add('заголовков «$kIntuitionHeader» — $intuitions '
          '(ожидался ровно 1)');
    }
    if (mechanics != 1) {
      why.add('заголовков «$kMechanicsHeader» — $mechanics '
          '(ожидался ровно 1)');
    }
    if (paragraphs != 2) {
      why.add('абзацев (по пустой строке) — $paragraphs (ожидалось ровно 2)');
    }
    if (why.isEmpty) continue;

    out.add(Finding(
      code: TreeCheckCode.detailsSectionShape,
      severity: FindingSeverity.warn,
      nodeId: n.id,
      message: 'details не в двухсекционном формате (цель «deep», уровень '
          '${_levelLabel(file.topic.targetLevel)}): ${why.join('; ')}. '
          'Ожидается два абзаца: «$kIntuitionHeader», затем '
          '«$kMechanicsHeader».',
      data: {
        'intuitionHeaders': intuitions,
        'mechanicsHeaders': mechanics,
        'paragraphs': paragraphs,
      },
    ));
  }
  return out;
}

/// `details` длиннее лимита из `tool/probe/jargon.dart`.
List<Finding> checkDetailsLength(TopicFile file) => [
      for (final n in file.nodes)
        if (n.details.trim().length > kDetailsMaxLength)
          Finding(
            code: TreeCheckCode.detailsLength,
            severity: FindingSeverity.warn,
            nodeId: n.id,
            message: 'details длиной ${n.details.trim().length} символов, '
                'лимит $kDetailsMaxLength (тот же, что в промптах контента)',
            data: {
              'length': n.details.trim().length,
              'limit': kDetailsMaxLength,
            },
          ),
    ];

/// Сокращение из словаря употреблено, но не расшифровано в этом же узле.
List<Finding> checkAbbreviationsGlossed(TopicFile file) {
  final out = <Finding>[];
  for (final n in file.nodes) {
    final text = '${n.oneLiner}\n${n.details}\n${n.analogy ?? ''}';
    if (text.trim().isEmpty) continue;
    final squeezed = _squeeze(text);
    for (final entry in kAbbreviationDictionary) {
      if (!_containsAbbreviation(text, entry.abbreviation)) continue;
      if (_containsGloss(squeezed, entry.glosses)) continue;
      out.add(Finding(
        code: TreeCheckCode.abbreviationGlossed,
        severity: FindingSeverity.warn,
        nodeId: n.id,
        message: 'Сокращение «${entry.abbreviation}» есть в контенте узла, '
            'но расшифровки рядом нет. Подходит любая форма: '
            '${entry.glosses.take(3).join(' / ')}',
        data: {'abbreviation': entry.abbreviation},
      ));
    }
  }
  return out;
}

/// Необъяснённый жаргон — тот же детектор, что в probe.
///
/// Проверка активна на ЛЮБОМ уровне, включая `solid_understanding`
/// (аудитория `intermediate`): молча выключать её по «уровень выше 2»
/// нельзя — это ровно тот случай, где материал всё ещё остаётся плотным.
/// Уровень всегда указан в сообщении, чтобы читатель отчёта понимал, к кому
/// это относится.
List<Finding> checkJargonFree(TopicFile file) {
  final level = _jargonLevel(file.topic.targetLevel);
  final out = <Finding>[];
  for (final n in file.nodes) {
    final fields = <(String, String)>[
      ('one_liner', n.oneLiner),
      ('details', n.details),
      ('analogy', n.analogy ?? ''),
    ];
    final terms = <String>{};
    for (final f in fields) {
      terms.addAll(findJargon(f.$2, level));
    }
    if (terms.isEmpty) continue;
    final sorted = terms.toList()..sort();
    out.add(Finding(
      code: TreeCheckCode.jargonFree,
      severity: FindingSeverity.warn,
      nodeId: n.id,
      message: 'Термины без пояснения при уровне аудитории '
          '${_levelLabel(file.topic.targetLevel)} (строгость $level): '
          '${sorted.join(', ')}',
      data: {'terms': sorted, 'jargonLevel': level},
    ));
  }
  return out;
}

/// Доля узлов с аналогией; при цели `deep` ниже 50% — warn.
List<Finding> checkAnalogyCoverage(TopicFile file) {
  final total = file.nodes.length;
  if (total == 0) return const [];
  final withAnalogy = [for (final n in file.nodes) if (_hasAnalogy(n)) n.id];
  final ratio = withAnalogy.length / total;
  final ratioText = '${(ratio * 100).toStringAsFixed(1)}%';
  final minText =
      '${(kMinAnalogyCoverageForDeep * 100).toStringAsFixed(0)}%';
  final isDeep = file.topic.goal == LearningGoal.deep;
  final tooLow = isDeep && ratio < kMinAnalogyCoverageForDeep;
  return [
    Finding(
      code: TreeCheckCode.analogyCoverage,
      severity: tooLow
          ? FindingSeverity.warn
          : FindingSeverity.info,
      message: tooLow
          ? 'Аналогия есть только у ${withAnalogy.length} из $total узлов '
              '($ratioText), а цель «deep» требует не меньше $minText'
          : 'Аналогия есть у ${withAnalogy.length} из $total узлов '
              '($ratioText)',
      data: {
        'withAnalogy': withAnalogy.length,
        'total': total,
        'ratio': double.parse(ratio.toStringAsFixed(4)),
        'deepGoal': isDeep,
      },
    ),
  ];
}

/// `difficulty` выше потолка для уровней не выше `solid_understanding`.
List<Finding> checkDifficultyFit(TopicFile file) {
  final levelIndex = MasteryLevel.order.indexOf(file.topic.targetLevel);
  if (levelIndex > kLastLenientLevelIndex) return const [];
  return [
    for (final n in file.nodes)
      if (n.difficulty > kMaxDifficultyForBasicLevel)
        Finding(
          code: TreeCheckCode.difficultyFit,
          severity: FindingSeverity.warn,
          nodeId: n.id,
          message: 'Узел «${n.label}» помечен как сложный '
              '(difficulty ${n.difficulty.toStringAsFixed(2)}), а targetLevel = '
              '${file.topic.targetLevel.raw}; потолок для этого уровня — '
              '${kMaxDifficultyForBasicLevel.toStringAsFixed(2)}',
          data: {
            'difficulty': n.difficulty,
            'targetLevel': file.topic.targetLevel.raw,
          },
        ),
  ];
}

/// Сумма `estimatedTimeMinutes` (по листьям и по L2) против бюджета темы.
///
/// Считаем два основания намеренно: сумма по листьям — реальная цена
/// прохождения, сумма по L2 — цена, которую движок показывает в плане. Расхождение
/// больше бюджета в 3 раза — уже не «оценка», а нереалистичное обещание.
List<Finding> checkTimeBudgetFit(TopicFile file) {
  final budget = file.topic.timeBudgetMinutes;
  if (budget <= 0) {
    return const [
      Finding(
        code: TreeCheckCode.timeBudgetFit,
        severity: FindingSeverity.info,
        message: 'Временной бюджет темы не задан (timeBudgetMinutes = 0) — '
            'сравнивать не с чем',
      ),
    ];
  }

  final parents = <String>{
    for (final n in file.nodes)
      if (n.parentId != null) n.parentId!,
  };
  final leafMinutes = [
    for (final n in file.nodes)
      if (!parents.contains(n.id)) n.estimatedTimeMinutes,
  ].fold<int>(0, (a, b) => a + b);
  final l2Minutes = [
    for (final n in file.nodes)
      if (n.level == 2) n.estimatedTimeMinutes,
  ].fold<int>(0, (a, b) => a + b);

  FindingSeverity? severityFor(int sum) {
    final ratio = sum / budget;
    if (ratio >= kTimeBudgetFailRatio) return FindingSeverity.fail;
    if (ratio >= kTimeBudgetWarnRatio) return FindingSeverity.warn;
    return null;
  }

  final out = <Finding>[];
  for (final entry in <(String, int)>[
    ('листья', leafMinutes),
    ('узлы L2', l2Minutes),
  ]) {
    final severity = severityFor(entry.$2);
    if (severity == null) continue;
    final ratio = entry.$2 / budget;
    out.add(Finding(
      code: TreeCheckCode.timeBudgetFit,
      severity: severity,
      message: 'Сумма estimatedTimeMinutes по ${entry.$1} — ${entry.$2} мин '
          'при бюджете $budget мин ('
          '${ratio.toStringAsFixed(2)}x; warn от '
          '${kTimeBudgetWarnRatio}x, fail от ${kTimeBudgetFailRatio}x)',
      data: {
        'basis': entry.$1,
        'sumMinutes': entry.$2,
        'budgetMinutes': budget,
        'ratio': double.parse(ratio.toStringAsFixed(4)),
      },
    ));
  }
  return out;
}

/// Один узел оценён дольше `maxMinutesPerNode` движка.
List<Finding> checkNodeTimeFit(TopicFile file) => [
      for (final n in file.nodes)
        if (n.estimatedTimeMinutes > maxMinutesPerNode)
          Finding(
            code: TreeCheckCode.nodeTimeFit,
            severity: FindingSeverity.warn,
            nodeId: n.id,
            message: 'estimatedTimeMinutes = ${n.estimatedTimeMinutes} мин '
                'выходит за разумный предел $maxMinutesPerNode мин на узел',
            data: {'minutes': n.estimatedTimeMinutes},
          ),
    ];

/// Детерминированная близость `one_liner` у разных веток.
///
/// Без эмбеддингов и без расстояний по векторам: три правила на нормализованный
/// текст — точное совпадение, префикс и Jaccard/пересечение по множеству
/// значащих слов. Этого хватает, чтобы поймать «Последовательное удаление
/// шума из случайного вектора…» и «Итеративное удаление шума из случайного
/// вектора…» (общие 4 значащих слова из 5) без ложных срабатываний на честных
/// формулировках.
///
/// Мердж отличается от Jaccard именно для этого случая: у переформулированных
/// one_liner множества почти равны, но не совпадают, и обычный Jaccard падает
/// ниже порога.
List<Finding> checkNearDuplicateContent(TopicFile file) {
  final nodes = <KnowledgeNode>[
    for (final n in file.nodes)
      if (_normalize(n.oneLiner).isNotEmpty) n,
  ];
  final byId = <String, KnowledgeNode>{for (final n in file.nodes) n.id: n};
  final out = <Finding>[];
  final reported = <String>{};

  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      final a = nodes[i];
      final b = nodes[j];
      if (reported.contains(a.id) || reported.contains(b.id)) continue;
      final why = _nearDuplicateReason(
        _normalize(a.oneLiner),
        _normalize(b.oneLiner),
        a,
        b,
        _isAncestor(byId, a, b) || _isAncestor(byId, b, a),
      );
      if (why == null) continue;
      reported.add(a.id);
      reported.add(b.id);
      out.add(Finding(
        code: TreeCheckCode.nearDuplicateContent,
        severity: FindingSeverity.warn,
        nodeId: a.id,
        message: 'one_liner узлов «${a.label}» и «${b.label}» — $why',
        data: {'nodeA': a.id, 'nodeB': b.id},
      ));
    }
  }
  return out;
}

/// Является ли [maybeAncestor] предком [node] (по цепочке `parentId`).
bool _isAncestor(
  Map<String, KnowledgeNode> byId,
  KnowledgeNode maybeAncestor,
  KnowledgeNode node,
) {
  var current = byId[node.parentId];
  var guard = 0;
  while (current != null && guard < 64) {
    if (current.id == maybeAncestor.id) return true;
    current = byId[current.parentId];
    guard++;
  }
  return false;
}

/// Почему два `one_liner` считаются близкими (или `null`).
String? _nearDuplicateReason(
  String a,
  String b,
  KnowledgeNode nodeA,
  KnowledgeNode nodeB,
  bool relatedByLineage,
) {
  if (a == b) return 'совпадают дословно';

  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  final prefixHit = longer.startsWith(shorter);
  if (prefixHit && shorter.length >= longer.length * kNearDuplicatePrefixShare) {
    return 'один является префиксом другого '
        '(${shorter.length} из ${longer.length} симв.)';
  }

  // Словарные меры не применяем только к паре «предок → потомок»: там повтор
  // законен (ребёнок уточняет родителя). Для соседей и далёких веток повтор —
  // это дефект, поэтому меряем.
  if (relatedByLineage) return null;

  final wa = _significantWords(a);
  final wb = _significantWords(b);
  final minSize = wa.length < wb.length ? wa.length : wb.length;
  if (minSize < kNearDuplicateMinWords) return null;
  final intersection = wa.intersection(wb).length;
  final union = wa.union(wb).length;
  final jaccard = union == 0 ? 0.0 : intersection / union;
  final overlap = minSize == 0 ? 0.0 : intersection / minSize;
  if (jaccard > kNearDuplicateJaccard) {
    return 'Jaccard по значащим словам '
        '${jaccard.toStringAsFixed(2)} > '
        '${kNearDuplicateJaccard.toStringAsFixed(2)}';
  }
  if (overlap >= kNearDuplicateOverlap) {
    return 'пересечение значащих слов $intersection из $minSize '
        '(${(overlap * 100).toStringAsFixed(0)}%) — та же мысль другими '
        'словами';
  }
  return null;
}

/// Последовательности обучения: нет ни одной — warn, мало — info.
List<Finding> checkSequencesEmpty(TopicFile file) {
  if (file.nodes.isEmpty) return const [];
  final withSeq = <String>[
    for (final n in file.nodes)
      if (n.sequences.isNotEmpty) n.id,
  ];
  if (withSeq.isEmpty) {
    return [
      Finding(
        code: TreeCheckCode.sequencesEmpty,
        severity: FindingSeverity.warn,
        message: 'sequences пусты у всех ${file.nodes.length} узлов — в теме '
            'нет прогрессии обучения (порядок прохождения не задан)',
        data: {'total': file.nodes.length, 'withSequences': 0},
      ),
    ];
  }
  if (withSeq.length == file.nodes.length) return const [];
  return [
    Finding(
      code: TreeCheckCode.sequencesEmpty,
      severity: FindingSeverity.info,
      message: 'Последовательности есть у ${withSeq.length} из '
          '${file.nodes.length} узлов '
          '(${_percent(withSeq.length, file.nodes.length).toStringAsFixed(1)}%)',
      data: {
        'withSequences': withSeq.length,
        'total': file.nodes.length,
      },
    ),
  ];
}

/// Один и тот же источник у несвязанных узлов — вероятная ошибка атрибуции.
///
/// Реальный случай из экспорта: «Sohl-Dickstein et al., 2015» стоял и у score
/// matching, и у DDIM. Один источник у родственных узлов (родитель/ребёнок,
/// связанные `relations`) — норма, у несвязанных — повод перепроверить.
List<Finding> checkSourcesSanity(TopicFile file) {
  final bySource = <String, List<String>>{};
  final original = <String, String>{};
  for (final n in file.nodes) {
    for (final source in n.sources) {
      final key = _normalize(source);
      if (key.isEmpty) continue;
      original.putIfAbsent(key, () => source.trim());
      (bySource[key] ??= <String>[]).add(n.id);
    }
  }
  if (bySource.isEmpty) return const [];

  final related = _relatednessMatrix(file.nodes);
  final out = <Finding>[];
  for (final key in bySource.keys.toList()..sort()) {
    final ids = (bySource[key] ?? const <String>[]).toSet().toList()..sort();
    if (ids.length < 2) continue;
    var pairs = 0;
    final involved = <String>{};
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        if (related(ids[i], ids[j])) continue;
        pairs++;
        involved
          ..add(ids[i])
          ..add(ids[j]);
      }
    }
    if (pairs == 0) continue;
    out.add(Finding(
      code: TreeCheckCode.sourcesSanity,
      severity: FindingSeverity.warn,
      nodeId: involved.first,
      message: 'Источник «${original[key]}» встречается в $pairs '
          'несвязанных парах узлов (${_idList(involved, limit: 10)}); '
          'похоже на ошибку атрибуции — перепроверь',
      data: {'source': original[key], 'unrelatedPairs': pairs},
    ));
  }
  return out;
}

/// Матрица «связанности» узлов: родитель↔ребёнок, предок↔потомок и любая
/// связь `relations` в обе стороны.
bool Function(String, String) _relatednessMatrix(List<KnowledgeNode> nodes) {
  final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};
  final direct = <String, Set<String>>{};
  void link(String a, String b) {
    (direct[a] ??= <String>{}).add(b);
    (direct[b] ??= <String>{}).add(a);
  }

  for (final n in nodes) {
    final parent = n.parentId;
    if (parent != null && byId.containsKey(parent)) link(n.id, parent);
    for (final r in n.relations) {
      if (byId.containsKey(r.to)) link(n.id, r.to.trim());
    }
  }

  final ancestors = <String, Set<String>>{};
  for (final n in nodes) {
    final chain = <String>{};
    var current = byId[n.parentId];
    var guard = 0;
    while (current != null && guard < 64) {
      chain.add(current.id);
      current = byId[current.parentId];
      guard++;
    }
    ancestors[n.id] = chain;
  }

  return (a, b) {
    if (a == b) return true;
    if ((direct[a] ?? const <String>{}).contains(b)) return true;
    return (ancestors[a] ?? const <String>{}).contains(b) ||
        (ancestors[b] ?? const <String>{}).contains(a);
  };
}

/// Эвристика «поверхностного» дерева: нет ветки про применение/примеры и нет
/// ветки про сравнение с альтернативой.
///
/// Только информация: это не «правильность», а подсказка, что дерево сводит
/// тему к перечислению определений. Смотрим только подписи L1/L2 — у листьев
/// слова «пример» законны в любом случае.
List<Finding> checkGoalCoverageGap(TopicFile file) {
  final topLabels = [
    for (final n in file.nodes)
      if (n.level <= 2) _normalize(n.label),
  ];
  bool matches(List<String> keywords) =>
      topLabels.any((label) => keywords.any(label.contains));

  final hasApplication = matches(kApplicationKeywords);
  final hasComparison = matches(kComparisonKeywords);

  final out = <Finding>[];
  if (!hasApplication) {
    out.add(Finding(
      code: TreeCheckCode.goalCoverageGap,
      severity: FindingSeverity.info,
      message: 'Среди подписей L1/L2 нет ветки про применение и примеры '
          '(«${kApplicationKeywords.take(3).join('», «')}…») — тема, '
          'возможно, подана только определениями',
      data: {'missing': 'application'},
    ));
  }
  if (!hasComparison) {
    out.add(Finding(
      code: TreeCheckCode.goalCoverageGap,
      severity: FindingSeverity.info,
      message: 'Среди подписей L1/L2 нет ветки про сравнение с альтернативой '
          '(«${kComparisonKeywords.take(3).join('», «')}…») — не видно, чем '
          'подход отличается от соседних',
      data: {'missing': 'comparison'},
    ));
  }
  return out;
}

/// `conceptType` из множества `ConceptType` (или не задан).
///
/// Оговорка: `ConceptType.fromString` возвращает `null` и на отсутствующем, и
/// на нераспознанном значении, поэтому без сырого JSON мы видим только «не
/// задано». Сырые значения (если загрузчик их дал) проверяются точно.
List<Finding> checkConceptTypePlausible(
  TopicFile file, {
  RawConceptTypes rawConceptTypes = const {},
}) {
  final allowed = <String>{for (final t in ConceptType.values) t.raw};
  final out = <Finding>[];
  final byId = <String, KnowledgeNode>{for (final n in file.nodes) n.id: n};

  for (final nodeId in rawConceptTypes.keys.toList()..sort()) {
    final raw = (rawConceptTypes[nodeId] ?? '').trim();
    if (raw.isEmpty || allowed.contains(raw)) continue;
    out.add(Finding(
      code: TreeCheckCode.conceptTypePlausible,
      severity: FindingSeverity.info,
      nodeId: nodeId,
      message: 'conceptType «$raw» не входит в ConceptType; разбор подставит '
          'null. Допустимы: ${(allowed.toList()..sort()).join(', ')}',
      data: {
        'raw': raw,
        'label': byId[nodeId]?.label,
      },
    ));
  }

  final without = <String>[
    for (final n in file.nodes)
      if (n.conceptType == null) n.id,
  ];
  if (without.length > file.nodes.length / 2) {
    out.add(Finding(
      code: TreeCheckCode.conceptTypePlausible,
      severity: FindingSeverity.info,
      message: 'conceptType не задан у ${without.length} из '
          '${file.nodes.length} узлов (${_idList(without)}): по ним нельзя '
          'отбирать задания и строить путь обучения',
      data: {
        'without': without.length,
        'total': file.nodes.length,
      },
    ));
  }
  return out;
}

// ─── Точка входа ─────────────────────────────────────────────────────────────

/// Прогоняет все проверки дерева и возвращает стабильно отсортированный список.
///
/// Сырые значения (`rawRelationTypes`, `rawConceptTypes`) необязательны: без них
/// разбор файла уже потерял часть информации, и проверки, которые зависят от
/// сырых строк, просто не дают находок (а не выдумывают их).
List<Finding> runTreeChecks(
  TopicFile file, {
  RawRelationTypes rawRelationTypes = const {},
  RawConceptTypes rawConceptTypes = const {},
}) {
  final nodes = file.nodes;
  final out = <Finding>[
    // Связи.
    ...checkRelationTargetsExist(file),
    ...checkRelationScopeHash(file),
    ...checkRelationSelfLoops(file),
    ...checkRelationTypeValid(nodes, rawRelationTypes),
    ...checkRelationTypePromptMismatch(),
    ...checkRelationDependencyCycles(file),
    // Контент.
    ...checkDetailsSectionShape(file),
    ...checkDetailsLength(file),
    ...checkAbbreviationsGlossed(file),
    ...checkJargonFree(file),
    ...checkAnalogyCoverage(file),
    ...checkNearDuplicateContent(file),
    // Оценки и структура.
    ...checkDifficultyFit(file),
    ...checkTimeBudgetFit(file),
    ...checkNodeTimeFit(file),
    ...checkSequencesEmpty(file),
    ...checkSourcesSanity(file),
    ...checkGoalCoverageGap(file),
    ...checkConceptTypePlausible(file, rawConceptTypes: rawConceptTypes),
  ];
  return sortedFindings(out);
}