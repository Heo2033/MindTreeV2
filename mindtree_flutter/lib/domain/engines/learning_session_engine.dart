import 'dart:developer' as developer;
import 'dart:math';

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/scheduler.dart';
import '../../data/llm/client.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';
import 'package:mindtree_flutter/domain/lib/activity_blob.dart';
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

  /// Явный запрос «учить заново»: накопленный прогресс не читается — уже
  /// изученные концепты остаются в плане и не влияют на порядок. Дефолт
  /// `false`: новая сессия продолжает прогресс (due → слабые → новые).
  final bool includeLearned;

  const CreateSessionInput({
    this.journeyId,
    required this.topicId,
    required this.goal,
    required this.timeBudgetMinutes,
    this.milestoneId,
    this.includeLearned = false,
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

    // Что уже освоено: прочно изученные уходят в knownNodeIds (новый план их
    // не включает), due/слабые — в приоритет порядка. При явном includeLearned
    // прогресс игнорируется — пользователь просит пройти тему целиком.
    final prior = await _priorLearning(input.topicId,
        ignoreProgress: input.includeLearned);

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
      knownNodeIds: prior.solid.isEmpty ? null : prior.solid,
    ));

    // Новая сессия не начинается «с нуля»: повторения и слабые понятия идут
    // раньше новых, недостающие due/weak возвращаются в план принудительно —
    // LLM-отбор оптимизирует по цели и может их не выбрать.
    var items = plan.curriculum.items;
    if (prior.due.isNotEmpty || prior.weak.isNotEmpty) {
      items = _withStudyPriority(
        items,
        ordered,
        prior,
        input.timeBudgetMinutes > 0 ? input.timeBudgetMinutes : 60,
      );
    }
    // Всё уже изучено — пустая сессия хуже отказа: строка сессии НЕ создаётся
    // (исключение уходит до `repo.createSession`), UI показывает готовую
    // подсказку. Если же known пуст и план пуст (пустое дерево), поведение
    // прежнее — сессия создаётся с пустым планом.
    if (items.isEmpty && prior.solid.isNotEmpty) {
      throw Exception(
        'Все концепции по теме уже изучены — новая сессия не нужна. '
        'Переходите к следующей вехе или измените цель.',
      );
    }
    // Сумма финальных пунктов: принудительные добавления и refit меняют план,
    // готовый `totalEstimatedMinutes` из generate уже неточен.
    final totalEstimatedMinutes =
        items.fold<int>(0, (s, i) => s + i.estimatedMinutes);

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
        items: items,
        totalEstimatedMinutes: totalEstimatedMinutes,
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

  /// Последняя незавершённая сессия темы либо null — вход для «продолжить
  /// после перезапуска приложения»: id сессии живёт в БД, а не в памяти.
  Future<LearningSession?> latestUnfinishedSessionForTopic(String topicId) =>
      repo.latestUnfinishedSessionForTopic(topicId);

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

  /// Завершает пункт плана и, если передан `nodeId`, отдаёт результат в SRS.
  ///
  /// [quality] — escape hatch для вызывающего (assessment, досрочная отмена).
  /// Если не передан, качество ДЕТЕРМИНИРОВАННО выводится из шагов активности
  /// (`deriveCompletionQuality`). Раньше параметр жёстко дефолтился в
  /// 'correct', поэтому кнопка «Завершить концепт» всегда давала
  /// +0.15 recall / +0.1 understanding и продлевала интервал SRS независимо от
  /// того, как ученик отвечал на шаги.
  Future<void> markItemCompleted(
    String sessionId,
    String itemId, {
    String? nodeId,
    String? quality,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    // Выводим качество ДО `updated`: activityJson очищается в этой же записи.
    final effectiveQuality =
        quality ?? deriveCompletionQuality(session.activityJson, itemId);

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
      // `evidence: {}` — закрытие пункта плана это не ответ: измерения за него
      // уже записали шаги активности (см. FeedbackEngine). SRS по качеству
      // завершения двигаем, мастерство — нет.
      await reviewScheduler.onAnswered(
        session.topicId,
        nodeId,
        effectiveQuality,
        evidence: const {},
      );
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

  /// Уже изученное по теме — вход для планирования новой сессии.
  ///
  /// - [due] — узлы с истёкшим интервалом SRS (повторить в первую очередь);
  /// - [weak] — слабые концепты (`masteryScore < 0.6`, от слабейшего);
  /// - [solid] — прочно освоенные: пройденные пункты прошлых сессий со
  ///   score ≥ [kMasteredMasteryScore] и не ждущие повторения. Их новый план
  ///   не включает (`knownNodeIds`); due-узел остаётся в плане даже при
  ///   высоком мастерстве — SRS-повернение не отменяется.
  ///
  /// [ignoreProgress] — «учить заново»: прогресс не читается вообще.
  Future<({List<String> due, List<String> weak, Set<String> solid})>
      _priorLearning(String topicId, {required bool ignoreProgress}) async {
    if (ignoreProgress) {
      return (
        due: const <String>[],
        weak: const <String>[],
        solid: const <String>{},
      );
    }

    // `upcomingReviews` помечает «due» и узлы без профиля (p == null): нужны
    // только реально запланированные повторения — у нового узла dueAt пуст.
    final due = <String>[
      for (final r
          in await reviewScheduler.upcomingReviews(topicId, limit: 100))
        if (r.dueAt != null) r.nodeId,
    ];

    final weak = await learnerModel.getWeakConcepts(topicId, limit: 100);

    // Прочный = пройденный пункт плана прошлой сессии с высоким мастерством:
    // завершение пункта без ответов даёт score 0 и в плане он полагается снова.
    final completed = <String>{};
    for (final s in await repo.listSessionsForTopic(topicId)) {
      for (final it in s.curriculum.items) {
        if (it.status == CurriculumItemStatus.completed &&
            it.nodeId.isNotEmpty) {
          completed.add(it.nodeId);
        }
      }
    }
    final solid = <String>{};
    for (final p in await learnerModel.getConceptProfiles(topicId)) {
      if (p.masteryScore < kMasteredMasteryScore) continue;
      if (!completed.contains(p.nodeId)) continue;
      if (due.contains(p.nodeId)) continue;
      solid.add(p.nodeId);
    }
    return (due: due, weak: weak, solid: solid);
  }

  /// Расставляет приоритеты новой сессии: due → слабые → остальные.
  ///
  /// Due/weak-узлы, которых нет в плане (LLM-отбор мог их пропустить),
  /// добавляются принудительно — иначе «повторить сейчас» потерялось бы до
  /// следующего планирования ревью. Порядок стабилен: tie-break по исходному
  /// индексу (Dart `sort` нестабилен), затем перенумерация `order` и повторный
  /// `fitPlanToBudget` — сумма минут от порядка не зависит, поэтому refit
  /// корректно режет хвост по бюджету.
  List<CurriculumItem> _withStudyPriority(
    List<CurriculumItem> items,
    List<KnowledgeNode> ordered,
    ({List<String> due, List<String> weak, Set<String> solid}) prior,
    int budgetMinutes,
  ) {
    final rank = <String, int>{};
    for (final id in prior.due) {
      rank.putIfAbsent(id, () => 0);
    }
    for (final id in prior.weak) {
      rank.putIfAbsent(id, () => 1);
    }

    final byId = <String, KnowledgeNode>{for (final n in ordered) n.id: n};
    final present = {for (final it in items) it.nodeId};
    final result = [...items];

    for (final id in <String>{...prior.due, ...prior.weak}) {
      if (present.contains(id)) continue;
      final node = byId[id];
      if (node == null) continue; // узел вне дерева — не добавляем
      present.add(id);
      final est = _estMinutesOf(node);
      result.add(CurriculumItem(
        id: shortIdWith('ci_'),
        nodeId: id,
        label: node.label,
        // Перенумерация ниже выставит реальный order.
        order: 0,
        type: curriculumEngine.itemTypeFor(node),
        estimatedMinutes: est,
        priority: scorePriority(
          goalRelevanceOf(node),
          prerequisiteValueOf(node, [], byId),
          node.importance,
          est.toDouble(),
        ),
        status: CurriculumItemStatus.pending,
        reason: prior.due.contains(id)
            ? 'Повторение по расписанию: интервал SRS истёк'
            : 'Слабое понятие: его нужно закрепить в первую очередь',
      ));
    }

    final indexed = result
        .asMap()
        .entries
        .map((e) => (idx: e.key, item: e.value))
        .toList()
      ..sort((a, b) {
        final ra = rank[a.item.nodeId] ?? 2;
        final rb = rank[b.item.nodeId] ?? 2;
        if (ra != rb) return ra.compareTo(rb);
        return a.idx.compareTo(b.idx);
      });

    return fitPlanToBudget([
      for (var i = 0; i < indexed.length; i++)
        _renumberItem(indexed[i].item, i + 1),
    ], budgetMinutes);
  }

  static CurriculumItem _renumberItem(CurriculumItem it, int order) =>
      CurriculumItem(
        id: it.id,
        nodeId: it.nodeId,
        label: it.label,
        order: order,
        type: it.type,
        estimatedMinutes: it.estimatedMinutes,
        priority: it.priority,
        status: it.status,
        content: it.content,
        reason: it.reason,
      );

  /// Оценка времени узла той же формулой, что в `deterministicSelect`
  /// (незаданное время — 5 минут, потолок — 20).
  static int _estMinutesOf(KnowledgeNode n) {
    final est = n.estimatedTimeMinutes > 0 ? n.estimatedTimeMinutes : 5;
    return min(est, 20);
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
