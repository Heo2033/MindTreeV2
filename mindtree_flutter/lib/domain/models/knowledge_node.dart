import 'primitives.dart';

/// Lifecycle state of a knowledge node.
enum NodeState {
  new_,
  structureGenerated,
  expanded,
  validating,
  valid,
  invalid,
  repairing,
  contentPending,
  contentGenerated,
  needsReview,
  failed;

  static NodeState fromString(String v) {
    switch (v) {
      case 'new':
        return NodeState.new_;
      case 'structure_generated':
        return NodeState.structureGenerated;
      case 'expanded':
        return NodeState.expanded;
      case 'validating':
        return NodeState.validating;
      case 'valid':
        return NodeState.valid;
      case 'invalid':
        return NodeState.invalid;
      case 'repairing':
        return NodeState.repairing;
      case 'content_pending':
        return NodeState.contentPending;
      case 'content_generated':
        return NodeState.contentGenerated;
      case 'needs_review':
        return NodeState.needsReview;
      case 'failed':
        return NodeState.failed;
      default:
        return NodeState.new_;
    }
  }

  String get wire {
    switch (this) {
      case NodeState.new_:
        return 'new';
      case NodeState.structureGenerated:
        return 'structure_generated';
      case NodeState.expanded:
        return 'expanded';
      case NodeState.validating:
        return 'validating';
      case NodeState.valid:
        return 'valid';
      case NodeState.invalid:
        return 'invalid';
      case NodeState.repairing:
        return 'repairing';
      case NodeState.contentPending:
        return 'content_pending';
      case NodeState.contentGenerated:
        return 'content_generated';
      case NodeState.needsReview:
        return 'needs_review';
      case NodeState.failed:
        return 'failed';
    }
  }
}

/// A relation between two knowledge nodes.
class Relation {
  final String from;
  final String to;
  final RelationType type;
  final String? label;

  const Relation({required this.from, required this.to, required this.type, this.label});

  factory Relation.fromJson(Map<String, dynamic> json) => Relation(
        from: json['from'] as String,
        to: json['to'] as String,
        type: RelationType.fromString(json['type'] as String?),
        label: json['label'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'type': type.raw,
        if (label != null) 'label': label,
      };
}

/// A step within a learning sequence.
class SequenceStep {
  final String conceptId;
  final int order;
  final String? label;
  final String? description;

  const SequenceStep({required this.conceptId, required this.order, this.label, this.description});

  factory SequenceStep.fromJson(Map<String, dynamic> json) => SequenceStep(
        conceptId: json['conceptId'] as String,
        order: (json['order'] as num).toInt(),
        label: json['label'] as String?,
        description: json['description'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'conceptId': conceptId,
        'order': order,
        if (label != null) 'label': label,
        if (description != null) 'description': description,
      };
}

/// A learning sequence (ordered path through concepts).
class Sequence {
  final String id;
  final String label;
  final List<SequenceStep> steps;
  final String? description;

  const Sequence({required this.id, required this.label, required this.steps, this.description});

  factory Sequence.fromJson(Map<String, dynamic> json) => Sequence(
        id: json['id'] as String,
        label: json['label'] as String,
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => SequenceStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        description: json['description'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'steps': steps.map((e) => e.toJson()).toList(),
        if (description != null) 'description': description,
      };
}

/// A node in the knowledge tree.
class KnowledgeNode {
  final String id;
  final String topicId;
  final String? parentId;
  final int level;
  final String label;
  final String oneLiner;
  final String details;
  final String? analogy;
  final List<String> sources;
  final ConceptType? conceptType;
  final double importance;
  final double difficulty;
  final int estimatedTimeMinutes;
  final NodeState state;
  final bool contentLoaded;
  final bool leaf;
  final List<Relation> relations;
  final List<Sequence> sequences;

  const KnowledgeNode({
    required this.id,
    required this.topicId,
    required this.parentId,
    required this.level,
    required this.label,
    required this.oneLiner,
    required this.details,
    this.analogy,
    this.sources = const [],
    this.conceptType,
    this.importance = 0.5,
    this.difficulty = 0.5,
    this.estimatedTimeMinutes = 5,
    this.state = NodeState.new_,
    this.contentLoaded = false,
    this.leaf = false,
    this.relations = const [],
    this.sequences = const [],
  });

  factory KnowledgeNode.fromJson(Map<String, dynamic> json) => KnowledgeNode(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        parentId: json['parentId'] as String?,
        level: (json['level'] as num).toInt(),
        label: json['label'] as String,
        oneLiner: json['oneLiner'] as String? ?? '',
        details: json['details'] as String? ?? '',
        analogy: json['analogy'] as String?,
        sources: (json['sources'] as List<dynamic>? ?? []).cast<String>(),
        conceptType: ConceptType.fromString(json['conceptType'] as String?),
        importance: (json['importance'] as num? ?? 0.5).toDouble(),
        difficulty: (json['difficulty'] as num? ?? 0.5).toDouble(),
        estimatedTimeMinutes: (json['estimatedTimeMinutes'] as num? ?? 5).toInt(),
        state: NodeState.fromString(json['state'] as String? ?? 'new'),
        contentLoaded: json['contentLoaded'] as bool? ?? false,
        leaf: json['leaf'] as bool? ?? false,
        relations: (json['relations'] as List<dynamic>? ?? [])
            .map((e) => Relation.fromJson(e as Map<String, dynamic>))
            .toList(),
        sequences: (json['sequences'] as List<dynamic>? ?? [])
            .map((e) => Sequence.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'parentId': parentId,
        'level': level,
        'label': label,
        'oneLiner': oneLiner,
        'details': details,
        if (analogy != null) 'analogy': analogy,
        'sources': sources,
        'conceptType': conceptType?.raw,
        'importance': importance,
        'difficulty': difficulty,
        'estimatedTimeMinutes': estimatedTimeMinutes,
        'state': state.wire,
        'contentLoaded': contentLoaded,
        'leaf': leaf,
        'relations': relations.map((e) => e.toJson()).toList(),
        'sequences': sequences.map((e) => e.toJson()).toList(),
      };

  KnowledgeNode copyWith({
    String? id,
    String? topicId,
    String? Function()? parentId,
    int? level,
    String? label,
    String? oneLiner,
    String? details,
    String? Function()? analogy,
    List<String>? sources,
    ConceptType? Function()? conceptType,
    double? importance,
    double? difficulty,
    int? estimatedTimeMinutes,
    NodeState? state,
    bool? contentLoaded,
    bool? leaf,
    List<Relation>? relations,
    List<Sequence>? sequences,
  }) =>
      KnowledgeNode(
        id: id ?? this.id,
        topicId: topicId ?? this.topicId,
        parentId: parentId != null ? parentId() : this.parentId,
        level: level ?? this.level,
        label: label ?? this.label,
        oneLiner: oneLiner ?? this.oneLiner,
        details: details ?? this.details,
        analogy: analogy != null ? analogy() : this.analogy,
        sources: sources ?? this.sources,
        conceptType: conceptType != null ? conceptType() : this.conceptType,
        importance: importance ?? this.importance,
        difficulty: difficulty ?? this.difficulty,
        estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
        state: state ?? this.state,
        contentLoaded: contentLoaded ?? this.contentLoaded,
        leaf: leaf ?? this.leaf,
        relations: relations ?? this.relations,
        sequences: sequences ?? this.sequences,
      );
}
