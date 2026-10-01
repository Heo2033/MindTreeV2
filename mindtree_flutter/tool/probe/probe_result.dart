// DTO результата probe: всё, что нужно для отчёта, в одном месте.
//
// Отчёт строится ТОЛЬКО из этого объекта. Сюда намеренно не попадают
// wall-clock тайминги, абсолютные timestamp'ы и случайные идентификаторы
// сессий — иначе два прогона с одинаковым входом дали бы разные файлы.
// Всё недетерминированное живёт в `RunStats` и попадает только в
// `run-stats.json`.

import 'package:mindtree_flutter/data/llm/telemetry.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/engines/mastery_engine.dart';
import 'package:mindtree_flutter/domain/models/activity.dart';
import 'package:mindtree_flutter/domain/models/assessment.dart';
import 'package:mindtree_flutter/domain/models/curriculum.dart';
// Из dtos берём только `MasteryEvaluation`: там дублируются
// `DiagnosticQuestion`/`DiagnosticResult`, которые нужны в версии из
// diagnostic_engine — именно её возвращает `DiagnosticEngine.generate`.
import 'package:mindtree_flutter/domain/models/dtos.dart'
    hide DiagnosticQuestion, DiagnosticResult;
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/learning.dart';

import 'quality_checks.dart';

/// Параметры прогона, попадающие в отчёт.
class ProbeParams {
  /// Запросы пользователя (может быть несколько — probe гоняет каждый).
  final List<String> queries;
  final String goal;
  final int level;
  final int minutes;

  /// Признак mock-прогона: в отчёте фиксируется явно, чтобы отличать
  /// детерминированный прогон от реального LLM.
  final bool mock;
  final bool contentSkipped;
  final bool sessionSkipped;

  const ProbeParams({
    required this.queries,
    required this.goal,
    required this.level,
    required this.minutes,
    this.mock = false,
    this.contentSkipped = false,
    this.sessionSkipped = false,
  });

  Map<String, dynamic> toJson() => {
        'queries': queries,
        'goal': goal,
        'level': level,
        'minutes': minutes,
        'mock': mock,
        'contentSkipped': contentSkipped,
        'sessionSkipped': sessionSkipped,
      };
}

/// Ответ пользователя на один шаг активности — для раздела «ответы».
class AnswerRecord {
  final String nodeId;
  final String nodeLabel;
  final String stepType;
  final String stepTitle;
  final String userAnswer;

  /// `null` для открытых шагов, где движок не возвращает вердикт.
  final bool? correct;
  final String feedback;
  final String misconception;

  const AnswerRecord({
    required this.nodeId,
    required this.nodeLabel,
    required this.stepType,
    required this.stepTitle,
    required this.userAnswer,
    this.correct,
    required this.feedback,
    this.misconception = '',
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'nodeLabel': nodeLabel,
        'stepType': stepType,
        'stepTitle': stepTitle,
        'userAnswer': userAnswer,
        if (correct != null) 'correct': correct,
        'feedback': feedback,
        if (misconception.isNotEmpty) 'misconception': misconception,
      };
}

/// Один прогон по одному запросу.
class QueryOutcome {
  /// Стабильный id темы: `probe_<index>_<hash8(query)>`.
  final String topicId;
  final String query;
  final String rootId;

  /// Полное дерево в стабильном порядке обхода.
  final List<KnowledgeNode> nodes;

  final Curriculum? curriculum;
  final List<String> alreadyKnown;

  final List<DiagnosticQuestion> diagnosticQuestions;
  final List<DiagnosticAnswer> diagnosticAnswers;
  final DiagnosticResult? diagnosticResult;

  final LearningSession? session;
  final LearningActivity? activity;
  final List<AnswerRecord> answers;

  final Assessment? assessment;
  final List<AssessmentQuestion> assessmentQuestions;

  /// Мастерство до учебной сессии (для раздела «до/после»).
  final MasteryEvaluation? masteryBefore;

  /// Мастерство после сессии.
  final MasteryEvaluation? masteryAfter;

  /// Детализация мастерства по 4 измерениям из `MasteryResult`.
  final MasteryResult? masteryConcepts;

  final List<LearningMilestone> milestones;

  /// Заметки о ходе прогона: какие шаги пропущены и почему.
  final List<String> notes;

  const QueryOutcome({
    required this.topicId,
    required this.query,
    required this.rootId,
    required this.nodes,
    this.curriculum,
    this.alreadyKnown = const [],
    this.diagnosticQuestions = const [],
    this.diagnosticAnswers = const [],
    this.diagnosticResult,
    this.session,
    this.activity,
    this.answers = const [],
    this.assessment,
    this.assessmentQuestions = const [],
    this.masteryBefore,
    this.masteryAfter,
    this.masteryConcepts,
    this.milestones = const [],
    this.notes = const [],
  });
}

/// Расход одной операции LLM: сколько раз звали и сколько токенов сожгли.
///
/// Считается из телеметрии scheduler (`OperationTelemetry`), которая уже
/// различает операции — проба лишь агрегирует её по `operation`.
class OpUsage {
  final int calls;

  /// Сумма `retryCount` по вызовам операции: 0 — ни один вызов не повторялся.
  final int retries;

  final int inputTokens;
  final int outputTokens;

  /// Токены рассуждений — часть [outputTokens].
  ///
  /// Отделены от «полезного» вывода, потому что именно они обычно съедают
  /// бюджет: на живом прогоне reasoning составлял ~99% вывода операции
  /// `oneline-rewrite`, чей реальный ответ — одна короткая фраза.
  final int reasoningTokens;

  /// Сумма `usage.cost_rub` от провайдера; `null`, если он её не отдавал.
  ///
  /// Это авторитетная стоимость в рублях: считать её по каталогу в probe
  /// нельзя — тарифы меняются, а у части провайдеров есть ступенчатые тарифы
  /// по длине промпта.
  final double? costRub;

  /// Модели, реально отработавшие на этой операции (отсортированы).
  ///
  /// Не пусто даже при провале: scheduler пишет телеметрию и на неуспешной
  /// попытке с замерами, поэтому видно, какой вендор упал.
  final List<String> models;

  const OpUsage({
    required this.calls,
    this.retries = 0,
    required this.inputTokens,
    required this.outputTokens,
    this.reasoningTokens = 0,
    this.costRub,
    this.models = const [],
  });

  OpUsage merge(OperationTelemetry op) {
    final hasRub = costRub != null || op.costRub != null;
    return OpUsage(
      calls: calls + 1,
      retries: retries + op.retryCount,
      inputTokens: inputTokens + op.inputTokens,
      outputTokens: outputTokens + op.outputTokens,
      reasoningTokens: reasoningTokens + op.reasoningTokens,
      costRub: hasRub ? (costRub ?? 0) + (op.costRub ?? 0) : null,
      models: {...models, op.model}.toList()..sort(),
    );
  }

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'retries': retries,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'reasoningTokens': reasoningTokens,
        if (costRub != null) 'costRub': costRub,
        'models': models,
      };
}

/// Агрегаты по LLM: детерминированные счётчики (без времени).
class LlmStats {
  /// Сколько раз вызывался scheduler за прогон.
  final int calls;

  /// Разбивка по видам промптов, ключи отсортированы.
  final Map<String, int> callsByKind;

  /// Разбивка токенов и ретраев по видам промптов, ключи отсортированы.
  ///
  /// Раньше probe отдавал только агрегат, и стоимость прогона приходилось
  /// оценивать «на глаз», распределяя токены по операциям — это давало
  /// неверные числа. Теперь каждый вид промпта виден со своей долей.
  final Map<String, OpUsage> usageByKind;

  /// Все модели, отработавшие в прогоне (отсортированы).
  final List<String> modelsUsed;

  final int inputTokens;
  final int outputTokens;

  /// Сумма reasoning-токенов по прогону (часть [outputTokens]).
  final int reasoningTokens;

  /// Сумма `usage.cost_rub` от провайдера; `null`, если он её не отдавал.
  final double? costRub;

  const LlmStats({
    required this.calls,
    required this.callsByKind,
    this.usageByKind = const {},
    this.modelsUsed = const [],
    required this.inputTokens,
    required this.outputTokens,
    this.reasoningTokens = 0,
    this.costRub,
  });

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'callsByKind': callsByKind,
        'usageByKind': {for (final e in usageByKind.entries) e.key: e.value.toJson()},
        'modelsUsed': modelsUsed,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'reasoningTokens': reasoningTokens,
        if (costRub != null) 'costRub': costRub,
      };
}

/// Недетерминированные данные прогона: попадают ТОЛЬКО в `run-stats.json`.
///
/// Держим отдельно от [ProbeResult], чтобы случайно не внести их в
/// сравниваемый отчёт.
class RunStats {
  final int totalCalls;
  final int failures;
  final List<String> failuresDetail;
  final int retries;

  /// Сколько попыток транспорта реально было сделано (включая проваленные).
  final int transportAttempts;

  /// Сколько попыток транспорта завершилось ошибкой (до ретрая/фолбэка).
  final int failedAttempts;

  /// Длительности в миллисекундах — зависят от машины и сети.
  final int wallClockMs;
  final List<int> callDurationsMs;

  const RunStats({
    required this.totalCalls,
    this.failures = 0,
    this.failuresDetail = const [],
    this.retries = 0,
    this.transportAttempts = 0,
    this.failedAttempts = 0,
    this.wallClockMs = 0,
    this.callDurationsMs = const [],
  });

  Map<String, dynamic> toJson() => {
        'totalCalls': totalCalls,
        'failures': failures,
        'failuresDetail': failuresDetail,
        'retries': retries,
        'transportAttempts': transportAttempts,
        'failedAttempts': failedAttempts,
        'wallClockMs': wallClockMs,
        'callDurationsMs': callDurationsMs,
      };
}

/// Полный результат probe.
class ProbeResult {
  final ProbeParams params;
  final List<QueryOutcome> outcomes;
  final List<CheckResult> checks;
  final LlmStats llm;

  const ProbeResult({
    required this.params,
    required this.outcomes,
    required this.checks,
    required this.llm,
  });

  /// Сводка по quality-проверкам.
  CheckSummary get summary => summarize(checks);

  /// Список шагов recall из активности — для `recall_wellformed`.
  List<ActivityStep> get recallSteps => [
        for (final o in outcomes)
          for (final s in o.activity?.steps ?? const <ActivityStep>[])
            if (s.type == 'recall') s,
      ];

  /// Список шагов apply из активности — для `apply_wellformed`.
  List<ActivityStep> get applySteps => [
        for (final o in outcomes)
          for (final s in o.activity?.steps ?? const <ActivityStep>[])
            if (s.type == 'apply') s,
      ];
}
