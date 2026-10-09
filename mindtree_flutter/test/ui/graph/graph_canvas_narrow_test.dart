import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/ui/graph/graph_canvas.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';

KnowledgeNode _node(String id, String label) => KnowledgeNode(
      id: id,
      topicId: 't1',
      parentId: id == 'a' ? null : 'a',
      level: id == 'a' ? 1 : 2,
      label: label,
      oneLiner: 'Короткое описание понятия для проверки читаемости.',
      details: 'Подробности.',
    );

GraphLayoutNode _fixedNode({
  required String id,
  required double x,
  required double y,
  required bool compact,
}) =>
    (
      id: id,
      x: x,
      y: y,
      w: 200,
      h: 80,
      color: const Color(0xFF3B82F6),
      node: _node(id, id == 'a' ? 'Корневое понятие' : 'Дальний раздел'),
      isCompact: compact,
      canReveal: false,
      canDeepen: false,
    );

/// Холст 360x600 (узкий экран) с двумя узлами, растянутыми на 2000 world
/// units: подгонка даёт масштаб 0.15, карточка узла на экране ~30x12 px —
/// меньше минимального тач-таргета.
Widget _canvas({required void Function(String) onTap}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 600,
          child: GraphCanvas(
            nodes: [
              _fixedNode(id: 'a', x: 0, y: 0, compact: false),
              _fixedNode(id: 'b', x: 1800, y: 0, compact: true),
            ],
            edges: const [],
            onNodeTap: onTap,
            onNodeLongPress: (_) {},
          ),
        ),
      ),
    );

Future<void> _tap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Hover нужен, чтобы MouseRegion не гасил `onTapUp` (см. graph_canvas_test).
Future<void> _hover(WidgetTester tester, Offset at) async {
  final p = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(p.hover(at));
  await tester.pump();
}

void main() {
  group('GraphCanvas на узком экране', () {
    testWidgets('рисуется без ошибок при компенсации кегля', (tester) async {
      await tester.pumpWidget(_canvas(onTap: (_) {}));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('тап в 8 px под карточкой попадает в уменьшенный узел',
        (tester) async {
      var tapped = '';
      await tester.pumpWidget(_canvas(onTap: (id) => tapped = id));
      await tester.pump();

      // fit=(30,294), base=0.15 → карточка узла «a» на экране (30,294)-(60,306).
      await _hover(tester, const Offset(45, 314));
      await _tap(tester, const Offset(45, 314));
      expect(tapped, 'a');
    });

    testWidgets('тап далеко за карточкой не попадает в узел', (tester) async {
      var tapped = '';
      await tester.pumpWidget(_canvas(onTap: (id) => tapped = id));
      await tester.pump();

      // Тач-зона расширяется максимум на 24 px с каждой стороны:
      // карточка заканчивается на y=306, предел — y=330.
      await _hover(tester, const Offset(45, 340));
      await _tap(tester, const Offset(45, 340));
      expect(tapped, isEmpty);
    });
  });
}
