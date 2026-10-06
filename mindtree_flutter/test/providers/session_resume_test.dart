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

// Ид-конвенции: узлы — scoped-иды (`~` + 8 hex), сессии/пункты плана —
// префикс + 8 символов, как в shortIdWith(). Случайности нет.
const _topicId = 't1';
const _journeyId = 'journey_a1b2c3d4';
const _sessionId = 'session_a1b2c3d4';
const _n1 = 'n1~ab01cd02';
const _n2 = 'n2~cd03ef04';

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

CurriculumItem _item(
  String id,
  String nodeId,
  int order, {
  CurriculumItemStatus status = CurriculumItemStatus.pending,
  String? label,
}) =>
    CurriculumItem(
      id: id,
      nodeId: nodeId,
      label: label ?? 'Раздел ${order + 1}',
      order: order,
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
      status: status,
    );

/// Сессия из БД «после перезапуска»: первый пункт пройден, второй нет.
LearningSession _unfinished({int currentIndex = 1, List<CurriculumItem>? items}) =>
    LearningSession(
      id: _sessionId,
      journeyId: _journeyId,
      topicId: _topicId,
      goal: 'overview',
      status: SessionStatus.active,
      curriculum: Curriculum(
        sessionId: _sessionId,
        items: items ??
            [
              _item('ci_a1b2c3d4', _n1, 0, status: CurriculumItemStatus.completed),
              _item('ci_e5f6a7b8', _n2, 1),
            ],
      ),
      currentIndex: currentIndex,
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late TreeScheduler scheduler;
  late LearningSessionEngine engine;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    // isMock: LLM недоступен — сеть и ключи не нужны, вызовы детерминированы.
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
    await repo.createJourney(_journeyId, _topicId);
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

  group('SessionNotifier.loadResumable — предложение «Продолжить»', () {
    test('находит незавершённую сессию и НЕ меняет state.session', () async {
      await repo.createSession(_unfinished());

      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);
      final alreadyRunning = _unfinished();
      n.state = SessionState(session: alreadyRunning);

      await n.loadResumable(_topicId);

      expect(n.state.resumable?.id, _sessionId,
          reason: 'карточка «Продолжить» должна получить сессию из БД');
      expect(n.state.session, same(alreadyRunning),
          reason: 'loadResumable не трогает активную сессию');
      expect(n.state.loading, isFalse,
          reason: 'проверка локальная — экран блокировать нельзя');
      expect(n.state.error, isNull);
    });

    test('не затирает ошибку уже идущей сессии', () async {
      await repo.createSession(_unfinished());

      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);
      n.state = const SessionState(session: null, error: 'LLM недоступен');

      await n.loadResumable(_topicId);

      expect(n.state.resumable?.id, _sessionId);
      expect(n.state.error, 'LLM недоступен',
          reason: 'предложение продолжить не должно гасить ошибку сессии');
    });

    test('завершённая сессия не предлагается', () async {
      await repo.createSession(_unfinished().copyWith(status: SessionStatus.completed));

      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);

      await n.loadResumable(_topicId);

      expect(n.state.resumable, isNull);
      expect(n.state.session, isNull);
      expect(n.state.error, isNull);
    });
  });

  group('SessionNotifier.resumeSession — перенос в активную сессию', () {
    test('переносит resumable в session и дочитывает currentItem/currentIndex',
        () async {
      await repo.createSession(_unfinished());

      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);

      await n.loadResumable(_topicId);
      expect(n.state.resumable, isNotNull);
      expect(n.state.session, isNull,
          reason: 'до тапа «Продолжить» активной сессии нет');

      await n.resumeSession();

      expect(n.state.session?.id, _sessionId);
      expect(n.state.resumable, isNull, reason: 'предложение использовано');
      expect(n.state.currentItem?.id, 'ci_e5f6a7b8',
          reason: 'currentItem дочитан по id из БД');
      expect(n.state.currentIndex, 1);
      expect(n.state.error, isNull);
      expect(n.state.loading, isFalse);
    });

    test('resumable == null — безопасный no-op', () async {
      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);
      n.state = const SessionState();

      await n.resumeSession();

      expect(n.state.session, isNull);
      expect(n.state.resumable, isNull);
      expect(n.state.currentItem, isNull);
      expect(n.state.currentIndex, 0);
      expect(n.state.error, isNull);
    });

    test('resumable == null при активной сессии — сессия не трогается',
        () async {
      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);
      n.state = SessionState(session: _unfinished());

      await n.resumeSession();

      expect(n.state.session?.id, _sessionId);
      expect(n.state.error, isNull);
    });
  });

  group('SessionNotifier.reset', () {
    test('сбрасывает и resumable, и session', () async {
      await repo.createSession(_unfinished());

      final c = makeContainer();
      await c.read(repositoryProvider.future);
      final n = c.read(sessionStoreProvider.notifier);

      await n.loadResumable(_topicId);
      expect(n.state.resumable, isNotNull);

      n.reset();

      expect(n.state.resumable, isNull,
          reason: 'после reset предложение «Продолжить» не должно всплыть');
      expect(n.state.session, isNull);
      expect(n.state.error, isNull);
      expect(n.state.loading, isFalse);
    });
  });
}
