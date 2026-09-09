import 'dart:math' as math;

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import 'learner_model_service.dart';

class AnalyticsService {
  final MindtreeRepository repo;
  final LearnerModelService learnerModel;

  AnalyticsService({
    required this.repo,
    required this.learnerModel,
  });

  Future<TopicMetrics?> topicMetrics(String topicId) async {
    final topic = await repo.getTopic(topicId);
    if (topic == null) return null;

    final targetLevel = topic.targetLevel;
    final currentLevel = await learnerModel.getCurrentLevel(topicId);
    final initialLevel = await learnerModel.getInitialLevel(topicId);
    final profiles = await learnerModel.getConceptProfiles(topicId);

    final meanMastery = profiles.isNotEmpty
        ? profiles.map((p) => p.masteryScore).reduce((s, v) => s + v) /
            profiles.length
        : 0.0;

    final levelIndex = <String, int>{};
    for (var i = 0; i < MasteryLevel.order.length; i++) {
      levelIndex[MasteryLevel.order[i].raw] = i;
    }

    final currentIdx = levelIndex[currentLevel.raw] ?? 0;
    final initialIdx = levelIndex[initialLevel.raw] ?? 0;
    final learningGain = currentIdx - initialIdx;

    final studyMinutes = await _studyMinutesForTopic(topicId);
    final learningGainPerMinute =
        studyMinutes > 0 ? math.max(0, learningGain) / (studyMinutes / 60) : 0.0;

    final accuracy = await _accuracyByType(topicId);
    double findAccuracy(String type) {
      for (final a in accuracy) {
        if (a['type'] == type) return (a['accuracy'] as num).toDouble();
      }
      return 0;
    }

    final immediateRecall = findAccuracy('recall');
    final applicationAccuracy = findAccuracy('application');
    final transferAccuracy = findAccuracy('transfer');
    final delayedRecall = await _delayedRecall(topicId);

    final sessionCompletion = await _sessionCompletionForTopic(topicId);
    final milestoneProgression =
        await _milestoneProgressionForTopic(topicId);

    final timeToTargetMinutes =
        await _timeToTarget(topicId, targetLevel);

    return TopicMetrics(
      topicId: topicId,
      topicName: topic.name,
      currentLevel: currentLevel,
      targetLevel: targetLevel,
      goal: topic.goal.raw,
      masteryReached: currentIdx >= (levelIndex[targetLevel.raw] ?? 0),
      learningGain: math.max(0, learningGain.toDouble()),
      learningGainPerMinute: learningGainPerMinute,
      meanMastery: meanMastery,
      immediateRecall: immediateRecall,
      delayedRecall: delayedRecall,
      applicationAccuracy: applicationAccuracy,
      transferAccuracy: transferAccuracy,
      sessionCompletion: sessionCompletion,
      milestoneProgression: milestoneProgression,
      timeToTargetMinutes: timeToTargetMinutes,
      studyMinutes: studyMinutes,
      conceptCount: profiles.length,
    );
  }

  Future<AnalyticsSummary> summary() async {
    final topics = await repo.listTopics();
    final topicMetricsList = <TopicMetrics>[];
    for (final t in topics) {
      final m = await topicMetrics(t.id);
      if (m != null) topicMetricsList.add(m);
    }

    final allSessions = <LearningSession>[];
    for (final t in topics) {
      allSessions.addAll(await repo.listSessionsForTopic(t.id));
    }

    final totalSessions = allSessions.length;
    final completedSessions =
        allSessions.where((s) => s.status == SessionStatus.completed).length;

    var totalMilestones = 0;
    var completedMilestones = 0;
    for (final t in topics) {
      final journey = await repo.getJourneyForTopic(t.id);
      if (journey != null) {
        for (final m in journey.milestones) {
          totalMilestones++;
          if (m.status == MilestoneStatus.completed) completedMilestones++;
        }
      }
    }

    final studyMinutes =
        topicMetricsList.fold<int>(0, (s, t) => s + t.studyMinutes);

    return AnalyticsSummary(
      topics: topicMetricsList,
      totals: AnalyticsTotals(
        completedSessions: completedSessions,
        totalSessions: totalSessions,
        sessionCompletion:
            totalSessions > 0 ? completedSessions / totalSessions : 0,
        milestonesCompleted: completedMilestones,
        totalMilestones: totalMilestones,
        milestoneProgression:
            totalMilestones > 0 ? completedMilestones / totalMilestones : 0,
        studyMinutes: studyMinutes,
        meanLearningGain: topicMetricsList.isNotEmpty
            ? topicMetricsList.map((t) => t.learningGain).reduce((s, v) => s + v) /
                topicMetricsList.length
            : 0,
      ),
    );
  }

  // ─── Private helpers ────────────────────────────────────────────────────────

  Future<int> _studyMinutesForTopic(String topicId) async {
    final sessions = await repo.listSessionsForTopic(topicId);
    var totalDurationMs = 0;
    for (final s in sessions) {
      final events = await repo.listEvents(s.id);
      for (final e in events) {
        totalDurationMs += e.durationMs;
      }
    }
    var minutes = (totalDurationMs / 60000).round();

    if (minutes == 0 && sessions.isNotEmpty) {
      final firstStarted = sessions
          .map((s) => s.startedAt)
          .where((s) => s.isNotEmpty)
          .fold<String?>(null, (prev, s) {
        if (prev == null) return s;
        return s.compareTo(prev) < 0 ? s : prev;
      });
      if (firstStarted != null) {
        final start = DateTime.tryParse(firstStarted);
        if (start != null) {
          final now = DateTime.now();
          minutes = (now.difference(start).inMilliseconds / 60000).round();
          minutes = math.min(minutes, sessions.length * 60);
        }
      }
    }
    return minutes;
  }

  Future<List<Map<String, dynamic>>> _accuracyByType(String topicId) async {
    final sessions = await repo.listSessionsForTopic(topicId);
    final assessmentIds = <String>[];
    for (final s in sessions) {
      final assessment = await repo.latestAssessmentForSession(s.id, 'final');
      if (assessment != null) assessmentIds.add(assessment.id);
      final quiz = await repo.latestAssessmentForSession(s.id, 'quiz');
      if (quiz != null) assessmentIds.add(quiz.id);
      final diag = await repo.latestAssessmentForSession(s.id, 'diagnostic');
      if (diag != null) assessmentIds.add(diag.id);
    }

    final byType = <String, _AccuracyBucket>{};

    for (final aId in assessmentIds) {
      final assessment = await repo.getAssessment(aId);
      if (assessment == null) continue;
      final attempts = await repo.listAttempts(aId);

      for (final att in attempts) {
        AssessmentQuestion? q;
        for (final question in assessment.questions) {
          if (question.id == att.questionId) {
            q = question;
            break;
          }
        }
        final type = q?.type.wire ?? 'recall';
        byType.putIfAbsent(type, () => _AccuracyBucket());
        if (att.correct) byType[type]!.correct++;
        byType[type]!.total++;
      }
    }

    return byType.entries
        .map((e) => {
              'type': e.key,
              'accuracy': e.value.total > 0 ? e.value.correct / e.value.total : 0.0,
            })
        .toList();
  }

  Future<double> _delayedRecall(String topicId) async {
    final sessions = await repo.listSessionsForTopic(topicId);
    var correct = 0;
    var total = 0;

    for (final s in sessions) {
      final assessments = <Assessment?>[
        await repo.latestAssessmentForSession(s.id, 'quiz'),
        await repo.latestAssessmentForSession(s.id, 'diagnostic'),
      ];
      for (final assessment in assessments) {
        if (assessment == null) continue;
        final attempts = await repo.listAttempts(assessment.id);
        for (final att in attempts) {
          AssessmentQuestion? q;
          for (final question in assessment.questions) {
            if (question.id == att.questionId) {
              q = question;
              break;
            }
          }
          if ((q?.type.wire ?? 'recall') != 'recall') continue;
          if (att.correct) correct++;
          total++;
        }
      }
    }
    return total > 0 ? correct / total : 0.0;
  }

  Future<double> _sessionCompletionForTopic(String topicId) async {
    final sessions = await repo.listSessionsForTopic(topicId);
    if (sessions.isEmpty) return 0;
    final completed =
        sessions.where((s) => s.status == SessionStatus.completed).length;
    return completed / sessions.length;
  }

  Future<double> _milestoneProgressionForTopic(String topicId) async {
    final journey = await repo.getJourneyForTopic(topicId);
    if (journey == null || journey.milestones.isEmpty) return 0;
    final completed = journey.milestones
        .where((m) => m.status == MilestoneStatus.completed)
        .length;
    return completed / journey.milestones.length;
  }

  Future<int?> _timeToTarget(String topicId, MasteryLevel target) async {
    final currentLevel = await learnerModel.getCurrentLevel(topicId);
    final levelIndex = <String, int>{};
    for (var i = 0; i < MasteryLevel.order.length; i++) {
      levelIndex[MasteryLevel.order[i].raw] = i;
    }
    if ((levelIndex[currentLevel.raw] ?? 0) < (levelIndex[target.raw] ?? 0)) {
      return null;
    }

    final sessions = await repo.listSessionsForTopic(topicId);
    if (sessions.isEmpty) return 0;

    String? firstStarted;
    String? lastCompleted;
    for (final s in sessions) {
      if (s.startedAt.isNotEmpty) {
        if (firstStarted == null || s.startedAt.compareTo(firstStarted) < 0) {
          firstStarted = s.startedAt;
        }
      }
      if (s.completedAt != null && s.completedAt!.isNotEmpty) {
        if (lastCompleted == null || s.completedAt!.compareTo(lastCompleted) > 0) {
          lastCompleted = s.completedAt;
        }
      }
    }

    final anchor = firstStarted != null
        ? (DateTime.tryParse(firstStarted) ?? DateTime.now())
        : DateTime.now();
    final end = lastCompleted != null
        ? (DateTime.tryParse(lastCompleted) ?? DateTime.now())
        : DateTime.now();

    return math.max(0, (end.difference(anchor).inMilliseconds / 60000).round());
  }
}

class _AccuracyBucket {
  int correct = 0;
  int total = 0;
}
