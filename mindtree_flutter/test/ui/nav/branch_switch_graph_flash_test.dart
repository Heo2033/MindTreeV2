import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/current_topic.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/router.dart';
import 'package:mindtree_flutter/ui/screens/focus_screen.dart';
import 'package:mindtree_flutter/ui/screens/graph_screen.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';

/// Регрессия: при переключении между пунктами раздела «Учить» (одна ветка
/// `StatefulShellBranch`) экран предыдущего маршрута — например GraphScreen —
/// не должен оставаться на экране.
///
/// Механим до фикса: go_router внутри ветки объявленно заменяет страницу в
/// `Navigator.pages`, уходящая страница при этом жила весь
/// `reverseTransitionDuration` (300 мс по умолчанию), а переход у нас не
/// анимируется (`IgnorePointerPageTransitionsBuilder` рисует ребёнка как есть).
/// Новая страница ещё не успевает стать `opaque`, поэтому старая оставалась
/// onstage и видна сквозь прозрачный фон `SessionScreen` ~300 мс — «мелькание».
///
/// Проверяем `find.byType(GraphScreen)` без `skipOffstage: false`: это ровно
/// те элементы, которые рисует `_Theater` (см. `debugVisitOnstageChildren`).
/// Один кадр в дереве при `maintainState` допустим — такой элемент не
/// леится, не красится и не получает hit-test; после завершения кадров он
/// обязан быть размонтирован полностью.

List<KnowledgeNode> _tree() => [
      const KnowledgeNode(
        id: 'n1',
        topicId: 't1',
        parentId: null,
        level: 1,
        label: 'Корень',
        oneLiner: 'Корень темы.',
        details: 'О корне.',
      ),
      const KnowledgeNode(
        id: 'n2',
        topicId: 't1',
        parentId: 'n1',
        level: 2,
        label: 'Раздел А',
        oneLiner: 'Первый раздел.',
        details: 'Про раздел А.',
      ),
      const KnowledgeNode(
        id: 'n3',
        topicId: 't1',
        parentId: 'n1',
        level: 2,
        label: 'Раздел Б',
        oneLiner: 'Второй раздел.',
        details: 'Про раздел Б.',
      ),
    ];

/// Граф-стор без БД: детерминированное дерево, без фоновой заливки контента.
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref) {
    state = _loaded('t1');
  }

  static GraphState _loaded(String id) => GraphState(
        topicId: id,
        topicName: 'Тема',
        nodes: _tree(),
        visibleLevel: 2,
      );

  @override
  Future<void> loadTopic(String id) async {
    state = _loaded(id);
  }

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

/// Сессия без движков: карточка старта рендерится из пустого состояния.
class _FakeSessionNotifier extends SessionNotifier {
  _FakeSessionNotifier(super.ref);

  @override
  Future<void> loadResumable(String topicId) async {}

  @override
  Future<void> resume() async {}
}

class _FakeLearnerNotifier extends LearnerNotifier {
  _FakeLearnerNotifier(super.ref);

  @override
  Future<void> load(String topicId) async {}
}

/// Поднимает реальный `appRouter` с фейковыми сторами и памятной БД.
Future<ProviderContainer> _pumpApp(WidgetTester tester, String location) async {
  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);

  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWith((ref) async => db),
    currentTopicIdProvider.overrideWith((ref) => 't1'),
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => _FakeSessionNotifier(ref)),
    learnerStoreProvider.overrideWith((ref) => _FakeLearnerNotifier(ref)),
  ]);
  addTearDown(container.dispose);

  appRouter.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: appRouter,
        theme: lightTheme(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Число GraphScreen, которые рисуются (onstage) на каждом из 25 кадров по
/// 16 мс после тапа по чипу [label].
Future<List<int>> _tapChipAndCountGraph(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  final counts = <int>[];
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    counts.add(find.byType(GraphScreen).evaluate().length);
  }
  return counts;
}

bool _chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  testWidgets('Фокус → СессИЯ: GraphScreen не показывается ни на одном кадре',
      (tester) async {
    await _pumpApp(tester, '/topic/learn/focus');
    expect(find.byType(FocusScreen), findsOneWidget);

    final counts = await _tapChipAndCountGraph(tester, 'Сессия');

    expect(counts, everyElement(0),
        reason: 'GraphScreen оказался на экране при переключении '
            'Фокус → СессИЯ: $counts');
    expect(find.byType(SessionScreen), findsOneWidget);
    // Подсветка активного чипа не должна сломаться.
    expect(_chipSelected(tester, 'Сессия'), isTrue);
    expect(_chipSelected(tester, 'Фокус'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Граф → СессИЯ: уходящий GraphScreen не остаётся на экране',
      (tester) async {
    await _pumpApp(tester, '/topic/learn/graph');
    expect(find.byType(GraphScreen), findsOneWidget);

    final counts = await _tapChipAndCountGraph(tester, 'Сессия');

    expect(counts, everyElement(0),
        reason: 'GraphScreen оставался на экране после перехода на СессИЯ: '
            'первые кадры после тапа он ещё рисовался — $counts');
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(_chipSelected(tester, 'Сессия'), isTrue);
    // После завершения перехода экран графа обязан быть размонтирован.
    expect(find.byType(GraphScreen, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Граф → Фокус → СессИЯ подряд: GraphScreen выгружается',
      (tester) async {
    await _pumpApp(tester, '/topic/learn/graph');

    // Пользователь жмёт чипы один за другим, не дожидаясь конца кадров.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Фокус'));
    await tester.pump(const Duration(milliseconds: 16));
    final counts = await _tapChipAndCountGraph(tester, 'Сессия');

    expect(counts, everyElement(0),
        reason: 'GraphScreen ещё рисовался во время переключения на СессИЯ '
            'после недавнего визита на граф: $counts');
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(find.byType(GraphScreen, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
