import '../models/mastery.dart';
import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';

/// Type of the four mastery skill dimensions.
typedef SkillDimension = String;
const String dimUnderstanding = 'understanding';
const String dimRecall = 'recall';
const String dimApplication = 'application';
const String dimTransfer = 'transfer';

/// A computed concept profile with SRS fields flattened in.
class ConceptProfile {
  final String nodeId;
  final double understanding;
  final double recall;
  final double application;
  final double transfer;
  final double confidence;
  final List<Misconception> errors;
  final String lastAssessedAt;
  final double masteryScore;
  final String? lastReviewedAt;
  final int reviewCount;
  final int srsInterval;
  final double srsEase;
  final String? srsDueAt;

  const ConceptProfile({
    required this.nodeId,
    required this.understanding,
    required this.recall,
    required this.application,
    required this.transfer,
    required this.confidence,
    required this.errors,
    required this.lastAssessedAt,
    required this.masteryScore,
    this.lastReviewedAt,
    this.reviewCount = 0,
    this.srsInterval = 0,
    this.srsEase = 2.5,
    this.srsDueAt,
  });

  factory ConceptProfile.fromMastery(ConceptMastery cm) {
    final average =
        (cm.understanding + cm.recall + cm.application + cm.transfer) / 4;
    return ConceptProfile(
      nodeId: cm.nodeId,
      understanding: cm.understanding,
      recall: cm.recall,
      application: cm.application,
      transfer: cm.transfer,
      confidence: cm.confidence,
      errors: cm.errors,
      lastAssessedAt: cm.lastAssessedAt,
      masteryScore: average,
      lastReviewedAt: cm.lastReviewedAt,
      reviewCount: cm.reviewCount,
      srsInterval: cm.srsInterval,
      srsEase: cm.srsEase,
      srsDueAt: cm.srsDueAt,
    );
  }
}

/// Manages persistent learner mastery per topic, backed by the repository.
class LearnerModelService {
  final MindtreeRepository repo;
  static const String userId = 'default';

  LearnerModelService(this.repo);

  String _now() => DateTime.now().toIso8601String();

  Future<LearnerModel> getModel(String topicId) async {
    final m = await repo.getLearnerModel(topicId);
    if (m != null) return m;
    final created = LearnerModel(
      id: topicId,
      userId: userId,
      topicId: topicId,
      conceptMasteries: const [],
      updatedAt: _now(),
      initialOverallLevel: MasteryLevel.awareness,
    );
    await repo.saveLearnerModel(created);
    return created;
  }

  /// Отдаёт список мастери, который вызывающий код может свободно менять
  /// (`_findOrCreate`/`_replace` делают list.add). `const []` немодифицируемый,
  /// поэтому при отсутствии строки learner_model отдаём growable-копию —
  /// иначе первое же обновление мастери падало бы с
  /// «Cannot add to an unmodifiable list».
  Future<List<ConceptMastery>> _masteriesOf(String topicId) async {
    final m = await repo.getLearnerModel(topicId);
    return List<ConceptMastery>.from(
      m?.conceptMasteries ?? const <ConceptMastery>[],
    );
  }

  Future<void> _saveMasteries(String topicId, List<ConceptMastery> masteries) async {
    final m = await getModel(topicId);
    await repo.saveLearnerModel(LearnerModel(
      id: m.id,
      userId: m.userId,
      topicId: topicId,
      overallLevel: m.overallLevel,
      conceptMasteries: masteries,
      updatedAt: _now(),
      initialOverallLevel: m.initialOverallLevel,
    ));
  }

  Future<MasteryLevel> getInitialLevel(String topicId) async =>
      (await getModel(topicId)).initialOverallLevel;

  Future<MasteryLevel> getCurrentLevel(String topicId) async =>
      (await getModel(topicId)).overallLevel;

  Future<List<ConceptProfile>> getConceptProfiles(String topicId) async =>
      (await _masteriesOf(topicId)).map(ConceptProfile.fromMastery).toList();

  Future<void> setOverallLevel(String topicId, MasteryLevel level) async {
    final m = await getModel(topicId);
    await repo.saveLearnerModel(LearnerModel(
      id: m.id,
      userId: m.userId,
      topicId: topicId,
      overallLevel: level,
      conceptMasteries: m.conceptMasteries,
      updatedAt: _now(),
      initialOverallLevel: m.initialOverallLevel,
    ));
  }

  Future<ConceptProfile?> getConceptProfile(String nodeId, String topicId) async {
    final masteries = await _masteriesOf(topicId);
    for (final cm in masteries) {
      if (cm.nodeId == nodeId) return ConceptProfile.fromMastery(cm);
    }
    return null;
  }

  Future<void> updateMasteryDimensions(
    String topicId,
    String nodeId,
    Map<String, double> dims,
  ) async {
    final masteries = await _masteriesOf(topicId);
    var cm = _findOrCreate(masteries, nodeId);
    if (dims.containsKey(dimUnderstanding)) {
      cm = cm.copyWith(understanding: _clamp01(dims[dimUnderstanding]!));
    }
    if (dims.containsKey(dimRecall)) {
      cm = cm.copyWith(recall: _clamp01(dims[dimRecall]!));
    }
    if (dims.containsKey(dimApplication)) {
      cm = cm.copyWith(application: _clamp01(dims[dimApplication]!));
    }
    if (dims.containsKey(dimTransfer)) {
      cm = cm.copyWith(transfer: _clamp01(dims[dimTransfer]!));
    }
    cm = cm.copyWith(lastAssessedAt: _now(), confidence: cm.average);
    _replace(masteries, cm);
    await _saveMasteries(topicId, masteries);
  }

  Future<void> addMisconception(
    String topicId,
    String nodeId,
    MisconceptionType type,
    String description,
  ) async {
    final masteries = await _masteriesOf(topicId);
    var cm = _findOrCreate(masteries, nodeId);
    cm = cm.copyWith(
      errors: [
        ...cm.errors,
        Misconception(
          nodeId: nodeId,
          type: type,
          description: description,
          detectedAt: _now(),
        ),
      ],
    );
    _replace(masteries, cm);
    await _saveMasteries(topicId, masteries);
  }

  Future<void> updateMisconception(
    String topicId,
    String nodeId,
    MisconceptionType? type,
    String? description,
  ) async {
    final masteries = await _masteriesOf(topicId);
    final idx = masteries.indexWhere((c) => c.nodeId == nodeId);
    if (idx < 0) return;
    if (type == null) {
      masteries[idx] = masteries[idx].copyWith(errors: []);
    } else {
      masteries[idx] = masteries[idx].copyWith(
        errors: [
          ...masteries[idx].errors,
          Misconception(
            nodeId: nodeId,
            type: type,
            description: description ?? '',
            detectedAt: _now(),
          ),
        ],
      );
    }
    await _saveMasteries(topicId, masteries);
  }

  Future<void> updateSrs(
    String topicId,
    String nodeId,
    ({int interval, double ease, String dueAt}) srs,
  ) async {
    final masteries = await _masteriesOf(topicId);
    final cm = _findOrCreate(masteries, nodeId);
    final updated = cm.copyWith(
      lastReviewedAt: () => _now(),
      reviewCount: cm.reviewCount + 1,
      srsInterval: srs.interval,
      srsEase: srs.ease,
      srsDueAt: () => srs.dueAt,
    );
    _replace(masteries, updated);
    await _saveMasteries(topicId, masteries);
  }

  Future<List<String>> getWeakConcepts(String topicId, {int limit = 10}) async {
    final masteries = await _masteriesOf(topicId);
    final profiles = masteries.map(ConceptProfile.fromMastery).toList()
      ..sort((a, b) => a.masteryScore.compareTo(b.masteryScore));
    return profiles
        .where((p) => p.masteryScore < 0.6)
        .take(limit)
        .map((p) => p.nodeId)
        .toList();
  }

  Future<List<String>> getDueConcepts(String topicId, {int limit = 10}) async {
    final masteries = await _masteriesOf(topicId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final profiles = masteries.map(ConceptProfile.fromMastery).toList()
      ..sort((a, b) => (a.srsDueAt ?? '0').compareTo(b.srsDueAt ?? '0'));
    return profiles
        .where((p) {
          if (p.srsDueAt == null) return true;
          final t = DateTime.tryParse(p.srsDueAt!);
          return t == null || t.millisecondsSinceEpoch <= now;
        })
        .take(limit)
        .map((p) => p.nodeId)
        .toList();
  }

  static ConceptMastery _findOrCreate(List<ConceptMastery> list, String nodeId) {
    for (final cm in list) {
      if (cm.nodeId == nodeId) return cm;
    }
    final created = ConceptMastery(nodeId: nodeId, lastAssessedAt: DateTime.now().toIso8601String());
    list.add(created);
    return created;
  }

  static void _replace(List<ConceptMastery> list, ConceptMastery cm) {
    final idx = list.indexWhere((c) => c.nodeId == cm.nodeId);
    if (idx >= 0) {
      list[idx] = cm;
    } else {
      list.add(cm);
    }
  }

  static double _clamp01(double n) => n < 0 ? 0 : (n > 1 ? 1 : n);
}
