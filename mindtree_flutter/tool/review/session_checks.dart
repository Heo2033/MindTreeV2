// Детерминированные проверки качества ПРОЖИТОЙ УЧЕБНОЙ СЕССИИ.
//
// Файл намеренно НЕ зависит от БД, drift и UI: загрузчик (отдельный агент)
// читает сессию и заполняет плоские DTO ниже, а проверки работают только с
// ними. Так их можно прогонять из теста на готовом JSON, не поднимая SQLite.
//
// ДЕЙЕРМИНИЗМ. Ни «сейчас», ни случайности: все сравнения — по числам из
// данных. Порядок находок задаёт `sortedFindings` из `finding.dart`.

import 'finding.dart';

/// Стабильные коды проверок сессии. Значения — часть контракта отчёта.
abstract final class SessionCheckCode {
  /// Активность ссылается на узел, которого нет в плане/дереве.
  static const activityNodeUnknown = 'session_activity_node_unknown';

  /// В активности нет ни recall, ни apply шага — только лекция.
  static const stepMix = 'session_step_mix';

  /// У recall меньше 2 или больше 4 вариантов, либо `correctIndex` вне диапазона.
  static const recallOptions = 'session_recall_options';

  /// У apply нет инструкции или нет эталонного ответа.
  static const applyContract = 'session_apply_contract';

  /// На отвеченный шаг нет фидбека.
  static const feedbackMissing = 'session_feedback_missing';

  /// Ответ есть, а вердикт (`correct`) не выставлен.
  static const answerNotScored = 'session_answer_not_scored';

  /// apply-этал совпадает с инструкцией / пользователь «угадал» подряд.
  static const applyDegenerate = 'session_apply_degenerate';

  /// Время шагов расходится с бюджетом либо нулевое при длинных текстах.
  static const stepDuration = 'session_step_duration';

  /// Статус сессии не согласован с ответами и флагом завершения активностей.
  static const completion = 'session_completion';

  /// Мастерство выросло на узлах, которых не было ни в плане, ни в активностях.
  static const masteryDelta = 'session_mastery_delta';

  /// Мисконцепция зафиксирована, но отработки (follow-up) на её узле нет.
  static const misconceptionWithoutRemediation =
      'session_misconception_without_remediation';

  /// У вопроса нечем оценить ответ: у закрытого — нечем объяснить правильный
  /// вариант, у открытого — нет рубрики. Неразрешимый правильный вариант сюда
  /// НЕ попадает: это отдельная находка [questionAnswerUnresolved].
  static const questionShallow = 'session_question_shallow';

  /// Доля повторов одного типа шага подряд слишком велика.
  static const progression = 'session_progression';

  /// `correctAnswer` не сопоставился ни с одним вариантом: правильный ответ
  /// неизвестен, поэтому проверить фидбек и оценку нечем.
  ///
  /// Резолв индекса/текста общий с движком (`lib/domain/lib/option_matching.dart`),
  /// так что сюда попадают только действительно битые данные.
  static const questionAnswerUnresolved = 'session_question_answer_unresolved';

  /// Балл assessment не сходится с долей верных попыток.
  static const scoreMismatch = 'session_score_mismatch';

  /// Вердикт противоречит ответу: ученик выбрал правильный вариант (по контракту
  /// — тем же индексом, что и `correctAnswer`; для старых записей — дословно
  /// текстом варианта), а в БД `correct = false`.
  ///
  /// Такой ответ портит mastery и мисконцепции — это уже не «тонкий материал»,
  /// а испорченный учебный след.
  static const verdictContradictsAnswer = 'session_verdict_contradicts_answer';
}

/// Допуск расхождения между `assessments.score` и долей верных попыток.
const double kScoreMismatchTolerance = 0.2;

// ─── Пороги ───────────────────────────────────────────────────────────────────

/// Шаг считается «отвеченным», если есть текст ответа ИЛИ выставлен вердикт.

/// Диапазон числа вариантов в recall-шаге (контракт активной сессии).
const int kMinRecallOptions = 2;
const int kMaxRecallOptions = 4;

/// Множители бюджета: >2x — warn, >5x — fail.
const double kSessionDurationWarnRatio = 2.0;
const double kSessionDurationFailRatio = 5.0;

/// Сколько ответов считается «сессия фактически пройдена».
const int kEnoughAnswersForCompletion = 3;

/// Длина текста шага (в символах), при которой нулевое время — подозрительно.
const int kLongStepTextChars = 400;

/// Подряд совпавших с эталом apply-ответов, начиная с которого это подозрительно.
const int kApplyEchoRun = 3;

/// Порог доли повторов одного типа шага подряд.
const double kMaxSameTypeRunRatio = 0.6;

/// Минимум шагов, чтобы доля повторов вообще что-то значила.
const int kMinStepsForProgression = 4;

/// Порог минимальной длины правильного варианта, который ищем в фидбеке.
const int kMinOptionLengthForExplain = 8;

/// Минимальная длина ответа/эталона для сравнения «дословно совпал».
const int kMinAnswerLengthForEcho = 12;

/// Слова, по которым фидбек считается пояснением даже без цитаты варианта.
const List<String> _kFeedbackAffirmations = <String>[
  'верно',
  'правильн',
  'ошибка',
  'неверно',
  'потому что',
  'так как',
  'следовательно',
  'поэтому',
];

/// Тип шага — как в `ActivityStep.type` (`lib/domain/models/activity.dart`).
const String kStepExplain = 'explain';
const String kStepExample = 'example';
const String kStepRecall = 'recall';
const String kStepApply = 'apply';

/// Статусы сессии (`SessionStatus` в `lib/domain/models/learning.dart`).
const String kStatusCompleted = 'completed';

// ─── DTO ─────────────────────────────────────────────────────────────────────

/// Шаг активности в виде плоских данных (без БД).
class SessionStepView {
  /// `explain` | `example` | `recall` | `apply`.
  final String type;
  final String title;
  final String? body;
  final String? instruction;
  final List<String>? options;
  final int? correctIndex;
  final String? bestAnswer;
  final String? userAnswer;
  final bool? correct;
  final String? feedback;

  /// Затраченное на шаг время, мс (0 — неизвестно).
  final int durationMs;

  const SessionStepView({
    required this.type,
    required this.title,
    this.body,
    this.instruction,
    this.options,
    this.correctIndex,
    this.bestAnswer,
    this.userAnswer,
    this.correct,
    this.feedback,
    this.durationMs = 0,
  });

  /// Ответ ученика непустой — по нему и судим, что шаг отвечен.
  bool get isAnswered =>
      (userAnswer != null && userAnswer!.trim().isNotEmpty) ||
      correct != null;

  /// Есть ли варианты ответа.
  bool get hasOptions => options != null && options!.isNotEmpty;

  /// Полный текст шага (для проверок времени и «этал = инструкция»).
  String get fullText => [
        body ?? '',
        instruction ?? '',
        bestAnswer ?? '',
      ].join('\n');
}

/// Активность одного узла в плоском виде.
class SessionActivityView {
  final String nodeId;
  final String nodeLabel;
  final List<SessionStepView> steps;

  /// Флаг завершения активности.
  ///
  /// Приоритет у явного `isComplete` из данных. Приложение его не пишет, поэтому
  /// при отсутствии флага загрузчик выводит завершение из отвеченности шагов.
  final bool isComplete;

  const SessionActivityView({
    required this.nodeId,
    this.nodeLabel = '',
    this.steps = const [],
    this.isComplete = false,
  });

  /// Шаги этого типа, в порядке следования.
  List<SessionStepView> stepsOfType(String type) =>
      [for (final s in steps) if (s.type == type) s];

  /// Есть ли хоть один шаг активной отработки (recall или apply).
  bool get hasActivePractice =>
      steps.any((s) => s.type == kStepRecall || s.type == kStepApply);
}

/// Вопрос диагностики/оценки в плоском виде.
class SessionQuestionView {
  final String nodeId;
  final String question;

  /// `QuestionType.wire` (`recall`, `application`, ...). Может быть пустым —
  /// тогда тип определяется по наличию вариантов.
  final String type;

  final List<String>? options;

  /// `AssessmentQuestion.correctAnswer`: у закрытого вопроса — строковый
  /// ИНДЕКС правильного варианта («"0".."3"»), у открытого — пуст по
  /// построению (эталон ему не нужен, см. [rubric]).
  final String? correctAnswer;
  final int? correctIndex;

  /// Рубрика открытого вопроса (`AssessmentQuestion.explanation`).
  ///
  /// По контракту оценки эталон открытому вопросу не нужен и не существует:
  /// `gradeOpenEnded(answer, rubric: explanation)` — единственный способ его
  /// проверить, а пустая рубрика засчитывает любой непустой ответ как верный.
  /// Поэтому рубрика лежит отдельным полем, а не подменяется `feedback`: у
  /// попытки свой текст фидбека.
  final String? rubric;

  final String? userAnswer;
  final bool? correct;
  final String? feedback;
  final int timeSpentMs;

  const SessionQuestionView({
    required this.nodeId,
    required this.question,
    this.type = '',
    this.options,
    this.correctAnswer,
    this.correctIndex,
    this.rubric,
    this.userAnswer,
    this.correct,
    this.feedback,
    this.timeSpentMs = 0,
  });

  bool get hasOptions => options != null && options!.isNotEmpty;

  /// Открытый вопрос — на него отвечают текстом, а не выбором.
  bool get isOpen => !hasOptions;

  /// Есть чем оценивать открытый ответ — непустая рубрика.
  bool get hasRubric => (rubric ?? '').trim().isNotEmpty;

  /// Тип, по которому решаем, «вопрос это или прикидка»: явный тип важнее
  /// структуры, но `recall`/`application` подставляются по форме, если загрузчик
  /// тип не отдал.
  String get effectiveType {
    if (type.trim().isNotEmpty) return type.trim();
    return hasOptions ? kStepRecall : kStepApply;
  }
}

/// Событие сессии: тип + длительность (остальное ревью не интересует).
class SessionEventView {
  /// `LearningEventType.wire`.
  final String type;
  final int durationMs;

  const SessionEventView({required this.type, this.durationMs = 0});
}

/// Одна оценка сессии: что записано в БД и что получилось по попыткам.
class AssessmentScoreView {
  /// `Assessments.type` (`quiz`, `diagnostic`, `final`).
  final String type;

  /// `Assessments.score` — как записала система; `null`, если не заполнен.
  final double? recordedScore;

  /// Сколько попыток есть по этой оценке.
  final int attempts;

  /// Из них верных.
  final int correctAttempts;

  const AssessmentScoreView({
    required this.type,
    this.recordedScore,
    this.attempts = 0,
    this.correctAttempts = 0,
  });

  /// Доля верных попыток; `null`, если попыток нет.
  double? get actualRatio => attempts == 0 ? null : correctAttempts / attempts;
}

/// Сессия целиком в плоском виде — единственный вход всех проверок.
class SessionView {
  final String topicName;
  final String goal;

  /// `MasteryLevel.raw` целевой аудитории.
  final String targetLevel;
  final int timeBudgetMinutes;

  /// ISO-время старта/финиша. Никакого «сейчас»: только то, что записано.
  final String startedAt;
  final String completedAt;

  /// `SessionStatus.name`.
  final String status;

  final List<SessionActivityView> activities;
  final List<SessionQuestionView> questions;
  final List<SessionEventView> events;

  /// `nodeId → средний балл` до сессии.
  final Map<String, double> masteryBefore;

  /// `nodeId → средний балл` после сессии.
  final Map<String, double> masteryAfter;

  /// Тексты мисконцепций (как их отдаёт движок).
  final List<String> misconceptions;

  /// Узлы учебного плана/curriculum.
  final List<String> plannedNodeIds;

  /// `nodeId → текст мисконцепции`: та же информация, но с узлом.
  ///
  /// Нужна для `session_misconception_without_remediation`: без узла нельзя
  /// понять, была ли отработка. Если загрузчик map не заполнил, проверка
  /// честно скажет, что данных не хватает (см. описание проверки).
  final Map<String, String> misconceptionsByNode;

  /// Оценки сессии: записанный балл против фактических попыток.
  ///
  /// Нужны для сверки `assessments.score` с долей верных ответов: без неё
  /// «ответ верный, но correct = false и score = 0» осталось бы незаметным.
  final List<AssessmentScoreView> assessments;

  const SessionView({
    required this.topicName,
    this.goal = 'overview',
    this.targetLevel = 'basic_understanding',
    this.timeBudgetMinutes = 0,
    this.startedAt = '',
    this.completedAt = '',
    this.status = 'active',
    this.activities = const [],
    this.questions = const [],
    this.events = const [],
    this.masteryBefore = const {},
    this.masteryAfter = const {},
    this.misconceptions = const [],
    this.plannedNodeIds = const [],
    this.misconceptionsByNode = const {},
    this.assessments = const [],
  });

  /// Все шаги сессии в едином порядке: активности по порядку, шаги внутри.
  List<SessionStepView> get allSteps => [
        for (final a in activities) ...a.steps,
      ];

  /// Отвеченные шаги.
  List<SessionStepView> get answeredSteps =>
      [for (final s in allSteps) if (s.isAnswered) s];

  /// Узлы, которые реально были в сессии (план ∪ активности ∪ вопросы).
  Set<String> get touchedNodeIds => <String>{
        ...plannedNodeIds,
        for (final a in activities) a.nodeId,
        for (final q in questions) q.nodeId,
      };
}

// ─── Хелперы ─────────────────────────────────────────────────────────────────

final RegExp _nonAlphaNum = RegExp('[^0-9a-zа-я]+');

String _squeeze(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_nonAlphaNum, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Нормализованный ответ: буквы/цифры и одиночные пробелы. Так «Ответ.  Да!»
/// и «ответ да» сравниваются как одно и то же — а именно совпадение целиком
/// и есть подозрение на копипаст.
String _squeezedAnswer(String? s) => _squeeze(s ?? '');

String _nonEmpty(String? s) => (s ?? '').trim();

/// Короткий список для сообщения: сортировка + ограничение длины.
String _idList(Iterable<String> ids, {int limit = 8}) {
  final sorted = [...ids]..sort();
  if (sorted.length <= limit) return sorted.join(', ');
  return '${sorted.take(limit).join(', ')} и ещё ${sorted.length - limit}';
}

/// Идентификатор шага для сообщений: «активность/шаг №N «Заголовок»».
String _stepLabel(SessionActivityView activity, int index, SessionStepView step) {
  final node = activity.nodeLabel.trim().isEmpty
      ? activity.nodeId
      : activity.nodeLabel.trim();
  return '$node / шаг №${index + 1} «${_nonEmpty(step.title)}»';
}

// ─── Проверки ────────────────────────────────────────────────────────────────

/// Активности ссылаются на узлы, которые есть в плане (или в дереве, если
/// плана нет — тогда известными считаются узлы из mastery/вопросов).
List<Finding> checkActivityNodesKnown(SessionView view) {
  if (view.activities.isEmpty) return const [];

  var known = <String>{...view.plannedNodeIds};
  if (known.isEmpty) {
    known = <String>{
      ...view.masteryBefore.keys,
      ...view.masteryAfter.keys,
      for (final q in view.questions) q.nodeId,
    };
  }
  if (known.isEmpty) {
    return const [
      Finding(
        code: SessionCheckCode.activityNodeUnknown,
        severity: FindingSeverity.info,
        message: 'Нет ни учебного плана, ни mastery/вопросов по узлам — '
            'проверить, откуда взялись активности, нечем',
      ),
    ];
  }

  return [
    for (final a in view.activities)
      if (!known.contains(a.nodeId))
        Finding(
          code: SessionCheckCode.activityNodeUnknown,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'Активность «${_nonEmpty(a.nodeLabel)}» ссылается на узел '
              '«${a.nodeId}», которого нет ни в плане, ни в mastery, ни среди '
              'вопросов (известно ${known.length} узлов)',
          data: {'knownCount': known.length},
        ),
  ];
}

/// В активности есть хотя бы recall или apply — иначе это лекция, а не
/// активная учебная сессия.
List<Finding> checkActivityStepMix(SessionView view) => [
      for (final a in view.activities)
        if (!a.hasActivePractice)
          Finding(
            code: SessionCheckCode.stepMix,
            severity: FindingSeverity.warn,
            nodeId: a.nodeId,
            message: 'В активности «${_nonEmpty(a.nodeLabel)}» нет ни recall, '
                'ни apply шага (типы: '
                '${a.steps.map((s) => s.type).join(', ')}) — ученик только '
                'читает, проверки понимания нет',
            data: {
              'stepTypes': [for (final s in a.steps) s.type],
            },
          ),
    ];

/// recall-шаг: 2..4 варианта и `correctIndex` в диапазоне.
List<Finding> checkRecallOptions(SessionView view) {
  final out = <Finding>[];
  for (final a in view.activities) {
    for (var i = 0; i < a.steps.length; i++) {
      final step = a.steps[i];
      if (step.type != kStepRecall) continue;
      final label = _stepLabel(a, i, step);

      if (!step.hasOptions) {
        out.add(Finding(
          code: SessionCheckCode.recallOptions,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'recall «$label»: вариантов нет (ожидалось '
              '$kMinRecallOptions..$kMaxRecallOptions)',
        ));
        continue;
      }
      final options = step.options!;
      if (options.length < kMinRecallOptions ||
          options.length > kMaxRecallOptions) {
        out.add(Finding(
          code: SessionCheckCode.recallOptions,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'recall «$label»: вариантов ${options.length}, ожидалось '
              '$kMinRecallOptions..$kMaxRecallOptions',
          data: {'options': options.length},
        ));
      }
      final correctIndex = step.correctIndex;
      if (correctIndex == null) {
        out.add(Finding(
          code: SessionCheckCode.recallOptions,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'recall «$label»: не задан correctIndex — шаг нечем '
              'проверить',
        ));
      } else if (correctIndex < 0 || correctIndex >= options.length) {
        out.add(Finding(
          code: SessionCheckCode.recallOptions,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'recall «$label»: correctIndex $correctIndex вне диапазона '
              '0..${options.length - 1}',
          data: {'correctIndex': correctIndex, 'options': options.length},
        ));
      }
    }
  }
  return out;
}

/// apply-шаг: есть инструкция и эталонный ответ.
List<Finding> checkApplyContract(SessionView view) {
  final out = <Finding>[];
  for (final a in view.activities) {
    for (var i = 0; i < a.steps.length; i++) {
      final step = a.steps[i];
      if (step.type != kStepApply) continue;
      final label = _stepLabel(a, i, step);
      if (_nonEmpty(step.instruction).isEmpty) {
        out.add(Finding(
          code: SessionCheckCode.applyContract,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'apply «$label»: пустая инструкция — ученику не сказано, '
              'что именно делать',
        ));
      }
      if (_nonEmpty(step.bestAnswer).isEmpty) {
        out.add(Finding(
          code: SessionCheckCode.applyContract,
          severity: FindingSeverity.fail,
          nodeId: a.nodeId,
          message: 'apply «$label»: нет эталонного ответа (bestAnswer) — '
              'задание невозможно проверить',
        ));
      }
    }
  }
  return out;
}

/// На отвеченный шаг есть фидбек.
List<Finding> checkFeedbackMissing(SessionView view) {
  final out = <Finding>[];
  for (final a in view.activities) {
    for (var i = 0; i < a.steps.length; i++) {
      final step = a.steps[i];
      if (!step.isAnswered) continue;
      if (_nonEmpty(step.feedback).isNotEmpty) continue;
      out.add(Finding(
        code: SessionCheckCode.feedbackMissing,
        severity: FindingSeverity.warn,
        nodeId: a.nodeId,
        message: 'Шаг «${_stepLabel(a, i, step)}» отвечен, но фидбек пуст: '
            'ученик не узнает, почему такой ответ верный или неверный',
      ));
    }
  }
  return out;
}

/// Ответ есть, а вердикт не выставлен — оценка не посчиталась.
List<Finding> checkAnswersScored(SessionView view) {
  final out = <Finding>[];
  for (final a in view.activities) {
    for (var i = 0; i < a.steps.length; i++) {
      final step = a.steps[i];
      if (_nonEmpty(step.userAnswer).isEmpty) continue;
      if (step.correct != null) continue;
      out.add(Finding(
        code: SessionCheckCode.answerNotScored,
        severity: FindingSeverity.warn,
        nodeId: a.nodeId,
        message: 'Шаг «${_stepLabel(a, i, step)}»: ответ есть, а correct == '
            'null — шаг не попал в mastery и в SRS',
      ));
    }
  }
  for (var i = 0; i < view.questions.length; i++) {
    final q = view.questions[i];
    if (_nonEmpty(q.userAnswer).isEmpty) continue;
    if (q.correct != null) continue;
    out.add(Finding(
      code: SessionCheckCode.answerNotScored,
      severity: FindingSeverity.warn,
      nodeId: q.nodeId,
      message: 'Вопрос №${i + 1} «${_nonEmpty(q.question)}»: ответ есть, '
          'а correct == null',
    ));
  }
  return out;
}

/// apply-этал совпадает с инструкцией, либо пользователь «угадал» подряд.
///
/// Оба симптома говорят о том, что задание не проверяет понимание: в первом
/// случае этал — это пересказ задания, во втором — ответ ученика дословно равен
/// эталону несколько раз подряд (копипаст или «всё угадал»).
List<Finding> checkApplyDegenerate(SessionView view) {
  final out = <Finding>[];
  var echoRun = 0;
  final echoRuns = <int>[];

  for (final a in view.activities) {
    for (var i = 0; i < a.steps.length; i++) {
      final step = a.steps[i];
      if (step.type != kStepApply) continue;
      final label = _stepLabel(a, i, step);

      final instruction = _squeezedAnswer(step.instruction);
      final best = _squeezedAnswer(step.bestAnswer);
      if (instruction.length >= kMinAnswerLengthForEcho &&
          instruction == best) {
        out.add(Finding(
          code: SessionCheckCode.applyDegenerate,
          severity: FindingSeverity.warn,
          nodeId: a.nodeId,
          message: 'apply «$label»: bestAnswer дословно совпадает с '
              'инструкцией — этал не добавляет ничего к заданию',
        ));
      }

      final answer = _squeezedAnswer(step.userAnswer);
      final isEcho = answer.length >= kMinAnswerLengthForEcho &&
          best.isNotEmpty &&
          answer == best;
      if (isEcho) {
        echoRun++;
      } else {
        if (echoRun >= kApplyEchoRun) echoRuns.add(echoRun);
        echoRun = 0;
      }
    }
  }
  if (echoRun >= kApplyEchoRun) echoRuns.add(echoRun);

  if (echoRuns.isNotEmpty) {
    final maxRun = echoRuns.reduce((a, b) => a > b ? a : b);
    out.add(Finding(
      code: SessionCheckCode.applyDegenerate,
      severity: FindingSeverity.warn,
      message: 'Подряд идущих apply-шагов, где ответ совпал с эталом '
          'дословно: максимум $maxRun (порог $kApplyEchoRun). Похоже на '
          'копипаст или на «всё угадал», а не на усвоение',
      data: {'runs': echoRuns, 'maxRun': maxRun},
    ));
  }
  return out;
}

/// Время шагов против бюджета сессии + нулевое время при длинных текстах.
List<Finding> checkStepDuration(SessionView view) {
  final budgetMs = view.timeBudgetMinutes * 60 * 1000;
  var totalMs = 0;
  for (final step in view.allSteps) {
    totalMs += step.durationMs;
  }
  for (final q in view.questions) {
    totalMs += q.timeSpentMs;
  }

  final out = <Finding>[];
  if (budgetMs > 0 && totalMs > 0) {
    final ratio = totalMs / budgetMs;
    if (ratio > kSessionDurationFailRatio) {
      out.add(Finding(
        code: SessionCheckCode.stepDuration,
        severity: FindingSeverity.fail,
        message: 'Сумма времени шагов и вопросов — '
            '${(totalMs / 60000).toStringAsFixed(1)} мин при бюджете '
            '${view.timeBudgetMinutes} мин ('
            '${ratio.toStringAsFixed(1)}x; warn от '
            '${kSessionDurationWarnRatio}x, fail от '
            '${kSessionDurationFailRatio}x)',
        data: {
          'totalMs': totalMs,
          'budgetMinutes': view.timeBudgetMinutes,
          'ratio': double.parse(ratio.toStringAsFixed(4)),
        },
      ));
    } else if (ratio > kSessionDurationWarnRatio) {
      out.add(Finding(
        code: SessionCheckCode.stepDuration,
        severity: FindingSeverity.warn,
        message: 'Сумма времени шагов и вопросов — '
            '${(totalMs / 60000).toStringAsFixed(1)} мин при бюджете '
            '${view.timeBudgetMinutes} мин (${ratio.toStringAsFixed(1)}x)',
        data: {
          'totalMs': totalMs,
          'budgetMinutes': view.timeBudgetMinutes,
          'ratio': double.parse(ratio.toStringAsFixed(4)),
        },
      ));
    }
  }

  // «Нулевое» время при длинных текстах: значит, замер не вёлся вовсе.
  for (final a in view.activities) {
    final silent = <String>[
      for (var i = 0; i < a.steps.length; i++)
        if (a.steps[i].durationMs == 0 &&
            a.steps[i].fullText.trim().length >= kLongStepTextChars)
          '${a.nodeId}#${i + 1}',
    ];
    if (silent.isEmpty) continue;
    out.add(Finding(
      code: SessionCheckCode.stepDuration,
      severity: FindingSeverity.warn,
      nodeId: a.nodeId,
      message: '${silent.length} шагов с нулевым временем при тексте от '
          '$kLongStepTextChars символов (${_idList(silent)}) — тайминг не '
          'записывался, метрика Learning Gain / Time недостоверна',
      data: {'silentSteps': silent.length},
    ));
  }
  return out;
}

/// Статус сессии согласован с ответами и флагом завершения активностей.
List<Finding> checkSessionCompletion(SessionView view) {
  final answered = view.answeredSteps.length;
  final activitiesWithAnswers = <SessionActivityView>[
    for (final a in view.activities)
      if (a.steps.any((s) => s.isAnswered)) a,
  ];
  final out = <Finding>[];

  if (view.status != kStatusCompleted &&
      answered >= kEnoughAnswersForCompletion &&
      activitiesWithAnswers.length == view.activities.length &&
      view.activities.isNotEmpty) {
    out.add(Finding(
      code: SessionCheckCode.completion,
      severity: FindingSeverity.warn,
      message: 'status = «${view.status}», но отвечено $answered шагов во всех '
          '${view.activities.length} активностях и записано '
          '${view.events.length} событий — сессия выглядит завершённой, '
          'просто статус не переключили',
      data: {'answeredSteps': answered, 'events': view.events.length},
    ));
  }

  final incomplete = [
    for (final a in view.activities)
      if (!a.isComplete) a.nodeId,
  ];
  if (answered > 0 && incomplete.length == view.activities.length) {
    out.add(Finding(
      code: SessionCheckCode.completion,
      severity: FindingSeverity.warn,
      message: 'Ни одна из ${view.activities.length} активностей не помечена '
          'завершённой (isComplete == false), хотя ответы есть: прогресс '
          'потеряется при перезапуске',
      data: {'activities': view.activities.length},
    ));
  }
  return out;
}

/// Мастерство выросло только на тех узлах, которые были в сессии.
///
/// Рост можно утверждать ТОЛЬКО когда известно состояние «до». Узла, которого
/// не было в `masteryBefore`, это обычное дело (он новый для сессии), и любая
/// ненулевая mastery на нём выглядела бы как «выросло с нуля» — это шум, а не
/// дефект. Снимка «до» в БД нет by design (`learner_models` хранит только
/// текущее состояние), поэтому такой случай честно отдаётся одной info.
///
/// Рост на узле, которого не было ни в плане, ни в активностях, — признак
/// либо баги в разборе событий, либо подмены id.
List<Finding> checkMasteryDelta(SessionView view) {
  if (view.masteryAfter.isEmpty) {
    return const [
      Finding(
        code: SessionCheckCode.masteryDelta,
        severity: FindingSeverity.info,
        message: 'Нет данных о мастерстве ПОСЛЕ сессии — дельту проверить '
            'нечем',
      ),
    ];
  }
  if (view.masteryBefore.isEmpty) {
    return const [
      Finding(
        code: SessionCheckCode.masteryDelta,
        severity: FindingSeverity.info,
        message: 'Нет снимка мастерства ДО сессии: learner_models хранит '
            'только текущее состояние, поэтому оценить, выросло ли мастерство, '
            'нельзя',
      ),
    ];
  }
  final known = view.touchedNodeIds;
  final out = <Finding>[];
  for (final nodeId in view.masteryAfter.keys.toList()..sort()) {
    final after = view.masteryAfter[nodeId]!;
    final before = view.masteryBefore[nodeId];
    // Узел новый для сессии: «до» не знаем, а значит и рост не доказан.
    if (before == null) continue;
    if (after <= before) continue;
    if (known.contains(nodeId)) continue;
    out.add(Finding(
      code: SessionCheckCode.masteryDelta,
      severity: FindingSeverity.warn,
      nodeId: nodeId,
      message: 'Мастерство на узле «$nodeId» выросло '
          '(${before.toStringAsFixed(3)} → ${after.toStringAsFixed(3)}), '
          'но этого узла не было ни в плане, ни в активностях, ни в вопросах '
          'сессии',
      data: {
        'before': before,
        'after': double.parse(after.toStringAsFixed(4)),
      },
    ));
  }
  return out;
}

/// Мисконцепция зафиксирована, но отработки на её узле нет.
///
/// Отработка = активность на этом узле, в которой есть apply-шаг (ещё лучше —
/// если активность идёт ПОСЛЕ вопроса, но порядок в плоском DTO не
/// гарантирован, поэтому проверяем наличие, а не позицию).
List<Finding> checkMisconceptionRemediation(SessionView view) {
  if (view.misconceptions.isEmpty &&
      view.misconceptionsByNode.isEmpty) {
    return const [];
  }
  if (view.misconceptionsByNode.isEmpty) {
    return [
      Finding(
        code: SessionCheckCode.misconceptionWithoutRemediation,
        severity: FindingSeverity.warn,
        message: 'Зафиксировано мисконцепций: ${view.misconceptions.length}, '
            'но без nodeId (заполни misconceptionsByNode) — проверить, была '
            'ли отработка, невозможно',
        data: {'count': view.misconceptions.length},
      ),
    ];
  }

  final out = <Finding>[];
  for (final nodeId in view.misconceptionsByNode.keys.toList()..sort()) {
    final activities = [
      for (final a in view.activities)
        if (a.nodeId == nodeId) a,
    ];
    if (activities.isEmpty) {
      out.add(Finding(
        code: SessionCheckCode.misconceptionWithoutRemediation,
        severity: FindingSeverity.warn,
        nodeId: nodeId,
        message: 'Мисконцепция «${_nonEmpty(view.misconceptionsByNode[nodeId])}» '
            'зафиксирована, но активностей по узлу не было вовсе',
      ));
      continue;
    }
    final hasApply = activities.any((a) => a.steps.isNotEmpty &&
        a.steps.any((s) => s.type == kStepApply));
    if (hasApply) continue;
    out.add(Finding(
      code: SessionCheckCode.misconceptionWithoutRemediation,
      severity: FindingSeverity.warn,
      nodeId: nodeId,
      message: 'Мисконцепция «${_nonEmpty(view.misconceptionsByNode[nodeId])}» '
          'зафиксирована, но на узле ${activities.length} активностей без '
          'apply-шага — отработки не было',
      data: {'activities': activities.length},
    ));
  }
  return out;
}

/// Вопросы дают чем оценить ответ и объясняют правильный ответ.
///
/// Контракт боевой оценки (`assessment_engine.dart` + экраны quiz/final):
/// * ЗАКРЫТЫЙ вопрос (`options` непустой) проверяется сверкой индексов
///   `selected.toString() == q.correctAnswer`, поэтому неразрешимый правильный
///   вариант — это отдельная находка [SessionCheckCode.questionAnswerUnresolved]
///   (дефект данных), и здесь она НЕ дублируется: пока вариант неизвестен,
///   «фидбека нет» и «фидбек плохой» — одно и то же рассуждение, скажем один
///   раз. При известном варианте фидбек обязан либо процитировать его, либо
///   содержать оценочную связку («верно», «потому что»).
/// * ОТКРЫТЫЙ вопрос (`options` пуст) эталона не имеет и по контракту иметь не
///   должен: `correctAnswer` у него пуст по построению, а оценивает
///   `gradeOpenEnded` по рубрике из `explanation`. Поэтому проверяем РУБРИКУ, а
///   не `correctAnswer`; рубрики нет — такой вопрос действительно неоцениваем,
///   засчитывался бы как верный на любой непустой ответ, и это warn, а не info.
List<Finding> checkQuestionDepth(SessionView view) {
  final out = <Finding>[];
  for (var i = 0; i < view.questions.length; i++) {
    final q = view.questions[i];
    final label = 'вопрос №${i + 1} «${_nonEmpty(q.question)}»';
    final type = q.effectiveType;
    final feedback = _squeezedAnswer(q.feedback);

    if (q.hasOptions) {
      final options = q.options!;
      final index = q.correctIndex;
      // Правильный вариант не сопоставили (или индекс вне диапазона): без него
      // неизвестно, процитировала ли обратная связь ответ, и оценка в самом
      // приложении тоже не сойдётся. Это дефект данных, а не shallow-фидбека —
      // и второй раз обсуждать его здесь нельзя.
      if (index == null || index < 0 || index >= options.length) {
        final raw = _nonEmpty(q.correctAnswer);
        final how = index == null
            ? 'индекс не разрешён'
            : 'индекс $index вне диапазона 0..${options.length - 1}';
        out.add(Finding(
          code: SessionCheckCode.questionAnswerUnresolved,
          severity: FindingSeverity.warn,
          nodeId: q.nodeId,
          message: '$label ($type): correctAnswer не совпал ни с одним из '
              '${options.length} вариантов (в базе «$raw», $how; резолв — сначала '
              'индекс, потом нормализованный текст) — правильный ответ не '
              'определён, поэтому ни фидбек, ни оценку проверить нельзя',
          data: {
            'correctAnswer': q.correctAnswer,
            'optionCount': options.length,
            'correctIndex': index,
          },
        ));
        continue;
      }

      if (feedback.isEmpty) {
        out.add(Finding(
          code: SessionCheckCode.questionShallow,
          severity: FindingSeverity.warn,
          nodeId: q.nodeId,
          message: '$label ($type): по вопросу с вариантами нет фидбека — '
              'правильный ответ не пояснён',
        ));
        continue;
      }

      // Правильный вариант цитируется в фидбеке ИЛИ фидбек содержит оценочную
      // связку («верно», «потому что») — второе засчитываем как пояснение: раз
      // вариант известен, понятно, ЧТО объясняется.
      final option = _nonEmpty(options[index]);
      final citesOption = option.length >= kMinOptionLengthForExplain &&
          feedback.contains(_squeezedAnswer(option));
      final hasVerdict =
          _kFeedbackAffirmations.any((w) => feedback.contains(_squeeze(w)));
      if (citesOption || hasVerdict) continue;
      out.add(Finding(
        code: SessionCheckCode.questionShallow,
        severity: FindingSeverity.warn,
        nodeId: q.nodeId,
        message: '$label ($type): фидбек не объясняет правильный вариант '
            '<${_nonEmpty(option)}> - это явно и верно, но чем именно '
            'выбран этот вариант, не сказано',
      ));
      continue;
    }

    // Открытый вопрос: эталона нет и не должно быть — нужна рубрика.
    if (!q.hasRubric) {
      out.add(Finding(
        code: SessionCheckCode.questionShallow,
        severity: FindingSeverity.warn,
        nodeId: q.nodeId,
        message: '$label ($type): открытый вопрос без рубрики (explanation) — '
            'без эталонного ответа оценивать нечем: gradeOpenEnded с пустой '
            'рубрикой засчитывает любой непустой ответ как верный',
      ));
    }
  }
  return out;
}

/// Разнообразие типов шагов: доля повторов одного типа подряд.
List<Finding> checkSessionProgression(SessionView view) {
  final types = [for (final s in view.allSteps) s.type];
  if (types.length < kMinStepsForProgression) return const [];
  var repeats = 0;
  for (var i = 1; i < types.length; i++) {
    if (types[i] == types[i - 1]) repeats++;
  }
  final slots = types.length - 1;
  final ratio = repeats / slots;
  if (ratio <= kMaxSameTypeRunRatio) return const [];
  return [
    Finding(
      code: SessionCheckCode.progression,
      severity: FindingSeverity.info,
      message: 'Подряд повторяющийся тип шага: $repeats из $slots переходов '
          '(${(ratio * 100).toStringAsFixed(0)}%, порог '
          '${(kMaxSameTypeRunRatio * 100).toStringAsFixed(0)}%). '
          'Порядок типов: ${types.join(' → ')}',
      data: {
        'types': types,
        'repeats': repeats,
        'transitions': slots,
        'ratio': double.parse(ratio.toStringAsFixed(4)),
      },
    ),
  ];
}

// ─── Точка входа ─────────────────────────────────────────────────────────────

/// Прогоняет все проверки сессии и возвращает стабильно отсортированный список.
List<Finding> runSessionChecks(SessionView view) {
  final out = <Finding>[
    ...checkActivityNodesKnown(view),
    ...checkActivityStepMix(view),
    ...checkRecallOptions(view),
    ...checkApplyContract(view),
    ...checkFeedbackMissing(view),
    ...checkAnswersScored(view),
    ...checkApplyDegenerate(view),
    ...checkStepDuration(view),
    ...checkSessionCompletion(view),
    ...checkMasteryDelta(view),
    ...checkMisconceptionRemediation(view),
    ...checkQuestionDepth(view),
    ...checkSessionProgression(view),
    ...checkAssessmentScores(view),
    ...checkVerdictConsistency(view),
  ];
  return sortedFindings(out);
}

/// Вердикт не согласован с самим ответом.
///
/// Кейс из архива сессии: `userAnswer` — это правильный вариант (по контракту
/// тем же индексом, что и `correctAnswer`, для старых записей — дословно его
/// текстом), а попытка записана как неверная. Раньше это проходило молча —
/// «неверно» попадало в mastery и в мисконцепции.
///
/// Проверяем только закрытые вопросы с известным правильным вариантом: для
/// открытых ответов вердикт ставит `gradeOpenEnded` по рубрике, и сравнение
/// текстов даёт ложные срабатывания.
List<Finding> checkVerdictConsistency(SessionView view) {
  final out = <Finding>[];
  for (var i = 0; i < view.questions.length; i++) {
    final q = view.questions[i];
    final verdict = q.correct;
    final answer = _nonEmpty(q.userAnswer);
    if (verdict != false || answer.isEmpty) continue;
    if (q.correctIndex == null || !q.hasOptions) continue;

    // correctIndex приходит из данных: за границами вариантов быть не может,
    // иначе проверка упала бы на ровно том мусоре, который и проверяет.
    final idx = q.correctIndex!;
    if (idx < 0 || idx >= q.options!.length) continue;

    // По контракту и `correctAnswer`, и `userAnswer` закрытого вопроса — индексы
    // вариантов строкой, так что первое сравнение и есть проверка по контракту.
    // Второе оставлено для данных, где ученикский ответ записан текстом
    // варианта (старые сессии, ручные правки БД).
    final matchesAnswer = _nonEmpty(q.correctAnswer) == answer;
    final matchesOptionText = answer == q.options![idx].trim();
    if (!matchesAnswer && !matchesOptionText) continue;

    out.add(Finding(
      code: SessionCheckCode.verdictContradictsAnswer,
      severity: FindingSeverity.fail,
      nodeId: q.nodeId,
      message: 'вопрос №${i + 1} <${_squeezedAnswer(q.question)}>: ответ '
          '«${_squeezedAnswer(answer)}» совпадает с правильным вариантом, '
          'но попытка записана как неверная — mastery и мисконцепции считают '
          'это ошибкой',
      data: {
        'questionId': i,
        'userAnswer': q.userAnswer,
        'correctAnswer': q.correctAnswer,
        'correctIndex': q.correctIndex,
        'type': q.effectiveType,
      },
    ));
  }
  return out;
}

/// Записанный балл оценки не сходится с фактическими попытками.
///
/// Типовой дефект: ответ верный, но `attempts.correct = false`, и `score`
/// посчитан по старым попыткам. Без сверки отчёт показывал «0 из 0 неверных»
/// и молчал, а `hasFailures` был неверным.
List<Finding> checkAssessmentScores(SessionView view) {
  final out = <Finding>[];
  for (final a in view.assessments) {
    final recorded = a.recordedScore;
    final actual = a.actualRatio;
    if (recorded == null) continue;
    if (actual == null) {
      // Балл записан, а попыток нет: сверить нечего. Это либо потерянные
      // `assessment_attempts`, либо оценка из другого источника — молчать
      // нельзя, но и severity тут низкий.
      out.add(Finding(
        code: SessionCheckCode.scoreMismatch,
        severity: FindingSeverity.warn,
        message: 'оценка <${a.type.isEmpty ? 'без типа' : a.type}>: записан '
            'score=${_trimNumber(recorded)}, но попыток в базе нет - сверить '
            'балл не с чем, возможны потерянные assessment_attempts',
        data: {'type': a.type, 'recordedScore': recorded, 'attempts': 0},
      ));
      continue;
    }
    final diff = (recorded - actual).abs();
    if (diff <= kScoreMismatchTolerance) continue;
    out.add(Finding(
      code: SessionCheckCode.scoreMismatch,
      severity: diff > 0.5 ? FindingSeverity.fail : FindingSeverity.warn,
      message: 'Оценка «${a.type.isEmpty ? 'без типа' : a.type}»: в базе '
          'score=${_trimNumber(recorded)}, по попыткам ${a.correctAttempts} из '
          '${a.attempts} (${_trimNumber(actual)}). Расхождение '
          '${_trimNumber(diff)} — оценка и фактические ответы не согласованы.',
      data: {
        'type': a.type,
        'recordedScore': recorded,
        'actualRatio': actual,
        'attempts': a.attempts,
        'correctAttempts': a.correctAttempts,
      },
    ));
  }
  return out;
}

String _trimNumber(double v) => v.toStringAsFixed(2);