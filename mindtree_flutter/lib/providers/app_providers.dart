import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindtree_flutter/config/provider_config_service.dart';
import 'package:mindtree_flutter/data/database/database.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/engines/adaptive_learning_engine.dart';
import 'package:mindtree_flutter/domain/engines/ai_tutor_service.dart';
import 'package:mindtree_flutter/domain/engines/analytics_service.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/engines/feedback_engine.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/mastery_engine.dart';
import 'package:mindtree_flutter/domain/engines/milestone_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';

/// A provider that lazily obtains an already-open [MindtreeRepository],
/// throwing if the database is not ready yet.
MindtreeRepository _requireRepository(Ref ref) {
  final repo = ref.watch(repositoryProvider).valueOrNull;
  if (repo == null) {
    throw StateError('Database not ready');
  }
  return repo;
}

/// A provider returning the currently-loaded [llm_client.LLMConfig] or a
/// safe default when the effective config has not finished loading yet.
final llmConfigStateProvider = StateProvider<llm_client.LLMConfig?>((ref) => null);

/// Opens the MindTree SQLite database.
final databaseProvider = FutureProvider<MindtreeDb>((ref) => openDatabase());

/// The repository built on top of the opened database.
final repositoryProvider = FutureProvider<MindtreeRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MindtreeRepository(db);
});

/// Service that resolves build-time and runtime LLM provider configuration.
final providerConfigServiceProvider = Provider<ProviderConfigService>(
  (ref) => ProviderConfigService(),
);

/// The effective (build + runtime merged) LLM configuration.
final effectiveConfigProvider = FutureProvider<EffectiveConfig>((ref) {
  final svc = ref.watch(providerConfigServiceProvider);
  return svc.load();
});

/// Bootstraps the app: loads the effective config and publishes it to the
/// [llmConfigStateProvider] so the scheduler can use it synchronously.
final initAppProvider = FutureProvider<void>((ref) async {
  final initFuture = ref.watch(effectiveConfigProvider.future);
  final ec = await initFuture;
  ref.read(llmConfigStateProvider.notifier).state = llm_client.configFromEffective(ec);
});

/// The LLM scheduler. Its configProvider reflects the last-loaded effective
/// config, falling back to an offline/default config before load completes.
final schedulerProvider = Provider<TreeScheduler>((ref) {
  return TreeScheduler(
    configProvider: () =>
        ref.read(llmConfigStateProvider) ?? const llm_client.LLMConfig(),
  );
});

/// Core learner model service, backed by the repository.
final learnerModelProvider = Provider<LearnerModelService>(
  (ref) => LearnerModelService(_requireRepository(ref)),
);

/// SRS-backed review scheduler.
final reviewSchedulerProvider = Provider<ReviewScheduler>(
  (ref) => ReviewScheduler(_requireRepository(ref)),
);

/// Persistent event bus.
final eventBusProvider = Provider<EventBus>(
  (ref) => EventBus(_requireRepository(ref)),
);

/// Orchestrates knowledge-tree generation (structure -> expand -> validate ->
/// repair -> content) with injected prompt builders.
final knowledgeGraphEngineProvider = Provider<KnowledgeGraphEngine>((ref) {
  final repo = _requireRepository(ref);
  final scheduler = ref.watch(schedulerProvider);
  return KnowledgeGraphEngine(
    repo: repo,
    scheduler: scheduler,
    generateStructure: (ctx) => buildL1Prompt(
      ctx.query,
      goal: ctx.options.goal,
      level: ctx.options.level,
    ),
    generateL2: (ctx) => buildL2Prompt(
      userQuery: ctx.userQuery,
      rootId: ctx.root.id,
      rootTitle: ctx.root.title,
      rootCanonicalDefinition: ctx.root.canonicalDefinition,
      goal: ctx.options?.goal,
      level: ctx.options?.level,
      timeBudgetMinutes: ctx.options?.timeBudgetMinutes,
    ),
    generateL3: (ctx) => buildL3Prompt(
      userQuery: ctx.userQuery,
      rootTitle: ctx.rootTitle,
      parentId: ctx.parent.id,
      parentTitle: ctx.parent.title,
      parentCanonicalDefinition: ctx.parent.canonicalDefinition,
      siblings: [
        for (final s in ctx.siblings)
          {
            'id': s.id,
            'title': s.title,
            'canonical_definition': s.canonicalDefinition,
          },
      ],
      goal: ctx.options?.goal,
      level: ctx.options?.level,
    ),
    generateExpand: (ctx) => buildExpandPrompt(
      rootTopic: ctx.rootTopic,
      contextPaths: ctx.contextPaths,
      nodesToExpand: [
        for (final n in ctx.nodesToExpand)
          {'id': n.id, 'title': n.title, 'path': n.path},
      ],
      existingTree: [
        for (final n in ctx.existingTree)
          {'id': n.id, 'title': n.title, 'parentId': n.parentId, 'level': n.level},
      ],
      goal: ctx.options?.goal,
      level: ctx.options?.level,
    ),
    generateValidate: (ctx) => buildValidatePrompt(
      [
        for (final n in ctx.nodes)
          {
            'id': n.id,
            'parentId': n.parentId,
            'level': n.level,
            'label': n.label,
            'one_liner': n.oneLiner,
            'details': n.details,
            'conceptType': n.conceptType,
            'semantic_axis': n.semanticAxis,
            'canonical_definition': n.canonicalDefinition,
            'forbidden_interpretations': n.forbiddenInterpretations,
          },
      ],
      focusIds: ctx.focusIds,
    ),
    generateRepair: (ctx) => buildRepairPrompt(
      problemNodes: [
        for (final n in ctx.problemNodes)
          {
            'id': n.id,
            'parentId': n.parentId,
            'level': n.level,
            'label': n.label,
            'one_liner': n.oneLiner,
            'details': n.details,
            'conceptType': n.conceptType,
            'semantic_axis': n.semanticAxis,
            'canonical_definition': n.canonicalDefinition,
            'forbidden_interpretations': n.forbiddenInterpretations,
          },
      ],
      issues: [
        for (final i in ctx.issues)
          {'type': i.type, 'node_id': i.nodeId, 'reason': i.reason},
      ],
      level: ctx.level,
    ),
    generateContent: (ctx) => buildContentPrompt(
      rootTopic: ctx.rootTopic,
      nodePath: ctx.nodePath,
      nodeId: ctx.node.id,
      nodeLabel: ctx.node.label,
      siblings: ctx.siblings,
      knowledgeLevel: ctx.knowledgeLevel,
      goal: ctx.goal,
      nodeLevel: ctx.nodeLevel,
      isRoot: ctx.isRoot,
      isCriticalDomain: ctx.isCriticalDomain,
      ontologyContext: {
        'canonical_definition': ctx.ontologyContext.canonicalDefinition,
        'semantic_axis': ctx.ontologyContext.semanticAxis,
        'forbidden_interpretations': ctx.ontologyContext.forbiddenInterpretations,
      },
    ),
  );
});

/// Builds a curriculum plan from the knowledge tree.
final curriculumEngineProvider = Provider<CurriculumEngine>((ref) {
  return CurriculumEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
    learnerModel: ref.watch(learnerModelProvider),
  );
});

/// Generates learning milestones for a journey.
final milestoneEngineProvider = Provider<MilestoneEngine>((ref) {
  return MilestoneEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Generates and grades diagnostic / quiz / final assessments.
final assessmentEngineProvider = Provider<AssessmentEngine>((ref) {
  return AssessmentEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Runs an initial diagnostic to estimate starting mastery.
final diagnosticEngineProvider = Provider<DiagnosticEngine>((ref) {
  return DiagnosticEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Generates adaptive feedback for learning activities.
final feedbackEngineProvider = Provider<FeedbackEngine>((ref) {
  return FeedbackEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Coordinates learning sessions.
final learningSessionEngineProvider = Provider<LearningSessionEngine>((ref) {
  return LearningSessionEngine(
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
    learnerModel: ref.watch(learnerModelProvider),
    reviewScheduler: ref.watch(reviewSchedulerProvider),
    eventBus: ref.watch(eventBusProvider),
    curriculumEngine: ref.watch(curriculumEngineProvider),
    assessmentEngine: ref.watch(assessmentEngineProvider),
  );
});

/// Builds and steps through per-concept learning activities.
final learningActivityServiceProvider = Provider<LearningActivityService>((ref) {
  return LearningActivityService(
    engine: ref.watch(learningSessionEngineProvider),
    repo: _requireRepository(ref),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Adaptive decisions for a session.
final adaptiveLearningEngineProvider = Provider<AdaptiveLearningEngine>((ref) {
  return AdaptiveLearningEngine(
    repo: _requireRepository(ref),
    learnerModel: ref.watch(learnerModelProvider),
    reviewScheduler: ref.watch(reviewSchedulerProvider),
    sessionEngine: ref.watch(learningSessionEngineProvider),
  );
});

/// Evaluates mastery from answers.
final masteryEngineProvider = Provider<MasteryEngine>((ref) {
  return MasteryEngine(
    repo: _requireRepository(ref),
    learnerModel: ref.watch(learnerModelProvider),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Aggregated analytics across topics and sessions.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(
    repo: _requireRepository(ref),
    learnerModel: ref.watch(learnerModelProvider),
  );
});

/// Contextual AI tutor.
final aiTutorProvider = Provider<AITutorService>((ref) {
  return AITutorService(
    repo: _requireRepository(ref),
    learnerModel: ref.watch(learnerModelProvider),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Top-level boot provider: ensures the database and effective config are
/// loaded and the LLM config is published before the app starts.
final appInitializedProvider = FutureProvider<void>((ref) async {
  final dbFuture = ref.watch(databaseProvider.future);
  await dbFuture;
  await ref.watch(initAppProvider.future);
});
