import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindtree_flutter/config/provider_config_service.dart';
import 'package:mindtree_flutter/data/database/database.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/adaptive_learning_engine.dart';
import 'package:mindtree_flutter/domain/engines/ai_tutor_service.dart';
import 'package:mindtree_flutter/domain/engines/analytics_service.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
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
///
/// It stays a standalone provider (rather than living inside the engine
/// bundle) because it is the transport seam: tests override
/// `schedulerProvider` with a mock, and that override must reach every engine.
/// A runtime settings change is still picked up without rebuilding anything,
/// because the config is read lazily per LLM call.
final schedulerProvider = Provider<TreeScheduler>((ref) {
  return TreeScheduler(
    configProvider: () =>
        ref.read(llmConfigStateProvider) ?? const llm_client.LLMConfig(),
  );
});

/// All domain engines, assembled by the shared pure-Dart factory.
///
/// The factory is the single source of truth for the engine graph; the
/// per-engine providers below are thin accessors so that widget code keeps
/// watching individual services. The scheduler is injected from
/// [schedulerProvider] so it stays overridable in tests.
final enginesProvider = Provider<MindtreeEngines>((ref) {
  return buildEngines(
    repo: _requireRepository(ref),
    configProvider: () =>
        ref.read(llmConfigStateProvider) ?? const llm_client.LLMConfig(),
    scheduler: ref.watch(schedulerProvider),
  );
});

/// Core learner model service, backed by the repository.
final learnerModelProvider = Provider<LearnerModelService>(
  (ref) => ref.watch(enginesProvider).learnerModel,
);

/// SRS-backed review scheduler.
final reviewSchedulerProvider = Provider<ReviewScheduler>(
  (ref) => ref.watch(enginesProvider).review,
);

/// Persistent event bus.
final eventBusProvider = Provider<EventBus>(
  (ref) => ref.watch(enginesProvider).events,
);

/// Orchestrates knowledge-tree generation (structure -> expand -> validate ->
/// repair -> content) with injected prompt builders.
final knowledgeGraphEngineProvider = Provider<KnowledgeGraphEngine>(
  (ref) => ref.watch(enginesProvider).graph,
);

/// Builds a curriculum plan from the knowledge tree.
final curriculumEngineProvider = Provider<CurriculumEngine>(
  (ref) => ref.watch(enginesProvider).curriculum,
);

/// Generates learning milestones for a journey.
final milestoneEngineProvider = Provider<MilestoneEngine>(
  (ref) => ref.watch(enginesProvider).milestones,
);

/// Generates and grades diagnostic / quiz / final assessments.
final assessmentEngineProvider = Provider<AssessmentEngine>(
  (ref) => ref.watch(enginesProvider).assessment,
);

/// Runs an initial diagnostic to estimate starting mastery.
final diagnosticEngineProvider = Provider<DiagnosticEngine>(
  (ref) => ref.watch(enginesProvider).diagnostic,
);

/// Generates adaptive feedback for learning activities.
final feedbackEngineProvider = Provider<FeedbackEngine>(
  (ref) => ref.watch(enginesProvider).feedback,
);

/// Coordinates learning sessions.
final learningSessionEngineProvider = Provider<LearningSessionEngine>(
  (ref) => ref.watch(enginesProvider).session,
);

/// Builds and steps through per-concept learning activities.
final learningActivityServiceProvider = Provider<LearningActivityService>(
  (ref) => ref.watch(enginesProvider).activity,
);

/// Adaptive decisions for a session.
final adaptiveLearningEngineProvider = Provider<AdaptiveLearningEngine>(
  (ref) => ref.watch(enginesProvider).adaptive,
);

/// Evaluates mastery from answers.
final masteryEngineProvider = Provider<MasteryEngine>(
  (ref) => ref.watch(enginesProvider).mastery,
);

/// Aggregated analytics across topics and sessions.
final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => ref.watch(enginesProvider).analytics,
);

/// Contextual AI tutor.
final aiTutorProvider = Provider<AITutorService>(
  (ref) => ref.watch(enginesProvider).tutor,
);

/// Top-level boot provider: ensures the database and effective config are
/// loaded and the LLM config is published before the app starts.
final appInitializedProvider = FutureProvider<void>((ref) async {
  final dbFuture = ref.watch(databaseProvider.future);
  await dbFuture;
  await ref.watch(initAppProvider.future);
});
