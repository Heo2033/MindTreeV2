// Регрессия: последний концепт сессии должен уводить в итоговый тест.
//
// Двигатель клампит `currentIndex` на последнем пункте плана
// (`LearningSessionEngine.markItemCompleted`), поэтому после закрытия
// последнего концепта `currentItem` остаётся НЕ null — и экран раньше
// показывал карточку «Изучать» уже пройденного понятия вместо завершения.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~aaaa1111';

class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Стор без движка: закрытие понятия и финиш задаются тестом, чтобы проверить
/// именно навигацию экрана, а не персистентность сессии.
class _FakeSessionNotifier extends SessionNotifier {
  _FakeSessionNotifier(super.ref);

  int finalizeCalls = 0;

  void seed({
    required LearningSession session,
    required CurriculumItem current,
    LearningActivity? activity,
  }) {
    state = SessionState(
      session: session,
      currentItem: current,
      currentIndex: session.currentIndex,
      activity: activity,
    );
  }

  @override
  Future<void> completeConcept(
    String itemId, {
    String? nodeId,
    String? quality,
  }) async {
    final session = state.session;
    if (session == null) return;
    final items = [
      for (final i in session.curriculum.items)
        i.id == itemId
            ? i.copyWith(status: CurriculumItemStatus.completed)
            : i,
    ];
    state = state.copyWith(
      session: session.copyWith(
        curriculum: Curriculum(
          sessionId: session.id,
          items: items,
          totalEstimatedMinutes: session.curriculum.totalEstimatedMinutes,
        ),
      ),
      clearActivity: true,
      loading: false,
      error: null,
    );
  }

  @override
  Future<String?> finalize() async {
    finalizeCalls += 1;
    return 'asmt1';
  }
}

CurriculumItem _item(String id, String label,
        {CurriculumItemStatus status = CurriculumItemStatus.pending}) =>
    CurriculumItem(
      id: id,
      nodeId: _n1,
      label: label,
      order: int.parse(id.replaceAll(RegExp(r'\D'), '')),
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
      status: status,
    );

/// Активность, все шаги которой закрыты → карточка «Завершить концепт».
/// `currentStep: 2` — двигатель ставит индекс на первый незакрытый шаг,
/// а их больше нет.
const _doneActivity = LearningActivity(
  sessionId: 's1',
  itemId: 'i1',
  nodeId: _n1,
  nodeLabel: 'Рекурсия',
  goal: 'overview',
  currentStep: 2,
  steps: [
    ActivityStep(
      type: 'explain',
      title: 'Изучаем понятие',
      body: 'Текст объяснения.',
      status: 'answered',
    ),
    ActivityStep(
      type: 'recall',
      title: 'Проверка',
      body: 'Вопрос?',
      status: 'answered',
      correct: true,
    ),
  ],
);

Future<(ProviderContainer, _FakeSessionNotifier, GoRouter)> _pumpScreen(
  WidgetTester tester, {
  required LearningSession session,
  required CurriculumItem current,
  LearningActivity? activity,
}) async {
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = MindtreeRepository(db);
  final scheduler = TreeScheduler(
    configProvider: () => const llm_client.LLMConfig(isMock: true),
  );

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWith((ref) async => repo),
    schedulerProvider.overrideWithValue(scheduler),
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => _FakeSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);

  container.read(graphStoreProvider.notifier).state = const GraphState(
    topicId: _topicId,
    topicName: 'Теорема остановки',
  );
  (container.read(sessionStoreProvider.notifier) as _FakeSessionNotifier).seed(
    session: session,
    current: current,
    activity: activity,
  );

  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const SessionScreen(topicId: _topicId),
    ),
    GoRoute(
      path: '/topic/check/final',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('ИТОГОВЫЙ ТЕСТ'))),
    ),
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
    container.read(sessionStoreProvider.notifier) as _FakeSessionNotifier,
    router,
  );
}

LearningSession _session(List<CurriculumItem> items, {int currentIndex = 0}) =>
    LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      status: SessionStatus.active,
      currentIndex: currentIndex,
      curriculum: Curriculum(
        sessionId: 's1',
        items: items,
        totalEstimatedMinutes: items.length * 5,
      ),
    );

void main() {
  testWidgets('последний концепт закрыт → сразу итоговый тест',
      (tester) async {
    final (_, fake, router) = await _pumpScreen(
      tester,
      session: _session([_item('i1', 'Раздел 1')]),
      current: _item('i1', 'Раздел 1'),
      activity: _doneActivity,
    );

    expect(find.text('Завершить концепт'), findsOneWidget);

    await tester.tap(find.text('Завершить концепт'));
    await tester.pumpAndSettle();

    expect(fake.finalizeCalls, 1);
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/topic/check/final');
  });

  testWidgets('концепт не последний → остаёмся в сессии', (tester) async {
    final (_, fake, router) = await _pumpScreen(
      tester,
      session: _session([_item('i1', 'Раздел 1'), _item('i2', 'Раздел 2')]),
      current: _item('i1', 'Раздел 1'),
      activity: _doneActivity,
    );

    await tester.tap(find.text('Завершить концепт'));
    await tester.pumpAndSettle();

    expect(fake.finalizeCalls, 0);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    // Следующий раздел плана ждёт своего часа.
    expect(find.text('Изучать'), findsOneWidget);
  });

  testWidgets(
      'план пройден, но finalize не дал id → карточка «Все концепты изучены!» '
      'вместо кнопки «Изучать» у уже закрытого понятия', (tester) async {
    // Регрессия исходного бага: `currentItem` указывает на завершённый
    // последний пункт, и раньше экран показывал для него «Изучать».
    await _pumpScreen(
      tester,
      session: _session([
        _item('i1', 'Раздел 1', status: CurriculumItemStatus.completed),
      ]),
      current: _item('i1', 'Раздел 1',
          status: CurriculumItemStatus.completed),
    );

    expect(find.text('Все концепты изучены!'), findsOneWidget);
    expect(find.text('Перейти к итоговому тесту'), findsOneWidget);
    expect(find.text('Изучать'), findsNothing);
    // На пройденном плане баннер «Достаточно» не дублирует смысл.
    expect(find.text('Достаточно для твоей цели'), findsNothing);
  });
}
