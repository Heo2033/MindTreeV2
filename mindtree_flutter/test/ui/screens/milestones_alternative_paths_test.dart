// Шаг 5 аудита (Continue): alternativePaths движок сохраняет вместе с вехой,
// но экран их не показывал. Здесь — рендер «возможных направлений» и статус
// «не готовы», когда данных нет, плюс то, что действие у направления то же,
// что у основного пути: старт сессии вехи — через пикер бюджета времени
// («сколько у меня сейчас времени» задаётся на входе в сессию).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/milestones_screen.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';

const _topicId = 't1';

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Сессия-заглушка: фиксирует параметры создания, без БД и LLM.
class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier(super.ref);

  final List<String?> createdMilestones = [];
  final List<int> createdBudgets = [];

  @override
  Future<void> createSession(
    String topicId, {
    String goal = 'overview',
    String? milestoneId,
    int timeBudget = 30,
  }) async {
    createdMilestones.add(milestoneId);
    createdBudgets.add(timeBudget);
  }

  @override
  Future<void> startStudy(String nodeId) async {}
}

Widget _routeStub(String text) => Scaffold(body: Center(child: Text(text)));

/// Две вехи: активная — с альтернативными путями, следующая — без них.
Future<MindtreeRepository> _seedDb() async {
  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = MindtreeRepository(db);
  await repo.createTopic(const Topic(id: _topicId, name: 'Тема'));
  await repo.createJourney('j1', _topicId);
  await repo.insertMilestones(
    [
      LearningMilestone(
        id: 'ms_active',
        level: MasteryLevel.basicUnderstanding,
        title: 'Базовое понимание',
        status: MilestoneStatus.active,
        estimatedHours: 3,
        alternativePaths: const [
          LearningPath(
            id: 'p1',
            title: 'Через практику',
            description: 'Сразу решаем задачи по теме',
            estimatedHours: 2,
          ),
          LearningPath(
            id: 'p2',
            title: 'Через теорию',
            description: 'Сначала разбираем основы',
            estimatedHours: 1.5,
          ),
        ],
      ),
      const LearningMilestone(
        id: 'ms_next',
        level: MasteryLevel.solidUnderstanding,
        title: 'Уверенное понимание',
        status: MilestoneStatus.notStarted,
      ),
    ],
    journeyId: 'j1',
  );
  return repo;
}

Future<(ProviderContainer, FakeSessionNotifier, GoRouter)> _pumpScreen(
  WidgetTester tester,
  MindtreeRepository repo,
) async {
  // Высокий экран, чтобы ListView показал обе вехи без прокрутки.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWith((ref) async => repo),
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => FakeSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  // FutureProvider: экран читает valueOrNull в initState — ждём завершения.
  await container.read(repositoryProvider.future);
  container.read(graphStoreProvider.notifier).state =
      const GraphState(topicId: _topicId, topicName: 'Тема');

  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const MilestonesScreen(topicId: _topicId),
    ),
    GoRoute(path: '/topic/learn/session', builder: (_, _) => _routeStub('Сессия')),
    GoRoute(path: '/topic/learn/graph', builder: (_, _) => _routeStub('Граф')),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return (
    container,
    container.read(sessionStoreProvider.notifier) as FakeSessionNotifier,
    router,
  );
}

void main() {
  testWidgets('альтернативные направления рендерятся у вехи с оценкой времени',
      (tester) async {
    final repo = await _seedDb();
    final (container, _, _) = await _pumpScreen(tester, repo);

    expect(find.text('Возможные направления'), findsOneWidget);
    expect(find.text('Через практику'), findsOneWidget);
    expect(find.text('Через теорию'), findsOneWidget);
    expect(find.text('Сразу решаем задачи по теме'), findsOneWidget);
    // Оценка по времени: целые часы без «.0», дробные — с одним знаком.
    expect(find.text('≈ 2 ч'), findsOneWidget);
    expect(find.text('≈ 1.5 ч'), findsOneWidget);
    // Кнопка действия у каждого направления.
    expect(find.text('Начать сессию'), findsNWidgets(2));
    expect(container.read(sessionStoreProvider.notifier), isNotNull);
  });

  testWidgets('направление ведёт в сессию вехи, у которой оно записано',
      (tester) async {
    final repo = await _seedDb();
    final (_, session, router) = await _pumpScreen(tester, repo);

    await tester.tap(find.text('Начать сессию').first);
    await tester.pumpAndSettle();

    // Старт перехватывает пикер бюджета — без подтверждения сессии нет.
    expect(find.text('Сколько времени у тебя есть?'), findsOneWidget);
    expect(session.createdMilestones, isEmpty);

    await tester.tap(find.widgetWithText(AppButton, 'Начать'));
    await tester.pumpAndSettle();

    expect(session.createdMilestones, ['ms_active'],
        reason: 'действие направления — та же сессия вехи, что и у основного пути');
    expect(session.createdBudgets, [30],
        reason: 'бюджет — из выбранного в пикере, а не из темы');
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/topic/learn/session');
  });

  testWidgets('отмена пикера не запускает сессию', (tester) async {
    final repo = await _seedDb();
    final (_, session, router) = await _pumpScreen(tester, repo);

    await tester.tap(find.text('Начать сессию').first);
    await tester.pumpAndSettle();
    expect(find.text('Сколько времени у тебя есть?'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Отмена'));
    await tester.pumpAndSettle();

    expect(session.createdMilestones, isEmpty);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('без данных об альтернативах — статус «пока не готовы»',
      (tester) async {
    final repo = await _seedDb();
    await _pumpScreen(tester, repo);

    // У вехи без alternativePaths — аккуратный статус вместо пустоты.
    expect(find.text('Другие направления пока не готовы'), findsOneWidget);
    // И она не получает секцию «Возможные направления».
    expect(find.text('Возможные направления'), findsOneWidget);
    expect(find.text('Начать сессию'), findsNWidgets(2));
  });
}
