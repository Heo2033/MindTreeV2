import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/graph_screen.dart';

/// Граф-нотифаер без БД и LLM: фиксируем вызовы expandNode, остальное — no-op.
class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  final List<String> expanded = [];
  final List<String> generated = [];

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {
    expanded.add(nodeId);
  }

  @override
  Future<void> generateContent(String nodeId) async {
    generated.add(nodeId);
  }
}

class FakeLearnerNotifier extends LearnerNotifier {
  FakeLearnerNotifier(super.ref);

  @override
  Future<void> load(String topicId) async {}
}

KnowledgeNode _node(
  String id,
  int level, {
  String? parentId,
  String label = '',
}) =>
    KnowledgeNode(
      id: id,
      topicId: 't1',
      parentId: parentId,
      level: level,
      label: label,
      oneLiner: '',
      details: '',
      state: NodeState.structureGenerated,
    );

KnowledgeNode _root() => _node('n1', 1, label: 'Корень');

/// n2 (level 2) имеет скрытого ребёнка n4 (level 3). Панель отбирает узлы
/// через nodeActions.canReveal, который обходит ВСЕХ потомков, поэтому при
/// visibleLevel=2 кандидатами становятся и корень n1, и n2.
List<KnowledgeNode> _deepTree() => [
      _root(),
      _node('n2', 2, parentId: 'n1', label: 'Раздел А'),
      _node('n3', 2, parentId: 'n1', label: 'Раздел Б'),
      _node('n4', 3, parentId: 'n2', label: 'Подраздел А1'),
    ];

Future<FakeGraphNotifier> _pumpGraph(
  WidgetTester tester, {
  required List<KnowledgeNode> nodes,
  int visibleLevel = 2,
}) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    learnerStoreProvider.overrideWith((ref) => FakeLearnerNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  container.read(graphStoreProvider.notifier).state = GraphState(
    topicId: 't1',
    topicName: 'Тема',
    nodes: nodes,
    visibleLevel: visibleLevel,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: GraphScreen(topicId: 't1')),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return container.read(graphStoreProvider.notifier) as FakeGraphNotifier;
}

void main() {
  testWidgets('панель «Есть подразделы» перечисляет узлы со скрытыми потомками',
      (tester) async {
    await _pumpGraph(tester, nodes: _deepTree());

    // Кандидаты: n1 (скрытый внук n4) и n2 (скрытый ребёнок n4).
    expect(find.text('Есть подразделы (2)'), findsOneWidget);
    expect(find.text('Корень'), findsOneWidget);
    expect(find.text('Раздел А'), findsOneWidget);
    expect(find.text('Раскрыть'), findsNWidgets(2));
    // Показаны n1..n3, скрыт только n4.
    expect(find.text('Скрыто 1 узл.'), findsOneWidget);
  });

  testWidgets('список панели сворачивается и разворачивается по заголовку',
      (tester) async {
    await _pumpGraph(tester, nodes: _deepTree());
    expect(find.text('Раскрыть'), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    await tester.tap(find.text('Есть подразделы (2)'));
    await tester.pump();
    expect(find.text('Раскрыть'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    await tester.tap(find.text('Есть подразделы (2)'));
    await tester.pump();
    expect(find.text('Раскрыть'), findsNWidgets(2));
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
  });

  testWidgets('«Раскрыть» у узла вызывает expandNode с его id', (tester) async {
    final graph = await _pumpGraph(tester, nodes: _deepTree());

    // Второй ряд — n2 («Раздел А»), первый — корень n1.
    await tester.tap(find.text('Раскрыть').last);
    await tester.pump();
    await tester.pump();
    expect(graph.expanded, ['n2']);
  });

  testWidgets('блок «Скрыто N узл.» не показывается при visibleLevel >= 5',
      (tester) async {
    // n5 (level 6) скрыт, но уровень видимости уже максимальный:
    // подпись про число скрытых узлов не рендерится.
    final nodes = [
      _root(),
      _node('n2', 2, parentId: 'n1', label: 'Раздел А'),
      _node('n5', 6, parentId: 'n2', label: 'Глубокий'),
    ];
    await _pumpGraph(tester, nodes: nodes, visibleLevel: 5);

    expect(find.text('Есть подразделы (2)'), findsOneWidget);
    expect(find.textContaining('Скрыто'), findsNothing);
  });

  testWidgets('без скрытых потомков панель отсутствует', (tester) async {
    final nodes = [_root(), _node('n2', 2, parentId: 'n1', label: 'Раздел А')];
    await _pumpGraph(tester, nodes: nodes);

    expect(find.textContaining('Есть подразделы'), findsNothing);
    expect(find.text('Раскрыть'), findsNothing);
  });
}