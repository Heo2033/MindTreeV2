import 'package:mindtree_flutter/domain/lib/srs.dart';
import '../models/models.dart';
import 'learner_model_service.dart';
import '../../data/database/mindtree_repository.dart';

/// SRS-backed review scheduler.
class ReviewScheduler {
  final LearnerModelService _learnerModel;
  final MindtreeRepository repo;

  ReviewScheduler(this.repo) : _learnerModel = LearnerModelService(repo);

  /// Записать ответ по теме/узлу: SRS + (необязательно) свидетельства.
  ///
  /// Разделение ответственности:
  /// - [quality] ('correct' | 'again' | 'incorrect') уходит в SM-2
  ///   (`scheduleReview`): 'incorrect'/'again' обнуляют интервал, 'correct'
  ///   двигает его вперёд.
  /// - [evidence] — измерения, по которым ответ даёт свидетельство. Если не
  ///   переданы, берётся [defaultEvidence]. Шаги активности и экзамены
  ///   передают своё (у них своя типология измерений), а «завершил концепт»
  ///   передаёт пустую карту: это отметка о закрытии пункта плана, а не ответ —
  ///   расти мастерству ей не за что.
  /// - [recordCareless] — писать ли мисконцепцию `careless` под 'incorrect'.
  ///   Вызывающий, который уже записал тип ошибки точнее (см. `FeedbackEngine`),
  ///   её выключает.
  ///
  /// Измерения пишутся ТОЛЬКО здесь и ТОЛЬКО через `recordEvidence`. Раньше
  /// метод подмешивал `+0.15 recall` / `+0.1 understanding` поверх бленда,
  /// который уже сделал `FeedbackEngine`: recall получал двойную порцию, а
  /// application/transfer по одной, и модель разъезжалась с ответами.
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {
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

    final dims = evidence ?? defaultEvidence(quality);
    if (dims.isNotEmpty) {
      await _learnerModel.recordEvidence(topicId, nodeId, dims);
    }

    if (quality == 'incorrect' && recordCareless) {
      // Ложная мисконцепция пишется только под 'incorrect' — про ответ на
      // карточке повторения. 'again' означает «нужен повтор скоро»
      // (см. вывод качества в `deriveCompletionQuality`), и это НЕ «небрежный
      // ответ на повторении»: раньше ветка else ловила любое не-'correct' и
      // засоряла модель выдуманной ошибкой.
      await _learnerModel.addMisconception(
        topicId,
        nodeId,
        MisconceptionType.careless,
        MisconceptionType.careless.defaultDescription,
      );
    }
  }

  /// Свидетельство по умолчанию для вызывающих без своей типологии.
  ///
  /// Карточка повторения — это чистая проверка памяти по узлу: верный ответ
  /// подтверждает `recall`, неверный — опровергает. Считается один раз и той
  /// же формулой накопления, что и остальные измерения.
  static Map<String, double> defaultEvidence(String quality) => {
        dimRecall: quality == 'correct' ? 1.0 : 0.0,
      };

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
