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
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';
const _n2 = 'n2~ab01';

KnowledgeNode _node(String id, String? parentId, int level) => KnowledgeNode(
      id: id,
      topicId: _topicId,
      parentId: parentId,
      level: level,
      label: 'Концепт $id',
      oneLiner: 'Определение $id',
      details: '',
      estimatedTimeMinutes: 5,
    );

CurriculumItem _item(String id, String nodeId, int order) => CurriculumItem(
      id: id,
      nodeId: nodeId,
      label: 'Концепт $nodeId',
      order: order,
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
    );

/// Регрессия «после первого концепта второй сразу завершился»: после
/// completeConcept(первого) пройденная активность обязана уйти из стейта
/// (copуWith сбрасывает activity), а startStudy(второго) открывает его шаги
/// (explain first, currentStep == 0), а не экран «Концепт проработан».
void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late TreeScheduler scheduler;
  late LearningSessionEngine engine;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    // isMock: LLM недоступен — все вызовы падают в детерминированные fallback
    // (как в реальном окружении пользователя при недоступном провайдере).
    scheduler = TreeScheduler(
      configProvider: () => const llm_client.LLMConfig(isMock: true),
    );
    engine = LearningSessionEngine(
      repo: repo,
      scheduler: scheduler,
      learnerModel: LearnerModelService(repo),
      reviewScheduler: ReviewScheduler(repo),
      eventBus: EventBus(repo),
      curriculumEngine: CurriculumEngine(repo: repo, scheduler: scheduler),
      assessmentEngine: AssessmentEngine(repo: repo, scheduler: scheduler),
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Тема'));
    await repo.createJourney('j1', _topicId);
    await repo.insertNodes([_node(_n1, null, 1), _node(_n2, _n1, 2)]);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      repositoryProvider.overrideWith((ref) async => repo),
      schedulerProvider.overrideWithValue(scheduler),
      learningSessionEngineProvider.overrideWithValue(engine),
      sessionStoreProvider.overrideWith((ref) => SessionNotifier(ref)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('после первого концепта активность сбрасывается и второй концепт '
      'открывается с шагами', () async {
    final session = LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      curriculum: Curriculum(
        sessionId: 's1',
        items: [_item('i1', _n1, 0), _item('i2', _n2, 1)],
      ),
      currentIndex: 0,
    );
    await repo.createSession(session);

    final c = makeContainer();
    // Как в реальном приложении (appInitializedProvider): ждём открытия БД,
    // иначе первый синхронный ref.read(activityServiceProvider) упадёт
    // «Database not ready».
    await c.read(repositoryProvider.future);
    final notifier = c.read(sessionStoreProvider.notifier);
    notifier.state = SessionState(
      session: session,
      currentItem: _item('i1', _n1, 0),
      currentIndex: 0,
    );

    // ── Концепт 1 ──
    await notifier.startStudy(_n1);
    final act1 = notifier.state.activity;
    expect(act1, isNotNull, reason: 'startStudy первого концепта строит шаги');
    expect(act1!.steps, hasLength(4));

    await notifier.answerStep(0, '');
    await notifier.answerStep(1, '');
    await notifier.answerStep(2, '0');
    await notifier.answerStep(3, 'мой ответ');

    await notifier.completeConcept('i1', nodeId: _n1, quality: 'correct');
    expect(notifier.state.error, isNull);
    expect(notifier.state.currentItem?.nodeId, _n2,
        reason: 'текущий концепт переходит на второй');
    expect(notifier.state.activity, isNull,
        reason: 'пройденная активность обязана исчезнуть из стейта — иначе '
            'следующий концепт показывает «Концепт проработан»');

    // ── Концепт 2 ──
    await notifier.startStudy(_n2);
    expect(notifier.state.error, isNull);
    final act2 = notifier.state.activity;
    expect(act2, isNotNull, reason: 'startStudy второго концепта строит шаги');
    expect(act2!.nodeId, _n2);
    expect(act2.steps, hasLength(4));
    expect(act2.isComplete, isFalse,
        reason: 'второй концепт не должен быть завершён сразу');
    expect(act2.currentStep, 0);
    expect(act2.steps.first.isAnswered, isFalse);
    expect(act2.steps.first.type, 'explain');
  });
}