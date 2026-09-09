/// Shared domain primitive types for MindTree.
library;

/// Learning goals a user can select for a topic.
enum LearningGoal {
  overview,
  exam,
  deep;

  static LearningGoal fromString(String? v) =>
      LearningGoal.values.firstWhere((e) => e.name == v, orElse: () => LearningGoal.overview);

  String get raw => name;
}

/// Declared knowledge level (user's prior knowledge).
enum KnowledgeLevel {
  beginner,
  intermediate,
  expert;

  static KnowledgeLevel fromString(String? v) =>
      KnowledgeLevel.values.firstWhere((e) => e.name == v, orElse: () => KnowledgeLevel.beginner);

  String get raw => name;
}

/// Type of a knowledge concept.
enum ConceptType {
  topic,
  concept,
  component,
  mechanism,
  process,
  property,
  rule,
  method,
  example;

  static ConceptType? fromString(String? v) {
    if (v == null) return null;
    try {
      return ConceptType.values.firstWhere((e) => e.name == v);
    } catch (_) {
      return null;
    }
  }

  String get raw => name;
}

/// Relationship type between knowledge nodes.
enum RelationType {
  related,
  dependsOn,
  requires,
  exampleOf,
  similarTo,
  contrastsWith,
  causes,
  enables,
  usedFor,
  alternativeTo;

  static RelationType fromString(String? v) {
    switch (v) {
      case 'depends_on':
        return RelationType.dependsOn;
      case 'example_of':
        return RelationType.exampleOf;
      case 'similar_to':
        return RelationType.similarTo;
      case 'contrasts_with':
        return RelationType.contrastsWith;
      case 'used_for':
        return RelationType.usedFor;
      case 'alternative_to':
        return RelationType.alternativeTo;
      default:
        try {
          return RelationType.values.firstWhere((e) => e.raw == v);
        } catch (_) {
          return RelationType.related;
        }
    }
  }

  /// Raw snake_case wire value (used by LLM/JSON).
  String get raw {
    switch (this) {
      case RelationType.dependsOn:
        return 'depends_on';
      case RelationType.exampleOf:
        return 'example_of';
      case RelationType.similarTo:
        return 'similar_to';
      case RelationType.contrastsWith:
        return 'contrasts_with';
      case RelationType.usedFor:
        return 'used_for';
      case RelationType.alternativeTo:
        return 'alternative_to';
      default:
        return name;
    }
  }
}
