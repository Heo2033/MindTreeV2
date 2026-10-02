import 'dart:developer' as developer;
import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';
import 'package:mindtree_flutter/domain/lib/tree_reading.dart';

import '../../data/prompts/prompts.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';
import 'event_bus.dart';
import 'curriculum_engine.dart';
import 'assessment_engine.dart';

class CreateSessionInput {
  final String? journeyId;
  final String topicId;
  final String goal;
  final int timeBudgetMinutes;
  final String? milestoneId;

  const CreateSessionInput({
    this.journeyId,
    required this.topicId,
    required this.goal,
    required this.timeBudgetMinutes,
    this.milestoneId,
  });
}

class LearningSessionEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final LearnerModelService learnerModel;
  final ReviewScheduler reviewScheduler;
  final EventBus eventBus;
  final CurriculumEngine curriculumEngine;
  final AssessmentEngine assessmentEngine;

  LearningSessionEngine({
    required this.repo,
    required this.scheduler,
    required this.learnerModel,
    required this.reviewScheduler,
    required this.eventBus,
    required this.curriculumEngine,
    required this.assessmentEngine,
  });

  Future<LearningSession> create(CreateSessionInput input) async {
    var journeyId = input.journeyId;
    if (journeyId == null || journeyId.isEmpty) {
      // Journey на тему должен быть один. Раньше здесь безусловно создавался
      // новый, поэтому каждая сессия плодила дубль, а `getJourneyForTopic`
      // падал с «Bad state: Too many elements» (drift внутри getSingleOrNull
      // делает `list.single`). Переиспользуем существующий journey.
      final existing = await repo.getJourneyForTopic(input.topicId);
      if (existing != null) {
        journeyId = existing.id;
      } else {
        journeyId = shortIdWith('journey_');
        await repo.createJourney(journeyId, input.topicId);
      }
    }

    final nodes = await repo.listNodes(input.topicId);
    final ordered = readingOrder(nodes);
    final targetLevel = await _getTargetLevel(input.topicId);
    final topic = await repo.getTopic(input.topicId);
    final topicName = topic?.name ?? '';
    final currentLevel = await learnerModel.getCurrentLevel(input.topicId);

    // CurriculumEngine строит промпт с реальными prerequisites и сам
    // применяет fitPlanToBudget в конце (зеркало server LearningSessionEngine).
    final plan = await curriculumEngine.generate(CurriculumRequest(
      topicId: input.topicId,
      topicName: topicName,
      goal: input.goal,
      targetLevel: targetLevel,
      currentLevel: currentLevel.raw,
      timeBudgetMinutes: input.timeBudgetMinutes,
      nodes: ordered,
    ));
    final curriculum = plan.curriculum;

    final sessionId = shortIdWith('session_');
    final session = LearningSession(
      id: sessionId,
      journeyId: journeyId,
      milestoneId: input.milestoneId,
      topicId: input.topicId,
      goal: input.goal,
      timeBudgetMinutes: input.timeBudgetMinutes,
      startedAt: DateTime.now().toIso8601String(),
      status: SessionStatus.active,
      curriculum: Curriculum(
        sessionId: sessionId,
        items: curriculum.items,
        totalEstimatedMinutes: curriculum.totalEstimatedMinutes,
      ),
      currentIndex: 0,
    );

    await repo.createSession(session);
    // Открываем границу времени: событие, закрывающее единицу работы
    // (activity_answer/step_done/item_completed), принесёт реальную длительность.
    eventBus.markUnitStart(sessionId);
    await eventBus.emit(
      sessionId: sessionId,
      topicId: input.topicId,
      kind: 'session_started',
      payload: {'goal': input.goal},
    );

    return session;
  }

  Future<LearningSession?> getSession(String sessionId) async =>
      repo.getSession(sessionId);

  Future<({CurriculumItem item, int index, Curriculum curriculum})?>
      getCurrentItem(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return null;
    if (session.currentIndex >= session.curriculum.items.length) return null;
    final item = session.curriculum.items[session.currentIndex];
    return (item: item, index: session.currentIndex, curriculum: session.curriculum);
  }

  Future<({
    Map<String, dynamic> content,
    KnowledgeNode node,
  })> studyNode(String sessionId, String nodeId) async {
    final session = await getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final node = await repo.getNode(nodeId);
    if (node == null || node.topicId != session.topicId) throw Exception('Node not found');

    if (!node.contentLoaded) {
      final path = await _nodePath(session.topicId, nodeId);
      final siblingNodes = await _siblings(session.topicId, node.parentId ?? '');
      final topic = await repo.getTopic(session.topicId);
      final topicName = topic?.name ?? '';
      final level = await learnerModel.getCurrentLevel(session.topicId);
      final knowledgeLevel = _masteryLevelToKnowledgeLevel(level);

      final prompt = buildContentPrompt(
        rootTopic: topicName,
        nodePath: path,
        nodeId: node.id,
        nodeLabel: node.label,
        nodeOneLiner: node.oneLiner,
        siblings: siblingNodes,
        knowledgeLevel: knowledgeLevel,
        goal: session.goal,
        nodeLevel: node.level,
        isRoot: node.level <= 1 && node.parentId == null,
        isCriticalDomain: _isCriticalDomain(topicName, path),
        ontologyContext: {
          'canonical_definition': node.oneLiner.isNotEmpty ? node.oneLiner : null,
          'semantic_axis': node.conceptType?.raw,
        },
      );

      Map<String, dynamic> content;
      try {
        final res = await scheduler.execute<Map<String, dynamic>>(
          'content',
          () => prompt,
          (raw) => parseLLMJson<Map<String, dynamic>>(raw),
        );
        content = {
          'one_liner': (res.result['one_liner'] as String?) ?? node.oneLiner,
          'details': (res.result['details'] as String?) ?? node.details,
          'analogy': res.result['analogy'] != null &&
                  (res.result['analogy'] as String).isNotEmpty
              ? res.result['analogy']
              : null,
          'relations': res.result['relations'] is List ? res.result['relations'] : <dynamic>[],
          'sources': res.result['sources'] is List
              ? (res.result['sources'] as List).map((e) => e.toString()).toList()
              : <String>[],
        };
      } catch (e, st) {
        developer.log('[studyNode] content generation failed for $nodeId', error: e, stackTrace: st);
        content = {
          'one_liner': node.oneLiner,
          'details': node.details,
          'relations': <dynamic>[],
          'sources': <String>[],
        };
      }

      final details = content['details'] as String;
      final hasContent = details.isNotEmpty;
      final updatedNode = node.copyWith(
        oneLiner: content['one_liner'] as String,
        details: details,
        analogy: () => content['analogy'] as String?,
        sources: content['sources'] as List<String>,
        contentLoaded: hasContent,
        state: hasContent ? NodeState.contentGenerated : node.state,
      );
      await repo.updateNode(updatedNode);

      // Событие-маркер чтения: таймер единицы не расходуем и не сбрасываем —
      // время чтения придёт в событии, закрывающем шаг активности.
      await eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'explain',
        nodeId: nodeId,
        payload: {'label': node.label},
      );

      final fetched = await repo.getNode(nodeId) ?? updatedNode;
      return (content: content, node: fetched);
    } else {
      // Маркер чтения: длительность 0, граница времени не трогается.
      await eventBus.emit(
        sessionId: sessionId,
        topicId: session.topicId,
        kind: 'explain',
        nodeId: nodeId,
        payload: {'label': node.label},
      );
      return (
        content: {
          'one_liner': node.oneLiner,
          'details': node.details,
          'analogy': node.analogy,
          'sources': node.sources,
        },
        node: node,
      );
    }
  }

  Future<void> markItemCompleted(
    String sessionId,
    String itemId, {
    String? nodeId,
    String quality = 'correct',
  }) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    final items = [
      for (final it in session.curriculum.items)
        it.id == itemId ? it.copyWith(status: CurriculumItemStatus.completed) : it,
    ];
    // Текущий индекс не должен выходить за пределы последнего концепта:
    // при завершении последнего шага остаёмся на нём (getCurrentItem корректно
    // вернёт item, а дальнейшую финализацию инициирует сам UI).
    // maxIdx = 0 на пустом списке (зеркало server: Math.max(0, items.length - 1)).
    final maxIdx = items.isEmpty ? 0 : items.length - 1;
    final nextIdx = (session.currentIndex + 1).clamp(0, maxIdx);

    final updated = session.copyWith(
      curriculum: Curriculum(
        sessionId: sessionId,
        items: items,
        totalEstimatedMinutes: session.curriculum.totalEstimatedMinutes,
      ),
      currentIndex: nextIdx,
      activityJson: () => null,
      currentActivityStep: 0,
    );
    await repo.updateSession(updated);

    if (nodeId != null) {
      await reviewScheduler.onAnswered(session.topicId, nodeId, quality);
    }

    final completedCount = items.where((i) => i.status == CurriculumItemStatus.completed).length;
    final progress = items.isNotEmpty ? completedCount / items.length : 0.0;
    // Единица работы закрыта: пишем в событие реальные миллисекунды и сразу
    // открываем границу для следующего пункта.
    final spentMs = eventBus.closeUnit(sessionId);
    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'item_completed',
      nodeId: nodeId,
      payload: {'itemId': itemId, 'progress': progress},
      durationMs: spentMs,
    );
    eventBus.markUnitStart(sessionId);
  }

  Future<String> generateFinalAssessment(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final studiedNodeIds = session.curriculum.items
        .where((i) => i.status == CurriculumItemStatus.completed && i.nodeId.isNotEmpty)
        .map((i) => i.nodeId)
        .toList();

    final items = studiedNodeIds.isNotEmpty
        ? [for (final nid in studiedNodeIds) await _nodeBrief(session.topicId, nid)]
        : await _allNodeBriefs(session.topicId);

    // AssessmentEngine сам создаёт Assessment и пишет его в repo (строка 183
    // assessment_engine.dart) — двойной create здесь не нужен.
    final assessment = await assessmentEngine.generate(
      sessionId,
      session.topicId,
      items.map((i) => AssessmentItem(
            nodeId: i.nodeId,
            label: i.label,
            oneLiner: i.oneLiner,
            details: i.details,
          )).toList(),
      type: AssessmentType.final_,
      questionCount: 6,
      includeApplication: true,
    );
    final assessmentId = assessment.id;

    // Оценка — не единица работы: таймер не расходуем и не сбрасываем,
    // длительность остаётся 0.
    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'assessment',
      payload: {'assessmentId': assessmentId},
    );

    return assessmentId;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<({String nodeId, String label, String oneLiner, String details})>
      _nodeBrief(String topicId, String nodeId) async {
    final node = await repo.getNode(nodeId);
    if (node == null || node.topicId != topicId) {
      return (nodeId: nodeId, label: '', oneLiner: '', details: '');
    }
    return (
      nodeId: node.id,
      label: node.label,
      oneLiner: node.oneLiner,
      details: node.details,
    );
  }

  Future<List<({String nodeId, String label, String oneLiner, String details})>>
      _allNodeBriefs(String topicId) async {
    final nodes = await repo.listNodes(topicId);
    return nodes.where((n) => n.leaf).take(12).map((n) => (
          nodeId: n.id,
          label: n.label,
          oneLiner: n.oneLiner,
          details: n.details,
        )).toList();
  }

  Future<List<String>> _nodePath(String topicId, String nodeId) async {
    final nodes = await repo.listNodes(topicId);
    final byId = {for (final n in nodes) n.id: n};
    final path = <String>[];
    KnowledgeNode? current = byId[nodeId];
    var guard = 0;
    while (current != null && guard < 50) {
      path.insert(0, current.label);
      current = current.parentId != null ? byId[current.parentId] : null;
      guard++;
    }
    return path;
  }

  Future<List<String>> _siblings(String topicId, String parentId) async {
    final nodes = await repo.listNodes(topicId);
    return nodes
        .where((n) => n.parentId == parentId && n.id != parentId)
        .map((n) => n.label)
        .take(8)
        .toList();
  }

  Future<String> _getTargetLevel(String topicId) async {
    final topic = await repo.getTopic(topicId);
    return topic?.targetLevel.raw ?? 'basic_understanding';
  }
}

// ─── MasteryLevel → KnowledgeLevel mapping ────────────────────────────────────

String _masteryLevelToKnowledgeLevel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.awareness:
    case MasteryLevel.basicUnderstanding:
      return 'beginner';
    case MasteryLevel.solidUnderstanding:
    case MasteryLevel.practicalApplication:
      return 'intermediate';
    case MasteryLevel.advanced:
    case MasteryLevel.expert:
      return 'expert';
  }
}

// ─── Critical domain detection (§64) ─────────────────────────────────────────

const _criticalDomainKeywords = [
  'медицина', 'медицин', 'фармаколог', 'фармац', 'терапи', 'хирург',
  'патолог', 'анатом', 'физиолог', 'клини', 'диагност',
  'law', 'право', 'юрис', 'уголовн', 'гражданск',
  'finance', 'финанс', 'экономик', 'бухгалт', 'налог',
  'medicine', 'medical', 'pharmacolog', 'clinical', 'surgery',
  'legal', 'jurisprud',
  'exam', 'экзамен', 'сертиф', ' licens',
  'наук', 'scientific', 'исследован',
];

bool _isCriticalDomain(String topicName, List<String> nodePath) {
  final text = ([topicName] + nodePath).join(' ').toLowerCase();
  return _criticalDomainKeywords.any((kw) => text.contains(kw));
}

// Content prompt building is now delegated to prompts.dart via buildContentPrompt.
// Duplicated constants removed to avoid stack drift.
