import 'mastery.dart';
import 'primitives.dart';
import 'knowledge_node.dart';

/// A learning topic created by the user.
class Topic {
  final String id;
  final String name;
  final LearningGoal goal;
  final MasteryLevel targetLevel;
  final int timeBudgetMinutes;
  final String createdAt;

  const Topic({
    required this.id,
    required this.name,
    this.goal = LearningGoal.overview,
    this.targetLevel = MasteryLevel.basicUnderstanding,
    this.timeBudgetMinutes = 60,
    this.createdAt = '',
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] as String,
        name: json['name'] as String,
        goal: LearningGoal.fromString(json['goal'] as String?),
        targetLevel: MasteryLevel.fromString(json['targetLevel'] as String?),
        timeBudgetMinutes: (json['timeBudgetMinutes'] as num? ?? 60).toInt(),
        createdAt: json['createdAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal.raw,
        'targetLevel': targetLevel.raw,
        'timeBudgetMinutes': timeBudgetMinutes,
        'createdAt': createdAt,
      };
}

/// A topic together with its full knowledge tree.
class TopicWithNodes {
  final Topic topic;
  final List<KnowledgeNode> nodes;

  const TopicWithNodes({required this.topic, this.nodes = const []});
}
