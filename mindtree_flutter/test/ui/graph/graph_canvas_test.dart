import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/ui/graph/graph_canvas.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';

KnowledgeNode _node(
  String id,
  int level, {
  String? parentId,
  String label = '',
  String oneLiner = '',
  bool leaf = false,
  NodeState state = NodeState.structureGenerated,
  List<Relation> relations = const [],
}) =>
    KnowledgeNode(
      id: id,
      topicId: 'topic1',
      parentId: parentId,
      level: level,
      label: label,
      oneLiner: oneLiner,
      details: '',
      state: state,
      leaf: leaf,
      relations: relations,
    );

/// A single fixed-position layout node. The canvas maps world coords into an
/// 800x600 viewport with fit=(300,260), base=1.0 when only this node exists,
/// so screen positions are deterministic.
GraphLayoutNode _fixedNode({
  required String id,
  required double x,
  required double y,
  required double w,
  required double h,
  required KnowledgeNode node,
  required bool isCompact,
  required bool canReveal,
  required bool canDeepen,
}) =>
    (
      id: id,
      x: x,
      y: y,
      w: w,
      h: h,
      color: const Color(0xFF3B82F6),
      node: node,
      isCompact: isCompact,
      canReveal: canReveal,
      canDeepen: canDeepen,
    );

Widget _canvas(WidgetTester tester) {
  final tree = [
    _node('n1', 1, label: 'Корневое понятие', relations: [
      Relation(from: 'n1', to: 'n3', type: RelationType.requires),
    ]),
    _node('n2', 2, parentId: 'n1', label: 'Раздел А'),
    _node('n3', 2, parentId: 'n1', label: 'Раздел Б'),
  ];
  final layout = layoutGraph(tree, visibleLevel: 2);
  expect(
    layout.edges.where((e) => e.kind == 'relation'),
    hasLength(1),
  );

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: GraphCanvas(
          nodes: layout.nodes,
          edges: layout.edges,
          onNodeTap: (_) {},
          onNodeLongPress: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('GraphCanvas', () {
    testWidgets('paints relation edges with arrows and labels', (tester) async {
      await tester.pumpWidget(_canvas(tester));
      await tester.pump();
      // A StateError from consuming the one-shot PathMetrics twice would fail
      // the test here; a clean pump means both the arrow and the label painted.
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a repaint on rebuild', (tester) async {
      await tester.pumpWidget(_canvas(tester));
      await tester.pumpWidget(_canvas(tester));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

testWidgets('hover shows «Углубить» on a true leaf; tapping it deepens',
        (tester) async {
      var tapped = '';
      var deepened = '';
      await _mount(
        tester,
        node: _node('n2', 2, parentId: 'n1', label: 'Раздел'),
        canReveal: false,
        canDeepen: true,
        onTap: (id) => tapped = id,
        onDeepen: (id) => deepened = id,
      );

      await _hover(tester, const Offset(400, 300));
      await _tap(tester, _chipScreen);
      expect(deepened, 'n2');
      expect(tapped, isEmpty);
    });

    testWidgets('hover shows «Раскрыть» when hidden children exist',
        (tester) async {
      var expanded = '';
      await _mount(
        tester,
        node: _node('n2', 2, parentId: 'n1', label: 'Раздел'),
        canReveal: true,
        canDeepen: false,
        onExpand: (id) => expanded = id,
      );

      await _hover(tester, const Offset(400, 300));
      await _tap(tester, _chipScreen);
      expect(expanded, 'n2');
    });

    testWidgets('entry node with no actions shows no chip', (tester) async {
      var tapped = false;
      await _mount(
        tester,
        node: _node('n1', 1, label: 'Корень'),
        canReveal: false,
        canDeepen: false,
        onTap: (_) => tapped = true,
        onExpand: (_) => fail('expand must not fire'),
        onDeepen: (_) => fail('deepen must not fire'),
      );

      await _hover(tester, const Offset(400, 300));
      // The chip-sized area below the card must behave like empty canvas.
      await _tap(tester, _chipScreen);
      expect(tapped, isFalse);
    });

    testWidgets('tapping a node selects it without an action chip',
        (tester) async {
      var tapped = '';
      await _mount(
        tester,
        node: _node('n2', 2, parentId: 'n1', label: 'Раздел'),
        canReveal: false,
        canDeepen: true,
        onTap: (id) => tapped = id,
      );

      // No hover: a tap on the card is a plain node selection.
      await _tap(tester, const Offset(400, 300));
      expect(tapped, 'n2');
    });

    testWidgets('hover over a relation edge highlights it; moving away clears',
        (tester) async {
      final a = _node('a', 1, label: 'A', relations: [
        Relation(from: 'a', to: 'b', type: RelationType.requires),
      ]);
      final b = _node('b', 2, parentId: 'a', label: 'B');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: GraphCanvas(
              nodes: [
                _fixedNode(
                    id: 'a',
                    x: 0,
                    y: 0,
                    w: 200,
                    h: 80,
                    node: a,
                    isCompact: false,
                    canReveal: false,
                    canDeepen: false),
                _fixedNode(
                    id: 'b',
                    x: 400,
                    y: 0,
                    w: 200,
                    h: 80,
                    node: b,
                    isCompact: false,
                    canReveal: false,
                    canDeepen: false),
              ],
              edges: [
                (
                  id: 'rel:a-b',
                  source: 'a',
                  target: 'b',
                  sourceHandle: 'right',
                  targetHandle: 'left',
                  kind: 'relation',
                  color: const Color(0xFFF97316),
                  label: 'требует',
                ),
              ],
              onNodeTap: (_) {},
              onNodeLongPress: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();

      // Узлы (0,0,200,80) и (400,0,200,80), base=0.625, fit=(212.5,275).
      // Середина ребра в мировых (300,40) → экран (400,300).
      await _hover(tester, const Offset(400, 300));
      final state =
          tester.state<GraphCanvasState>(find.byType(GraphCanvas));
      expect(state.debugHoveredEdgeId, 'rel:a-b');

      // Курсор в стороне от кривой — подсветка снимается.
      await _hover(tester, const Offset(40, 520));
      expect(state.debugHoveredEdgeId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('degenerate edge between overlapping nodes does not crash',
        (tester) async {
      // Регрессия «Bad state: No element» в _paintArrow/_paintEdgeLabel:
      // ребро, источник и цель которого лежат в одной точке (вырожденная
      // геометрия), не должно ронять отрисовку стрелки и метки.
      final a = _node('a', 1, label: 'A', relations: [
        Relation(from: 'a', to: 'a', type: RelationType.requires),
      ]);
      final node = _fixedNode(
          id: 'a',
          x: 140,
          y: 110,
          w: 200,
          h: 80,
          node: a,
          isCompact: false,
          canReveal: false,
          canDeepen: false);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: GraphCanvas(
              nodes: [node],
              edges: [
                (
                  id: 'rel:a-self',
                  source: 'a',
                  target: 'a',
                  sourceHandle: 'right',
                  targetHandle: 'right',
                  kind: 'relation',
                  color: const Color(0xFFF97316),
                  label: 'требует',
                ),
              ],
              onNodeTap: (_) {},
              onNodeLongPress: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Screen-space center of the action chip for the single-node test fixture.
/// The 200x80 node at the origin produces baseScale 1 and fit=(300,260), so a
/// chip at world (0,88,96,22) lands at the screen point (348,359).
const _chipScreen = Offset(348, 359);

/// Mount a single fixed-position node (200x80 at the origin) inside an 800x600
/// surface with the given actions.
Future<void> _mount(
  WidgetTester tester, {
  required KnowledgeNode node,
  required bool canReveal,
  required bool canDeepen,
  void Function(String)? onTap,
  void Function(String)? onExpand,
  void Function(String)? onDeepen,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: GraphCanvas(
          nodes: [
            _fixedNode(
              id: node.id,
              x: 0,
              y: 0,
              w: 200,
              h: 80,
              node: node,
              isCompact: false,
              canReveal: canReveal,
              canDeepen: canDeepen,
            ),
          ],
          edges: const [],
          onNodeTap: onTap ?? (_) {},
          onNodeLongPress: (_) {},
          onNodeExpand: onExpand,
          onNodeDeepen: onDeepen,
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Hover a mouse over a screen point so the MouseRegion reacts.
Future<void> _hover(WidgetTester tester, Offset at) async {
  final p = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(p.hover(at));
  await tester.pump();
}

/// Tap and advance past the double-tap rejection window so onTapUp resolves.
Future<void> _tap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}
