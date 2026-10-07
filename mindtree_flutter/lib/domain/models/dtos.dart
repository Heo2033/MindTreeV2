import 'curriculum.dart';
import 'mastery.dart';

/// Pace classification relative to target.
enum PaceClass {
  faster,
  onTrack,
  slower;

  static PaceClass fromString(String? v) => PaceClass.values
      .firstWhere((e) => e.name == v, orElse: () => PaceClass.onTrack);

  String get raw => name;
}

/// ETA / pace information for an active session.
class SessionEta {
  final int totalEstimatedMinutes;
  final int elapsedMinutes;
  final int completedItems;
  final int totalItems;
  final int remainingMinutesMin;
  final int remainingMinutesMax;
  final PaceClass pace;

  const SessionEta({
    this.totalEstimatedMinutes = 0,
    this.elapsedMinutes = 0,
    this.completedItems = 0,
    this.totalItems = 0,
    this.remainingMinutesMin = 0,
    this.remainingMinutesMax = 0,
    this.pace = PaceClass.onTrack,
  });

  factory SessionEta.fromJson(Map<String, dynamic> json) => SessionEta(
        totalEstimatedMinutes: (json['totalEstimatedMinutes'] as num? ?? 0).toInt(),
        elapsedMinutes: (json['elapsedMinutes'] as num? ?? 0).toInt(),
        completedItems: (json['completedItems'] as num? ?? 0).toInt(),
        totalItems: (json['totalItems'] as num? ?? 0).toInt(),
        remainingMinutesMin: (json['remainingMinutesMin'] as num? ?? 0).toInt(),
        remainingMinutesMax: (json['remainingMinutesMax'] as num? ?? 0).toInt(),
        pace: PaceClass.fromString(json['pace'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'totalEstimatedMinutes': totalEstimatedMinutes,
        'elapsedMinutes': elapsedMinutes,
        'completedItems': completedItems,
        'totalItems': totalItems,
        'remainingMinutesMin': remainingMinutesMin,
        'remainingMinutesMax': remainingMinutesMax,
        'pace': pace.raw,
      };
}

/// Recommended next action by the adaptive engine.
enum RecommendedAction {
  studyNext,
  review,
  finalAssessment,
  deeperMilestone,
  complete;

  static RecommendedAction fromString(String? v) {
    switch (v) {
      case 'study_next':
        return RecommendedAction.studyNext;
      case 'review':
        return RecommendedAction.review;
      case 'final_assessment':
        return RecommendedAction.finalAssessment;
      case 'deeper_milestone':
        return RecommendedAction.deeperMilestone;
      case 'complete':
        return RecommendedAction.complete;
      default:
        return RecommendedAction.studyNext;
    }
  }

  String get raw {
    switch (this) {
      case RecommendedAction.studyNext:
        return 'study_next';
      case RecommendedAction.review:
        return 'review';
      case RecommendedAction.finalAssessment:
        return 'final_assessment';
      case RecommendedAction.deeperMilestone:
        return 'deeper_milestone';
      case RecommendedAction.complete:
        return 'complete';
    }
  }
}

/// Adaptive decision returned to the UI.
class AdaptiveDecision {
  final RecommendedAction recommendedAction;
  final CurriculumItem? currentItem;
  final List<String> dueReviews;
  final String? nextMilestone;
  final List<String> reasons;
  final SessionEta? eta;

  const AdaptiveDecision({
    required this.recommendedAction,
    this.currentItem,
    this.dueReviews = const [],
    this.nextMilestone,
    this.reasons = const [],
    this.eta,
  });

  factory AdaptiveDecision.fromJson(Map<String, dynamic> json) => AdaptiveDecision(
        recommendedAction: RecommendedAction.fromString(json['recommendedAction'] as String?),
        currentItem: json['currentItem'] != null
            ? CurriculumItem.fromJson(json['currentItem'] as Map<String, dynamic>)
            : null,
        dueReviews: (json['dueReviews'] as List<dynamic>? ?? []).cast<String>(),
        nextMilestone: json['nextMilestone'] as String?,
        reasons: (json['reasons'] as List<dynamic>? ?? []).cast<String>(),
        eta: json['eta'] != null ? SessionEta.fromJson(json['eta'] as Map<String, dynamic>) : null,
      );

  Map<String, dynamic> toJson() => {
        'recommendedAction': recommendedAction.raw,
        if (currentItem != null) 'currentItem': currentItem!.toJson(),
        'dueReviews': dueReviews,
        'nextMilestone': nextMilestone,
        'reasons': reasons,
        if (eta != null) 'eta': eta!.toJson(),
      };
}

/// Mastery evaluation after submitting an assessment.
class MasteryEvaluation {
  final String topicId;
  final MasteryLevel newLevel;
  final double score;
  final bool reachedTarget;
  final Map<String, double> perConcept;
  final List<String> gaps;

  const MasteryEvaluation({
    required this.topicId,
    required this.newLevel,
    required this.score,
    required this.reachedTarget,
    this.perConcept = const {},
    this.gaps = const [],
  });

  factory MasteryEvaluation.fromJson(Map<String, dynamic> json) {
    final newLevelRaw = json['newLevel'];
    final perConceptRaw = json['perConcept'];
    return MasteryEvaluation(
      topicId: json['topicId'] as String,
      newLevel: MasteryLevel.fromString(_extractLevel(newLevelRaw)),
      score: _extractScore(newLevelRaw),
      reachedTarget: json['reachedTarget'] as bool? ?? false,
      perConcept: _extractPerConcept(perConceptRaw),
      gaps: (json['gaps'] as List<dynamic>? ?? []).cast<String>(),
    );
  }

  static String? _extractLevel(dynamic v) {
    if (v is Map) return v['label'] as String? ?? v['level'] as String?;
    if (v is String) return v;
    return null;
  }

  static double _extractScore(dynamic v) {
    if (v is Map) return (v['score'] as num? ?? 0).toDouble();
    return 0;
  }

  static Map<String, double> _extractPerConcept(dynamic v) {
    if (v is! Map) return {};
    final out = <String, double>{};
    v.forEach((k, val) {
      if (val is Map) {
        out[k.toString()] = (val['score'] as num? ?? 0).toDouble();
      } else if (val is num) {
        out[k.toString()] = val.toDouble();
      }
    });
    return out;
  }

  Map<String, dynamic> toJson() => {
        'topicId': topicId,
        'newLevel': {'label': newLevel.raw, 'score': score},
        'reachedTarget': reachedTarget,
        'perConcept': perConcept,
        'gaps': gaps,
      };
}

/// A quiz question.
class QuizQuestion {
  final String id;
  final String nodeId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final bool? misconception;

  const QuizQuestion({
    required this.id,
    required this.nodeId,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.misconception,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        id: json['id'] as String,
        nodeId: json['nodeId'] as String,
        question: json['question'] as String,
        options: (json['options'] as List<dynamic>? ?? []).cast<String>(),
        correctIndex: (json['correctIndex'] as num? ?? 0).toInt(),
        explanation: json['explanation'] as String? ?? '',
        misconception: json['misconception'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nodeId': nodeId,
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
        if (misconception != null) 'misconception': misconception,
      };
}

/// A quiz (set of questions).
class Quiz {
  final String id;
  final String topicId;
  final String title;
  final List<QuizQuestion> questions;

  const Quiz({
    required this.id,
    required this.topicId,
    required this.title,
    this.questions = const [],
  });

  factory Quiz.fromJson(Map<String, dynamic> json) => Quiz(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        title: json['title'] as String? ?? '',
        questions: (json['questions'] as List<dynamic>? ?? [])
            .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'title': title,
        'questions': questions.map((e) => e.toJson()).toList(),
      };
}

/// A diagnostic question.
class DiagnosticQuestion {
  final String id;
  final String nodeId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const DiagnosticQuestion({
    required this.id,
    required this.nodeId,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory DiagnosticQuestion.fromJson(Map<String, dynamic> json) => DiagnosticQuestion(
        id: json['id'] as String,
        nodeId: json['nodeId'] as String,
        question: json['question'] as String,
        options: (json['options'] as List<dynamic>? ?? []).cast<String>(),
        correctIndex: (json['correctIndex'] as num? ?? 0).toInt(),
        explanation: json['explanation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nodeId': nodeId,
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      };
}

/// A diagnostic answer in.
class DiagnosticAnswerIn {
  final String questionId;
  final String nodeId;
  final int selectedIndex;
  final int correctIndex;

  const DiagnosticAnswerIn({
    required this.questionId,
    required this.nodeId,
    required this.selectedIndex,
    required this.correctIndex,
  });

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'nodeId': nodeId,
        'selectedIndex': selectedIndex,
        'correctIndex': correctIndex,
      };
}

/// Result of evaluating a diagnostic.
class DiagnosticResult {
  final List<DiagnosticQuestion> questions;
  final MasteryLevel currentLevel;
  final List<String> knownConcepts;
  final List<String> unknownConcepts;
  final double score;

  const DiagnosticResult({
    this.questions = const [],
    this.currentLevel = MasteryLevel.awareness,
    this.knownConcepts = const [],
    this.unknownConcepts = const [],
    this.score = 0,
  });

  factory DiagnosticResult.fromJson(Map<String, dynamic> json) => DiagnosticResult(
        questions: (json['questions'] as List<dynamic>? ?? [])
            .map((e) => DiagnosticQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentLevel: MasteryLevel.fromString(json['currentLevel'] as String?),
        knownConcepts: (json['knownConcepts'] as List<dynamic>? ?? []).cast<String>(),
        unknownConcepts: (json['unknownConcepts'] as List<dynamic>? ?? []).cast<String>(),
        score: (json['score'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'questions': questions.map((e) => e.toJson()).toList(),
        'currentLevel': currentLevel.raw,
        'knownConcepts': knownConcepts,
        'unknownConcepts': unknownConcepts,
        'score': score,
      };
}

/// Session plan item for preview.
class SessionPlanItem {
  final String itemId;
  final String nodeId;
  final String label;
  final int order;
  final String type;
  final int estimatedMinutes;
  final double priority;
  final String status;
  final String? reason;

  const SessionPlanItem({
    required this.itemId,
    required this.nodeId,
    required this.label,
    required this.order,
    required this.type,
    required this.estimatedMinutes,
    required this.priority,
    required this.status,
    this.reason,
  });

  factory SessionPlanItem.fromJson(Map<String, dynamic> json) => SessionPlanItem(
        itemId: json['itemId'] as String,
        nodeId: json['nodeId'] as String,
        label: json['label'] as String? ?? '',
        order: (json['order'] as num? ?? 0).toInt(),
        type: json['type'] as String? ?? 'explain',
        estimatedMinutes: (json['estimatedMinutes'] as num? ?? 5).toInt(),
        priority: (json['priority'] as num? ?? 0).toDouble(),
        status: json['status'] as String? ?? 'pending',
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'nodeId': nodeId,
        'label': label,
        'order': order,
        'type': type,
        'estimatedMinutes': estimatedMinutes,
        'priority': priority,
        'status': status,
        if (reason != null) 'reason': reason,
      };
}

/// Full session plan.
class SessionPlan {
  final String sessionId;
  final String topicName;
  final List<SessionPlanItem> items;
  final int totalEstimatedMinutes;
  final List<Map<String, String>> skipped;

  const SessionPlan({
    required this.sessionId,
    required this.topicName,
    this.items = const [],
    this.totalEstimatedMinutes = 0,
    this.skipped = const [],
  });

  factory SessionPlan.fromJson(Map<String, dynamic> json) => SessionPlan(
        sessionId: json['sessionId'] as String,
        topicName: json['topicName'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => SessionPlanItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalEstimatedMinutes: (json['totalEstimatedMinutes'] as num? ?? 0).toInt(),
        skipped: (json['skipped'] as List<dynamic>? ?? [])
            .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'topicName': topicName,
        'items': items.map((e) => e.toJson()).toList(),
        'totalEstimatedMinutes': totalEstimatedMinutes,
        'skipped': skipped,
      };
}

// ─── Adapt (§80): действия пользователя над подачей и планом ──────────────────

/// Пять действий Adapt из §80: упрощённое объяснение, prerequisite, пропуск
/// уже известного, смена глубины (L1/L2/L3) и пересборка плана под оставшееся
/// время. Каждое возвращает свой типизированный результат (см. [AdaptResult]),
/// а не общий Map: вызывающий получает ровно те поля, которые ему нужны.
///
/// `fromJson` у типов Adapt намеренно НЕТ: результаты возвращаются вызывающему
/// напрямую (UI, probe) и не десериализуются — в отличие от [AdaptiveDecision],
/// который шлётся по wire в инструментах ревью.
enum AdaptAction {
  simplify,
  prerequisite,
  skip,
  changeDepth,
  replan;

  static AdaptAction fromString(String? v) => AdaptAction.values
      .firstWhere((e) => e.raw == v, orElse: () => AdaptAction.simplify);

  String get raw {
    switch (this) {
      case AdaptAction.simplify:
        return 'simplify';
      case AdaptAction.prerequisite:
        return 'prerequisite';
      case AdaptAction.skip:
        return 'skip';
      case AdaptAction.changeDepth:
        return 'change_depth';
      case AdaptAction.replan:
        return 'replan';
    }
  }
}

/// Источник текста LLM-действий ([AdaptSimplifyResult], [AdaptDepthResult]).
///
/// [AdaptSource.llm] — свежий ответ модели; [AdaptSource.stored] —
/// детерминированный fallback на сохранённый контент узла, когда LLM
/// недоступна или ответ не прошёл JSON-контракт (обязательное правило
/// AGENTS.md: сбой LLM не должен ронять сценарий).
enum AdaptSource {
  llm,
  stored;

  static AdaptSource fromString(String? v) => AdaptSource.values
      .firstWhere((e) => e.raw == v, orElse: () => AdaptSource.stored);

  String get raw => name;
}

/// Глубина подачи (§80 «изменить глубину»: L1/L2/L3).
///
/// - [overview] — обзор (L1): суть и место понятия, без глубоких деталей;
/// - [standard] — обычная подача сессии (L2): цель берётся из `session.goal`;
/// - [deep] — глубокое изучение (L3): механизм и подтемы.
///
/// Глубина меняет ЦЕЛЬ подачи, но не аудиторию: «глубже» ≠ «проще»
/// (аудитория меняется только в [AdaptSimplifyResult]).
enum ContentDepth {
  overview,
  standard,
  deep;

  static ContentDepth fromString(String? v) => ContentDepth.values
      .firstWhere((e) => e.raw == v, orElse: () => ContentDepth.standard);

  String get raw {
    switch (this) {
      case ContentDepth.overview:
        return 'overview';
      case ContentDepth.standard:
        return 'standard';
      case ContentDepth.deep:
        return 'deep';
    }
  }
}

/// Как prerequisite связан с запрошенным понятием.
enum PrerequisiteKind {
  /// Явная связь `depends_on`/`requires` самого узла.
  dependsOn,

  /// Предок по иерархии дерева (`parentId`) — путь L1→L2→L3.
  parent;

  static PrerequisiteKind fromString(String? v) => PrerequisiteKind.values
      .firstWhere((e) => e.raw == v, orElse: () => PrerequisiteKind.dependsOn);

  String get raw {
    switch (this) {
      case PrerequisiteKind.dependsOn:
        return 'depends_on';
      case PrerequisiteKind.parent:
        return 'parent';
    }
  }
}

/// Один prerequisite узла: на что опираться + статус изученности.
class PrerequisiteRef {
  final String nodeId;
  final String label;
  final String oneLiner;
  final PrerequisiteKind kind;

  /// Пункт плана с этим `nodeId` уже `completed` в текущей сессии.
  final bool studied;

  /// `masteryScore` профиля концепта; `null` — измерения ещё не было.
  final double? mastery;

  const PrerequisiteRef({
    required this.nodeId,
    required this.label,
    required this.oneLiner,
    required this.kind,
    required this.studied,
    this.mastery,
  });

  factory PrerequisiteRef.fromJson(Map<String, dynamic> json) => PrerequisiteRef(
        nodeId: json['nodeId'] as String,
        label: json['label'] as String? ?? '',
        oneLiner: json['oneLiner'] as String? ?? '',
        kind: PrerequisiteKind.fromString(json['kind'] as String?),
        studied: json['studied'] as bool? ?? false,
        mastery: (json['mastery'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'label': label,
        'oneLiner': oneLiner,
        'kind': kind.raw,
        'studied': studied,
        'mastery': mastery,
      };
}

/// Общий каркас результата Adapt-действия.
///
/// [title]/[text] — готовое к показу в UI (русский), [reasons] — почему
/// действие сработало именно так (в т.ч. когда включился fallback).
class AdaptResult {
  final AdaptAction action;
  final String sessionId;
  final String? nodeId;
  final String? itemId;

  /// Заголовок (как правило — понятие, к которому применено действие).
  final String title;

  /// Сводный текст для показа без дополнительной сборки.
  final String text;

  final List<String> reasons;

  const AdaptResult({
    required this.action,
    required this.sessionId,
    this.nodeId,
    this.itemId,
    required this.title,
    required this.text,
    this.reasons = const [],
  });

  Map<String, dynamic> _baseJson() => {
        'action': action.raw,
        'sessionId': sessionId,
        'nodeId': nodeId,
        'itemId': itemId,
        'title': title,
        'text': text,
        'reasons': reasons,
      };

  Map<String, dynamic> toJson() => _baseJson();
}

/// «Упрощённое объяснение» (§80): тот же узел, но аудитория — новичок.
class AdaptSimplifyResult extends AdaptResult {
  /// Откуда взялся текст: свежий ответ модели либо сохранённый контент.
  final AdaptSource source;
  final String oneLiner;
  final String details;
  final String? analogy;

  const AdaptSimplifyResult({
    required super.sessionId,
    required super.nodeId,
    required super.title,
    required super.text,
    super.reasons,
    required this.source,
    this.oneLiner = '',
    this.details = '',
    this.analogy,
  }) : super(action: AdaptAction.simplify);

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'source': source.raw,
        'oneLiner': oneLiner,
        'details': details,
        'analogy': analogy,
      };
}

/// «Смена глубины» (§80): переподача узла на обзор/стандарт/углубление.
class AdaptDepthResult extends AdaptResult {
  final AdaptSource source;
  final ContentDepth depth;
  final String oneLiner;
  final String details;
  final String? analogy;

  const AdaptDepthResult({
    required super.sessionId,
    required super.nodeId,
    required super.title,
    required super.text,
    super.reasons,
    required this.source,
    required this.depth,
    this.oneLiner = '',
    this.details = '',
    this.analogy,
  }) : super(action: AdaptAction.changeDepth);

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'source': source.raw,
        'depth': depth.raw,
        'oneLiner': oneLiner,
        'details': details,
        'analogy': analogy,
      };
}

/// «Prerequisite» (§80): чего не хватает, чтобы понять понятие.
///
/// Строится без LLM: явные связи `depends_on`/`requires` + предки по дереву.
class AdaptPrerequisiteResult extends AdaptResult {
  final List<PrerequisiteRef> prerequisites;

  /// `nodeId` ещё не изученных prerequisites (для кнопки «изучить сначала»).
  final List<String> missingNodeIds;

  const AdaptPrerequisiteResult({
    required super.sessionId,
    required super.nodeId,
    required super.title,
    required super.text,
    super.reasons,
    this.prerequisites = const [],
    this.missingNodeIds = const [],
  }) : super(action: AdaptAction.prerequisite);

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'prerequisites': prerequisites.map((p) => p.toJson()).toList(),
        'missingNodeIds': missingNodeIds,
      };
}

/// «Пропустить уже известное» (§80): пункт плана закрывается, измерения
/// обновляются свидетельством самооценки «знаю».
class AdaptSkipResult extends AdaptResult {
  /// `false` — пункт уже был завершён, повторный пропуск ничего не менял.
  final bool changed;

  /// Записанные свидетельства по измерениям (пусто, если `changed == false`).
  final Map<String, double> evidence;

  /// `masteryScore` профиля после записи; `null` — узла нет в модели.
  final double? masteryScore;

  /// Прогресс сессии после пропуска (completed / total, 0 если план пуст).
  final double progress;

  const AdaptSkipResult({
    required super.sessionId,
    required super.itemId,
    super.nodeId,
    required super.title,
    required super.text,
    super.reasons,
    this.changed = false,
    this.evidence = const {},
    this.masteryScore,
    this.progress = 0,
  }) : super(action: AdaptAction.skip);

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'changed': changed,
        'evidence': evidence,
        'masteryScore': masteryScore,
        'progress': progress,
      };
}

/// «Пересобрать план под оставшееся время» (§80 «адаптировать remaining»).
class AdaptReplanResult extends AdaptResult {
  /// Что осталось в плане (завершённое + влезшее по бюджету), порядок 1..n.
  final List<CurriculumItem> kept;

  /// Что вынесено за бюджет (только незавершённые пункты).
  final List<CurriculumItem> deferred;
  final int remainingMinutes;
  final int elapsedMinutes;
  final SessionEta eta;

  const AdaptReplanResult({
    required super.sessionId,
    required super.title,
    required super.text,
    super.reasons,
    this.kept = const [],
    this.deferred = const [],
    this.remainingMinutes = 0,
    this.elapsedMinutes = 0,
    required this.eta,
  }) : super(action: AdaptAction.replan);

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'kept': kept.map((i) => i.toJson()).toList(),
        'deferred': deferred.map((i) => i.toJson()).toList(),
        'remainingMinutes': remainingMinutes,
        'elapsedMinutes': elapsedMinutes,
        'eta': eta.toJson(),
      };
}

/// Topic metrics for analytics.
class TopicMetrics {
  final String topicId;
  final String topicName;
  final MasteryLevel currentLevel;
  final MasteryLevel targetLevel;
  final String goal;
  final bool masteryReached;
  final double learningGain;
  final double learningGainPerMinute;
  final double meanMastery;
  final double immediateRecall;
  final double delayedRecall;
  final double applicationAccuracy;
  final double transferAccuracy;
  final double sessionCompletion;
  final double milestoneProgression;
  final int? timeToTargetMinutes;
  final int studyMinutes;
  final int conceptCount;

  const TopicMetrics({
    required this.topicId,
    required this.topicName,
    required this.currentLevel,
    required this.targetLevel,
    required this.goal,
    required this.masteryReached,
    required this.learningGain,
    required this.learningGainPerMinute,
    required this.meanMastery,
    required this.immediateRecall,
    required this.delayedRecall,
    required this.applicationAccuracy,
    required this.transferAccuracy,
    required this.sessionCompletion,
    required this.milestoneProgression,
    this.timeToTargetMinutes,
    required this.studyMinutes,
    required this.conceptCount,
  });

  factory TopicMetrics.fromJson(Map<String, dynamic> json) => TopicMetrics(
        topicId: json['topicId'] as String,
        topicName: json['topicName'] as String? ?? '',
        currentLevel: MasteryLevel.fromString(json['currentLevel'] as String?),
        targetLevel: MasteryLevel.fromString(json['targetLevel'] as String?),
        goal: json['goal'] as String? ?? 'overview',
        masteryReached: json['masteryReached'] as bool? ?? false,
        learningGain: (json['learningGain'] as num? ?? 0).toDouble(),
        learningGainPerMinute: (json['learningGainPerMinute'] as num? ?? 0).toDouble(),
        meanMastery: (json['meanMastery'] as num? ?? 0).toDouble(),
        immediateRecall: (json['immediateRecall'] as num? ?? 0).toDouble(),
        delayedRecall: (json['delayedRecall'] as num? ?? 0).toDouble(),
        applicationAccuracy: (json['applicationAccuracy'] as num? ?? 0).toDouble(),
        transferAccuracy: (json['transferAccuracy'] as num? ?? 0).toDouble(),
        sessionCompletion: (json['sessionCompletion'] as num? ?? 0).toDouble(),
        milestoneProgression: (json['milestoneProgression'] as num? ?? 0).toDouble(),
        timeToTargetMinutes: (json['timeToTargetMinutes'] as num?)?.toInt(),
        studyMinutes: (json['studyMinutes'] as num? ?? 0).toInt(),
        conceptCount: (json['conceptCount'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'topicId': topicId,
        'topicName': topicName,
        'currentLevel': currentLevel.raw,
        'targetLevel': targetLevel.raw,
        'goal': goal,
        'masteryReached': masteryReached,
        'learningGain': learningGain,
        'learningGainPerMinute': learningGainPerMinute,
        'meanMastery': meanMastery,
        'immediateRecall': immediateRecall,
        'delayedRecall': delayedRecall,
        'applicationAccuracy': applicationAccuracy,
        'transferAccuracy': transferAccuracy,
        'sessionCompletion': sessionCompletion,
        'milestoneProgression': milestoneProgression,
        'timeToTargetMinutes': timeToTargetMinutes,
        'studyMinutes': studyMinutes,
        'conceptCount': conceptCount,
      };
}

/// Analytics totals across all topics.
class AnalyticsTotals {
  final int completedSessions;
  final int totalSessions;
  final double sessionCompletion;
  final int milestonesCompleted;
  final int totalMilestones;
  final double milestoneProgression;
  final int studyMinutes;
  final double meanLearningGain;

  const AnalyticsTotals({
    this.completedSessions = 0,
    this.totalSessions = 0,
    this.sessionCompletion = 0,
    this.milestonesCompleted = 0,
    this.totalMilestones = 0,
    this.milestoneProgression = 0,
    this.studyMinutes = 0,
    this.meanLearningGain = 0,
  });

  factory AnalyticsTotals.fromJson(Map<String, dynamic> json) => AnalyticsTotals(
        completedSessions: (json['completedSessions'] as num? ?? 0).toInt(),
        totalSessions: (json['totalSessions'] as num? ?? 0).toInt(),
        sessionCompletion: (json['sessionCompletion'] as num? ?? 0).toDouble(),
        milestonesCompleted: (json['milestonesCompleted'] as num? ?? 0).toInt(),
        totalMilestones: (json['totalMilestones'] as num? ?? 0).toInt(),
        milestoneProgression: (json['milestoneProgression'] as num? ?? 0).toDouble(),
        studyMinutes: (json['studyMinutes'] as num? ?? 0).toInt(),
        meanLearningGain: (json['meanLearningGain'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'completedSessions': completedSessions,
        'totalSessions': totalSessions,
        'sessionCompletion': sessionCompletion,
        'milestonesCompleted': milestonesCompleted,
        'totalMilestones': totalMilestones,
        'milestoneProgression': milestoneProgression,
        'studyMinutes': studyMinutes,
        'meanLearningGain': meanLearningGain,
      };
}

/// Analytics summary across topics.
class AnalyticsSummary {
  final List<TopicMetrics> topics;
  final AnalyticsTotals totals;

  const AnalyticsSummary({this.topics = const [], this.totals = const AnalyticsTotals()});

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) => AnalyticsSummary(
        topics: (json['topics'] as List<dynamic>? ?? [])
            .map((e) => TopicMetrics.fromJson(e as Map<String, dynamic>))
            .toList(),
        totals: json['totals'] != null
            ? AnalyticsTotals.fromJson(json['totals'] as Map<String, dynamic>)
            : const AnalyticsTotals(),
      );

  Map<String, dynamic> toJson() => {
        'topics': topics.map((e) => e.toJson()).toList(),
        'totals': totals.toJson(),
      };
}
