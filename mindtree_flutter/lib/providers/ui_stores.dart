import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/adaptive_learning_engine.dart';
import 'package:mindtree_flutter/domain/engines/ai_tutor_service.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';

// ─── TopicStore ──────────────────────────────────────────────────────────────

class TopicState {
  final List<Topic> topics;
  final bool loading;
  final String? error;

  const TopicState({this.topics = const [], this.loading = false, this.error});

  TopicState copyWith({List<Topic>? topics, bool? loading, String? error}) =>
      TopicState(
        topics: topics ?? this.topics,
        loading: loading ?? this.loading,
        error: error,
      );
}

class TopicNotifier extends StateNotifier<TopicState> {
  final Ref ref;
  TopicNotifier(this.ref) : super(const TopicState());

  MindtreeRepository? get _repo => ref.read(repositoryProvider).valueOrNull;

  Future<MindtreeRepository?> _repoOrNull() async {
    try {
      return await ref.read(repositoryProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadTopics() async {
    final repo = await _repoOrNull();
    if (repo == null) {
      state = state.copyWith(
        loading: false,
        error: 'Не удалось открыть хранилище. Проверьте доступ к базе данных.',
      );
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final topics = await repo.listTopics();
      state = TopicState(topics: topics);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<Topic> createTopic(
    String name, {
    String? goal,
    String? targetLevel,
    int timeBudgetMinutes = 60,
  }) async {
    final repo = _repo!;
    final id = _generateId();
    final topic = Topic(
      id: id,
      name: name,
      goal: LearningGoal.fromString(goal),
      targetLevel: MasteryLevel.fromString(targetLevel),
      timeBudgetMinutes: timeBudgetMinutes,
      createdAt: DateTime.now().toIso8601String(),
    );
    await repo.createTopic(topic);
    state = state.copyWith(topics: [...state.topics, topic]);
    return topic;
  }

  Future<void> removeTopic(String id) async {
    final repo = _repo!;
    await repo.deleteTopic(id);
    state = state.copyWith(
      topics: state.topics.where((t) => t.id != id).toList(),
    );
  }

  static String _generateId() => topicId();
}

final topicStoreProvider = StateNotifierProvider<TopicNotifier, TopicState>(
  (ref) => TopicNotifier(ref),
);

// ─── GraphStore ──────────────────────────────────────────────────────────────

class PipelineState {
  final String phase;
  final String message;
  final TreeStats? stats;
  final bool running;

  const PipelineState({
    this.phase = '',
    this.message = '',
    this.stats,
    this.running = false,
  });

  PipelineState copyWith({
    String? phase,
    String? message,
    TreeStats? stats,
    bool? running,
  }) =>
      PipelineState(
        phase: phase ?? this.phase,
        message: message ?? this.message,
        stats: stats ?? this.stats,
        running: running ?? this.running,
      );
}

class GraphState {
  final String? topicId;
  final String? topicName;
  final Topic? topic;
  final List<KnowledgeNode> nodes;
  final int visibleLevel;
  final Set<String> revealedNodes;
  final bool loading;
  final bool contentFilling;
  final String? error;
  final PipelineState pipeline;

  const GraphState({
    this.topicId,
    this.topicName,
    this.topic,
    this.nodes = const [],
    this.visibleLevel = 2,
    this.revealedNodes = const {},
    this.loading = false,
    this.contentFilling = false,
    this.error,
    this.pipeline = const PipelineState(),
  });

  GraphState copyWith({
    String? topicId,
    String? topicName,
    Topic? topic,
    List<KnowledgeNode>? nodes,
    int? visibleLevel,
    Set<String>? revealedNodes,
    bool? loading,
    bool? contentFilling,
    String? error,
    PipelineState? pipeline,
  }) =>
      GraphState(
        topicId: topicId ?? this.topicId,
        topicName: topicName ?? this.topicName,
        topic: topic ?? this.topic,
        nodes: nodes ?? this.nodes,
        visibleLevel: visibleLevel ?? this.visibleLevel,
        revealedNodes: revealedNodes ?? this.revealedNodes,
        loading: loading ?? this.loading,
        contentFilling: contentFilling ?? this.contentFilling,
        error: error,
        pipeline: pipeline ?? this.pipeline,
      );
}

class GraphNotifier extends StateNotifier<GraphState> {
  final Ref ref;
  GraphNotifier(this.ref) : super(const GraphState());

  MindtreeRepository? get _repo => ref.read(repositoryProvider).valueOrNull;
  KnowledgeGraphEngine? get _engine =>
      ref.read(knowledgeGraphEngineProvider);

  Future<MindtreeRepository?> _repoOrNull() async {
    try {
      return await ref.read(repositoryProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadTopic(String id) async {
    final repo = await _repoOrNull();
    if (repo == null) {
      state = state.copyWith(
        loading: false,
        error: 'Не удалось открыть хранилище. Проверьте доступ к базе данных.',
      );
      return;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final topic = await repo.getTopic(id);
      if (topic == null) {
        state = state.copyWith(loading: false, error: 'Тема не найдена');
        return;
      }
      final nodes = await repo.listNodes(id);
      final level = _visibleLevel(topic.targetLevel);
      state = GraphState(
        topicId: id,
        topicName: topic.name,
        topic: topic,
        nodes: nodes,
        visibleLevel: level,
      );
      if (nodes.any((n) => !n.contentLoaded)) {
        unawaited(_fillContentBackground(id));
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  void setTopicId(String id) {
    state = state.copyWith(topicId: id);
  }

  Future<void> generateTree(
    String query, {
    String? goal,
    String? level,
    int? timeBudgetMinutes,
  }) async {
    final engine = _engine;
    final repo = _repo;
    if (engine == null || repo == null) return;
    final topicId = state.topicId;
    if (topicId == null) return;

    state = state.copyWith(
      loading: true,
      error: null,
      pipeline: const PipelineState(running: true, phase: 'start', message: 'Начало генерации...'),
    );

    try {
      final result = await engine.generate(
        query,
        goal: goal,
        level: level,
        timeBudgetMinutes: timeBudgetMinutes,
        onProgress: (phase, message, [stats]) {
          state = state.copyWith(
            pipeline: PipelineState(running: true, phase: phase, message: message, stats: stats),
          );
        },
        onBatch: (batched) async {
          final scoped = scopeNodeIds(batched, topicId);
          final knowledgeNodes =
              scoped.map((d) => _draftToNode(d, topicId)).toList();
          await repo.insertOrReplaceNodes(knowledgeNodes);
        },
      );

      final scoped = scopeNodeIds(result.nodes, topicId);
      final knowledgeNodes =
          scoped.map((d) => _draftToNode(d, topicId)).toList();
      await repo.insertOrReplaceNodes(knowledgeNodes);

      final nodes = await repo.listNodes(topicId);
      final topic = await repo.getTopic(topicId);
      state = state.copyWith(
        nodes: nodes,
        topicName: topic?.name,
        topic: topic,
        visibleLevel: topic != null ? _visibleLevel(topic.targetLevel) : state.visibleLevel,
        loading: false,
        pipeline: const PipelineState(running: false, phase: 'done', message: 'Готово'),
      );
      if (nodes.any((n) => !n.contentLoaded)) {
        unawaited(_fillContentBackground(topicId));
      }
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: '$e',
        pipeline: const PipelineState(running: false),
      );
    }
  }

  void revealNode(String nodeId) {
    // Reveal the node itself; since visibility walks up the ancestor chain,
    // revealing any ancestor also exposes the subtree below it.
    state = state.copyWith(
      revealedNodes: {...state.revealedNodes, nodeId},
    );
  }

  Future<void> expandNode(String nodeId) async {
    final engine = _engine;
    final topicId = state.topicId;
    if (engine == null || topicId == null) return;
    try {
      // If the node already has (hidden) children, reveal them instantly
      // instead of regenerating. Expand (LLM) only real leaves without kids.
      final hasChildren = state.nodes.any((n) => n.parentId == nodeId);
      if (hasChildren) {
        revealNode(nodeId);
        return;
      }
      await engine.expandNodeFromDb(topicId, nodeId);
      final nodes = await _repo!.listNodes(topicId);
      final added = nodes.where((n) => n.parentId == nodeId).toList();
      state = state.copyWith(
        nodes: nodes,
        // Make freshly generated children visible immediately.
        revealedNodes: {...state.revealedNodes, nodeId, ...added.map((n) => n.id)},
      );
      if (added.isNotEmpty) {
        unawaited(_fillContentBackground(topicId));
      }
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> generateContent(String nodeId) async {
    final engine = _engine;
    final topicId = state.topicId;
    if (engine == null || topicId == null) return;
    try {
      await engine.generateNodeContentFromDb(topicId, nodeId);
      final nodes = await _repo!.listNodes(topicId);
      state = state.copyWith(nodes: nodes);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  final Set<String> _contentFillInFlight = {};

  Future<void> _fillContentBackground(String topicId) async {
    if (!_contentFillInFlight.add(topicId)) return;
    final repo = _repo;
    final engine = _engine;
    if (repo == null || engine == null) {
      _contentFillInFlight.remove(topicId);
      return;
    }
    state = state.copyWith(contentFilling: true);
    int filled = 0;
    try {
      final all = await repo.listNodes(topicId);
      final targets = all.where((n) => !n.contentLoaded).toList()
        ..sort((a, b) => a.level.compareTo(b.level));
      for (final node in targets) {
        if (state.topicId != topicId) return;
        try {
          await engine.generateNodeContentFromDb(topicId, node.id);
          filled++;
        } catch (_) {
          // После ошибки — пауза, чтобы scheduler успел восстановить cooldown.
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        if (state.topicId != topicId) return;
        // Обновляем состояние каждые несколько узлов, а не после каждого,
        // чтобы не перегружать Riverpod.
        if (filled % 3 == 0) {
          state = state.copyWith(nodes: await repo.listNodes(topicId));
        }
        // Пауза между вызовами (как LLM_BACKGROUND_INTERVAL_MS в server/pipeline.ts),
        // чтобы не упереться в RPM/RPD лимиты.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      _contentFillInFlight.remove(topicId);
      state = state.copyWith(contentFilling: false);
      // Финальное обновление состояния.
      if (state.topicId == topicId) {
        state = state.copyWith(nodes: await repo.listNodes(topicId));
      }
    }
  }

  void autoExpandVisible() {
    const maxDepth = 5;
    final nextLevel = min(state.visibleLevel + 1, maxDepth);
    // Reveal every node up to the new level so deeper leaves become visible.
    final toReveal = state.nodes
        .where((n) => n.level <= nextLevel)
        .map((n) => n.id)
        .toSet();
    state = state.copyWith(
      visibleLevel: nextLevel,
      revealedNodes: {...state.revealedNodes, ...toReveal},
    );
  }

  /// Max visible tree depth for the user's target mastery level.
  /// Mirrors web: beginner→2, intermediate→3, advanced+→4.
  static int _visibleLevel(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.awareness:
      case MasteryLevel.basicUnderstanding:
        return 2;
      case MasteryLevel.solidUnderstanding:
      case MasteryLevel.practicalApplication:
        return 3;
      case MasteryLevel.advanced:
      case MasteryLevel.expert:
        return 4;
    }
  }

  static KnowledgeNode _draftToNode(NodeDraft d, String topicId) {
    final childLevel = d.level;
    return KnowledgeNode(
      id: d.id,
      topicId: topicId,
      parentId: d.parentId,
      level: childLevel,
      label: d.title.trim(),
      oneLiner: d.canonicalDefinition ?? '',
      details: '',
      conceptType: ConceptType.fromString(d.conceptType),
      importance: d.importance ?? 0.5,
      difficulty: d.difficulty ?? 0.5,
      estimatedTimeMinutes: d.estimatedMinutes ?? 5,
      relations: (d.relations ?? [])
          .map((r) => Relation(
                from: r.from,
                to: r.to,
                type: RelationType.fromString(r.type),
                label: r.label,
              ))
          .toList(),
      state: NodeState.structureGenerated,
      contentLoaded: false,
      leaf: d.level >= 3,
    );
  }
}

final graphStoreProvider = StateNotifierProvider<GraphNotifier, GraphState>(
  (ref) => GraphNotifier(ref),
);

// ─── SessionStore ────────────────────────────────────────────────────────────

class SessionState {
  final LearningSession? session;
  final CurriculumItem? currentItem;
  final int currentIndex;
  final AdaptiveDecision? adaptive;
  final LearningActivity? activity;
  final int? answeredStepView;
  final bool studying;
  final bool loading;
  final bool advancing;
  final String? error;

  const SessionState({
    this.session,
    this.currentItem,
    this.currentIndex = 0,
    this.adaptive,
    this.activity,
    this.answeredStepView,
    this.studying = false,
    this.loading = false,
    this.advancing = false,
    this.error,
  });

  SessionState copyWith({
    LearningSession? session,
    CurriculumItem? currentItem,
    int? currentIndex,
    AdaptiveDecision? adaptive,
    LearningActivity? activity,
    bool clearActivity = false,
    int? Function()? answeredStepView,
    bool? studying,
    bool? loading,
    bool? advancing,
    String? error,
  }) =>
      SessionState(
        session: session ?? this.session,
        currentItem: currentItem ?? this.currentItem,
        currentIndex: currentIndex ?? this.currentIndex,
        adaptive: adaptive ?? this.adaptive,
        activity: clearActivity ? null : (activity ?? this.activity),
        answeredStepView:
            answeredStepView != null ? answeredStepView() : this.answeredStepView,
        studying: studying ?? this.studying,
        loading: loading ?? this.loading,
        advancing: advancing ?? this.advancing,
        error: error,
      );
}

class SessionNotifier extends StateNotifier<SessionState> {
  final Ref ref;
  SessionNotifier(this.ref) : super(const SessionState());

  LearningSessionEngine get _engine =>
      ref.read(learningSessionEngineProvider);
  LearningActivityService get _activityService =>
      ref.read(learningActivityServiceProvider);
  AdaptiveLearningEngine get _adaptiveEngine =>
      ref.read(adaptiveLearningEngineProvider);

  Future<void> createSession(
    String topicId, {
    String goal = 'overview',
    String? milestoneId,
    int timeBudget = 30,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final session = await _engine.create(CreateSessionInput(
        topicId: topicId,
        goal: goal,
        timeBudgetMinutes: timeBudget,
        milestoneId: milestoneId,
      ));
      final current = await _engine.getCurrentItem(session.id);
      state = state.copyWith(
        session: session,
        currentItem: current?.item,
        currentIndex: current?.index ?? 0,
        loading: false,
      );
      // Фоновая предгенерация следующих разделов (контент узлов + шаги activity).
      unawaited(_prefetchAhead(session.id, current?.index ?? 0));
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Фоново готовит 2 следующих раздела плана: details узлов + кэш шагов activity.
  Future<void> _prefetchAhead(String sessionId, int currentIndex) async {
    try {
      final session = await _engine.getSession(sessionId);
      if (session == null) return;
      final items = session.curriculum.items;
      final start = (currentIndex + 1).clamp(0, items.length);
      final ahead = items.sublist(start).take(2).toList();
      for (final item in ahead) {
        try {
          await _engine.studyNode(sessionId, item.nodeId);
          await _activityService.prefetchActivity(
            sessionId,
            item.nodeId,
            item.order,
          );
        } catch (e, st) {
          developer.log(
            '[prefetch] item ${item.nodeId} failed',
            error: e,
            stackTrace: st,
          );
        }
      }
    } catch (e, st) {
      developer.log('[prefetch] failed for session $sessionId', error: e, stackTrace: st);
    }
  }

  Future<void> loadCurrent() async {
    final sessionId = state.session?.id;
    if (sessionId == null) return;
    try {
      final session = await _engine.getSession(sessionId);
      if (session == null) return;
      final current = await _engine.getCurrentItem(sessionId);
      final adaptive = await _adaptiveEngine.nextStep(sessionId);
      state = state.copyWith(
        session: session,
        currentItem: current?.item,
        currentIndex: current?.index ?? session.currentIndex,
        adaptive: adaptive,
      );
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> resume() async {
    await loadCurrent();
  }

  Future<void> startStudy(String nodeId) async {
    final sessionId = state.session?.id;
    if (sessionId == null) return;
    state = state.copyWith(studying: true, loading: true, error: null);
    try {
      await _engine.studyNode(sessionId, nodeId);
      await ensureActivity();
      state = state.copyWith(studying: false, loading: false);
    } catch (e) {
      // Зеркально web-стору (sessionStore.ts): studying сбрасывается и при
      // ошибке, иначе UI навсегда остаётся на спиннере «Генерация объяснения…».
      state = state.copyWith(studying: false, loading: false, error: '$e');
    }
  }

  Future<void> ensureActivity() async {
    final sessionId = state.session?.id;
    if (sessionId == null) return;
    try {
      final activity = await _activityService.ensureActivity(sessionId);
      state = state.copyWith(activity: activity);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> answerStep(int stepIndex, String answer) async {
    final sessionId = state.session?.id;
    if (sessionId == null) return;
    // Busy-флаг на время оценки (особенно apply: LLM-вызов без видимого хода
    // заставлял думать, что кнопка «не работает»).
    state = state.copyWith(loading: true, error: null);
    try {
      final activity = await _activityService.answer(sessionId, stepIndex, answer);
      state = state.copyWith(
        activity: activity,
        answeredStepView: () => stepIndex,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> completeConcept(String itemId, {String? nodeId, String quality = 'correct'}) async {
    final sessionId = state.session?.id;
    if (sessionId == null) return;
    state = state.copyWith(loading: true, error: null, answeredStepView: () => null, advancing: true);
    try {
      await _engine.markItemCompleted(sessionId, itemId, nodeId: nodeId, quality: quality);
      final session = await _engine.getSession(sessionId);
      final current = await _engine.getCurrentItem(sessionId);
      final adaptive = await _adaptiveEngine.nextStep(sessionId);
      state = state.copyWith(
        session: session,
        currentItem: current?.item,
        currentIndex: current?.index ?? session?.currentIndex ?? 0,
        adaptive: adaptive,
        // Обязательно сбрасываем пройденную активность: без этого UI после
        // «Завершить концепт» показывает старую завершённую активность и
        // следующий концепт «сразу завершается».
        clearActivity: true,
        studying: false,
        loading: false,
        advancing: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e', advancing: false);
    }
  }

  Future<String?> finalize() async {
    final sessionId = state.session?.id;
    if (sessionId == null) return null;
    state = state.copyWith(loading: true, error: null);
    try {
      final assessmentId = await _engine.generateFinalAssessment(sessionId);
      state = state.copyWith(loading: false);
      return assessmentId;
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
      return null;
    }
  }

  void resetAnsweredView() {
    state = state.copyWith(answeredStepView: () => null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void reset() {
    state = const SessionState();
  }
}

final sessionStoreProvider = StateNotifierProvider<SessionNotifier, SessionState>(
  (ref) => SessionNotifier(ref),
);

// ─── LearnerStore ────────────────────────────────────────────────────────────

class LearnerState {
  final LearnerModel? model;
  final List<ConceptProfile> profiles;
  final List<String> weakConcepts;
  final List<String> dueConcepts;
  final bool loading;
  final String? error;

  const LearnerState({
    this.model,
    this.profiles = const [],
    this.weakConcepts = const [],
    this.dueConcepts = const [],
    this.loading = false,
    this.error,
  });

  LearnerState copyWith({
    LearnerModel? model,
    List<ConceptProfile>? profiles,
    List<String>? weakConcepts,
    List<String>? dueConcepts,
    bool? loading,
    String? error,
  }) =>
      LearnerState(
        model: model ?? this.model,
        profiles: profiles ?? this.profiles,
        weakConcepts: weakConcepts ?? this.weakConcepts,
        dueConcepts: dueConcepts ?? this.dueConcepts,
        loading: loading ?? this.loading,
        error: error,
      );
}

class LearnerNotifier extends StateNotifier<LearnerState> {
  final Ref ref;
  LearnerNotifier(this.ref) : super(const LearnerState());

  LearnerModelService get _service => ref.read(learnerModelProvider);

  Future<void> load(String topicId) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final model = await _service.getModel(topicId);
      final profiles = await _service.getConceptProfiles(topicId);
      final weak = await _service.getWeakConcepts(topicId);
      final due = await _service.getDueConcepts(topicId);
      state = LearnerState(
        model: model,
        profiles: profiles,
        weakConcepts: weak,
        dueConcepts: due,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }
}

final learnerStoreProvider = StateNotifierProvider<LearnerNotifier, LearnerState>(
  (ref) => LearnerNotifier(ref),
);

// ─── TutorStore ──────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String role;
  final String content;
  final bool usedFallback;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.usedFallback = false,
  });
}

class TutorState {
  final List<ChatMessage> messages;
  final bool sending;
  final String? error;
  final int? timeRemainingMinutes;

  const TutorState({
    this.messages = const [],
    this.sending = false,
    this.error,
    this.timeRemainingMinutes,
  });

  TutorState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    String? error,
    int? Function()? timeRemainingMinutes,
  }) =>
      TutorState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        error: error,
        timeRemainingMinutes:
            timeRemainingMinutes != null ? timeRemainingMinutes() : this.timeRemainingMinutes,
      );
}

class TutorNotifier extends StateNotifier<TutorState> {
  final Ref ref;
  TutorNotifier(this.ref) : super(const TutorState());

  AITutorService get _tutor => ref.read(aiTutorProvider);

  Future<void> send(
    String topicId,
    String message, {
    String? sessionId,
    String? nodeId,
  }) async {
    final userMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      content: message,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      sending: true,
      error: null,
    );

    try {
      final reply = await _tutor.reply(topicId, message,
          sessionId: sessionId, nodeId: nodeId);
      final assistantMsg = ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'assistant',
        content: reply.text,
        usedFallback: reply.usedFallback,
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        sending: false,
        timeRemainingMinutes: () => reply.timeRemainingMinutes,
      );
    } catch (e) {
      state = state.copyWith(sending: false, error: '$e');
    }
  }

  Stream<Map<String, dynamic>> streamReply(
    String topicId,
    String message, {
    String? sessionId,
    String? nodeId,
  }) async* {
    final userMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      content: message,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      sending: true,
      error: null,
    );

    final buffer = StringBuffer();
    var usedFallback = false;
    int? timeRemaining;

    await for (final event in _tutor.streamReply(topicId, message,
        sessionId: sessionId, nodeId: nodeId)) {
      if (event['kind'] == 'token') {
        buffer.write(event['text']);
        yield event;
      } else if (event['kind'] == 'done') {
        usedFallback = event['usedFallback'] as bool? ?? false;
        timeRemaining = event['timeRemainingMinutes'] as int?;
      }
    }

    final assistantMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'assistant',
      content: buffer.toString(),
      usedFallback: usedFallback,
    );
    state = state.copyWith(
      messages: [...state.messages, assistantMsg],
      sending: false,
      timeRemainingMinutes: () => timeRemaining,
    );
  }
}

final tutorStoreProvider = StateNotifierProvider<TutorNotifier, TutorState>(
  (ref) => TutorNotifier(ref),
);

// ─── UiStore ─────────────────────────────────────────────────────────────────

class UiState {
  final String? toastMessage;
  final bool configReady;

  const UiState({this.toastMessage, this.configReady = false});

  UiState copyWith({String? toastMessage, bool? configReady}) => UiState(
        toastMessage: toastMessage,
        configReady: configReady ?? this.configReady,
      );
}

class UiNotifier extends StateNotifier<UiState> {
  UiNotifier() : super(const UiState());

  void showToast(String message) {
    state = state.copyWith(toastMessage: message);
  }

  void clearToast() {
    state = state.copyWith(toastMessage: null);
  }

  void setConfigReady(bool ready) {
    state = state.copyWith(configReady: ready);
  }
}

final uiStoreProvider = StateNotifierProvider<UiNotifier, UiState>(
  (ref) => UiNotifier(),
);
