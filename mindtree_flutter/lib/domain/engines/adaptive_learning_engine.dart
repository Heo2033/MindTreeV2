import 'dart:developer' as developer;

import '../models/models.dart';
import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../../data/prompts/prompts.dart';
import 'curriculum_engine.dart';
import 'learner_model_service.dart';
import 'review_scheduler.dart';
import 'learning_session_engine.dart';

/// Свидетельство «ученик сам сообщил, что понятие уже знает» ([AdaptiveLearningEngine.skip]).
///
/// Те же два измерения, что и верный ответ диагностики: understanding и recall.
/// Magnitude 1.0 — декларация полного знания; фактическое значение после
/// бленда (`kEvidenceWeight` = 0.5) — 0.5 с нуля, поэтому пропуск не равен
/// подтверждённому тестом знанию. Проверка придёт из SRS: `markItemCompleted`
/// с quality 'correct' планирует первое повторение через 1 день (SM-2).
/// application/transfer намеренно не трогаем: «знаю понятие» не evidencит
/// умение применять его в новой ситуации.
const Map<String, double> kSkipEvidence = {
  dimUnderstanding: 1.0,
  dimRecall: 1.0,
};

class AdaptiveLearningEngine {
  final MindtreeRepository repo;
  final LearnerModelService learnerModel;
  final ReviewScheduler reviewScheduler;
  final LearningSessionEngine sessionEngine;

  /// Единственный LLM-вход движка: simplify/changeDepth ходят в тот же
  /// `TreeScheduler`, что и весь остальной домен (кэш, RPM/RPD, retries).
  final TreeScheduler scheduler;

  AdaptiveLearningEngine({
    required this.repo,
    required this.learnerModel,
    required this.reviewScheduler,
    required this.sessionEngine,
    required this.scheduler,
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

  // ─── Adapt (§80): действия пользователя над подачей и планом ────────────────

  /// «Упрощённое объяснение»: тот же узел, но аудитория — новичок
  /// (антижаргон обязателен, тон `_contentLevelTones['beginner']`).
  ///
  /// Ответ НЕ персистится в узел: это альтернативная подача для одного
  /// чтения, а не новая версия контента — `node.details` управляет
  /// `studyNode` и его версионирование здесь не трогаем.
  Future<AdaptSimplifyResult> simplify(String sessionId, String nodeId) async {
    final (session, node) = await _sessionAndNode(sessionId, nodeId);
    final rendered = await _renderExplanation(
      session,
      node,
      knowledgeLevel: 'beginner',
      goal: session.goal,
      requested: 'простое объяснение без жаргона (аудитория — новичок)',
    );
    return AdaptSimplifyResult(
      sessionId: sessionId,
      nodeId: nodeId,
      title: node.label,
      text: rendered.text,
      reasons: rendered.reasons,
      source: rendered.source,
      oneLiner: rendered.oneLiner,
      details: rendered.details,
      analogy: rendered.analogy,
    );
  }

  /// «Сменить глубину» (§80 L1/L2/L3).
  ///
  /// - [ContentDepth.overview] — цель «общий обзор»;
  /// - [ContentDepth.standard] — цель самой сессии (`session.goal`);
  /// - [ContentDepth.deep] — цель «глубокое изучение» (механизм, подтемы).
  ///
  /// Аудитория при этом НЕ меняется (уровень ученика), в отличие от
  /// [simplify]: «глубже» ≠ «проще». Ответ тоже не персистится.
  Future<AdaptDepthResult> changeDepth(
    String sessionId,
    String nodeId,
    ContentDepth depth,
  ) async {
    final (session, node) = await _sessionAndNode(sessionId, nodeId);

    final goal = switch (depth) {
      ContentDepth.overview => 'overview',
      ContentDepth.standard => session.goal,
      ContentDepth.deep => 'deep',
    };
    final requested = switch (depth) {
      ContentDepth.overview => 'обзорная подача (без глубоких деталей)',
      ContentDepth.standard => 'обычная подача сессии',
      ContentDepth.deep => 'глубокая подача (механизм и подтемы)',
    };

    final level = await learnerModel.getCurrentLevel(session.topicId);
    final knowledgeLevel = masteryLevelToKnowledgeLevel(level.raw) ?? 'beginner';

    final rendered = await _renderExplanation(
      session,
      node,
      knowledgeLevel: knowledgeLevel,
      goal: goal,
      requested: requested,
    );
    return AdaptDepthResult(
      sessionId: sessionId,
      nodeId: nodeId,
      title: node.label,
      text: rendered.text,
      reasons: rendered.reasons,
      source: rendered.source,
      depth: depth,
      oneLiner: rendered.oneLiner,
      details: rendered.details,
      analogy: rendered.analogy,
    );
  }

  /// «Получить prerequisite» (§80).
  ///
  /// Два источника, оба детерминированы (без LLM):
  /// 1. явные связи `depends_on`/`requires` самого узла (`prerequisitesOf`);
  /// 2. предки по `parentId` — путь L1→L2→L3, без которого узел нечитаем.
  ///
  /// Дубли (предок, на который уже ссылаются связью) не повторяются; порядок
  /// стабилен: сначала связи в порядке `node.relations`, затем предки от
  /// корня к непосредственному родителю.
  Future<AdaptPrerequisiteResult> prerequisites(String sessionId, String nodeId) async {
    final (session, node) = await _sessionAndNode(sessionId, nodeId);

    final nodes = await repo.listNodes(session.topicId);
    final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};
    final allIds = [for (final n in nodes) n.id];

    final found = <(KnowledgeNode, PrerequisiteKind)>[];
    final seen = <String>{};
    void add(KnowledgeNode n, PrerequisiteKind kind) {
      // Свой id не бывает prerequisite; `seen` дедуплицирует «связь = предок».
      if (n.id == node.id || !seen.add(n.id)) return;
      found.add((n, kind));
    }

    for (final depId in prerequisitesOf(node, byId, allIds)) {
      final dep = byId[depId];
      if (dep != null) add(dep, PrerequisiteKind.dependsOn);
    }

    final ancestors = <KnowledgeNode>[];
    var current = node.parentId != null ? byId[node.parentId] : null;
    var guard = 0;
    while (current != null && guard < 50) {
      ancestors.add(current);
      current = current.parentId != null ? byId[current.parentId] : null;
      guard++;
    }
    for (final ancestor in ancestors.reversed) {
      add(ancestor, PrerequisiteKind.parent);
    }

    final studiedIds = {
      for (final it in session.curriculum.items)
        if (it.status == CurriculumItemStatus.completed && it.nodeId.isNotEmpty) it.nodeId,
    };
    final masteryByNode = {
      for (final p in await learnerModel.getConceptProfiles(session.topicId)) p.nodeId: p.masteryScore,
    };

    final refs = [
      for (final (n, kind) in found)
        PrerequisiteRef(
          nodeId: n.id,
          label: n.label,
          oneLiner: n.oneLiner,
          kind: kind,
          studied: studiedIds.contains(n.id),
          mastery: masteryByNode[n.id],
        ),
    ];
    final missing = [for (final r in refs) if (!r.studied) r.nodeId];
    final missingLabels = [
      for (final r in refs)
        if (!r.studied) r.label,
    ];

    final text = refs.isEmpty
        ? 'У понятия «${node.label}» нет обязательных prerequisite — его можно изучать само по себе.'
        : missingLabels.isEmpty
            ? 'Все prerequisite понятия «${node.label}» уже изучены: ${refs.map((r) => r.label).join(', ')}.'
            : 'Не хватает: ${missingLabels.join(', ')}.';

    return AdaptPrerequisiteResult(
      sessionId: sessionId,
      nodeId: nodeId,
      title: 'Prerequisites: ${node.label}',
      text: text,
      reasons: [
        if (refs.isEmpty)
          'Связей depends_on/requires нет, предков по дереву у узла нет.'
        else
          'Источники: связи depends_on/requires + иерархия дерева (без LLM).',
        if (missing.isNotEmpty) 'Не изучено: ${missingLabels.join(', ')}.',
      ],
      prerequisites: refs,
      missingNodeIds: missing,
    );
  }

  /// «Пропустить уже известное» (§80).
  ///
  /// Детерминированно и без LLM:
  /// 1. пункт плана переводится в `completed` через `markItemCompleted`
  ///    (та же консистентность, что у обычного завершения: сдвиг индекса,
  ///    очистка blob активности, событие сессии и SRS `quality: 'correct'` —
  ///    концепт «уже знаю» проверится повторением через интервал SM-2);
  /// 2. самооценка «знаю» фиксируется свидетельством [kSkipEvidence]
  ///    формулой накопления `recordEvidence`.
  ///
  /// `overallLevel` не двигается: это самооценка, а не результат проверки
  /// (поднимает уровень только диагностика/экзамен).
  Future<AdaptSkipResult> skip(String sessionId, String itemId) async {
    final session = await sessionEngine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');
    final itemIdx = session.curriculum.items.indexWhere((i) => i.id == itemId);
    if (itemIdx < 0) throw Exception('Item not found');
    final item = session.curriculum.items[itemIdx];
    final nodeId = item.nodeId.isNotEmpty ? item.nodeId : null;

    var changed = false;
    if (item.status != CurriculumItemStatus.completed) {
      await sessionEngine.markItemCompleted(
        sessionId,
        itemId,
        nodeId: nodeId,
        quality: 'correct',
      );
      if (nodeId != null) {
        await learnerModel.recordEvidence(session.topicId, nodeId, kSkipEvidence);
      }
      changed = true;
    }

    final profile =
        nodeId != null ? await learnerModel.getConceptProfile(nodeId, session.topicId) : null;
    final after = await sessionEngine.getSession(sessionId) ?? session;
    final items = after.curriculum.items;
    final completedCount =
        items.where((i) => i.status == CurriculumItemStatus.completed).length;
    final label = item.label ?? '';

    return AdaptSkipResult(
      sessionId: sessionId,
      itemId: itemId,
      nodeId: nodeId,
      title: label.isEmpty ? 'Пропущено' : 'Пропущено: $label',
      text: changed
          ? 'Понятие «$label» помечено изученным: пункт уходит из плана, измерения обновлены.'
          : 'Пункт плана уже был завершён — повторный пропуск ничего не меняет.',
      reasons: [
        if (!changed) 'Пункт уже в статусе completed — без изменений.',
        if (changed) 'SRS: первый контроль — через 1 день (quality correct).',
        if (changed) 'Свидетельство самооценки записано в understanding/recall.',
      ],
      changed: changed,
      evidence: changed && nodeId != null ? kSkipEvidence : const {},
      masteryScore: profile?.masteryScore,
      progress: items.isEmpty ? 0 : completedCount / items.length,
    );
  }

  /// «Пересобрать план под оставшееся время» (§80 «адаптировать remaining»).
  ///
  /// Детерминированно и без LLM: состав держится через `fitPlanToBudget`
  /// (тот же кап бюджета, что при генерации плана; всегда оставляет ≥1
  /// незавершённый пункт), завершённые/пропущенные пункты не трогаются,
  /// порядок и нумерация перестраиваются под новый состав.
  ///
  /// [remainingMinutes] — сколько минут осталось у пользователя. Если не
  /// задано — берётся остаток бюджета сессии (`timeBudgetMinutes` минус
  /// суммарная длительность событий), как в ETA.
  Future<AdaptReplanResult> replanRemaining(
    String sessionId, {
    int? remainingMinutes,
  }) async {
    final session = await sessionEngine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final elapsed = await _elapsedMinutes(sessionId);
    final fromBudget = session.timeBudgetMinutes - elapsed;
    final remaining = remainingMinutes != null
        ? (remainingMinutes < 0 ? 0 : remainingMinutes)
        : (fromBudget < 0 ? 0 : fromBudget);

    final items = session.curriculum.items;
    final fixedIds = {
      for (final it in items)
        if (it.status == CurriculumItemStatus.completed ||
            it.status == CurriculumItemStatus.skipped)
          it.id,
    };
    final flexible = [for (final it in items) if (!fixedIds.contains(it.id)) it];
    final fitted = fitPlanToBudget(flexible, remaining);
    final fittedIds = {for (final it in fitted) it.id};
    final deferred = [for (final it in flexible) if (!fittedIds.contains(it.id)) it];

    // Состав: завершённое + влезшее, в исходном порядке; нумерация подряд.
    final kept = <CurriculumItem>[];
    for (final it in items) {
      if (!fixedIds.contains(it.id) && !fittedIds.contains(it.id)) continue;
      kept.add(CurriculumItem(
        id: it.id,
        nodeId: it.nodeId,
        label: it.label,
        order: kept.length + 1,
        type: it.type,
        estimatedMinutes: it.estimatedMinutes,
        priority: it.priority,
        status: it.status,
        content: it.content,
        reason: it.reason,
      ));
    }

    // Текущий пункт: если выжил — остаёмся на нём, иначе первый незавершённый.
    final oldCurrent = session.currentIndex >= 0 && session.currentIndex < items.length
        ? items[session.currentIndex]
        : null;
    final currentKept = oldCurrent != null &&
        (fixedIds.contains(oldCurrent.id) || fittedIds.contains(oldCurrent.id));
    var newIndex = oldCurrent == null ? -1 : kept.indexWhere((i) => i.id == oldCurrent.id);
    if (newIndex < 0) {
      newIndex = kept.indexWhere((i) =>
          i.status == CurriculumItemStatus.pending ||
          i.status == CurriculumItemStatus.active);
    }
    if (newIndex < 0) newIndex = kept.isEmpty ? 0 : kept.length - 1;

    final total = kept.fold<int>(0, (s, i) => s + i.estimatedMinutes);
    await repo.updateSession(session.copyWith(
      curriculum: Curriculum(
        sessionId: sessionId,
        items: kept,
        totalEstimatedMinutes: total,
      ),
      currentIndex: newIndex,
      // Активность нарисована под старый текущий пункт: если он выбыл —
      // blob и шаг стираем, иначе UI продолжит чужой шаг.
      activityJson: () => currentKept ? session.activityJson : null,
      currentActivityStep: currentKept ? session.currentActivityStep : 0,
    ));

    final completed = kept.where((i) => i.status == CurriculumItemStatus.completed).length;
    final eta = computeEtaFrom(elapsed, completed, kept.length, total);
    final deferredLabels = [for (final it in deferred) it.label ?? it.nodeId];

    return AdaptReplanResult(
      sessionId: sessionId,
      title: 'План пересобран под $remaining мин',
      text: deferred.isEmpty
          ? 'План укладывается в $remaining мин: оставлено ${kept.length} пунктов.'
          : 'Под $remaining мин осталось ${kept.length} пунктов, отложено '
              '${deferred.length}: ${deferredLabels.join(', ')}.',
      reasons: [
        'Прошло $elapsed мин из ${session.timeBudgetMinutes} мин бюджета.',
        'Остаток: $remaining мин.',
        if (deferred.isNotEmpty) 'Отложено: ${deferredLabels.join(', ')}.',
      ],
      kept: kept,
      deferred: deferred,
      remainingMinutes: remaining,
      elapsedMinutes: elapsed,
      eta: eta,
    );
  }

  // ─── LLM-подача (общая для simplify/changeDepth) ───────────────────────────

  /// Сессия + узел, с проверками в том же стиле, что у `studyNode`.
  Future<(LearningSession, KnowledgeNode)> _sessionAndNode(
    String sessionId,
    String nodeId,
  ) async {
    final session = await sessionEngine.getSession(sessionId);
    if (session == null) throw Exception('Session not found');
    final node = await repo.getNode(nodeId);
    if (node == null || node.topicId != session.topicId) throw Exception('Node not found');
    return (session, node);
  }

  /// Рендер объяснения с явными аудиторией/целью: ровно этими двумя
  /// параметрами simplify/changeDepth отличаются от обычного чтения узла.
  ///
  /// Fallback детерминирован: любой сбой (нет сети, битый JSON, пустой ответ
  /// модели) даёт сохранённый текст узла с пометкой [AdaptSource.stored] —
  /// сбой LLM не роняет сценарий.
  Future<({
    AdaptSource source,
    String oneLiner,
    String details,
    String? analogy,
    String text,
    List<String> reasons,
  })> _renderExplanation(
    LearningSession session,
    KnowledgeNode node, {
    required String knowledgeLevel,
    required String goal,
    required String requested,
  }) async {
    final prompt = await _contentPrompt(
      session,
      node,
      knowledgeLevel: knowledgeLevel,
      goal: goal,
    );

    try {
      final res = await scheduler.execute<Map<String, dynamic>>(
        'content',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final map = res.result;
      final oneLiner = _field(map, 'one_liner', node.oneLiner);
      final details = _field(map, 'details', node.details);
      final rawAnalogy = map['analogy'];
      final analogy = rawAnalogy is String && rawAnalogy.trim().isNotEmpty
          ? rawAnalogy.trim()
          : null;
      if (oneLiner.isEmpty && details.isEmpty) {
        // Модель вернула JSON без содержания — это не ответ, а повод уйти
        // в сохранённый текст.
        throw const FormatException('empty content response');
      }
      final text = details.isNotEmpty
          ? details
          : (oneLiner.isNotEmpty ? oneLiner : node.details);
      return (
        source: AdaptSource.llm,
        oneLiner: oneLiner,
        details: details,
        analogy: analogy,
        text: text,
        reasons: ['Запрошено: $requested.'],
      );
    } catch (e, st) {
      developer.log('[adaptive] content render failed for ${node.id}',
          error: e, stackTrace: st);
      final text = node.details.isNotEmpty
          ? node.details
          : (node.oneLiner.isNotEmpty
              ? node.oneLiner
              : 'Для понятия «${node.label}» ещё нет сгенерированного текста.');
      return (
        source: AdaptSource.stored,
        oneLiner: node.oneLiner,
        details: node.details,
        analogy: node.analogy,
        text: text,
        reasons: [
          'Модель недоступна или ответ невалиден — показан сохранённый текст узла.',
          'Запрошено: $requested.',
        ],
      );
    }
  }

  /// Тот же билдер контента, что у `studyNode`, но с явной аудиторией/целью.
  Future<String> _contentPrompt(
    LearningSession session,
    KnowledgeNode node, {
    required String? knowledgeLevel,
    required String? goal,
  }) async {
    final nodes = await repo.listNodes(session.topicId);
    final byId = <String, KnowledgeNode>{for (final n in nodes) n.id: n};

    final path = <String>[];
    KnowledgeNode? current = node;
    var guard = 0;
    while (current != null && guard < 50) {
      path.insert(0, current.label);
      current = current.parentId != null ? byId[current.parentId] : null;
      guard++;
    }
    final siblings = nodes
        .where((n) => n.parentId == node.parentId && n.id != node.parentId)
        .map((n) => n.label)
        .take(8)
        .toList();

    final topic = await repo.getTopic(session.topicId);
    final topicName = topic?.name ?? '';

    return buildContentPrompt(
      rootTopic: topicName,
      nodePath: path,
      nodeId: node.id,
      nodeLabel: node.label,
      nodeOneLiner: node.oneLiner,
      siblings: siblings,
      knowledgeLevel: knowledgeLevel,
      goal: goal,
      nodeLevel: node.level,
      isRoot: node.level <= 1 && node.parentId == null,
      isCriticalDomain: isCriticalDomain(topicName, path),
      ontologyContext: {
        'canonical_definition': node.oneLiner.isNotEmpty ? node.oneLiner : null,
        'semantic_axis': node.conceptType?.raw,
      },
    );
  }

  /// Строковое поле ответа модели; пустое значение → сохранённое в узле.
  static String _field(Map<String, dynamic> map, String key, String fallback) {
    final v = map[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : fallback;
  }

  // ─── ETA computation (§39–40) ─────────────────────────────────────────────

  /// Прошедшее время сессии в минутах: сумма `durationMs` событий с теми же
  /// правилами, что и ETA (`>0`, floor до минут).
  Future<int> _elapsedMinutes(String sessionId) async {
    final events = await repo.listEvents(sessionId);
    final elapsedMs = events
        .where((e) => e.durationMs > 0)
        .fold<int>(0, (s, e) => s + e.durationMs);
    return (elapsedMs / 60000).floor().clamp(0, 9999);
  }

  Future<SessionEta> _computeEta(
    String sessionId,
    int completedItems,
    int totalItems,
    int baseTotalMinutes,
  ) async {
    final elapsedMinutes = await _elapsedMinutes(sessionId);
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
