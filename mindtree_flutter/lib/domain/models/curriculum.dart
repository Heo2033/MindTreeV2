/// Type of a curriculum item (learning step type).
enum CurriculumItemType {
  explain,
  example,
  recall,
  apply,
  assessment,
  synthesis;

  static CurriculumItemType fromString(String? v) =>
      CurriculumItemType.values.firstWhere((e) => e.name == v, orElse: () => CurriculumItemType.explain);

  String get raw => name;
}

/// Status of a curriculum item within a session.
enum CurriculumItemStatus {
  pending,
  active,
  completed,
  skipped;

  static CurriculumItemStatus fromString(String? v) => CurriculumItemStatus.values
      .firstWhere((e) => e.name == v, orElse: () => CurriculumItemStatus.pending);

  String get raw => name;
}

/// A single item in a learning curriculum.
class CurriculumItem {
  final String id;
  final String nodeId;
  final String? label;
  final int order;
  final CurriculumItemType type;
  final int estimatedMinutes;
  final double priority;
  final CurriculumItemStatus status;
  final String? content;
  final String? reason;

  const CurriculumItem({
    required this.id,
    required this.nodeId,
    this.label,
    required this.order,
    this.type = CurriculumItemType.explain,
    this.estimatedMinutes = 5,
    this.priority = 0,
    this.status = CurriculumItemStatus.pending,
    this.content,
    this.reason,
  });

  factory CurriculumItem.fromJson(Map<String, dynamic> json) => CurriculumItem(
        id: json['id'] as String,
        nodeId: json['nodeId'] as String,
        label: json['label'] as String?,
        order: (json['order'] as num? ?? 0).toInt(),
        type: CurriculumItemType.fromString(json['type'] as String?),
        estimatedMinutes: (json['estimatedMinutes'] as num? ?? 5).toInt(),
        priority: (json['priority'] as num? ?? 0).toDouble(),
        status: CurriculumItemStatus.fromString(json['status'] as String?),
        content: json['content'] as String?,
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nodeId': nodeId,
        if (label != null) 'label': label,
        'order': order,
        'type': type.raw,
        'estimatedMinutes': estimatedMinutes,
        'priority': priority,
        'status': status.raw,
        if (content != null) 'content': content,
        if (reason != null) 'reason': reason,
      };

  CurriculumItem copyWith({CurriculumItemStatus? status}) => CurriculumItem(
        id: id,
        nodeId: nodeId,
        label: label,
        order: order,
        type: type,
        estimatedMinutes: estimatedMinutes,
        priority: priority,
        status: status ?? this.status,
        content: content,
        reason: reason,
      );
}

/// A learning curriculum for a session.
class Curriculum {
  final String sessionId;
  final List<CurriculumItem> items;
  final int totalEstimatedMinutes;

  const Curriculum({
    required this.sessionId,
    this.items = const [],
    this.totalEstimatedMinutes = 0,
  });

  factory Curriculum.fromJson(Map<String, dynamic> json) => Curriculum(
        sessionId: json['sessionId'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => CurriculumItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalEstimatedMinutes: (json['totalEstimatedMinutes'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'items': items.map((e) => e.toJson()).toList(),
        'totalEstimatedMinutes': totalEstimatedMinutes,
      };
}
