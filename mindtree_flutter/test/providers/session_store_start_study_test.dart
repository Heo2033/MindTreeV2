import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';

const _nodeId = 'n1~abcdef01';

KnowledgeNode _node() => KnowledgeNode(
      id: _nodeId,
      topicId: 't1',
      parentId: null,
      level: 1,
      label: 'Производная',
      oneLiner: 'Предел отношения приращения функции к приращению аргумента.',
      details: '',
    );

CurriculumItem _item() => const CurriculumItem(
      id: 'i1',
      nodeId: _nodeId,
      label: 'Производная',
      order: 0,
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
    );

LearningSession _session() => LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: 't1',
      curriculum: Curriculum(sessionId: 's1', items: [_item()]),
    );

/// studyNode всегда падает — как при недоступном/зависшем LLM после дедлайна.
class _ThrowingStudyEngine extends LearningSessionEngine {
  _ThrowingStudyEngine({
    required super.repo,
    required super.scheduler,
    required super.learnerModel,
    required super.reviewScheduler,
    required super.eventBus,
    required super.curriculumEngine,
    required super.assessmentEngine,
  });

  @override
  Future<({Map<String, dynamic> content, KnowledgeNode node})> studyNode(
    String sessionId,
    String nodeId,
  ) async {
    throw Exception('LLM down (test)');
  }
}

class _OkStudyEngine extends LearningSessionEngine {
  _OkStudyEngine({
    required super.repo,
    required super.scheduler,
    required super.learnerModel,
    required super.reviewScheduler,
    required super.eventBus,
    required super.curriculumEngine,
    required super.assessmentEngine,
  });

  @override
  Future<({Map<String, dynamic> content, KnowledgeNode node})> studyNode(
    String sessionId,
    String nodeId,
  ) async {
    final node = await repo.getNode(nodeId);
    if (node == null) throw Exception('Node missing (test)');
    return (content: {'details': 'description (test)'}, node: node);
  }
}

class _OkActivityService extends LearningActivityService {
  _OkActivityService({
    required super.engine,
    required super.repo,
    required super.scheduler,
  });

  @override
  Future<LearningActivity> ensureActivity(String sessionId) async {
    return LearningActivity(
      sessionId: sessionId,
      itemId: 'i1',
      nodeId: _nodeId,
      nodeLabel: 'Производная',
      goal: 'overview',
      steps: const [
        ActivityStep(type: 'explain', title: 'Изучаем понятие', status: 'current'),
      ],
    );
  }
}

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late TreeScheduler scheduler;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    scheduler = TreeScheduler(
      configProvider: () => const llm_client.LLMConfig(isMock: true),
    );
    await repo.createTopic(const Topic(id: 't1', name: 'Математический анализ'));
    await repo.createJourney('j1', 't1');
    await repo.insertNodes([_node()]);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer(LearningSessionEngine engine,
      {LearningActivityService? activityService}) {
    final container = ProviderContainer(overrides: [
      learningSessionEngineProvider.overrideWithValue(engine),
      learningActivityServiceProvider.overrideWithValue(
        activityService ??
            _OkActivityService(
              engine: engine,
              repo: repo,
              scheduler: scheduler,
            ),
      ),
      sessionStoreProvider.overrideWith((ref) => SessionNotifier(ref)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('SessionNotifier.startStudy — сброс флага studying', () {
    test('ошибка LLM: studying=false, loading=false, error установлен', () async {
      final engine = _ThrowingStudyEngine(
        repo: repo,
        scheduler: scheduler,
        learnerModel: LearnerModelService(repo),
        reviewScheduler: ReviewScheduler(repo),
        eventBus: EventBus(repo),
        curriculumEngine: CurriculumEngine(repo: repo, scheduler: scheduler),
        assessmentEngine: AssessmentEngine(repo: repo, scheduler: scheduler),
      );
      final container = makeContainer(engine);
      final notifier = container.read(sessionStoreProvider.notifier);
      notifier.state = SessionState(session: _session(), currentItem: _item());

      await notifier.startStudy(_nodeId);

      // Регрессия «сессия зависает на спиннере»: раньше studying оставался true.
      expect(notifier.state.studying, isFalse);
      expect(notifier.state.loading, isFalse);
      expect(notifier.state.error, contains('LLM down'));
      expect(notifier.state.activity, isNull);
    });

    test('успех: studying=false, активность подставлена', () async {
      final engine = _OkStudyEngine(
        repo: repo,
        scheduler: scheduler,
        learnerModel: LearnerModelService(repo),
        reviewScheduler: ReviewScheduler(repo),
        eventBus: EventBus(repo),
        curriculumEngine: CurriculumEngine(repo: repo, scheduler: scheduler),
        assessmentEngine: AssessmentEngine(repo: repo, scheduler: scheduler),
      );
      final container = makeContainer(engine);
      final notifier = container.read(sessionStoreProvider.notifier);
      notifier.state = SessionState(session: _session(), currentItem: _item());

      await notifier.startStudy(_nodeId);

      expect(notifier.state.studying, isFalse);
      expect(notifier.state.loading, isFalse);
      expect(notifier.state.error, isNull);
      expect(notifier.state.activity, isNotNull);
      expect(notifier.state.activity!.steps, hasLength(1));
    });
  });
}