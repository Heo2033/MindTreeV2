/// Mastery level hierarchy.
enum MasteryLevel {
  awareness,
  basicUnderstanding,
  solidUnderstanding,
  practicalApplication,
  advanced,
  expert;

  static const List<MasteryLevel> order = [
    awareness,
    basicUnderstanding,
    solidUnderstanding,
    practicalApplication,
    advanced,
    expert,
  ];

  static MasteryLevel fromString(String? v) => MasteryLevel.order.firstWhere(
        (e) => e.raw == v,
        orElse: () => MasteryLevel.awareness,
      );

  /// Wire / snake_case string.
  String get raw {
    switch (this) {
      case MasteryLevel.awareness:
        return 'awareness';
      case MasteryLevel.basicUnderstanding:
        return 'basic_understanding';
      case MasteryLevel.solidUnderstanding:
        return 'solid_understanding';
      case MasteryLevel.practicalApplication:
        return 'practical_application';
      case MasteryLevel.advanced:
        return 'advanced';
      case MasteryLevel.expert:
        return 'expert';
    }
  }
}

/// Type of a misconception detected in the learner.
enum MisconceptionType {
  unknown,
  confused,
  incomplete,
  definitionOnly,
  mechanismError,
  applicationFailure,
  careless;

  static MisconceptionType fromString(String v) {
    switch (v) {
      case 'confused':
        return MisconceptionType.confused;
      case 'incomplete':
        return MisconceptionType.incomplete;
      case 'definition_only':
        return MisconceptionType.definitionOnly;
      case 'mechanism_error':
        return MisconceptionType.mechanismError;
      case 'application_failure':
        return MisconceptionType.applicationFailure;
      case 'careless':
        return MisconceptionType.careless;
      default:
        return MisconceptionType.unknown;
    }
  }

  String get wire {
    switch (this) {
      case MisconceptionType.unknown:
        return 'unknown';
      case MisconceptionType.confused:
        return 'confused';
      case MisconceptionType.incomplete:
        return 'incomplete';
      case MisconceptionType.definitionOnly:
        return 'definition_only';
      case MisconceptionType.mechanismError:
        return 'mechanism_error';
      case MisconceptionType.applicationFailure:
        return 'application_failure';
      case MisconceptionType.careless:
        return 'careless';
    }
  }

  /// Осмысленный текст-заглушка для случая «тип известен, объяснения нет».
  ///
  /// Нужен потому, что пустое `description` в БД бесполезно: такие записи
  /// ничего не объясняют, но попадают в профиль ошибок и в контекст промптов.
  /// Если объяснения нет — пишем текст по типу, а не пустую строку.
  ///
  /// Для [MisconceptionType.unknown] возвращает пустую строку: неизвестный тип
  /// означает, что ошибаться нечем записывать — такую запись не создают.
  String get defaultDescription {
    switch (this) {
      case MisconceptionType.unknown:
        return '';
      case MisconceptionType.confused:
        return 'Ответ перепутан с другим понятием темы';
      case MisconceptionType.incomplete:
        return 'Ответ неполон: не раскрыта ключевая часть понятия';
      case MisconceptionType.definitionOnly:
        return 'Ответ повторяет определение, но не показывает применение';
      case MisconceptionType.mechanismError:
        return 'Ответ неверно описывает механизм понятия';
      case MisconceptionType.applicationFailure:
        return 'Ответ неверно применяет понятие: описанная ситуация ему не соответствует';
      case MisconceptionType.careless:
        return 'Ответ небрежный: понятие не вспомнено при повторении';
    }
  }
}

/// A single misconception detected for a concept.
class Misconception {
  final String nodeId;
  final MisconceptionType type;
  final String description;
  final String detectedAt;
  final bool resolved;

  const Misconception({
    required this.nodeId,
    required this.type,
    required this.description,
    required this.detectedAt,
    this.resolved = false,
  });

  factory Misconception.fromJson(Map<String, dynamic> json) => Misconception(
        nodeId: json['nodeId'] as String,
        type: MisconceptionType.fromString(json['type'] as String? ?? 'unknown'),
        description: json['description'] as String? ?? '',
        detectedAt: json['detectedAt'] as String? ?? '',
        resolved: json['resolved'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'type': type.wire,
        'description': description,
        'detectedAt': detectedAt,
        'resolved': resolved,
      };

  Misconception copyWith({bool? resolved}) => Misconception(
        nodeId: nodeId,
        type: type,
        description: description,
        detectedAt: detectedAt,
        resolved: resolved ?? this.resolved,
      );
}

/// Mastery of a single concept across four skill dimensions, plus flattened
/// SRS state (interval/ease/due/review bookkeeping for spaced repetition).
class ConceptMastery {
  final String nodeId;
  final double understanding;
  final double recall;
  final double application;
  final double transfer;
  final double confidence;
  final List<Misconception> errors;
  final String lastAssessedAt;
  final int reviewCount;
  final String? lastReviewedAt;
  final int srsInterval;
  final double srsEase;
  final String? srsDueAt;

  const ConceptMastery({
    required this.nodeId,
    this.understanding = 0,
    this.recall = 0,
    this.application = 0,
    this.transfer = 0,
    this.confidence = 0,
    this.errors = const [],
    this.lastAssessedAt = '',
    this.reviewCount = 0,
    this.lastReviewedAt,
    this.srsInterval = 0,
    this.srsEase = 2.5,
    this.srsDueAt,
  });

  factory ConceptMastery.fromJson(Map<String, dynamic> json) => ConceptMastery(
        nodeId: json['nodeId'] as String,
        understanding: (json['understanding'] as num? ?? 0).toDouble(),
        recall: (json['recall'] as num? ?? 0).toDouble(),
        application: (json['application'] as num? ?? 0).toDouble(),
        transfer: (json['transfer'] as num? ?? 0).toDouble(),
        confidence: (json['confidence'] as num? ?? 0).toDouble(),
        errors: (json['errors'] as List<dynamic>? ?? [])
            .map((e) => Misconception.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastAssessedAt: json['lastAssessedAt'] as String? ?? '',
        reviewCount: (json['reviewCount'] as num? ?? 0).toInt(),
        lastReviewedAt: json['lastReviewedAt'] as String?,
        srsInterval: (json['srsInterval'] as num? ?? 0).toInt(),
        srsEase: (json['srsEase'] as num? ?? 2.5).toDouble(),
        srsDueAt: json['srsDueAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'understanding': understanding,
        'recall': recall,
        'application': application,
        'transfer': transfer,
        'confidence': confidence,
        'errors': errors.map((e) => e.toJson()).toList(),
        'lastAssessedAt': lastAssessedAt,
        'reviewCount': reviewCount,
        'lastReviewedAt': lastReviewedAt,
        'srsInterval': srsInterval,
        'srsEase': srsEase,
        'srsDueAt': srsDueAt,
      };

  double get average =>
      (understanding + recall + application + transfer) / 4;

  ConceptMastery copyWith({
    double? understanding,
    double? recall,
    double? application,
    double? transfer,
    double? confidence,
    List<Misconception>? errors,
    String? lastAssessedAt,
    int? reviewCount,
    String? Function()? lastReviewedAt,
    int? srsInterval,
    double? srsEase,
    String? Function()? srsDueAt,
  }) =>
      ConceptMastery(
        nodeId: nodeId,
        understanding: understanding ?? this.understanding,
        recall: recall ?? this.recall,
        application: application ?? this.application,
        transfer: transfer ?? this.transfer,
        confidence: confidence ?? this.confidence,
        errors: errors ?? this.errors,
        lastAssessedAt: lastAssessedAt ?? this.lastAssessedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        lastReviewedAt: lastReviewedAt != null ? lastReviewedAt() : this.lastReviewedAt,
        srsInterval: srsInterval ?? this.srsInterval,
        srsEase: srsEase ?? this.srsEase,
        srsDueAt: srsDueAt != null ? srsDueAt() : this.srsDueAt,
      );
}

/// Persistent learner mastery model for a user + topic.
class LearnerModel {
  final String id;
  final String userId;
  final String topicId;
  final MasteryLevel overallLevel;
  final List<ConceptMastery> conceptMasteries;
  final String updatedAt;
  final MasteryLevel initialOverallLevel;

  const LearnerModel({
    required this.id,
    required this.userId,
    required this.topicId,
    this.overallLevel = MasteryLevel.awareness,
    this.conceptMasteries = const [],
    this.updatedAt = '',
    this.initialOverallLevel = MasteryLevel.awareness,
  });

  factory LearnerModel.fromJson(Map<String, dynamic> json) => LearnerModel(
        id: json['id'] as String,
        userId: json['userId'] as String? ?? 'default',
        topicId: json['topicId'] as String,
        overallLevel: MasteryLevel.fromString(json['overallLevel'] as String?),
        conceptMasteries: (json['conceptMasteries'] as List<dynamic>? ?? [])
            .map((e) => ConceptMastery.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: json['updatedAt'] as String? ?? '',
        initialOverallLevel:
            MasteryLevel.fromString(json['initialOverallLevel'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'topicId': topicId,
        'overallLevel': overallLevel.raw,
        'conceptMasteries': conceptMasteries.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt,
        'initialOverallLevel': initialOverallLevel.raw,
      };

  LearnerModel copyWith({
    MasteryLevel? overallLevel,
    List<ConceptMastery>? conceptMasteries,
    String? updatedAt,
    MasteryLevel? initialOverallLevel,
  }) =>
      LearnerModel(
        id: id,
        userId: userId,
        topicId: topicId,
        overallLevel: overallLevel ?? this.overallLevel,
        conceptMasteries: conceptMasteries ?? this.conceptMasteries,
        updatedAt: updatedAt ?? this.updatedAt,
        initialOverallLevel: initialOverallLevel ?? this.initialOverallLevel,
      );
}
