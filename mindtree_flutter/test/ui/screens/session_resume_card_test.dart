import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'package:mindtree_flutter/ui/screens/session_screen.dart';

const _topicId = 't1';
const _journeyId = 'journey_a1b2c3d4';
const _sessionId = 'session_a1b2c3d4';
const _n1 = 'n1~ab01cd02';
const _n2 = 'n2~cd03ef04';

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

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

/// Сессия «после перезапуска приложения»: один из двух пунктов плана пройден.
LearningSession _unfinished({int currentIndex = 1, bool allCompleted = false}) {
  final items = [
    _item('ci_a1b2c3d4', _n1, 0, status: CurriculumItemStatus.completed),
    _item(
      'ci_e5f6a7b8',
      _n2,
      1,
      status: allCompleted ? CurriculumItemStatus.completed : CurriculumItemStatus.pending,
    ),
  ];
  return LearningSession(
    id: _sessionId,
    journeyId: _journeyId,
    topicId: _topicId,
    goal: 'overview',
    status: SessionStatus.active,
    curriculum: Curriculum(sessionId: _sessionId, items: items),
    currentIndex: currentIndex,
  );
}

/// Поднимает SessionScreen с in-memory БД, реальным стором и подменённым
/// graph-стором (без дерева). [session] == null — в БД сессий нет.
Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  LearningSession? session,
}) async {
  final db = MindtreeDb(NativeDatabase.memory());
  final repo = MindtreeRepository(db);
  addTearDown(db.close);

  final scheduler = TreeScheduler(
    configProvider: () => const llm_client.LLMConfig(isMock: true),
  );
  final engine = LearningSessionEngine(
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
  if (session != null) {
    await repo.createSession(session);
  }

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWith((ref) async => repo),
    schedulerProvider.overrideWithValue(scheduler),
    learningSessionEngineProvider.overrideWithValue(engine),
    sessionStoreProvider.overrideWith((ref) => SessionNotifier(ref)),
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  // Как в реальном приложении (appInitializedProvider): ждём открытия БД,
  // иначе enginesProvider упадёт «Database not ready».
  await container.read(repositoryProvider.future);
  container.read(graphStoreProvider.notifier).state = const GraphState(
    topicId: _topicId,
    topicName: 'Тема',
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SessionScreen(topicId: _topicId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return container;
}

void main() {
  testWidgets(
      'есть незавершённая сессия — карточка «Продолжить» над стартовой, '
      'тап открывает активную сессию', (tester) async {
    await _pumpScreen(tester, session: _unfinished());

    // Карточка продолжения видна, карточка «начать заново» осталась ниже.
    expect(find.text('Продолжить сессию'), findsOneWidget);
    expect(find.text('Пройдено 1 из 2 разделов'), findsOneWidget);
    expect(find.text('Остановились на «Раздел 2»'), findsOneWidget);
    expect(find.text('Начать сессию'), findsOneWidget);

    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    // Предложение использовано: открылась активная сессия, авто-навигации нет
    // (мы ровно там, куда вёл тап — экран сессии).
    expect(find.text('Продолжить сессию'), findsNothing);
    expect(find.text('План сессии'), findsOneWidget);
    expect(find.text('1/2 концептов'), findsOneWidget);
    expect(find.text('Изучать'), findsOneWidget);
  });

  testWidgets('незавершённых сессий нет — карточки «Продолжить» нет',
      (tester) async {
    // В БД только завершённая сессия — предлагать нечего.
    await _pumpScreen(
      tester,
      session: _unfinished().copyWith(status: SessionStatus.completed),
    );

    expect(find.text('Продолжить сессию'), findsNothing);
    expect(find.text('Пройдено 1 из 2 разделов'), findsNothing);
    expect(find.text('Начать сессию'), findsOneWidget);
  });

  testWidgets(
      'сессия, где все пункты плана пройдена, не предлагается для '
      'продолжения', (tester) async {
    await _pumpScreen(
      tester,
      session: _unfinished(currentIndex: 2, allCompleted: true),
    );

    expect(find.text('Продолжить сессию'), findsNothing);
    expect(find.text('Пройдено 2 из 2 разделов'), findsNothing);
    // Способ проигнорировать предложение — и единственный доступный путь.
    expect(find.text('Начать сессию'), findsOneWidget);
  });
}
