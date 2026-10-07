import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/analytics_screen.dart';

const _topicId = 't1';

/// Регрессия: ключевая метрика продукта Learning Gain / Time считалась в
/// `AnalyticsService`, но на экране аналитики не показывалась вовсе —
/// пользователь видел только «Понятий» и «Время».
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

Future<MindtreeRepository> _openRepo() async {
  final db = MindtreeDb(NativeDatabase.memory());
  final repo = MindtreeRepository(db);
  addTearDown(db.close);
  await repo.createTopic(const Topic(id: _topicId, name: 'Матан'));
  return repo;
}

/// Поднимает уровень с 1 на 2 → Learning Gain = 1 уровень.
Future<void> _raiseLevel(MindtreeRepository repo) async {
  final learner = LearnerModelService(repo);
  await learner.raiseOverallLevel(
    _topicId,
    MasteryLevel.basicUnderstanding,
    asInitial: true,
  );
  await learner.raiseOverallLevel(_topicId, MasteryLevel.solidUnderstanding);
}

/// Час достоверных занятий: `studyMinutes` = 60.
Future<void> _seedHourOfStudy(MindtreeRepository repo) async {
  await repo.createSession(const LearningSession(
    id: 's1',
    journeyId: 'j1',
    topicId: _topicId,
    goal: 'overview',
    startedAt: '2026-01-01T00:00:00.000',
  ));
  await repo.insertEvent(const LearningEvent(
    id: 'ev_ok',
    sessionId: 's1',
    type: LearningEventType.itemCompleted,
    durationMs: 60 * 60 * 1000,
  ));
}

Future<ProviderContainer> _container(MindtreeRepository repo) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    repositoryProvider.overrideWith((ref) async => repo),
  ]);
  addTearDown(container.dispose);
  // БД открыта на загрузке приложения — enginesProvider читает её сразу.
  await container.read(repositoryProvider.future);
  container.read(graphStoreProvider.notifier).state =
      const GraphState(topicId: _topicId, topicName: 'Матан');
  return container;
}

Future<void> _pumpScreen(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: AnalyticsScreen(topicId: _topicId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Learning Gain / Time выведен на экран: прирост, период и цена уровня',
      (tester) async {
    final repo = await _openRepo();
    await _seedHourOfStudy(repo);
    await _raiseLevel(repo);
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    // Заголовок блока совпадает с описанием раздела «Метрики» в навигации.
    expect(find.text('Прирост понимания и время'), findsOneWidget);
    // Прирост: 1 уровень (awareness→basic был стартовым, дальше solid).
    expect(find.text('+1 уровень понимания'), findsOneWidget);
    // Период и цена времени — человеческими единицами.
    expect(
      find.text('За 60 мин занятий — ~60 мин на уровень (1,0 уровня в час).'),
      findsOneWidget,
    );
    // Соседние карточки на месте.
    expect(find.text('Понятий'), findsOneWidget);
    expect(find.text('Время'), findsOneWidget);
  });

  testWidgets('без прироста блок честно говорит об этом', (tester) async {
    final repo = await _openRepo();
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    expect(find.text('Прирост понимания и время'), findsOneWidget);
    expect(find.text('Пока без прироста'), findsOneWidget);
    expect(
      find.text('Нет замеров времени занятий — метрика появится после занятий.'),
      findsOneWidget,
    );
  });
}
