// Регрессии профиля обучающегося: мисконцепции и человеческие подписи.
//
// Раньше экран показывал сырые идентификаторы движка (`n3_b~1a2b3c4d`),
// а блока с мисконцепциями не было вовсе — модель замечала ошибочное
// понимание, но пользователь его не видел.
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
import 'package:mindtree_flutter/ui/screens/learner_model_screen.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _bId = 'n3_b~$_scope';

/// Фейк графа: экран сам дёргает `loadTopic` в initState ради подписей
/// узлов, в тесте подписи мы подставляем руками в состояние.
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

KnowledgeNode _nodeB() => KnowledgeNode(
      id: _bId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Понятие B',
      oneLiner: 'Суть понятия B.',
      details: 'Подробности понятия B.',
    );

Future<MindtreeRepository> _openRepo() async {
  final db = MindtreeDb(NativeDatabase.memory());
  final repo = MindtreeRepository(db);
  addTearDown(db.close);
  await repo.createTopic(const Topic(id: _topicId, name: 'Матан'));
  return repo;
}

Future<ProviderContainer> _container(MindtreeRepository repo) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    repositoryProvider.overrideWith((ref) async => repo),
  ]);
  addTearDown(container.dispose);
  await container.read(repositoryProvider.future);
  container.read(graphStoreProvider.notifier).state = GraphState(
    topicId: _topicId,
    topicName: 'Матан',
    nodes: [_nodeB()],
  );
  return container;
}

Future<void> _pumpScreen(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: LearnerModelScreen(topicId: _topicId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Появление текста не должно сопровождаться сырым id узла.
void _expectNoRawNodeIds(WidgetTester tester) {
  expect(
    find.textContaining(_bId),
    findsNothing,
    reason: 'внутренние идентификаторы движка пользователю не показываем',
  );
}

void main() {
  testWidgets('мисконцепции: понятие подписью и описание ошибки',
      (tester) async {
    final repo = await _openRepo();
    final learner = LearnerModelService(repo);
    await learner.addMisconception(
      _topicId,
      _bId,
      MisconceptionType.confused,
      'Причину и следствие перепутаны местами',
    );
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    expect(find.text('Мисконцепции'), findsOneWidget);
    // Подпись понятия, а не scoped-id (профиль и мисконцепция — оба здесь).
    expect(find.text('Понятие B'), findsWidgets);
    expect(
      find.text('Причину и следствие перепутаны местами'),
      findsOneWidget,
    );
    _expectNoRawNodeIds(tester);
  });

  testWidgets('мисконцепций нет — честное «Пока нет», блок не спрятан',
      (tester) async {
    final repo = await _openRepo();
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    expect(find.text('Мисконцепции'), findsOneWidget);
    expect(find.text('Пока нет'), findsOneWidget);
  });

  testWidgets('пустое описание ошибки заменяется текстом по типу',
      (tester) async {
    final repo = await _openRepo();
    final learner = LearnerModelService(repo);
    await learner.addMisconception(
      _topicId,
      _bId,
      MisconceptionType.incomplete,
      '',
    );
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    expect(find.text('Мисконцепции'), findsOneWidget);
    expect(
      find.text('Ответ неполон: не раскрыта ключевая часть понятия'),
      findsOneWidget,
    );
  });

  testWidgets('профили и списки не показывают сырые id узлов',
      (tester) async {
    final repo = await _openRepo();
    final learner = LearnerModelService(repo);
    // Низкое мастерство → понятие попадает и в «Слабые понятия».
    await learner.recordEvidence(_topicId, _bId, const {
      'understanding': 0.2,
      'recall': 0.2,
      'application': 0.2,
      'transfer': 0.2,
    });
    final container = await _container(repo);

    await _pumpScreen(tester, container);

    expect(find.text('Профили концептов'), findsOneWidget);
    expect(find.text('Слабые понятия'), findsOneWidget);
    expect(find.text('Понятие B'), findsWidgets);
    _expectNoRawNodeIds(tester);
  });
}
