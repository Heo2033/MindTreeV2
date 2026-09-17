import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/focus_screen.dart';

/// Граф-нотифаер без БД и LLM: все мутирующие методы — no-op.
class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

class FakeLearnerNotifier extends LearnerNotifier {
  FakeLearnerNotifier(super.ref);

  @override
  Future<void> load(String topicId) async {}
}

KnowledgeNode _node(String id, int level, {String? parentId, String label = ''}) =>
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

/// Порядок чтения (DFS pre-order, дети по id): [n1, n2, n4, n3].
/// План фокуса для n2 строится как pathTo(n2) + subtree(n2) = [n1, n2, n4].
List<KnowledgeNode> _tree() => [
      _node('n1', 1, label: 'Корень'),
      _node('n2', 2, parentId: 'n1', label: 'Раздел А'),
      _node('n3', 2, parentId: 'n1', label: 'Раздел Б'),
      _node('n4', 3, parentId: 'n2', label: 'Подраздел А1'),
    ];

Future<void> _pumpFocus(WidgetTester tester, {List<KnowledgeNode>? nodes}) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    learnerStoreProvider.overrideWith((ref) => FakeLearnerNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  container.read(graphStoreProvider.notifier).state = GraphState(
    topicId: 't1',
    topicName: 'Тема',
    nodes: nodes ?? _tree(),
    visibleLevel: 2,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FocusScreen(topicId: 't1')),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// KeyboardListener не авто-фокусируется, поэтому перед отправкой клавиши
/// явно просим фокус у его FocusNode (иначе sendKeyEvent уйдёт в никуда).
Future<void> _pressArrow(WidgetTester tester, LogicalKeyboardKey key) async {
  final listener = tester.widget<KeyboardListener>(find.byType(KeyboardListener));
  listener.focusNode.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// Текущий узел из _NavBar: в ближайшей Column вокруг подписи «Текущий узел»
/// второй Text — имя узла.
String _currentNodeLabel(WidgetTester tester) {
  final column = find
      .ancestor(of: find.text('Текущий узел'), matching: find.byType(Column))
      .first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: column, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts.last!;
}

bool _prevEnabled(WidgetTester tester) => tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left))
        .onPressed !=
    null;

bool _nextEnabled(WidgetTester tester) => tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right))
        .onPressed !=
    null;

void main() {
  testWidgets('без выбранного pivot стрелки ничего не делают', (tester) async {
    await _pumpFocus(tester);

    expect(find.text('Выберите раздел для фокусировки'), findsOneWidget);

    await _pressArrow(tester, LogicalKeyboardKey.arrowRight);
    await _pressArrow(tester, LogicalKeyboardKey.arrowLeft);

    expect(find.text('Выберите раздел для фокусировки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('тап по разделу фокусирует его первый узел плана', (tester) async {
    await _pumpFocus(tester);

    await tester.tap(find.text('Раздел А'));
    await tester.pump();

    expect(find.text('Текущий узел'), findsOneWidget);
    expect(_currentNodeLabel(tester), 'Раздел А');
    // План [n1, n2, n4]: prev указывает на корень, next — на подраздел.
    expect(_prevEnabled(tester), isTrue);
    expect(_nextEnabled(tester), isTrue);
  });

  testWidgets('ArrowRight переводит на следующий узел, ArrowLeft — назад',
      (tester) async {
    await _pumpFocus(tester);
    await tester.tap(find.text('Раздел А'));
    await tester.pump();
    expect(_currentNodeLabel(tester), 'Раздел А');

    await _pressArrow(tester, LogicalKeyboardKey.arrowRight);
    expect(_currentNodeLabel(tester), 'Подраздел А1');
    expect(_nextEnabled(tester), isFalse); // последний узел плана

    await _pressArrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(_currentNodeLabel(tester), 'Раздел А');

    await _pressArrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(_currentNodeLabel(tester), 'Корень');
    expect(_prevEnabled(tester), isFalse); // первый узел плана
  });

  testWidgets('стрелки не выходят за границы плана', (tester) async {
    await _pumpFocus(tester);
    await tester.tap(find.text('Раздел А'));
    await tester.pump();

    // Уходим на первый узел и пробуем ещё левее.
    await _pressArrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(_currentNodeLabel(tester), 'Корень');
    await _pressArrow(tester, LogicalKeyboardKey.arrowLeft);
    expect(_currentNodeLabel(tester), 'Корень');
    expect(_prevEnabled(tester), isFalse);

    // Уходим на последний узел и пробуем ещё правее.
    await _pressArrow(tester, LogicalKeyboardKey.arrowRight); // n2
    await _pressArrow(tester, LogicalKeyboardKey.arrowRight); // n4
    expect(_currentNodeLabel(tester), 'Подраздел А1');
    await _pressArrow(tester, LogicalKeyboardKey.arrowRight);
    expect(_currentNodeLabel(tester), 'Подраздел А1');
    expect(_nextEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);
  });
}