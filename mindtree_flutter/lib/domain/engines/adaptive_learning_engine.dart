import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';
import 'learning_session_engine.dart';

class AdaptiveLearningEngine {
  final MindtreeRepository repo;
  final LearnerModelService learnerModel;
  final ReviewScheduler reviewScheduler;
  final LearningSessionEngine sessionEngine;

  AdaptiveLearningEngine({
    required this.repo,
    required this.learnerModel,
    required this.reviewScheduler,
    required this.sessionEngine,
  });

  Future<AdaptiveDecision> nextStep(String sessionId) async {
    final session = await sessionEngine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final reasons = <String>[];

    final dueReviews = await reviewScheduler.upcomingReviews(session.topicId, limit: 5);
    if (dueReviews.isNotEmpty) {
      reasons.add('${dueReviews.length} concepts due for review by schedule');
    }

    final weak = await learnerModel.getWeakConcepts(session.topicId, limit: 3);
    if (weak.isNotEmpty) {
      reasons.add('Weak concepts need reinforcement');
    }

    final remaining = session.curriculum.items
        .where((i) => i.status != CurriculumItemStatus.completed)
        .toList();
    final completed = session.curriculum.items.length - remaining.length;
    final total = session.curriculum.items.isEmpty ? 1 : session.curriculum.items.length;
    final progress = completed / total;

    final eta = await _computeEta(session.id, completed, session.curriculum.items.length,
        session.curriculum.totalEstimatedMinutes);

    if (progress >= 0.85) {
      return AdaptiveDecision(
        recommendedAction: RecommendedAction.finalAssessment,
        dueReviews: dueReviews.map((d) => d.nodeId).toList(),
        reasons: [...reasons, 'Session nearly complete — time for final assessment'],
        eta: eta,
      );
    }

    if (session.currentIndex < session.curriculum.items.length) {
      final currentItem = session.curriculum.items[session.currentIndex];
      if (currentItem.status == CurriculumItemStatus.pending) {
        return AdaptiveDecision(
          recommendedAction: RecommendedAction.studyNext,
          currentItem: currentItem,
          dueReviews: dueReviews.map((d) => d.nodeId).toList(),
          reasons: [...reasons, 'Continue with session schedule'],
          eta: eta,
        );
      }
    }

    return AdaptiveDecision(
      recommendedAction: RecommendedAction.finalAssessment,
      dueReviews: dueReviews.map((d) => d.nodeId).toList(),
      reasons: [...reasons, 'All planned concepts studied'],
      eta: eta,
    );
  }

  // ─── ETA computation (§39–40) ─────────────────────────────────────────────

  Future<SessionEta> _computeEta(
    String sessionId,
    int completedItems,
    int totalItems,
    int baseTotalMinutes,
  ) async {
    final events = await repo.listEvents(sessionId);
    final elapsedMs = events
        .where((e) => e.durationMs > 0)
        .fold<int>(0, (s, e) => s + e.durationMs);
    final elapsedMinutes = (elapsedMs / 60000).floor().clamp(0, 9999);
    return computeEtaFrom(elapsedMinutes, completedItems, totalItems, baseTotalMinutes);
  }

  static SessionEta computeEtaFrom(
    int elapsedMinutes,
    int completedItems,
    int totalItems,
    int baseTotalMinutes,
  ) {
    final totalItemsSafe = totalItems < 1 ? 1 : totalItems;
    final completedSafe = completedItems < 1 ? 1 : completedItems;
    final minutesPerItem = elapsedMinutes / completedSafe;
    final remainingItems = (totalItems - completedItems).clamp(0, totalItems);
    final projectedRemaining = minutesPerItem * remainingItems;

    final plannedMinutesPerItem = baseTotalMinutes / totalItemsSafe;
    final ratio = plannedMinutesPerItem > 0 ? minutesPerItem / plannedMinutesPerItem : 1.0;
    final pace = ratio < 0.85
        ? PaceClass.faster
        : ratio > 1.2
            ? PaceClass.slower
            : PaceClass.onTrack;

    final mid = projectedRemaining < 5 ? 5 : projectedRemaining.round();
    return SessionEta(
      totalEstimatedMinutes: baseTotalMinutes,
      elapsedMinutes: elapsedMinutes,
      completedItems: completedItems,
      totalItems: totalItemsSafe,
      remainingMinutesMin: (mid * 0.6).floor().clamp(0, 9999),
      remainingMinutesMax: (mid * 1.4).ceil(),
      pace: pace,
    );
  }
}
