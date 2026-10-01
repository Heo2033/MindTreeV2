// Pipeline прогона probe через настоящие доменные движки.
//
// Probe НЕ переписывает логику движков — он собирает те же экземпляры, что и
// приложение (`buildEngines`), и проходит по тем же вызовам:
// дерево → контент → curriculum → diagnostic → session/activity →
// assessment → mastery → milestones.
//
// ДЕТЕРМИНИЗМ. Ничего в этом файле не использует `DateTime.now()`,
// `Random` или счётчики для содержимого отчёта:
// - `topicId` выводится из индекса запроса и хэша текста;
// - `createdAt` фиксируется константой;
// - ответы пользователя — детерминированная функция от id узла и шага;
// - порядок обхода задаётся `sortNodesForReport`.
// Случайные id остаются только в БД, отчёт их не показывает.

import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/mastery_engine.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/activity.dart';
import 'package:mindtree_flutter/domain/models/assessment.dart';
import 'package:mindtree_flutter/domain/models/curriculum.dart';
// Из dtos нужен только `MasteryEvaluation`: `DiagnosticQuestion` и
// `DiagnosticResult` там дублируют версии из diagnostic_engine, а движок
// возвращает именно engine-версии.
import 'package:mindtree_flutter/domain/models/dtos.dart'
    hide DiagnosticQuestion, DiagnosticResult;
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/learning.dart';
import 'package:mindtree_flutter/domain/models/mastery.dart';
import 'package:mindtree_flutter/domain/models/primitives.dart';
import 'package:mindtree_flutter/domain/models/topic.dart';

import 'probe_result.dart';
import 'quality_checks.dart';
import 'tree_mapper.dart';

/// Фиксированная дата создания темы: настоящее время сделало бы отчёт
/// недетерминированным.
const String _fixedCreatedAt = '1970-01-01T00:00:00.000Z';

/// Опции одного прогона.
class PipelineOptions {
  final List<String> queries;
  final String goal;
  final int level;
  final int minutes;

  /// Пропустить генерацию контента (`--skip-content`).
  final bool skipContent;

  /// Пропустить учебную сессию и всё, что после неё
  /// (`--skip-session`).
  final bool skipSession;

  /// Ограничить число узлов дерева (`--max-nodes`). `0` — без лимита.
  final int maxNodes;

  /// Колбэк прогресса для `--verbose`.
  final void Function(String message)? onProgress;

  /// Помечает прогон как детерминированный (fake LLM, без сети).
  /// Попадает в `params.mock` отчёта.
  final bool mock;

  const PipelineOptions({
    required this.queries,
    required this.goal,
    required this.level,
    required this.minutes,
    this.skipContent = false,
    this.skipSession = false,
    this.maxNodes = 0,
    this.onProgress,
    this.mock = false,
  });
}

/// Детерминированный id темы: индекс + хэш текста запроса.
///
/// Индекс входит в id, чтобы одинаковые запросы в одном прогоне давали
/// разные темы (иначе они перетирали бы друг друга в БД).
String probeTopicId(int index, String query) =>
    'probe_${index}_${_hash8(query)}';

/// 8-hex хэш строки (FNV-1a). Детерминирован на всех платформах.
String _hash8(String s) {
  var hash = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    // 32-битное переполнение: маска эквивалентна модулю 2^32.
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Чётный байт хэша — для чередования «верный/неверный» ответ.
bool _hashParity(String s) => _hash8(s).codeUnitAt(7) % 2 == 0;

/// Мастерство-уровень по числовому уровню из CLI.
MasteryLevel _masteryLevel(int level) {
  if (level <= 1) return MasteryLevel.basicUnderstanding;
  if (level == 2) return MasteryLevel.solidUnderstanding;
  if (level == 3) return MasteryLevel.practicalApplication;
  if (level == 4) return MasteryLevel.advanced;
  return MasteryLevel.expert;
}

/// Уровень знаний строкой, как его ждёт `KnowledgeGraphEngine.generate`.
String _levelLabel(int level) {
  if (level <= 1) return 'beginner';
  if (level == 2) return 'intermediate';
  if (level == 3) return 'advanced';
  return 'expert';
}

/// Цель обучения: берём raw-строку как есть, движок сам разбирает неизвестное.
String _goalRaw(String goal) => goal.trim().isEmpty ? 'overview' : goal.trim();

// ─── Детерминированные ответы пользователя ───────────────────────────────────

/// Ответ пользователя на один шаг активности.
typedef _PlannedAnswer = ({String text, bool expectCorrect});

/// Recall: чередуем верный и неверный ответ по чётности хэша id узла, чтобы
/// в отчёте были обе ветки. Apply: фиксированный текст — он уходит в
/// mastery-движок как `userAnswer`.
_PlannedAnswer _planAnswer(String nodeId, ActivityStep step) {
  if (step.type == 'recall') {
    final options = step.options ?? const <String>[];
    if (options.isEmpty) return (text: '0', expectCorrect: true);
    final correct = step.correctIndex ?? 0;
    final wantWrong = _hashParity(nodeId);
    final index = wantWrong
        ? (correct + 1) % options.length
        : correct.clamp(0, options.length - 1);
    return (text: '$index', expectCorrect: !wantWrong);
  }
  return (
    text: 'Попробую объяснить это своими словами и привести конкретный пример, '
        'где понятие действительно применяется на практике.',
    expectCorrect: true,
  );
}

/// Ответ на диагностический вопрос: чётность хэша id решает, верный он или нет.
int _planDiagnosticIndex(String questionId, DiagnosticQuestionView q) {
  if (q.options.isEmpty) return 0;
  return _hashParity(questionId)
      ? q.correctIndex
      : (q.correctIndex + 1) % q.options.length;
}

/// Минимальный срез диагностического вопроса, нужный для планирования ответа.
///
/// Отдельный typedef, чтобы не тащить в отчёт лишние поля движка.
typedef DiagnosticQuestionView = ({
  int correctIndex,
  List<String> options,
});

/// Извлекает мисконцепцию из текста фидбека.
///
/// У `ActivityStep` нет отдельного поля `misconception`: движок кодирует её в
/// тексте обратной связи. Probe фиксирует наличие и сам текст, чтобы раздел
/// «мисконцепции» не был пустым из-за формы данных.
String _misconceptionFrom(String? feedback) {
  if (feedback == null || feedback.isEmpty) return '';
  final lowered = feedback.toLowerCase();
  const markers = [
    'не хватает',
    'не показывает',
    'частично',
    'неверно',
    'ошиб',
    'путает',
  ];
  return markers.any(lowered.contains) ? feedback.trim() : '';
}

/// Обрезает дерево по лимиту узлов, сохраняя корень и целостность уровней.
({List<KnowledgeNode> kept, int dropped}) _limitNodes(
  List<KnowledgeNode> nodes,
  int maxNodes,
) {
  if (maxNodes <= 0 || nodes.length <= maxNodes) {
    return (kept: nodes, dropped: 0);
  }
  final kept = <KnowledgeNode>[];
  for (final level in ({for (final n in nodes) n.level}.toList()..sort())) {
    for (final n in nodes.where((n) => n.level == level)) {
      if (kept.length >= maxNodes) break;
      // Сироту не берём: её родитель не попал в выборку.
      if (n.parentId != null && !kept.any((k) => k.id == n.parentId)) continue;
      kept.add(n);
    }
  }
  return (kept: kept, dropped: nodes.length - kept.length);
}

/// Прогоняет все запросы и собирает [ProbeResult].
///
/// Движки берутся из [buildEngines], поэтому probe использует ровно ту же
/// сборку, что и приложение, но без Flutter и Riverpod.
Future<ProbeResult> runPipeline(
  MindtreeEngines engines,
  PipelineOptions opts,
) async {
  final outcomes = <QueryOutcome>[];

  for (var i = 0; i < opts.queries.length; i++) {
    final query = opts.queries[i];
    final topicId = probeTopicId(i, query);
    final notes = <String>[];
    final progress = opts.onProgress ?? (String _) {};
    progress('[$i] «$query» → тема $topicId');

    final topic = await engines.repo.createTopic(Topic(
      id: topicId,
      name: query,
      goal: LearningGoal.fromString(_goalRaw(opts.goal)),
      targetLevel: _masteryLevel(opts.level),
      timeBudgetMinutes: opts.minutes,
      createdAt: _fixedCreatedAt,
    ));

    // 1. Структура дерева. `generate` возвращает RAW id — скоупим их сами,
    //    ровно как `ui_stores.dart` перед сохранением.
    final build = await engines.graph.generate(
      query,
      goal: _goalRaw(opts.goal),
      level: _levelLabel(opts.level),
      timeBudgetMinutes: opts.minutes,
    );
    for (final w in build.warnings) {
      notes.add('Дерево: $w');
    }

    final limited = _limitNodes(draftsToNodes(
      scopeNodeIds(build.nodes, topicId),
      topic.id,
    ), opts.maxNodes);
    if (limited.dropped > 0) {
      notes.add('Дерево обрезано до ${limited.kept.length} узлов '
          '(--max-nodes=${opts.maxNodes}, отброшено ${limited.dropped})');
    }
    await engines.repo.insertNodes(limited.kept);
    final rootId = limited.kept
        .firstWhere((n) => n.parentId == null, orElse: () => limited.kept.first)
        .id;

    // 2. Контент узлов, в фиксированном порядке обхода.
    if (opts.skipContent) {
      notes.add('Контент пропущен (--skip-content)');
    } else {
      final targets = sortNodesForReport(limited.kept);
      // Контент узлов независим — генерируем пулом воркеров, как это делает
      // приложение (`_fillContentBackground`). Сортировка в отчёте всё равно
      // детерминированная (`sortNodesForReport`), поэтому порядок завершения
      // вызовов на report.json не влияет.
      // Ширина пула держится на уровне `SchedulerConfig.maxConcurrency`
      // (по умолчанию 6), иначе пул упирается в лимит планировщика и часть
      // параллелизма теряется.
      const concurrency = 6;
      var next = 0;
      int takeNext() => next < targets.length ? next++ : -1;
      await Future.wait([
        for (var w = 0; w < concurrency; w++)
          () async {
            while (true) {
              final i = takeNext();
              if (i < 0) return;
              final node = targets[i];
              progress('[$i] контент: ${node.label}');
              try {
                await engines.graph.generateNodeContentFromDb(topic.id, node.id);
              } catch (err) {
                notes.add('Контент для «${node.label}» не получен: $err');
              }
            }
          }(),
      ]);
    }
    final loaded = sortNodesForReport(await engines.repo.listNodes(topic.id));

    // 3. Мастерство ДО сессии — база для сравнения «до/после».
    MasteryEvaluation? masteryBefore;
    try {
      masteryBefore = await engines.mastery.evaluate(
        topic.id,
        const <MasteryItem>[],
        _masteryLevel(opts.level).raw,
      );
    } catch (err) {
      notes.add('Мастерство «до» недоступно: $err');
    }

    // 4. Диагностика: стартовый уровень по теме.
    var diagnosticQuestions = const <DiagnosticQuestion>[];
    var diagnosticAnswers = const <DiagnosticAnswer>[];
    DiagnosticResult? diagnosticResult;
    try {
      diagnosticQuestions = await engines.diagnostic.generate(topic.id);
      diagnosticAnswers = [
        for (final q in diagnosticQuestions)
          DiagnosticAnswer(
            questionId: q.id,
            nodeId: q.nodeId,
            selectedIndex: _planDiagnosticIndex(
              q.id,
              (correctIndex: q.correctIndex, options: q.options),
            ),
            correctIndex: q.correctIndex,
          ),
      ];
      if (diagnosticAnswers.isEmpty) {
        notes.add('Диагностика не вернула вопросов');
      } else {
        diagnosticResult = await engines.diagnostic.evaluate(
          topic.id,
          diagnosticAnswers,
        );
      }
    } catch (err) {
      notes.add('Диагностика не выполнена: $err');
    }

    // 5. Curriculum — нужен и для сессии, и для `goal_coverage`.
    var curriculum = const Curriculum(sessionId: '');
    var alreadyKnown = const <String>[];
    LearningSession? session;
    LearningActivity? activity;
    final answers = <AnswerRecord>[];
    Assessment? assessment;
    var assessmentQuestions = const <AssessmentQuestion>[];
    MasteryEvaluation? masteryAfter;

    try {
      final plan = await engines.curriculum.generate(CurriculumRequest(
        topicId: topic.id,
        topicName: query,
        goal: topic.goal.raw,
        targetLevel: topic.targetLevel.raw,
        timeBudgetMinutes: opts.minutes,
        nodes: loaded,
        knownNodeIds: {
          for (final id in diagnosticResult?.knownConcepts ?? const <String>[])
            id,
        },
      ));
      curriculum = plan.curriculum;
      alreadyKnown = plan.alreadyKnown;
    } catch (err) {
      notes.add('Curriculum не построен: $err');
    }

    if (opts.skipSession) {
      notes.add('Учебная сессия пропущена (--skip-session)');
    } else {
      try {
        session = await engines.session.create(CreateSessionInput(
              topicId: topic.id,
              goal: topic.goal.raw,
              timeBudgetMinutes: opts.minutes,
            ));
        curriculum = session.curriculum;

        // Активность — по текущему пункту плана (его выбирает движок).
        // `ensureActivity` бросает исключение, если пункта нет, поэтому
        // отдельной проверки на null здесь не требуется.
        try {
          activity = await engines.activity.ensureActivity(session.id);
          progress('[$i] активность: ${activity.nodeLabel}');
          for (var stepIndex = 0;
              stepIndex < activity.steps.length;
              stepIndex++) {
            final step = activity.steps[stepIndex];
            if (step.isAnswered) continue;
            final planned = _planAnswer(activity.nodeId, step);
            final updated = await engines.activity.answer(
              session.id,
              stepIndex,
              planned.text,
            );
            final answered = updated.steps[stepIndex];
            answers.add(AnswerRecord(
              nodeId: updated.nodeId,
              nodeLabel: updated.nodeLabel,
              stepType: step.type,
              stepTitle: step.title,
              userAnswer: answered.userAnswer ?? planned.text,
              correct: answered.correct,
              feedback: answered.feedback ?? '',
              misconception: _misconceptionFrom(answered.feedback),
            ));
          }
        } catch (err) {
          notes.add('Активность не пройдена: $err');
        }

        // Итоговая оценка по фактическим ответам.
        final assessItems = [
          for (final a in answers)
            AssessmentItem(
              nodeId: a.nodeId,
              label: a.nodeLabel,
              oneLiner: a.stepTitle,
              details: a.feedback,
            ),
        ];
        if (assessItems.isEmpty) {
          notes.add('Нет ответов: итоговая оценка не сформирована');
        } else {
          assessment = await engines.assessment.generate(
            session.id,
            topic.id,
            assessItems,
          );
          assessmentQuestions = assessment.questions;
          // Время ответа недетерминированно, но в отчёт не попадает, поэтому
          // фиксируем 0: report.json остаётся побайтово сравнимым.
          for (var qi = 0; qi < assessment.questions.length; qi++) {
            final q = assessment.questions[qi];
            await engines.assessment.recordAttempt(
              assessment.id,
              q.id,
              qi < answers.length ? answers[qi].userAnswer : '',
              qi < answers.length && answers[qi].correct == true,
              0,
              feedback: qi < answers.length ? answers[qi].feedback : null,
            );
          }
          final correctCount = answers.where((a) => a.correct == true).length;
          await engines.assessment.finalize(
            assessment.id,
            assessment.questions.isEmpty
                ? 0
                : correctCount / assessment.questions.length,
          );
          assessment = await engines.assessment.getById(assessment.id) ??
              assessment;
        }

        // Мастерство ПОСЛЕ сессии по фактическим ответам.
        masteryAfter = await engines.mastery.evaluate(
          topic.id,
          [
            for (final a in answers)
              MasteryItem(
                nodeId: a.nodeId,
                label: a.nodeLabel,
                type: a.stepType,
                userAnswer: a.userAnswer,
                correct: a.correct,
                rubric: a.feedback.isEmpty ? null : a.feedback,
              ),
          ],
          topic.targetLevel.raw,
        );
      } catch (err) {
        notes.add('Учебная сессия прервана: $err');
      }
    }

    // 6. Milestones — по journey темы.
    final milestones = <LearningMilestone>[];
    try {
      final journey = await engines.repo.getJourneyForTopic(topic.id);
      if (journey == null) {
        notes.add('Journey не найдена: milestones не построены');
      } else {
        // `MilestoneEngine.generate` САМ сохраняет milestones через
        // `repo.insertMilestones`. Повторный insert здесь давал
        // `UNIQUE constraint failed: learning_milestones.id`.
        final generated = await engines.milestones.generate(journey.id, topic.id);
        milestones.addAll(generated);
      }
    } catch (err) {
      notes.add('Milestones не построены: $err');
    }

    outcomes.add(QueryOutcome(
      topicId: topic.id,
      query: query,
      rootId: rootId,
      nodes: loaded,
      curriculum: curriculum,
      alreadyKnown: alreadyKnown,
      diagnosticQuestions: diagnosticQuestions,
      diagnosticAnswers: diagnosticAnswers,
      diagnosticResult: diagnosticResult,
      session: session,
      activity: activity,
      answers: answers,
      assessment: assessment,
      assessmentQuestions: assessmentQuestions,
      masteryBefore: masteryBefore,
      masteryAfter: masteryAfter,
      milestones: milestones,
      notes: notes,
    ));
  }

  // Quality-проверки — ОТДЕЛЬНО на каждый запрос.
  //
  // Проверки дерева по своей природе per-topic: один корень на ТЕМУ. Если
  // скормить `runChecks` сразу несколько тем, `single_root` видел 2 корня от
  // двух несвязанных деревьев и падал с ложным `fail`.
  final checks = <CheckResult>[];
  for (final o in outcomes) {
    checks.addAll(runChecks(QualityInput(
      nodes: o.nodes,
      targetLevel: opts.level,
      goal: opts.goal,
      recallSteps: [
        for (final s in o.activity?.steps ?? const <ActivityStep>[])
          if (s.type == 'recall') s,
      ],
      applySteps: [
        for (final s in o.activity?.steps ?? const <ActivityStep>[])
          if (s.type == 'apply') s,
      ],
      activities: [if (o.activity != null) o.activity!],
      diagnosticQuestions: o.diagnosticQuestions,
      assessmentQuestions: o.assessmentQuestions,
      curriculumNodeIds: [
        for (final i in o.curriculum?.items ?? const <CurriculumItem>[]) i.nodeId,
      ],
    )));
  }
  // Стабильный порядок: code, затем nodeId (иначе вывод «плавает»).
  checks.sort((a, b) {
    final byCode = a.code.compareTo(b.code);
    if (byCode != 0) return byCode;
    return (a.nodeId ?? '').compareTo(b.nodeId ?? '');
  });

  return ProbeResult(
    params: ProbeParams(
      queries: opts.queries,
      goal: opts.goal,
      level: opts.level,
      minutes: opts.minutes,
      contentSkipped: opts.skipContent,
      sessionSkipped: opts.skipSession,
      mock: opts.mock,
    ),
    outcomes: outcomes,
    checks: checks,
    llm: _llmStats(engines.scheduler),
  );
}

/// Детерминированные агрегаты по LLM из телеметрии scheduler.
///
/// Телеметрия уже различает операции (`OperationTelemetry.operation`), поэтому
/// разбивка по видам промптов и по токенам считается здесь, а не на стороне
/// клиента: агрегат без разбивки не позволяет честно посчитать стоимость
/// отдельных операций.
LlmStats _llmStats(TreeScheduler scheduler) {
  final telemetry = scheduler.telemetry;
  final aggregate = telemetry.aggregateStats();
  final ops = telemetry.recentOperations(limit: 10000);

  final byKind = <String, int>{};
  final usage = <String, OpUsage>{};
  final models = <String>{};
  for (final op in ops) {
    byKind.update(op.operation, (v) => v + 1, ifAbsent: () => 1);
    usage.update(
      op.operation,
      (v) => v.merge(op),
      ifAbsent: () => OpUsage(
        calls: 1,
        retries: op.retryCount,
        inputTokens: op.inputTokens,
        outputTokens: op.outputTokens,
        reasoningTokens: op.reasoningTokens,
        costRub: op.costRub,
        models: [op.model],
      ),
    );
    if (op.model.isNotEmpty) models.add(op.model);
  }

  final sortedKinds = <String, int>{
    for (final key in byKind.keys.toList()..sort()) key: byKind[key]!,
  };
  final sortedUsage = <String, OpUsage>{
    for (final key in usage.keys.toList()..sort()) key: usage[key]!,
  };
  return LlmStats(
    calls: aggregate.count,
    callsByKind: sortedKinds,
    usageByKind: sortedUsage,
    modelsUsed: models.toList()..sort(),
    inputTokens: aggregate.totalInput,
    outputTokens: aggregate.totalOutput,
    reasoningTokens: aggregate.totalReasoningTokens,
    costRub: aggregate.totalCostRub,
  );
}
