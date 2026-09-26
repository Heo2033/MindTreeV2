import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart' show parseLLMJson;
import '../../data/prompts/prompts.dart';
import 'learner_model_service.dart';

class MasteryItem {
  final String nodeId;
  final String label;
  final String type;
  final String userAnswer;
  final bool? correct;
  final String? rubric;

  const MasteryItem({
    required this.nodeId,
    required this.label,
    required this.type,
    required this.userAnswer,
    this.correct,
    this.rubric,
  });
}

class MasteryEngine {
  final MindtreeRepository repo;
  final LearnerModelService learnerModel;
  final TreeScheduler scheduler;

  MasteryEngine({
    required this.repo,
    required this.learnerModel,
    required this.scheduler,
  });

  Future<MasteryEvaluation> evaluate(
    String topicId,
    List<MasteryItem> items,
    String targetLevel,
  ) async {
    final topic = await repo.getTopic(topicId);

    MasteryResult? mastery;
    try {
      final prompt = buildMasteryPrompt(
        topic: topic?.name ?? '',
        targetLevel: targetLevel,
        items: items.map((i) => {
          'nodeId': i.nodeId,
          'label': i.label,
          'type': i.type,
          'userAnswer': i.userAnswer.length > 800 ? i.userAnswer.substring(0, 800) : i.userAnswer,
          'correct': i.correct,
          'rubric': i.rubric != null
              ? (i.rubric!.length > 400 ? i.rubric!.substring(0, 400) : i.rubric)
              : null,
        }).toList(),
      );
      final res = await scheduler.execute<Map<String, dynamic>>(
        'mastery',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      mastery = _parseMasteryResult(res.result);
    } catch (_) {
      mastery = _heuristic(items);
    }

    final perConcept = <String, double>{};
    for (final c in mastery.concepts) {
      await learnerModel.updateMasteryDimensions(topicId, c.nodeId, {
        'understanding': c.understanding,
        'recall': c.recall,
        'application': c.application,
        'transfer': c.transfer,
      });
      if (c.misconception != null) {
        await learnerModel.addMisconception(
          topicId,
          c.nodeId,
          MisconceptionType.fromString(c.misconception!['type'] as String? ?? 'unknown'),
          c.misconception!['description'] as String? ?? '',
        );
      }
      final score = c.confidence > 0
          ? c.confidence
          : _average([c.understanding]);
      perConcept[c.nodeId] = score;
    }

    final scores = perConcept.values.toList();
    final overallScore = _average(scores);
    final newLevel = levelFromScore(overallScore);
    await learnerModel.setOverallLevel(topicId, newLevel);

    final targetIndex = MasteryLevel.order.indexWhere(
      (l) => l.raw == targetLevel,
    );
    final reachedTarget = targetIndex >= 0 &&
        overallScore >= targetIndex / (MasteryLevel.order.length - 1) - 0.15;

    return MasteryEvaluation(
      topicId: topicId,
      newLevel: newLevel,
      score: overallScore,
      reachedTarget: mastery.enough ? true : reachedTarget,
      perConcept: perConcept,
      gaps: mastery.gaps,
    );
  }

  MasteryResult _heuristic(List<MasteryItem> items) {
    final byNode = <String, List<MasteryItem>>{};
    for (final item in items) {
      byNode.putIfAbsent(item.nodeId, () => []).add(item);
    }

    final concepts = byNode.entries.map((e) {
      final list = e.value;
      final correctCount = list.where((i) => i.correct == true).length;
      final ratio = list.isNotEmpty ? correctCount / list.length : 0.0;
      return MasteryConceptResult(
        nodeId: e.key,
        understanding: ratio,
        recall: ratio,
        application: ratio,
        transfer: ratio * 0.7,
        confidence: ratio,
        misconception: null,
      );
    }).toList();

    final avg = _average(concepts.map((c) => c.understanding).toList());
    return MasteryResult(
      concepts: concepts,
      enough: avg >= 0.6,
      overallLevel: levelFromScore(avg).raw,
      gaps: avg < 0.6
          ? ['Требуется дополнительное закрепление ключевых понятий']
          : [],
    );
  }

  MasteryResult _parseMasteryResult(Map<String, dynamic> data) {
    final conceptsRaw = data['concepts'];
    final List<MasteryConceptResult> concepts = conceptsRaw is List
        ? conceptsRaw.whereType<Map<String, dynamic>>().map((c) {
            final miscon = c['misconception'];
            return MasteryConceptResult(
              nodeId: c['nodeId'] as String? ?? '',
              understanding: (c['understanding'] as num? ?? 0).toDouble(),
              recall: (c['recall'] as num? ?? 0).toDouble(),
              application: (c['application'] as num? ?? 0).toDouble(),
              transfer: (c['transfer'] as num? ?? 0).toDouble(),
              confidence: (c['confidence'] as num? ?? 0).toDouble(),
              misconception: miscon is Map<String, dynamic>
                  ? miscon
                  : null,
            );
          }).toList()
        : [];

    return MasteryResult(
      concepts: concepts,
      enough: data['enough'] == true,
      overallLevel:
          data['overall_level'] as String? ?? 'awareness',
      gaps: data['gaps'] is List
          ? (data['gaps'] as List).whereType<String>().toList()
          : [],
    );
  }

  static double _average(List<double> arr) {
    if (arr.isEmpty) return 0;
    return arr.reduce((s, n) => s + n) / arr.length;
  }
}

MasteryLevel levelFromScore(double score) {
  final n = MasteryLevel.order.length;
  var idx = 0;
  for (var i = 0; i < n; i++) {
    if (score >= i / (n - 1) - 0.08) idx = i;
  }
  return MasteryLevel.order[idx];
}

class MasteryResult {
  final List<MasteryConceptResult> concepts;
  final bool enough;
  final String overallLevel;
  final List<String> gaps;

  const MasteryResult({
    required this.concepts,
    required this.enough,
    required this.overallLevel,
    required this.gaps,
  });
}

class MasteryConceptResult {
  final String nodeId;
  final double understanding;
  final double recall;
  final double application;
  final double transfer;
  final double confidence;
  final Map<String, dynamic>? misconception;

  const MasteryConceptResult({
    required this.nodeId,
    required this.understanding,
    required this.recall,
    required this.application,
    required this.transfer,
    required this.confidence,
    this.misconception,
  });
}
