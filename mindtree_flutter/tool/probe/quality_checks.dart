// Детерминированные quality-проверки probe.
//
// Каждая проверка — чистая функция от переданных данных: один и тот же вход
// всегда даёт один и тот же список результатов. Порядок результатов
// стабильный (сначала по коду, потом по порядку обхода), поэтому отчёты
// можно сравнивать побайтово.
//
// Проверки НЕ дублируют доменную валидацию дерева (`validateTreeShape`):
// здесь важно не «проходит/не проходит», а какие именно узлы нарушают
// контракт — чтобы отчёт показал конкретные примеры.

import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/models/activity.dart';
import 'package:mindtree_flutter/domain/models/assessment.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';

import 'jargon.dart';

/// Серьёзность нарушения.
enum Severity {
  info,
  warn,
  fail;

  /// Для сортировки отчёта: чем выше, тем хуже.
  int get rank => switch (this) {
        Severity.info => 0,
        Severity.warn => 1,
        Severity.fail => 2,
      };
}

/// Один результат проверки.
class CheckResult {
  /// Стабильный код проверки (см. [CheckCode]).
  final String code;
  final Severity severity;

  /// Узел-виновник, если применимо.
  final String? nodeId;
  final String message;

  const CheckResult({
    required this.code,
    required this.severity,
    this.nodeId,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'severity': severity.name,
        if (nodeId != null) 'nodeId': nodeId,
        'message': message,
      };

  @override
  String toString() =>
      '[${severity.name}] $code${nodeId == null ? '' : ' ($nodeId)'}: $message';
}

/// Стабильные коды проверок. Значения — часть контракта отчёта.
abstract final class CheckCode {
  static const oneLinerMaxLen = 'one_liner_max_len';
  static const singleRoot = 'single_root';
  static const parentExists = 'parent_exists';
  static const noCycles = 'no_cycles';
  static const levelConsistent = 'level_consistent';
  static const noEmptyContent = 'no_empty_content';
  static const noDuplicateLabels = 'no_duplicate_labels';
  static const jargonFree = 'jargon_free';
  static const recallWellformed = 'recall_wellformed';
  static const applyWellformed = 'apply_wellformed';
  static const noDuplicateActivity = 'no_duplicate_activity';
  static const goalCoverage = 'goal_coverage';
  static const contentCoverage = 'content_coverage';
  static const questionWellformed = 'question_wellformed';
  static const questionNodeKnown = 'question_node_known';
}

/// Вход для всех проверок: всё, что probe успел накопить на момент отчёта.
class QualityInput {
  /// Узлы дерева с уже загруженным контентом (или без — если контент
  /// пропущен флагом `--skip-content`).
  final List<KnowledgeNode> nodes;

  /// Целевой уровень пользователя: влияет на строгость антижарона.
  final int targetLevel;

  /// Заявленная цель обучения (свободный текст от пользователя).
  final String goal;

  /// Ответы recall-шагов из учебной активности.
  final List<ActivityStep> recallSteps;

  /// Ответы apply-шагов из учебной активности.
  final List<ActivityStep> applySteps;

  /// Сгенерированные активности целиком — нужна проверка дублей по nodeId.
  final List<LearningActivity> activities;

  /// Результаты диагностики (для проверки контракта вопросов).
  final List<DiagnosticQuestion> diagnosticQuestions;

  /// Результаты итоговой оценки.
  final List<AssessmentQuestion> assessmentQuestions;

  /// Узлы, попавшие в учебный план/curriculum.
  final List<String> curriculumNodeIds;

  const QualityInput({
    required this.nodes,
    required this.targetLevel,
    required this.goal,
    this.recallSteps = const [],
    this.applySteps = const [],
    this.activities = const [],
    this.diagnosticQuestions = const [],
    this.assessmentQuestions = const [],
    this.curriculumNodeIds = const [],
  });
}

/// Стабильная сортировка: сначала код, затем порядок обхода (insertion).
List<CheckResult> _sorted(List<CheckResult> results) {
  final indexed = [
    for (var i = 0; i < results.length; i++) (i, results[i]),
  ]..sort((a, b) {
      final byCode = a.$2.code.compareTo(b.$2.code);
      return byCode != 0 ? byCode : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

// ─── Проверки дерева ─────────────────────────────────────────────────────────

/// `one_liner` ≤ 120 символов (инвариант дерева знаний).
List<CheckResult> checkOneLinerLength(List<KnowledgeNode> nodes) => [
      for (final n in nodes)
        if (exceedsOneLinerLimit(n.oneLiner))
          CheckResult(
            code: CheckCode.oneLinerMaxLen,
            severity: Severity.fail,
            nodeId: n.id,
            message: 'one_liner длиной ${n.oneLiner.trim().length} '
                'символов, лимит $kOneLinerMaxLength',
          ),
    ];

/// Ровно один корень (`parentId == null`).
List<CheckResult> checkSingleRoot(List<KnowledgeNode> nodes) {
  final roots = [for (final n in nodes) if (n.parentId == null) n.id];
  if (roots.isEmpty) {
    return const [
      CheckResult(
        code: CheckCode.singleRoot,
        severity: Severity.fail,
        message: 'В дереве нет корня: ни один узел не имеет parentId == null',
      ),
    ];
  }
  if (roots.length > 1) {
    return [
      CheckResult(
        code: CheckCode.singleRoot,
        severity: Severity.fail,
        message: 'В дереве ${roots.length} корня, ожидался один: '
            '${roots.join(', ')}',
      ),
    ];
  }
  return const [];
}

/// `parentId` ссылается на существующий узел.
List<CheckResult> checkParentsExist(List<KnowledgeNode> nodes) {
  final ids = {for (final n in nodes) n.id};
  return [
    for (final n in nodes)
      if (n.parentId != null && !ids.contains(n.parentId))
        CheckResult(
          code: CheckCode.parentExists,
          severity: Severity.fail,
          nodeId: n.id,
          message: 'parentId "${n.parentId}" не найден среди узлов темы',
        ),
  ];
}

/// В дереве нет циклов по `parentId`.
List<CheckResult> checkNoCycles(List<KnowledgeNode> nodes) {
  final byId = {for (final n in nodes) n.id: n};
  final inCycle = <String>{};

  // Итеративный обход с отметкой посещённых: тот же алгоритм, что в
  // `validateTreeShape`, но он собирает ВИНОВНИКОВ, а не только факт.
  final done = <String>{};
  for (final n in nodes) {
    if (done.contains(n.id)) continue;
    final path = <String>[];
    final onPath = <String>{};
    var current = n.id;
    while (true) {
      if (onPath.contains(current)) {
        // Цикл найден: все узлы от повтора до текущего — участники.
        final start = path.indexOf(current);
        inCycle.addAll(path.sublist(start));
        break;
      }
      if (done.contains(current)) break;
      onPath.add(current);
      path.add(current);
      final parent = byId[current]?.parentId;
      if (parent == null) break;
      current = parent;
    }
    done.addAll(path);
  }

  return [
    for (final id in inCycle.toList()..sort())
      CheckResult(
        code: CheckCode.noCycles,
        severity: Severity.fail,
        nodeId: id,
        message: 'Узел участвует в цикле parentId',
      ),
  ];
}

/// `level` узла равен `level(родителя) + 1`, корень имеет `level == 1`.
List<CheckResult> checkLevelConsistency(List<KnowledgeNode> nodes) {
  final byId = {for (final n in nodes) n.id: n};
  return [
    for (final n in nodes)
      if (_levelViolation(byId, n) case final String why)
        CheckResult(
          code: CheckCode.levelConsistent,
          severity: Severity.fail,
          nodeId: n.id,
          message: why,
        ),
  ];
}

String? _levelViolation(Map<String, KnowledgeNode> byId, KnowledgeNode n) {
  if (n.parentId == null) {
    return n.level == 1 ? null : 'Корень имеет level == ${n.level}, ожидался 1';
  }
  final parent = byId[n.parentId];
  if (parent == null) return null; // уже ловится в `parent_exists`
  final expected = parent.level + 1;
  return n.level == expected
      ? null
      : 'level == ${n.level}, у родителя level == ${parent.level} '
          '(ожидался $expected)';
}

/// У узлов с `contentLoaded` заполнены `oneLiner` и `label`.
List<CheckResult> checkNoEmptyContent(List<KnowledgeNode> nodes) => [
      for (final n in nodes)
        if (n.contentLoaded) ...[
          if (n.oneLiner.trim().isEmpty)
            CheckResult(
              code: CheckCode.noEmptyContent,
              severity: Severity.fail,
              nodeId: n.id,
              message: 'Пустой one_liner при contentLoaded == true',
            ),
          if (n.label.trim().isEmpty)
            CheckResult(
              code: CheckCode.noEmptyContent,
              severity: Severity.fail,
              nodeId: n.id,
              message: 'Пустой label при contentLoaded == true',
            ),
        ],
    ];

/// Подписи узлов уникальны в пределах одного родителя.
List<CheckResult> checkNoDuplicateLabels(List<KnowledgeNode> nodes) {
  final byParent = <String?, List<KnowledgeNode>>{};
  for (final n in nodes) {
    byParent.putIfAbsent(n.parentId, () => <KnowledgeNode>[]).add(n);
  }
  final out = <CheckResult>[];
  for (final entry in byParent.entries) {
    final seen = <String, List<KnowledgeNode>>{};
    for (final n in entry.value) {
      final key = _normalize(n.label);
      if (key.isEmpty) continue;
      seen.putIfAbsent(key, () => <KnowledgeNode>[]).add(n);
    }
    for (final group in seen.values) {
      if (group.length < 2) continue;
      final ids = [for (final n in group) n.id]..sort();
      out.add(CheckResult(
        code: CheckCode.noDuplicateLabels,
        severity: Severity.warn,
        nodeId: ids.first,
        message: 'Подпись «${group.first.label}» повторяется '
            '${group.length} раза(ы) у одного родителя: ${ids.join(', ')}',
      ));
    }
  }
  return out;
}

/// Нормализация подписи для сравнения: регистр, пробелы, ё/е.
String _normalize(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Антижаргон: в контенте не-expert уровня не должно быть необъяснённых
/// терминов из словаря.
List<CheckResult> checkJargonFree(List<KnowledgeNode> nodes, int targetLevel) {
  final out = <CheckResult>[];
  for (final n in nodes) {
    if (!n.contentLoaded) continue;
    final terms = <String>{};
    for (final field in <(String, String)>[
      ('one_liner', n.oneLiner),
      ('details', n.details),
      if (n.analogy != null) ('analogy', n.analogy!),
    ]) {
      terms.addAll(findJargon(field.$2, targetLevel));
    }
    if (terms.isEmpty) continue;
    final sorted = terms.toList()..sort();
    out.add(CheckResult(
      code: CheckCode.jargonFree,
      severity: Severity.warn,
      nodeId: n.id,
      message: 'Термины без пояснения (уровень $targetLevel): '
          '${sorted.join(', ')}',
    ));
  }
  return out;
}

// ─── Проверки активности ─────────────────────────────────────────────────────

/// recall-шаг: есть варианты (2..4) и корректный индекс в их диапазоне.
List<CheckResult> checkRecallWellformed(List<ActivityStep> steps) => [
      for (final s in steps) ...[
        if (s.type != 'recall')
          CheckResult(
            code: CheckCode.recallWellformed,
            severity: Severity.fail,
            message: 'Шаг «${s.title}» имеет type "${s.type}", ожидался recall',
          )
        else ...[
          if (s.options == null || s.options!.length < 2 || s.options!.length > 4)
            CheckResult(
              code: CheckCode.recallWellformed,
              severity: Severity.fail,
              message: 'recall «${s.title}»: вариантов '
                  '${s.options?.length ?? 0}, ожидалось 2..4',
            ),
          if (s.correctIndex == null)
            CheckResult(
              code: CheckCode.recallWellformed,
              severity: Severity.fail,
              message: 'recall «${s.title}»: не задан correctIndex',
            )
          else if (s.options != null &&
              (s.correctIndex! < 0 || s.correctIndex! >= s.options!.length))
            CheckResult(
              code: CheckCode.recallWellformed,
              severity: Severity.fail,
              message: 'recall «${s.title}»: correctIndex ${s.correctIndex} '
                  'вне диапазона 0..${s.options!.length - 1}',
            ),
        ],
      ],
    ];

/// apply-шаг: есть инструкция и эталонный ответ, вариантов быть не должно.
List<CheckResult> checkApplyWellformed(List<ActivityStep> steps) => [
      for (final s in steps) ...[
        if (s.type != 'apply')
          CheckResult(
            code: CheckCode.applyWellformed,
            severity: Severity.fail,
            message: 'Шаг «${s.title}» имеет type "${s.type}", ожидался apply',
          )
        else ...[
          if (s.instruction == null || s.instruction!.trim().isEmpty)
            CheckResult(
              code: CheckCode.applyWellformed,
              severity: Severity.fail,
              message: 'apply «${s.title}»: пустая инструкция',
            ),
          if (s.bestAnswer == null || s.bestAnswer!.trim().isEmpty)
            CheckResult(
              code: CheckCode.applyWellformed,
              severity: Severity.fail,
              message: 'apply «${s.title}»: нет эталонного ответа (bestAnswer)',
            ),
          if (s.options != null && s.options!.isNotEmpty)
            CheckResult(
              code: CheckCode.applyWellformed,
              severity: Severity.fail,
              message: 'apply «${s.title}»: варианты недопустимы для '
                  'открытого вопроса',
            ),
        ],
      ],
    ];

/// На каждый узел — не больше одной активности в рамках прогона.
List<CheckResult> checkNoDuplicateActivity(List<LearningActivity> activities) {
  final byNode = <String, List<LearningActivity>>{};
  for (final a in activities) {
    byNode.putIfAbsent(a.nodeId, () => <LearningActivity>[]).add(a);
  }
  final out = <CheckResult>[];
  final nodeIds = byNode.keys.toList()..sort();
  for (final nodeId in nodeIds) {
    final group = byNode[nodeId]!;
    if (group.length < 2) continue;
    out.add(CheckResult(
      code: CheckCode.noDuplicateActivity,
      severity: Severity.warn,
      nodeId: nodeId,
      message: 'На узел «${group.first.nodeLabel}» построено '
          '${group.length} активностей вместо одной',
    ));
  }
  return out;
}

// ─── Проверки вопросов ───────────────────────────────────────────────────────

/// Контракт вопроса: у закрытого типа есть 2..4 варианта и корректный индекс,
/// у открытого — непустой текст вопроса.
List<CheckResult> checkQuestionsWellformed({
  required List<DiagnosticQuestion> diagnostic,
  required List<AssessmentQuestion> assessment,
}) {
  final out = <CheckResult>[];

  for (final q in diagnostic) {
    if (q.question.trim().isEmpty) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'diagnostic: пустой текст вопроса',
      ));
    }
    if (q.options.length < 2 || q.options.length > 4) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'diagnostic: вариантов ${q.options.length}, ожидалось 2..4',
      ));
    }
    if (q.correctIndex < 0 || q.correctIndex >= q.options.length) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'diagnostic: correctIndex ${q.correctIndex} вне диапазона '
            '0..${q.options.length - 1}',
      ));
    }
  }

  for (final q in assessment) {
    if (q.question.trim().isEmpty) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'assessment: пустой текст вопроса (id ${q.id})',
      ));
    }
    final hasOptions = q.options != null && q.options!.isNotEmpty;
    final isClosed = _isClosedAssessmentType(q.type);
    if (isClosed && !hasOptions) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'assessment: закрытый тип "${q.type.wire}" без вариантов',
      ));
    }
    if (isClosed && hasOptions && q.options!.length > 4) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.fail,
        nodeId: q.nodeId,
        message: 'assessment: вариантов ${q.options!.length}, ожидалось 2..4',
      ));
    }
    if (!isClosed && hasOptions) {
      out.add(CheckResult(
        code: CheckCode.questionWellformed,
        severity: Severity.warn,
        nodeId: q.nodeId,
        message: 'assessment: открытый тип "${q.type.wire}" содержит варианты',
      ));
    }
  }

  return out;
}

/// Типы вопросов, где ответ выбирается из вариантов.
bool _isClosedAssessmentType(QuestionType type) =>
    type == QuestionType.recognition || type == QuestionType.recall;

/// Все вопросы ссылаются на узлы, которые есть в дереве.
List<CheckResult> checkQuestionNodesKnown(
  List<KnowledgeNode> nodes, {
  required List<DiagnosticQuestion> diagnostic,
  required List<AssessmentQuestion> assessment,
}) {
  final known = {for (final n in nodes) n.id};
  final out = <CheckResult>[];
  for (final q in diagnostic) {
    if (!known.contains(q.nodeId)) {
      out.add(CheckResult(
        code: CheckCode.questionNodeKnown,
        severity: Severity.fail,
        message: 'diagnostic: вопрос ссылается на неизвестный узел '
            '"${q.nodeId}"',
      ));
    }
  }
  for (final q in assessment) {
    if (!known.contains(q.nodeId)) {
      out.add(CheckResult(
        code: CheckCode.questionNodeKnown,
        severity: Severity.fail,
        message: 'assessment: вопрос "${q.id}" ссылается на неизвестный узел '
            '"${q.nodeId}"',
      ));
    }
  }
  return out;
}

// ─── Проверки покрытия ──────────────────────────────────────────────────────
/// Хотя бы один узел учебного плана привязан к узлу дерева.
List<CheckResult> checkGoalCoverage(QualityInput input) {
  if (input.curriculumNodeIds.isEmpty) {
    return const [
      CheckResult(
        code: CheckCode.goalCoverage,
        severity: Severity.fail,
        message: 'Учебный план пуст: ни один узел не выбран под цель',
      ),
    ];
  }
  final ids = {for (final n in input.nodes) n.id};
  final unknown = [
    for (final id in input.curriculumNodeIds)
      if (!ids.contains(id)) id,
  ];
  if (unknown.isEmpty) return const [];
  final sorted = unknown.toList()..sort();
  return [
    CheckResult(
      code: CheckCode.goalCoverage,
      severity: Severity.fail,
      message: 'Учебный план ссылается на ${sorted.length} узла(ев), '
          'которых нет в дереве: ${sorted.join(', ')}',
    ),
  ];
}

/// Доля узлов с контентом: не ниже 80% (иначе — warn с точным процентом).
List<CheckResult> checkContentCoverage(
  List<KnowledgeNode> nodes, {
  double minRatio = 0.8,
}) {
  if (nodes.isEmpty) {
    return const [
      CheckResult(
        code: CheckCode.contentCoverage,
        severity: Severity.fail,
        message: 'Дерево пусто: нечего покрывать контентом',
      ),
    ];
  }
  final loaded = [for (final n in nodes) if (n.contentLoaded) n.id];
  final ratio = loaded.length / nodes.length;
  if (ratio >= minRatio) {
    return [
      CheckResult(
        code: CheckCode.contentCoverage,
        severity: Severity.info,
        message: 'Контент есть у ${loaded.length} из ${nodes.length} узлов '
            '(${(ratio * 100).toStringAsFixed(0)}%)',
      ),
    ];
  }
  return [
    CheckResult(
      code: CheckCode.contentCoverage,
      severity: Severity.warn,
      message: 'Контент есть только у ${loaded.length} из ${nodes.length} '
          'узлов (${(ratio * 100).toStringAsFixed(0)}%, минимум '
          '${(minRatio * 100).toStringAsFixed(0)}%)',
    ),
  ];
}

// ─── Точка входа ─────────────────────────────────────────────────────────────

/// Прогоняет все проверки и возвращает стабильно отсортированный список.
///
/// Проверки структурного дерева идут по фиксированному порядку [treeChecks],
/// затем активность, затем покрытие — и всё это в конце сортируется по коду,
/// так что порядок не зависит от порядка добавления проверок.
List<CheckResult> runChecks(QualityInput input) {
  final nodes = input.nodes;
  final out = <CheckResult>[
    ...checkOneLinerLength(nodes),
    ...checkSingleRoot(nodes),
    ...checkParentsExist(nodes),
    ...checkNoCycles(nodes),
    ...checkLevelConsistency(nodes),
    ...checkNoEmptyContent(nodes),
    ...checkNoDuplicateLabels(nodes),
    ...checkJargonFree(nodes, input.targetLevel),
    ...checkRecallWellformed(input.recallSteps),
    ...checkApplyWellformed(input.applySteps),
    ...checkNoDuplicateActivity(input.activities),
    ...checkQuestionsWellformed(
      diagnostic: input.diagnosticQuestions,
      assessment: input.assessmentQuestions,
    ),
    ...checkQuestionNodesKnown(
      nodes,
      diagnostic: input.diagnosticQuestions,
      assessment: input.assessmentQuestions,
    ),
    ...checkGoalCoverage(input),
    ...checkContentCoverage(nodes),
  ];
  return _sorted(out);
}

/// Сводка по проверкам: количество нарушений каждой серьёзности.
class CheckSummary {
  final int info;
  final int warn;
  final int fail;

  const CheckSummary({required this.info, required this.warn, required this.fail});

  int get total => info + warn + fail;
  bool get hasFailures => fail > 0;

  /// Есть ли нарушения, требующие внимания (warn или fail).
  bool get hasProblems => warn > 0 || fail > 0;

  Map<String, dynamic> toJson() => {
        'info': info,
        'warn': warn,
        'fail': fail,
        'total': total,
      };

  @override
  String toString() => 'checks: $total (fail=$fail, warn=$warn, info=$info)';
}

/// Считает сводку по списку результатов.
CheckSummary summarize(List<CheckResult> results) {
  var info = 0, warn = 0, fail = 0;
  for (final r in results) {
    switch (r.severity) {
      case Severity.info:
        info++;
      case Severity.warn:
        warn++;
      case Severity.fail:
        fail++;
    }
  }
  return CheckSummary(info: info, warn: warn, fail: fail);
}
