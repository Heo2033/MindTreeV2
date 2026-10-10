import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/graph/graph_canvas.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';
import 'package:mindtree_flutter/ui/screens/graph_screen.dart';

/// Те же фейковые нотифаеры, что в graph_screen_hidden_panel_test.
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

KnowledgeNode _node(
  String id,
  int level, {
  String? parentId,
  String label = '',
  String oneLiner = '',
}) =>
    KnowledgeNode(
      id: id,
      topicId: 't1',
      parentId: parentId,
      level: level,
      label: label,
      oneLiner: oneLiner,
      details: '',
      state: NodeState.structureGenerated,
    );

void main() {
  testWidgets('узкий экран: выбранный узел показывает панель-оверлей без overflow',
      (tester) async {
    // 360×740 — типичный телефон в портрете.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final nodes = [
      _node(
        'n1',
        1,
        label: 'Очень длинное название корневого понятия, которое не должно '
            'ломать вёрстку',
        oneLiner: 'Подпись с большим системным масштабом тоже обязана '
            'помещаться в панель деталей, иначе панель вылезает за низ экрана.',
      ),
      _node('n2', 2, parentId: 'n1', label: 'Дочерний узел'),
    ];

    final container = ProviderContainer(overrides: [
      graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
      learnerStoreProvider.overrideWith((ref) => FakeLearnerNotifier(ref)),
    ]);
    addTearDown(container.dispose);
    container.read(graphStoreProvider.notifier).state = GraphState(
      topicId: 't1',
      topicName: 'Тема',
      nodes: nodes,
      visibleLevel: 2,
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

    // Тап по координате корневого узла открывает панель деталей.
    final layout = layoutGraph(nodes, visibleLevel: 2, revealedNodes: const {});
    final root = layout.nodes.firstWhere((n) => n.id == 'n1');
    final state = tester.state<GraphCanvasState>(find.byType(GraphCanvas));
    // debugWorldToScreen даёт координаты в системе канваса; tapAt ожидает
    // глобальные — добавляем offset канваса на экране.
    final tap =
        tester.getTopLeft(find.byType(GraphCanvas)) +
        state.debugWorldToScreen(
          Offset(root.x + root.w / 2, root.y + root.h / 2),
        );
    // Hover перед тапом: MouseRegion гасит onTapUp без hover (см.
    // graph_canvas_narrow_test).
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tap));
    await tester.pump();
    await tester.tapAt(tap);
    await tester.pump(const Duration(milliseconds: 400));

    // Панель видна: кнопки действий и прогресс важности.
    expect(find.text('Фокус'), findsOneWidget);
    expect(find.textContaining('Важность'), findsOneWidget);
    // Ни выбранный узел, ни панель-оверлей не роняют лейаут.
    expect(tester.takeException(), isNull);
  });
}