import 'package:mindtree_flutter/domain/lib/srs.dart';
import '../models/models.dart';
import 'learner_model_service.dart';
import '../../data/database/mindtree_repository.dart';

/// SRS-backed review scheduler.
class ReviewScheduler {
  final LearnerModelService _learnerModel;
  final MindtreeRepository repo;

  ReviewScheduler(this.repo) : _learnerModel = LearnerModelService(repo);

  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality,
  ) async {
    final profile = await _learnerModel.getConceptProfile(nodeId, topicId);
    final prev = profile != null
        ? SrsState(
            interval: profile.srsInterval,
            ease: profile.srsEase,
            reps: profile.reviewCount,
            dueAt: profile.srsDueAt ?? DateTime.now().toIso8601String(),
          )
        : null;

    final next = scheduleReview(prev, quality);
    await _learnerModel.updateSrs(topicId, nodeId,
        (interval: next.interval, ease: next.ease, dueAt: next.dueAt));

    if (quality == 'correct') {
      final p = await _learnerModel.getConceptProfile(nodeId, topicId);
      if (p != null) {
        final rec = p.recall + 0.15 > 1.0 ? 1.0 : p.recall + 0.15;
        final und = p.understanding + 0.1 > 1.0 ? 1.0 : p.understanding + 0.1;
        await _learnerModel.updateMasteryDimensions(topicId, nodeId, {
          dimRecall: rec,
          dimUnderstanding: und,
        });
      }
    } else {
      await _learnerModel.addMisconception(
        topicId,
        nodeId,
        MisconceptionType.careless,
        'Ответ был неверным при повторении',
      );
    }
  }

  Future<bool> isDueNode(String nodeId, String topicId) async {
    final p = await _learnerModel.getConceptProfile(nodeId, topicId);
    if (p == null) return true;
    return isDue(SrsState(
      interval: p.srsInterval,
      ease: p.srsEase,
      reps: p.reviewCount,
      dueAt: p.srsDueAt ?? DateTime.now().toIso8601String(),
    ));
  }

  Future<List<({String nodeId, String? dueAt})>> upcomingReviews(
    String topicId, {
    int limit = 10,
  }) async {
    final nodes = await repo.listNodes(topicId);
    // Батч-чтение профилей одним запросом: раньше каждый узел делал
    // собственный getLearnerModel (N+1) — на тему с сотней узлов это сто
    // последовательных SELECT.
    final profiles = await _learnerModel.getConceptProfiles(topicId);
    final byNode = {
      for (final p in profiles) p.nodeId: p,
    };

    final due = <({String nodeId, String? dueAt})>[];
    for (final n in nodes) {
      final p = byNode[n.id];
      if (p == null || isDue(SrsState(
            interval: p.srsInterval,
            ease: p.srsEase,
            reps: p.reviewCount,
            dueAt: p.srsDueAt ?? DateTime.now().toIso8601String(),
          ))) {
        due.add((nodeId: n.id, dueAt: p?.srsDueAt));
      }
    }
    due.sort((a, b) => (a.dueAt ?? '0').compareTo(b.dueAt ?? '0'));
    return due.take(limit).toList();
  }
}
