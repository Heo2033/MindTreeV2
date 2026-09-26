import 'dart:math';

import '../models/models.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import '../../data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';

// ─── LLM parse types ─────────────────────────────────────────────────────────

class MilestoneAlternativePathResult {
  final String id;
  final String title;
  final double estimatedHours;
  final String description;

  const MilestoneAlternativePathResult({
    required this.id,
    required this.title,
    required this.estimatedHours,
    required this.description,
  });
}

class MilestoneResultItem {
  final String id;
  final String level;
  final String title;
  final String description;
  final List<String> capabilities;
  final double estimatedHours;
  final List<MilestoneAlternativePathResult> alternativePaths;

  const MilestoneResultItem({
    required this.id,
    required this.level,
    required this.title,
    required this.description,
    required this.capabilities,
    required this.estimatedHours,
    required this.alternativePaths,
  });
}

class MilestoneLlmResult {
  final List<MilestoneResultItem> milestones;
  const MilestoneLlmResult({required this.milestones});
}

MilestoneLlmResult parseMilestoneResult(dynamic data) {
  final obj = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
  final rawMilestones = obj['milestones'];
  if (rawMilestones is! List) return const MilestoneLlmResult(milestones: []);

  final milestones = rawMilestones.map((m) {
    final rawAlt = m['alternative_paths'];
    final alt = rawAlt is List
        ? rawAlt
            .map((a) => MilestoneAlternativePathResult(
                  id: a['id']?.toString() ?? '',
                  title: a['title']?.toString() ?? '',
                  estimatedHours: a['estimated_hours'] is num
                      ? (a['estimated_hours'] as num).toDouble()
                      : 1.0,
                  description: a['description']?.toString() ?? '',
                ))
            .toList()
        : <MilestoneAlternativePathResult>[];

    final rawCaps = m['capabilities'];
    final caps = rawCaps is List
        ? rawCaps.whereType<String>().toList()
        : <String>[];

    return MilestoneResultItem(
      id: m['id']?.toString() ?? '',
      level: m['level']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      capabilities: caps,
      estimatedHours: m['estimated_hours'] is num
          ? (m['estimated_hours'] as num).toDouble()
          : 1.0,
      alternativePaths: alt,
    );
  }).toList();

  return MilestoneLlmResult(milestones: milestones);
}

// ─── MilestoneEngine ──────────────────────────────────────────────────────────

class MilestoneEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;

  MilestoneEngine({required this.repo, required this.scheduler});

  /// Build learning milestones for a journey, persisted via repository.
  Future<List<LearningMilestone>> generate(String journeyId, String topicId) async {
    final topic = await repo.getTopic(topicId);
    final model = await repo.getLearnerModel(topicId);
    final currentLevel = model?.overallLevel ?? MasteryLevel.awareness;

    List<MilestoneResultItem> milestones;
    try {
      final prompt = buildMilestonePrompt(
          topic: topic?.name ?? '',
          currentLevel: currentLevel.raw,
          goal: topic?.goal.raw ?? '');

      final res = await scheduler.execute<MilestoneLlmResult>(
        'milestone',
        () => prompt,
        (raw) => parseMilestoneResult(parseLLMJson(raw)),
      );
      milestones = res.result.milestones;
    } catch (_) {
      milestones = fallbackMilestones(currentLevel);
    }

    final persisted = milestones.map((m) {
      final id = shortIdWith('ms_');
      final level = MasteryLevel.fromString(m.level);
      final status = level == currentLevel
          ? MilestoneStatus.active
          : MilestoneStatus.notStarted;

      return LearningMilestone(
        id: id,
        level: level,
        title: m.title,
        description: m.description,
        capabilities: m.capabilities,
        estimatedHours: m.estimatedHours,
        status: status,
        alternativePaths: m.alternativePaths
            .map((a) => LearningPath(
                  id: a.id,
                  title: a.title,
                  estimatedHours: a.estimatedHours,
                  description: a.description,
                ))
            .toList(),
      );
    }).toList();

    await repo.insertMilestones(persisted);
    return persisted;
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

List<MilestoneResultItem> fallbackMilestones(MasteryLevel currentLevel) {
  final startIdx = max(0, MasteryLevel.order.indexOf(currentLevel));
  return MasteryLevel.order.sublist(startIdx).map((level) {
    final idx = MasteryLevel.order.indexOf(level) - startIdx;
    return MilestoneResultItem(
      id: 'ms_fallback_$idx',
      level: level.raw,
      title: _beautifulTitle(level),
      description: 'Достижение уровня ${_beautifulTitle(level)}',
      capabilities: const [],
      estimatedHours: 2 + idx * 2,
      alternativePaths: const [],
    );
  }).toList();
}

String _beautifulTitle(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.awareness:
      return 'Знакомство';
    case MasteryLevel.basicUnderstanding:
      return 'Базовое понимание';
    case MasteryLevel.solidUnderstanding:
      return 'Твёрдое понимание';
    case MasteryLevel.practicalApplication:
      return 'Практическое применение';
    case MasteryLevel.advanced:
      return 'Продвинутый';
    case MasteryLevel.expert:
      return 'Эксперт';
  }
}
