import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/mindtree_db.dart';
import '../../domain/models/models.dart';

/// Conversions between drift row objects and domain models.
class Mappers {
  static Topic topicFromRow(TopicRowData r) => Topic(
        id: r.id,
        name: r.name,
        goal: LearningGoal.fromString(r.goal),
        targetLevel: MasteryLevel.fromString(r.targetLevel),
        timeBudgetMinutes: r.timeBudgetMinutes,
        createdAt: r.createdAt.toIso8601String(),
      );

  static TopicsCompanion topicToRow(Topic t) => TopicsCompanion(
        id: Value(t.id),
        name: Value(t.name),
        goal: Value(t.goal.raw),
        targetLevel: Value(t.targetLevel.raw),
        timeBudgetMinutes: Value(t.timeBudgetMinutes),
      );

  static KnowledgeNode nodeFromRow(KnowledgeNodeRowData r) => KnowledgeNode(
        id: r.id,
        topicId: r.topicId,
        parentId: r.parentId,
        level: r.level,
        label: r.label,
        oneLiner: r.oneLiner,
        details: r.details,
        analogy: r.analogy,
        sources: _strList(r.sourcesJson),
        conceptType: ConceptType.fromString(r.conceptType),
        importance: r.importance,
        difficulty: r.difficulty,
        estimatedTimeMinutes: r.estimatedTimeMinutes,
        state: NodeState.fromString(r.state),
        contentLoaded: r.contentLoaded,
        leaf: r.leaf,
        relations: _relations(r.relationsJson),
        sequences: _sequences(r.sequencesJson),
      );

  static KnowledgeNodesCompanion nodeToRow(KnowledgeNode n) {
    final nodeToCompanion = KnowledgeNodesCompanion(
      id: Value(n.id),
      topicId: Value(n.topicId),
      parentId: Value(n.parentId),
      level: Value(n.level),
      label: Value(n.label),
      oneLiner: Value(n.oneLiner),
      details: Value(n.details),
      analogy: Value(n.analogy),
      conceptType: Value(n.conceptType?.raw),
      importance: Value(n.importance),
      difficulty: Value(n.difficulty),
      estimatedTimeMinutes: Value(n.estimatedTimeMinutes),
      state: Value(n.state.wire),
      contentLoaded: Value(n.contentLoaded),
      leaf: Value(n.leaf),
      relationsJson: Value(jsonEncode(n.relations.map((e) => e.toJson()).toList())),
      sequencesJson: Value(jsonEncode(n.sequences.map((e) => e.toJson()).toList())),
      sourcesJson: Value(jsonEncode(n.sources)),
    );
    return nodeToCompanion;
  }

  static LearningJourney journeyFromRow(LearningJourneyRowData r, List<LearningMilestone> milestones) =>
      LearningJourney(
        id: r.id,
        topicId: r.topicId,
        milestones: milestones,
        createdAt: r.createdAt.toIso8601String(),
      );

  static LearningMilestone milestoneFromRow(LearningMilestoneRowData r) => LearningMilestone(
        id: r.id,
        level: MasteryLevel.fromString(r.level),
        title: r.title,
        description: r.description,
        capabilities: _strList(r.capabilitiesJson),
        estimatedHours: r.estimatedHours,
        status: MilestoneStatus.fromString(r.status),
        alternativePaths: (jsonDecode(r.alternativePathsJson) as List<dynamic>?)
                ?.map((e) => LearningPath.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  static LearningMilestonesCompanion milestoneToRow(LearningMilestone m, {String journeyId = ''}) =>
      LearningMilestonesCompanion(
        id: Value(m.id),
        journeyId: Value(journeyId),
        level: Value(m.level.raw),
        title: Value(m.title),
        description: Value(m.description),
        capabilitiesJson: Value(jsonEncode(m.capabilities)),
        estimatedHours: Value(m.estimatedHours),
        status: Value(m.status.raw),
        alternativePathsJson: Value(jsonEncode(m.alternativePaths.map((e) => e.toJson()).toList())),
      );

  static LearningSession sessionFromRow(LearningSessionRowData r) {
    Curriculum? curriculum;
    try {
      curriculum = Curriculum.fromJson(
        jsonDecode(r.curriculumJson) as Map<String, dynamic>,
      );
    } catch (_) {
      curriculum = const Curriculum(sessionId: '');
    }
    return LearningSession(
      id: r.id,
      journeyId: r.journeyId,
      milestoneId: r.milestoneId,
      topicId: r.topicId,
      goal: r.goal,
      timeBudgetMinutes: r.timeBudgetMinutes,
      startedAt: r.startedAt.toIso8601String(),
      completedAt: r.completedAt?.toIso8601String(),
      status: SessionStatus.fromString(r.status),
      curriculum: curriculum,
      currentIndex: r.currentIndex,
      activityJson: r.activityJson,
      currentActivityStep: r.currentActivityStep,
    );
  }

  static LearningSessionsCompanion sessionToRow(LearningSession s) => LearningSessionsCompanion(
        id: Value(s.id),
        journeyId: Value(s.journeyId),
        milestoneId: Value(s.milestoneId),
        topicId: Value(s.topicId),
        goal: Value(s.goal),
        timeBudgetMinutes: Value(s.timeBudgetMinutes),
        completedAt: Value(s.completedAt == null ? null : DateTime.tryParse(s.completedAt!)),
        status: Value(s.status.raw),
        curriculumJson: Value(jsonEncode(s.curriculum.toJson())),
        currentIndex: Value(s.currentIndex),
        activityJson: Value(s.activityJson ?? '[]'),
        currentActivityStep: Value(s.currentActivityStep),
      );

  static LearningEvent eventFromRow(LearningEventRowData r) => LearningEvent(
        id: r.id,
        sessionId: r.sessionId,
        timestamp: r.timestamp.toIso8601String(),
        type: LearningEventType.fromString(r.type),
        nodeId: r.nodeId,
        data: (jsonDecode(r.dataJson) as Map<String, dynamic>?) ?? {},
        durationMs: r.durationMs,
      );

  static LearnerModel learnerModelFromRow(LearnerModelRowData r) => LearnerModel(
        id: r.id,
        userId: r.userId,
        topicId: r.topicId,
        overallLevel: MasteryLevel.fromString(r.overallLevel),
        conceptMasteries: (jsonDecode(r.conceptMasteriesJson) as List<dynamic>?)
                ?.map((e) => ConceptMastery.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        updatedAt: r.updatedAt.toIso8601String(),
        initialOverallLevel: MasteryLevel.fromString(r.initialOverallLevel),
      );

  static LearnerModelsCompanion learnerModelToRow(LearnerModel m) => LearnerModelsCompanion(
        id: Value(m.id),
        userId: Value(m.userId),
        topicId: Value(m.topicId),
        overallLevel: Value(m.overallLevel.raw),
        conceptMasteriesJson: Value(jsonEncode(m.conceptMasteries.map((e) => e.toJson()).toList())),
        initialOverallLevel: Value(m.initialOverallLevel.raw),
      );

  static Assessment assessmentFromRow(AssessmentRowData r) => Assessment(
        id: r.id,
        sessionId: r.sessionId,
        type: AssessmentType.fromString(r.type),
        questions: (jsonDecode(r.questionsJson) as List<dynamic>?)
                ?.map((e) => AssessmentQuestion.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        startedAt: r.startedAt.toIso8601String(),
        completedAt: r.completedAt?.toIso8601String(),
        score: r.score,
      );

  static AssessmentsCompanion assessmentToRow(Assessment a) => AssessmentsCompanion(
        id: Value(a.id),
        sessionId: Value(a.sessionId),
        type: Value(a.type.wire),
        questionsJson: Value(jsonEncode(a.questions.map((e) => e.toJson()).toList())),
        completedAt: Value(a.completedAt == null ? null : DateTime.tryParse(a.completedAt!)),
        score: Value(a.score),
      );

  static Attempt attemptFromRow(AssessmentAttemptRowData r) => Attempt(
        id: r.id,
        assessmentId: r.assessmentId,
        questionId: r.questionId,
        answer: r.answer,
        correct: r.correct,
        timeSpentMs: r.timeSpentMs,
        feedback: r.feedback,
      );

  static AssessmentAttemptsCompanion attemptToRow(Attempt a) => AssessmentAttemptsCompanion(
        id: Value(a.id),
        assessmentId: Value(a.assessmentId),
        questionId: Value(a.questionId),
        answer: Value(a.answer),
        correct: Value(a.correct),
        timeSpentMs: Value(a.timeSpentMs),
        feedback: Value(a.feedback),
      );

  static List<String> _strList(String json) {
    try {
      return (jsonDecode(json) as List<dynamic>?)?.cast<String>() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static List<Relation> _relations(String json) {
    try {
      return (jsonDecode(json) as List<dynamic>?)
              ?.map((e) => Relation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  static List<Sequence> _sequences(String json) {
    try {
      return (jsonDecode(json) as List<dynamic>?)
              ?.map((e) => Sequence.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }
}
