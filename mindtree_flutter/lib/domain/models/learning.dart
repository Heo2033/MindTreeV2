import 'curriculum.dart';
import 'mastery.dart';

/// Status of a learning session.
enum SessionStatus {
  active,
  completed,
  abandoned;

  static SessionStatus fromString(String? v) =>
      SessionStatus.values.firstWhere((e) => e.name == v, orElse: () => SessionStatus.active);

  String get raw => name;
}

/// Status of a learning milestone.
enum MilestoneStatus {
  notStarted,
  active,
  completed;

  static MilestoneStatus fromString(String? v) => MilestoneStatus.values.firstWhere(
      (e) => e.name == (v ?? '').replaceAll('-', '_'),
      orElse: () => MilestoneStatus.notStarted);

  String get raw => name;
}

/// An alternative learning path within a milestone.
class LearningPath {
  final String id;
  final String title;
  final double estimatedHours;
  final String description;

  const LearningPath({
    required this.id,
    required this.title,
    this.estimatedHours = 1,
    this.description = '',
  });

  factory LearningPath.fromJson(Map<String, dynamic> json) => LearningPath(
        id: json['id'] as String,
        title: json['title'] as String,
        estimatedHours: (json['estimatedHours'] as num? ?? 1).toDouble(),
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'estimatedHours': estimatedHours,
        'description': description,
      };
}

/// A mastery milestone in a learning journey.
class LearningMilestone {
  final String id;
  final MasteryLevel level;
  final String title;
  final String description;
  final List<String> capabilities;
  final double estimatedHours;
  final MilestoneStatus status;
  final List<LearningPath> alternativePaths;

  const LearningMilestone({
    required this.id,
    required this.level,
    required this.title,
    this.description = '',
    this.capabilities = const [],
    this.estimatedHours = 1,
    this.status = MilestoneStatus.notStarted,
    this.alternativePaths = const [],
  });

  factory LearningMilestone.fromJson(Map<String, dynamic> json) => LearningMilestone(
        id: json['id'] as String,
        level: MasteryLevel.fromString(json['level'] as String?),
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        capabilities: (json['capabilities'] as List<dynamic>? ?? []).cast<String>(),
        estimatedHours: (json['estimatedHours'] as num? ?? 1).toDouble(),
        status: MilestoneStatus.fromString(json['status'] as String?),
        alternativePaths: (json['alternativePaths'] as List<dynamic>? ?? [])
            .map((e) => LearningPath.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level.raw,
        'title': title,
        'description': description,
        'capabilities': capabilities,
        'estimatedHours': estimatedHours,
        'status': status.raw,
        'alternativePaths': alternativePaths.map((e) => e.toJson()).toList(),
      };
}

/// A learning journey (container of milestones for a topic).
class LearningJourney {
  final String id;
  final String topicId;
  final List<LearningMilestone> milestones;
  final String? currentMilestoneId;
  final String createdAt;

  const LearningJourney({
    required this.id,
    required this.topicId,
    this.milestones = const [],
    this.currentMilestoneId,
    this.createdAt = '',
  });

  factory LearningJourney.fromJson(Map<String, dynamic> json) => LearningJourney(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        milestones: (json['milestones'] as List<dynamic>? ?? [])
            .map((e) => LearningMilestone.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentMilestoneId: json['currentMilestoneId'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'milestones': milestones.map((e) => e.toJson()).toList(),
        'currentMilestoneId': currentMilestoneId,
        'createdAt': createdAt,
      };
}

/// A learning session.
class LearningSession {
  final String id;
  final String journeyId;
  final String? milestoneId;
  final String topicId;
  final String goal;
  final int timeBudgetMinutes;
  final String startedAt;
  final String? completedAt;
  final SessionStatus status;
  final Curriculum curriculum;
  final int currentIndex;
  final String? activityJson;
  final int currentActivityStep;

  const LearningSession({
    required this.id,
    required this.journeyId,
    this.milestoneId,
    required this.topicId,
    this.goal = 'overview',
    this.timeBudgetMinutes = 60,
    this.startedAt = '',
    this.completedAt,
    this.status = SessionStatus.active,
    this.curriculum = const Curriculum(sessionId: ''),
    this.currentIndex = 0,
    this.activityJson,
    this.currentActivityStep = 0,
  });

  factory LearningSession.fromJson(Map<String, dynamic> json) => LearningSession(
        id: json['id'] as String,
        journeyId: json['journeyId'] as String? ?? '',
        milestoneId: json['milestoneId'] as String?,
        topicId: json['topicId'] as String,
        goal: json['goal'] as String? ?? 'overview',
        timeBudgetMinutes: (json['timeBudgetMinutes'] as num? ?? 60).toInt(),
        startedAt: json['startedAt'] as String? ?? '',
        completedAt: json['completedAt'] as String?,
        status: SessionStatus.fromString(json['status'] as String?),
        curriculum: json['curriculum'] != null
            ? Curriculum.fromJson(json['curriculum'] as Map<String, dynamic>)
            : const Curriculum(sessionId: ''),
        currentIndex: (json['currentIndex'] as num? ?? 0).toInt(),
        activityJson: (json['activityJson'] as String?) ?? (json['activity']?.toString()),
        currentActivityStep: (json['currentActivityStep'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'journeyId': journeyId,
        'milestoneId': milestoneId,
        'topicId': topicId,
        'goal': goal,
        'timeBudgetMinutes': timeBudgetMinutes,
        'startedAt': startedAt,
        'completedAt': completedAt,
        'status': status.raw,
        'curriculum': curriculum.toJson(),
        'currentIndex': currentIndex,
        if (activityJson != null) 'activity': activityJson,
        'currentActivityStep': currentActivityStep,
      };

  LearningSession copyWith({
    SessionStatus? status,
    String? completedAt,
    Curriculum? curriculum,
    int? currentIndex,
    String? Function()? activityJson,
    int? currentActivityStep,
  }) =>
      LearningSession(
        id: id,
        journeyId: journeyId,
        milestoneId: milestoneId,
        topicId: topicId,
        goal: goal,
        timeBudgetMinutes: timeBudgetMinutes,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        curriculum: curriculum ?? this.curriculum,
        currentIndex: currentIndex ?? this.currentIndex,
        activityJson: activityJson != null ? activityJson() : this.activityJson,
        currentActivityStep: currentActivityStep ?? this.currentActivityStep,
      );
}

/// Type of a learning event.
enum LearningEventType {
  explain,
  recall,
  apply,
  assessment,
  synthesis,
  tutorChat;

  static LearningEventType fromString(String? v) {
    switch (v) {
      case 'explain':
        return LearningEventType.explain;
      case 'recall':
        return LearningEventType.recall;
      case 'apply':
        return LearningEventType.apply;
      case 'assessment':
        return LearningEventType.assessment;
      case 'synthesis':
        return LearningEventType.synthesis;
      case 'tutor_chat':
        return LearningEventType.tutorChat;
      default:
        return LearningEventType.explain;
    }
  }

  String get wire {
    switch (this) {
      case LearningEventType.explain:
        return 'explain';
      case LearningEventType.recall:
        return 'recall';
      case LearningEventType.apply:
        return 'apply';
      case LearningEventType.assessment:
        return 'assessment';
      case LearningEventType.synthesis:
        return 'synthesis';
      case LearningEventType.tutorChat:
        return 'tutor_chat';
    }
  }
}

/// A learning event log entry.
class LearningEvent {
  final String id;
  final String sessionId;
  final String timestamp;
  final LearningEventType type;
  final String? nodeId;
  final Map<String, dynamic> data;
  final int durationMs;

  const LearningEvent({
    required this.id,
    required this.sessionId,
    this.timestamp = '',
    required this.type,
    this.nodeId,
    this.data = const {},
    this.durationMs = 0,
  });

  factory LearningEvent.fromJson(Map<String, dynamic> json) => LearningEvent(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        timestamp: json['timestamp'] as String? ?? '',
        type: LearningEventType.fromString(json['type'] as String?),
        nodeId: json['nodeId'] as String?,
        data: json['data'] as Map<String, dynamic>? ?? {},
        durationMs: (json['durationMs'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'timestamp': timestamp,
        'type': type.wire,
        'nodeId': nodeId,
        'data': data,
        'durationMs': durationMs,
      };
}
