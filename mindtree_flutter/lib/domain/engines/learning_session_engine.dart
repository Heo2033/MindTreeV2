import 'dart:async';
import 'dart:developer' as developer;
import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import '../../data/prompts/prompts.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';
import 'event_bus.dart';

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

  LearningSessionEngine({
    required this.repo,
    required this.scheduler,
    required this.learnerModel,
    required this.reviewScheduler,
    required this.eventBus,
  });

  Future<LearningSession> create(CreateSessionInput input) async {
    var journeyId = input.journeyId;
    if (journeyId == null) {
      journeyId = 'journey_${_shortId()}';
      await repo.createJourney(journeyId, input.topicId);
    }

    final nodes = await repo.listNodes(input.topicId);
    final ordered = _readingOrder(nodes);
    final targetLevel = await _getTargetLevel(input.topicId);
    final topic = await repo.getTopic(input.topicId);
    final topicName = topic?.name ?? '';
    final currentLevel = await learnerModel.getCurrentLevel(input.topicId);

    final curriculum = await _generateCurriculum(
      topicId: input.topicId,
      topicName: topicName,
      goal: input.goal,
      targetLevel: targetLevel,
      currentLevel: currentLevel,
      timeBudgetMinutes: input.timeBudgetMinutes,
      nodes: ordered,
    );

    final sessionId = 'session_${_shortId()}';
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
    final maxIdx = (items.length - 1).clamp(0, items.length - 1);
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
    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'item_completed',
      nodeId: nodeId,
      payload: {'itemId': itemId, 'progress': progress},
    );
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

    final assessmentId = 'assess_${_shortId()}';
    final assessment = Assessment(
      id: assessmentId,
      sessionId: sessionId,
      type: AssessmentType.final_,
      startedAt: DateTime.now().toIso8601String(),
      questions: await _generateAssessmentQuestions(session.topicId, items),
    );
    await repo.createAssessment(assessment);

    await eventBus.emit(
      sessionId: sessionId,
      topicId: session.topicId,
      kind: 'assessment',
      payload: {'assessmentId': assessmentId},
    );

    return assessmentId;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<Curriculum> _generateCurriculum({
    required String topicId,
    required String topicName,
    required String goal,
    required String targetLevel,
    required MasteryLevel currentLevel,
    required int timeBudgetMinutes,
    required List<KnowledgeNode> nodes,
  }) async {
    final nodesData = nodes.take(40).map((n) => <String, dynamic>{
      'id': n.id,
      'label': n.label,
      'one_liner': n.oneLiner,
      'importance': n.importance,
      'difficulty': n.difficulty,
      'estimated_time_minutes': n.estimatedTimeMinutes,
      'prerequisites': <String>[],
    }).toList();

    final prompt = buildCurriculumPrompt(
      topic: topicName,
      goal: goal,
      currentLevel: currentLevel.raw,
      targetLevel: targetLevel,
      timeBudgetMinutes: timeBudgetMinutes,
      nodes: nodesData,
    );

    try {
      // Таймаут 20с — если LLM медлит, быстро переходим к детерминированному fallback.
      // Curriculum — не критичный вызов; fallback даёт рабочий план.
      final res = await scheduler.execute<Map<String, dynamic>>(
        'curriculum',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('Curriculum LLM timeout'),
      );
      final parsed = parseCurriculumResult(res.result);
      final itemsRaw = parsed['items'] as List<Map<String, dynamic>>;
      final nodeById = {for (final n in nodes) n.id: n};

      final items = itemsRaw.asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        final nodeId = item['node_id'] as String;
        final node = nodeById[nodeId];
        return CurriculumItem(
          id: 'itemId_${i + 1}',
          nodeId: nodeId,
          label: node?.label ?? nodeId,
          order: (item['order'] as num?)?.toInt() ?? (i + 1),
          type: CurriculumItemType.explain,
          estimatedMinutes: (item['estimated_minutes'] as num?)?.toInt()
              ?? node?.estimatedTimeMinutes ?? 5,
          priority: node?.importance ?? 0.5,
          status: CurriculumItemStatus.pending,
          reason: item['why'] as String?,
        );
      }).toList();

      final fitted = fitPlanToBudget(items, timeBudgetMinutes);
      return Curriculum(
        sessionId: '',
        items: fitted,
        totalEstimatedMinutes: fitted.fold<int>(0, (s, i) => s + i.estimatedMinutes),
      );
    } catch (_) {
      final items = nodes.take(12).toList().asMap().entries.map((e) {
        final i = e.key;
        final n = e.value;
        return CurriculumItem(
          id: 'itemId_${i + 1}',
          nodeId: n.id,
          label: n.label,
          order: i + 1,
          type: CurriculumItemType.explain,
          estimatedMinutes: n.estimatedTimeMinutes,
          priority: n.importance,
          status: CurriculumItemStatus.pending,
        );
      }).toList();
      final fitted = fitPlanToBudget(items, timeBudgetMinutes);
      return Curriculum(
        sessionId: '',
        items: fitted,
        totalEstimatedMinutes: fitted.fold<int>(0, (s, i) => s + i.estimatedMinutes),
      );
    }
  }

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

  Future<List<AssessmentQuestion>> _generateAssessmentQuestions(
    String topicId,
    List<({String nodeId, String label, String oneLiner, String details})> items,
  ) async {
    final itemsJson = items
        .map((i) => '{"nodeId":"${i.nodeId}","label":"${i.label}","oneLiner":"${i.oneLiner}"}')
        .join(',');
    final prompt = '''# Роль
Ты — AI-тестолог. Сгенерируй финальную проверку для сессии.

# Узлы:
[$itemsJson]

# Задача
Сгенерируй 6 вопросов разного типа (recognition, recall, explanation, application, diagnosis, transfer).
Каждый вопрос:
- id: question_N
- nodeId: id узла
- type: тип вопроса
- question: текст вопроса
- options: 4 варианта ответа
- correctAnswer: правильный ответ
- explanation: объяснение

# Формат
Строго JSON:
{"questions":[...]}''';

    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'assessment',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final questionsRaw = res.result['questions'] as List<dynamic>? ?? [];
      return questionsRaw
          .whereType<Map<String, dynamic>>()
          .map(AssessmentQuestion.fromJson)
          .toList();
    } catch (_) {
      return items.take(3).map((i) => AssessmentQuestion(
            id: 'q_${i.nodeId}',
            type: QuestionType.recognition,
            nodeId: i.nodeId,
            question: 'Что означает понятие «${i.label}»?',
            options: [
              i.oneLiner.isNotEmpty ? i.oneLiner : 'Верный ответ',
              'Понятие, обратное изучаемому',
              'Термин из другого раздела',
              'Нерелевантный ответ',
            ],
            correctAnswer: i.oneLiner.isNotEmpty ? i.oneLiner : 'Верный ответ',
          )).toList();
    }
  }

  static String _shortId() {
    final hex = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return hex.substring(hex.length - 8);
  }

  static List<KnowledgeNode> _readingOrder(List<KnowledgeNode> nodes) {
    final sorted = List<KnowledgeNode>.from(nodes)
      ..sort((a, b) {
        if (a.level != b.level) return a.level.compareTo(b.level);
        return b.importance.compareTo(a.importance);
      });
    return sorted;
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

// ─── Time-budget fitting ───────────────────────────────────────────────────────

/// Детерминированно укладывает план в [budgetMinutes]: берёт пункты по порядку,
/// пока сумма не превысит бюджет. Первый пункт сохраняется всегда, даже если
/// сам по себе длиннее бюджета (иначе план был бы пустым).
List<CurriculumItem> fitPlanToBudget(List<CurriculumItem> items, int budgetMinutes) {
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
