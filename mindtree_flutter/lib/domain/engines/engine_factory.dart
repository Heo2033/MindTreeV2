import '../../data/database/mindtree_repository.dart';
import '../../data/llm/cache.dart';
import '../../data/llm/client.dart' as llm_client;
import '../../data/llm/scheduler.dart';
import '../../data/llm/telemetry.dart';
import '../../data/prompts/prompts.dart';
import 'adaptive_learning_engine.dart';
import 'ai_tutor_service.dart';
import 'analytics_service.dart';
import 'assessment_engine.dart';
import 'curriculum_engine.dart';
import 'diagnostic_engine.dart';
import 'event_bus.dart';
import 'feedback_engine.dart';
import 'knowledge_graph_engine.dart';
import 'learner_model_service.dart';
import 'learning_activity_service.dart';
import 'learning_session_engine.dart';
import 'mastery_engine.dart';
import 'milestone_engine.dart';
import 'review_scheduler.dart';

/// Единая сборка всех доменных движков MindTree.
///
/// Единственный источник истины о связях движков: и Riverpod-провайдеры
/// (`lib/providers/app_providers.dart`), и headless-инструменты
/// (`tool/`, e2e) получают ровно один и тот же граф зависимостей. Файл
/// намеренно остаётся pure Dart (никаких `package:flutter/*`), чтобы его
/// мог импортировать `dart run` CLI.
class MindtreeEngines {
  final MindtreeRepository repo;

  /// Единственная точка доступа к LLM: все движки берут `scheduler` отсюда.
  final TreeScheduler scheduler;

  final KnowledgeGraphEngine graph;
  final CurriculumEngine curriculum;
  final MilestoneEngine milestones;
  final AssessmentEngine assessment;
  final DiagnosticEngine diagnostic;
  final FeedbackEngine feedback;
  final LearningSessionEngine session;
  final LearningActivityService activity;
  final AdaptiveLearningEngine adaptive;
  final MasteryEngine mastery;
  final AnalyticsService analytics;
  final LearnerModelService learnerModel;
  final ReviewScheduler review;
  final AITutorService tutor;
  final EventBus events;

  const MindtreeEngines({
    required this.repo,
    required this.scheduler,
    required this.graph,
    required this.curriculum,
    required this.milestones,
    required this.assessment,
    required this.diagnostic,
    required this.feedback,
    required this.session,
    required this.activity,
    required this.adaptive,
    required this.mastery,
    required this.analytics,
    required this.learnerModel,
    required this.review,
    required this.tutor,
    required this.events,
  });
}

/// Собирает движки в порядке зависимостей (низ → верх).
///
/// [configProvider] — эффективный LLM-конфиг на текущий момент; уходит в
/// `configProvider` scheduler-а один-в-один, поэтому смена конфига на лету
/// работает так же, как в приложении (там конфиг живёт в
/// `llmConfigStateProvider`).
/// [scheduler] — готовый scheduler. Если передан, фабрика НЕ создаёт свой:
/// это точка подмены транспорта в тестах (и в приложении, где scheduler
/// создаётся провайдером). Если `null`, scheduler собирается из
/// [configProvider]/[schedulerConfig]/[cache]/[telemetry]/[llmCall].
/// [llmCall] — точка подмены транспорта (детерминированный fake для тестов и
/// headless-прогона); сам scheduler при этом сохраняет rate-limit/retry/кэш.
MindtreeEngines buildEngines({
  required MindtreeRepository repo,
  required llm_client.LLMConfig Function() configProvider,
  TreeScheduler? scheduler,
  SchedulerConfig? schedulerConfig,
  LLMCache? cache,
  LLMTelemetry? telemetry,
  LLMInvoke? llmCall,
}) {
  final sched = scheduler ??
      TreeScheduler(
        configProvider: configProvider,
        config: schedulerConfig,
        cache: cache,
        telemetry: telemetry,
        llmCall: llmCall,
      );

  final learnerModel = LearnerModelService(repo);
  final review = ReviewScheduler(repo);
  final events = EventBus(repo);

  final graph = KnowledgeGraphEngine(
    repo: repo,
    scheduler: sched,
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

  final curriculum = CurriculumEngine(
    repo: repo,
    scheduler: sched,
    learnerModel: learnerModel,
  );

  final milestones = MilestoneEngine(repo: repo, scheduler: sched);

  final assessment = AssessmentEngine(repo: repo, scheduler: sched);

  final diagnostic = DiagnosticEngine(repo: repo, scheduler: sched);

  final feedback = FeedbackEngine(repo: repo, scheduler: sched);

  final session = LearningSessionEngine(
    repo: repo,
    scheduler: sched,
    learnerModel: learnerModel,
    reviewScheduler: review,
    eventBus: events,
    curriculumEngine: curriculum,
    assessmentEngine: assessment,
  );

  final activity = LearningActivityService(
    engine: session,
    repo: repo,
    scheduler: sched,
  );

  final adaptive = AdaptiveLearningEngine(
    repo: repo,
    learnerModel: learnerModel,
    reviewScheduler: review,
    sessionEngine: session,
  );

  final mastery = MasteryEngine(
    repo: repo,
    learnerModel: learnerModel,
    scheduler: sched,
  );

  final analytics = AnalyticsService(repo: repo, learnerModel: learnerModel);

  final tutor = AITutorService(
    repo: repo,
    learnerModel: learnerModel,
    scheduler: sched,
  );

  return MindtreeEngines(
    repo: repo,
    scheduler: sched,
    graph: graph,
    curriculum: curriculum,
    milestones: milestones,
    assessment: assessment,
    diagnostic: diagnostic,
    feedback: feedback,
    session: session,
    activity: activity,
    adaptive: adaptive,
    mastery: mastery,
    analytics: analytics,
    learnerModel: learnerModel,
    review: review,
    tutor: tutor,
    events: events,
  );
}
