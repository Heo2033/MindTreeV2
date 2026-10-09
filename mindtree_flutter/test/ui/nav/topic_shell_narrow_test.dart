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
import 'package:mindtree_flutter/ui/screens/milestones_screen.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';

/// Мобильный режим оболочки темы (ширина < 600dp):
/// - разделы — в нижней `NavigationBar`, а не в боковом `NavigationRail`;
/// - чипы ветки раздела переносятся на строки (без горизонтального скролла);
/// - на экране нет переполнений (ошибка layout падала бы в `takeException`).

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
Future<void> _pumpApp(WidgetTester tester, String location) async {
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
}

void main() {
  testWidgets('узкий экран: нижняя панель разделов вместо rail, без переполнений',
      (tester) async {
    // 360x740 logical px — типичный телефон в портрете.
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, '/topic/learn/focus');

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Переполнения строк/колонок падают здесь же.
    expect(tester.takeException(), isNull);

    // Ветка раздела «Учить» доступна чипами без горизонтального скролла.
    for (final label in const ['Фокус', 'Сессия', 'Граф', 'Репетитор']) {
      expect(
        find.widgetWithText(ChoiceChip, label),
        findsOneWidget,
        reason: 'чип $label должен быть на экране',
      );
    }

    await tester.tap(find.widgetWithText(ChoiceChip, 'Сессия'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкий экран: переключение раздела через нижнюю панель',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, '/topic/learn/focus');
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);

    await tester.tap(find.text('Прогресс'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.byType(MilestonesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('широкий экран: rail и ряд чипов под шапкой остаются',
      (tester) async {
    // 800x600 — прежний десктопный режим (размер по умолчанию в тестах).
    await _pumpApp(tester, '/topic/learn/focus');

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(MilestonesScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
