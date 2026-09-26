import 'dart:math';

import '../models/models.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import '../../data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';
import 'learner_model_service.dart';

// ─── Request / result DTOs ────────────────────────────────────────────────────

class CurriculumRequest {
  final String topicId;
  final String topicName;
  final String goal;
  final String targetLevel;
  final String? currentLevel;
  final int timeBudgetMinutes;
  final List<KnowledgeNode> nodes;
  final Set<String>? knownNodeIds;

  const CurriculumRequest({
    required this.topicId,
    required this.topicName,
    required this.goal,
    required this.targetLevel,
    this.currentLevel,
    this.timeBudgetMinutes = 60,
    this.nodes = const [],
    this.knownNodeIds,
  });
}

class CurriculumPlanResult {
  final Curriculum curriculum;
  final List<String> alreadyKnown;

  const CurriculumPlanResult({required this.curriculum, this.alreadyKnown = const []});
}

// ─── CurriculumEngine ─────────────────────────────────────────────────────────

class CurriculumEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService learnerModel;

  CurriculumEngine({
    required this.repo,
    required this.scheduler,
    LearnerModelService? learnerModel,
  }) : learnerModel = learnerModel ?? LearnerModelService(repo);

  /// Generate a curriculum from the full knowledge tree.
  Future<CurriculumPlanResult> generate(CurriculumRequest req) async {
    final baseline = deterministicSelect(req);

    List<CurriculumItemResult> llmItems = baseline;
    try {
      llmItems = await llmSelect(req);
    } catch (_) {
      // fall back to deterministic baseline
    }

    final known = req.knownNodeIds ?? <String>{};
    final alreadyKnown = req.nodes
        .map((n) => n.id)
        .where((id) => known.contains(id))
        .where((id) => req.nodes.any((n) => n.id == id))
        .toList();

    final byId = <String, KnowledgeNode>{for (final n in req.nodes) n.id: n};

    final items = llmItems
        .where((i) => i.nodeId.isNotEmpty && !known.contains(i.nodeId))
        .map((item) {
      final node = byId[item.nodeId];
      final order = item.order;
      final goalRelevance = goalRelevanceOf(node);
      final prerequisiteValue =
          prerequisiteValueOf(node, llmItems.map((i) => i.nodeId).toList(), byId);
      final importance = node?.importance ?? 0.5;
      final est = max(1, item.estimatedMinutes).toDouble();
      final priority = scorePriority(goalRelevance, prerequisiteValue, importance, est);
      return CurriculumItem(
        id: shortIdWith('ci_'),
        nodeId: item.nodeId,
        label: node?.label ?? item.nodeId,
        order: order,
        type: itemTypeFor(node),
        estimatedMinutes: item.estimatedMinutes,
        priority: priority,
        status: CurriculumItemStatus.pending,
        reason: item.why.isNotEmpty ? item.why : null,
      );
    }).toList();

    final issues = validate(items, req.nodes);
    if (issues.isNotEmpty) {
      repairOrder(items, req.nodes);
    }

    // Детерминированный кап по бюджету времени: план не должен обещать
    // больше минут, чем пользователь выделил (зеркало server fitPlanToBudget).
    final fitted = fitPlanToBudget(
        items, req.timeBudgetMinutes > 0 ? req.timeBudgetMinutes : 60);

    final sessionId = shortIdWith('curriculum_');
    final total = fitted.fold<int>(0, (s, i) => s + i.estimatedMinutes);

    return CurriculumPlanResult(
      curriculum: Curriculum(
        sessionId: sessionId,
        items: fitted,
        totalEstimatedMinutes: total,
      ),
      alreadyKnown: alreadyKnown,
    );
  }

  /// Rebuild curriculum for a new goal using mastered concepts.
  Future<CurriculumPlanResult> planForGoal(
    CurriculumRequest req,
    LearnerModelService learnerSvc,
  ) async {
    final profiles = await learnerSvc.getConceptProfiles(req.topicId);
    final mastered = profiles
        .where((p) => p.masteryScore >= 0.7)
        .map((p) => p.nodeId)
        .toSet();
    return generate(CurriculumRequest(
      topicId: req.topicId,
      topicName: req.topicName,
      goal: req.goal,
      targetLevel: req.targetLevel,
      currentLevel: req.currentLevel,
      timeBudgetMinutes: req.timeBudgetMinutes,
      nodes: req.nodes,
      knownNodeIds: mastered,
    ));
  }

  // ─── Deterministic selection ────────────────────────────────────────────────

  List<CurriculumItemResult> deterministicSelect(CurriculumRequest req) {
    final budget = req.timeBudgetMinutes > 0 ? req.timeBudgetMinutes : 60;
    final byId = <String, KnowledgeNode>{for (final n in req.nodes) n.id: n};
    final known = req.knownNodeIds ?? <String>{};

    // Зеркало server: 0/незаданное время трактуется как 5 минут.
    int estMinutes(KnowledgeNode n) =>
        n.estimatedTimeMinutes > 0 ? n.estimatedTimeMinutes : 5;

    final scored = req.nodes
        .where((n) => n.level >= 2 && !known.contains(n.id))
        .map((n) {
          final est = max(1, estMinutes(n)).toDouble();
          final score = scorePriority(
            goalRelevanceOf(n),
            prerequisiteValueOf(n, [], byId),
            n.importance,
            est,
          );
          return (n: n, score: score);
        })
        .toList()
      // Tie-break по времени (зеркало server): при равном score сначала
      // идут более короткие понятия.
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return estMinutes(a.n).compareTo(estMinutes(b.n));
      });

    final selected = <CurriculumItemResult>[];
    var used = 0;
    for (final entry in scored) {
      final est = min(estMinutes(entry.n), 20);
      if (used + est > budget * 1.2) break;
      selected.add(CurriculumItemResult(
        nodeId: entry.n.id,
        order: selected.length + 1,
        estimatedMinutes: est,
        why: 'Важное понятие с высокой пользой на единицу времени',
      ));
      used += est;
    }

    // Детерминированный guard (зеркало server): при коротком бюджете падать
    // до пустого плана нельзя — берём лучший узел.
    if (selected.isEmpty && scored.isNotEmpty) {
      final best = scored.first.n;
      selected.add(CurriculumItemResult(
        nodeId: best.id,
        order: 1,
        estimatedMinutes: min(estMinutes(best), 20),
        why: 'Базовое понятие — план не может быть пустым',
      ));
    }
    return selected;
  }

  // ─── LLM selection ──────────────────────────────────────────────────────────

  Future<List<CurriculumItemResult>> llmSelect(CurriculumRequest req) async {
    final currentLevel =
        req.currentLevel ?? (await learnerModel.getCurrentLevel(req.topicId)).raw;

    final byId = <String, KnowledgeNode>{for (final n in req.nodes) n.id: n};
    final allIds = req.nodes.map((n) => n.id).toList();

    final nodesList = req.nodes.map((n) => {
      'id': n.id,
      'label': n.label,
      'one_liner': n.oneLiner,
      'importance': n.importance,
      'difficulty': n.difficulty,
      'estimated_time_minutes': n.estimatedTimeMinutes,
      'prerequisites': prerequisitesOf(n, byId, allIds),
    }).toList();

    final prompt = buildCurriculumPrompt(
      topic: req.topicName,
      goal: req.goal,
      currentLevel: currentLevel,
      targetLevel: req.targetLevel,
      timeBudgetMinutes: req.timeBudgetMinutes,
      nodes: nodesList,
    );

    final res = await scheduler.execute<CurriculumLlmResult>(
      'curriculum',
      () => prompt,
      (raw) => parseCurriculumResult(parseLLMJson(raw)),
    );

    final sorted = res.result.items
        .where((i) => i.nodeId.isNotEmpty)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return sorted
        .asMap()
        .entries
        .map((e) => CurriculumItemResult(
              nodeId: e.value.nodeId,
              order: e.key + 1,
              estimatedMinutes: e.value.estimatedMinutes,
              why: e.value.why,
            ))
        .toList();
  }

  CurriculumItemType itemTypeFor(KnowledgeNode? node) {
    if (node == null) return CurriculumItemType.explain;
    if (node.conceptType == ConceptType.process ||
        node.conceptType == ConceptType.mechanism) {
      return CurriculumItemType.explain;
    }
    if (node.leaf) return CurriculumItemType.recall;
    return CurriculumItemType.explain;
  }

  // ─── Validation & repair ────────────────────────────────────────────────────

  List<String> validate(List<CurriculumItem> items, List<KnowledgeNode> nodes) {
    final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};
    final selectedIds = items.map((i) => i.nodeId).toSet();
    final orderPos = <String, int>{};
    for (var idx = 0; idx < items.length; idx++) {
      orderPos[items[idx].nodeId] = idx;
    }

    final issues = <String>[];
    for (final item in items) {
      final node = byId[item.nodeId];
      final deps = prerequisitesOf(node, byId, nodes.map((n) => n.id).toList());
      for (final dep in deps) {
        if (selectedIds.contains(dep)) {
          final depPos = orderPos[dep];
          final ownPos = orderPos[item.nodeId];
          if (depPos != null && ownPos != null && depPos > ownPos) {
            issues.add(
              'Понятие «${node?.label ?? item.nodeId}» изучено раньше '
              'своего prerequisite «${byId[dep]?.label ?? dep}».',
            );
          }
        }
      }
    }
    return issues;
  }

  void repairOrder(List<CurriculumItem> items, List<KnowledgeNode> nodes) {
    final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};
    final allIds = nodes.map((n) => n.id).toList();
    final selected = items.map((i) => i.nodeId).toSet();
    final index = <String, int>{};
    for (var idx = 0; idx < items.length; idx++) {
      index[items[idx].nodeId] = idx;
    }

    List<String> depsOf(String nodeId) =>
        prerequisitesOf(byId[nodeId], byId, allIds)
            .where((d) => selected.contains(d) && index.containsKey(d))
            .toList();

    final visited = <String>{};
    final inStack = <String>{};
    final ordered = <CurriculumItem>[];

    void visit(CurriculumItem item) {
      if (visited.contains(item.nodeId) || inStack.contains(item.nodeId)) return;
      inStack.add(item.nodeId);
      for (final dep in depsOf(item.nodeId)) {
        visit(items[index[dep]!]);
      }
      inStack.remove(item.nodeId);
      visited.add(item.nodeId);
      ordered.add(item);
    }

    for (final item in items) {
      visit(item);
    }

    for (var idx = 0; idx < ordered.length; idx++) {
      final old = ordered[idx];
      ordered[idx] = CurriculumItem(
        id: old.id,
        nodeId: old.nodeId,
        label: old.label,
        order: idx + 1,
        type: old.type,
        estimatedMinutes: old.estimatedMinutes,
        priority: old.priority,
        status: old.status,
        content: old.content,
        reason: old.reason,
      );
    }

    items
      ..clear()
      ..addAll(ordered);
  }
}

/// Детерминированно укладывает план в [budgetMinutes]: берёт пункты по порядку,
/// пока сумма не превысит бюджет. Первый пункт сохраняется всегда, даже если
/// сам по себе длиннее бюджета (иначе план был бы пустым).
List<CurriculumItem> fitPlanToBudget(
    List<CurriculumItem> items, int budgetMinutes) {
  if (items.isEmpty) return items;
  final sorted = List<CurriculumItem>.from(items)
    ..sort((a, b) => a.order.compareTo(b.order));
  final fitted = <CurriculumItem>[];
  var sum = 0;
  for (final it in sorted) {
    if (fitted.isNotEmpty && sum + it.estimatedMinutes > budgetMinutes) break;
    fitted.add(it);
    sum += it.estimatedMinutes;
  }
  if (fitted.isEmpty) fitted.add(sorted.first);
  return fitted;
}

// ─── Priority model ───────────────────────────────────────────────────────────

/// §20 Priority Model:
/// priority = goal_relevance × prerequisite_value × importance ÷ estimated_time
/// Normalized to a 1..100 scale for display.
double scorePriority(
  double goalRelevance,
  double prerequisiteValue,
  double importance,
  double estimatedMinutes,
) {
  final raw = (goalRelevance + 0.5) *
      (prerequisiteValue + 0.5) *
      (importance + 0.5) /
      max(1.0, estimatedMinutes);
  return max(1, (raw * 100).round()).toDouble();
}

double goalRelevanceOf(KnowledgeNode? node) {
  if (node == null) return 0;
  final base = node.importance;
  final typeBoost = (node.conceptType == ConceptType.mechanism ||
          node.conceptType == ConceptType.process)
      ? 0.3
      : 0.0;
  return min(1.0, base + typeBoost);
}

/// Prerequisite value: how many other concepts directly depend on this node.
double prerequisiteValueOf(
  KnowledgeNode? node,
  List<String> selectedIds,
  Map<String, KnowledgeNode> byId,
) {
  if (node == null) return 0;
  var deps = 0;
  final seen = <String>{};
  for (final n in byId.values) {
    for (final rel in n.relations) {
      if ((rel.type == RelationType.dependsOn || rel.type == RelationType.requires) &&
          rel.from == node.id &&
          !seen.contains(n.id)) {
        seen.add(n.id);
        if (selectedIds.contains(n.id)) deps++;
      }
    }
  }
  return min(1.0, deps / 4.0);
}

/// Prerequisites of a node = ids of concepts it depends on.
List<String> prerequisitesOf(
  KnowledgeNode? node,
  Map<String, KnowledgeNode> byId,
  List<String> allIds,
) {
  final out = <String>[];
  for (final rel in node?.relations ?? []) {
    if ((rel.type == RelationType.dependsOn || rel.type == RelationType.requires) &&
        allIds.contains(rel.to)) {
      out.add(rel.to);
    }
  }
  return out;
}

// ─── LLM parse types ─────────────────────────────────────────────────────────

class CurriculumItemResult {
  final String nodeId;
  final int order;
  final int estimatedMinutes;
  final String why;

  const CurriculumItemResult({
    required this.nodeId,
    required this.order,
    required this.estimatedMinutes,
    this.why = '',
  });
}

class CurriculumLlmResult {
  final List<CurriculumItemResult> items;
  final int totalEstimatedMinutes;

  const CurriculumLlmResult({
    required this.items,
    required this.totalEstimatedMinutes,
  });
}

CurriculumLlmResult parseCurriculumResult(dynamic data) {
  final obj = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
  final rawItems = obj['items'];
  final items = rawItems is List
      ? rawItems
          .map((i) => CurriculumItemResult(
                nodeId: i['node_id']?.toString() ?? '',
                order: i['order'] is num ? (i['order'] as num).toInt() : 0,
                estimatedMinutes:
                    i['estimated_minutes'] is num ? (i['estimated_minutes'] as num).toInt() : 5,
                why: i['why']?.toString() ?? '',
              ))
          .toList()
      : <CurriculumItemResult>[];

  final totalEst = obj['total_estimated_minutes'] is num
      ? (obj['total_estimated_minutes'] as num).toInt()
      : items.fold<int>(0, (s, i) => s + i.estimatedMinutes);

  return CurriculumLlmResult(items: items, totalEstimatedMinutes: totalEst);
}
