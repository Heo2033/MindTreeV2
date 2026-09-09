import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';

KnowledgeNode _node(
  String id,
  int level, {
  String? parentId,
  String label = '',
  String oneLiner = '',
  ConceptType? type,
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
      conceptType: type,
      relations: relations,
    );

List<KnowledgeNode> _sampleTree() => [
      _node('n1', 1, label: 'Корневое понятие', type: ConceptType.concept),
      _node('n2', 2, parentId: 'n1', label: 'Раздел А', type: ConceptType.process),
      _node('n3', 2, parentId: 'n1', label: 'Раздел Б', type: ConceptType.mechanism),
      _node('n4', 3, parentId: 'n2', label: 'Подраздел А1', type: ConceptType.example),
      _node('n5', 3, parentId: 'n2', label: 'Подраздел А2', type: ConceptType.example),
    ];

void main() {
  group('compactW', () {
    test('short labels return the compact minimum', () {
      expect(compactW('AB'), 72);
    });
    test('long labels widen the compact node', () {
      final wide = compactW('Очень длинное название узла дерева знаний');
      expect(wide, greaterThan(72));
      expect(wide, lessThanOrEqualTo(300));
    });
  });

  group('nodeSize', () {
    test('L1/L2 use full-size cards, L3+ are compact', () {
      final full = nodeSize(1, 'Раздел');
      final compact = nodeSize(3, 'Раздел');
      expect(compact.w, lessThan(full.w));
      expect(compact.h, lessThan(full.h));
    });
  });

  group('getEdgeHandles', () {
    test('vertical displacement picks top/bottom', () {
      final h = getEdgeHandles(100, 0, 110, 60);
      expect(h.sourceHandle, 'bottom');
      expect(h.targetHandle, 'top');
      final up = getEdgeHandles(100, 100, 90, 0);
      expect(up.sourceHandle, 'top');
      expect(up.targetHandle, 'bottom');
    });
    test('horizontal displacement picks left/right', () {
      final h = getEdgeHandles(0, 100, 200, 100);
      expect(h.sourceHandle, 'right');
      expect(h.targetHandle, 'left');
    });
  });

  group('layoutGraph', () {
    test('root is centered at the origin', () {
      final layout = layoutGraph(_sampleTree());
      final root = layout.nodes.where((n) => n.id == 'n1').first;
      expect(root.x, 0);
      expect(root.y, 0);
      expect(root.w, nodeW);
      expect(root.h, nodeH);
    });

    test('produces hierarchy edges for visible parent-child pairs', () {
      final layout = layoutGraph(_sampleTree());
      // Level 3 is hidden when the visible level is 2 and nothing is revealed.
      final ids = layout.nodes.map((n) => n.id).toSet();
      expect(ids.contains('n1'), isTrue);
      expect(ids.contains('n2'), isTrue);
      expect(ids.contains('n4'), isFalse);
      expect(layout.edges, isNotEmpty);
    });

    test('level 3 nodes are visible when visibleLevel >= 3', () {
      final layout = layoutGraph(_sampleTree(), visibleLevel: 3);
      final ids = layout.nodes.map((n) => n.id).toSet();
      expect(ids.contains('n1'), isTrue);
      expect(ids.contains('n2'), isTrue);
      expect(ids.contains('n3'), isTrue);
      expect(ids.contains('n4'), isTrue);
      expect(ids.contains('n5'), isTrue);
    });

    test('reading order by branch color groups L2 subtrees', () {
      final layout =
          layoutGraph(_sampleTree(), revealedNodes: const {'n2'}, visibleLevel: 2);
      final a = layout.nodes.where((n) => n.id == 'n2').first;
      final a1 = layout.nodes.where((n) => n.id == 'n4').first;
      expect(a.color, a1.color);
    });

    test('adds relation edges with labels', () {
      final tree = _sampleTree();
      tree[0] = _node(
        'n1',
        1,
        parentId: null,
        label: 'Корневое понятие',
        relations: [
          Relation(from: 'n1', to: 'n3', type: RelationType.requires),
        ],
      );
      final layout = layoutGraph(tree);
      final rel = layout.edges.where((e) => e.kind == 'relation').toList();
      expect(rel, hasLength(1));
      expect(rel.first.label, 'requires');
    });
  });

  group('isGraphNodeVisible', () {
    final tree = _sampleTree();

    test('level <= visibleLevel always visible', () {
      expect(isGraphNodeVisible(_node('a', 0), tree, 2, const {}), isTrue);
      expect(isGraphNodeVisible(_node('b', 1), tree, 2, const {}), isTrue);
      expect(isGraphNodeVisible(_node('c', 2), tree, 2, const {}), isTrue);
    });
    test('deeper nodes need a revealed parent', () {
      final deep = _node('n4', 3, parentId: 'n2');
      expect(isGraphNodeVisible(deep, tree, 2, const {'n2'}), isTrue);
      expect(isGraphNodeVisible(deep, tree, 2, const {'other'}), isFalse);
    });
    test('revealing the node itself also shows it', () {
      final deep = _node('d', 4, parentId: 'x');
      expect(isGraphNodeVisible(deep, tree, 2, const {'d'}), isTrue);
    });
    test('revealing an intermediate ancestor exposes the whole subtree', () {
      // n4 (level 3) under n2 (level 2): revealing n2 exposes n4.
      final deep = _node('n4', 3, parentId: 'n2');
      expect(isGraphNodeVisible(deep, tree, 2, const {'n2'}), isTrue);
      // Level 4 under a level-3 parent is exposed only when an ancestor is revealed.
      final deeper = _node('n6', 4, parentId: 'n4');
      expect(
        isGraphNodeVisible(deeper, tree, 2, const {'n2'}),
        isTrue,
      );
      expect(isGraphNodeVisible(deeper, tree, 2, const {'other'}), isFalse);
    });
    test('visibleLevel 3 exposes level 3 without revealing', () {
      final leaf = _node('n4', 3, parentId: 'n2');
      expect(isGraphNodeVisible(leaf, tree, 3, const {}), isTrue);
    });
  });

  group('nodeActions', () {
    KnowledgeNode raw(
      String id,
      int level, {
      String? parentId,
      bool leaf = false,
      NodeState state = NodeState.structureGenerated,
    }) =>
        KnowledgeNode(
          id: id,
          topicId: 'topic1',
          parentId: parentId,
          level: level,
          label: id,
          oneLiner: '',
          details: '',
          leaf: leaf,
          state: state,
        );

    test('node with hidden children offers reveal, not deepen', () {
      final tree = [
        raw('n1', 1),
        raw('n2', 2, parentId: 'n1'),
        raw('n3', 3, parentId: 'n2'),
      ];
      final a = nodeActions(tree[1], tree, 2, const {});
      expect(a.canReveal, isTrue);
      expect(a.canDeepen, isFalse);
    });

    test('true leaf offers deepen, not reveal', () {
      final tree = [raw('n1', 1), raw('n2', 2, parentId: 'n1')];
      final a = nodeActions(tree[1], tree, 2, const {});
      expect(a.canReveal, isFalse);
      expect(a.canDeepen, isTrue);
    });

    test('revealing does not hide the revealed children again', () {
      final tree = [
        raw('n1', 1),
        raw('n2', 2, parentId: 'n1'),
        raw('n3', 3, parentId: 'n2'),
      ];
      final a = nodeActions(tree[1], tree, 2, const {'n2'});
      expect(a.canReveal, isFalse);
      expect(a.canDeepen, isFalse);
    });

    test('children already visible offer nothing', () {
      final tree = [
        raw('n1', 1),
        raw('n2', 2, parentId: 'n1'),
        raw('n3', 2, parentId: 'n2'),
      ];
      final a = nodeActions(tree[1], tree, 2, const {});
      expect(a.canReveal, isFalse);
      expect(a.canDeepen, isFalse);
    });

    test('terminal nodes (level >= 5) offer nothing', () {
      final tree = [
        raw('n1', 1),
        raw('n2', 5, parentId: 'n1', leaf: true),
      ];
      final a = nodeActions(tree[1], tree, 5, const {});
      expect(a.canReveal, isFalse);
      expect(a.canDeepen, isFalse);
    });

    test('expanded leaf is terminal and offers nothing', () {
      final tree = [
        raw('n1', 1),
        raw('n2', 4, parentId: 'n1', leaf: true, state: NodeState.expanded),
      ];
      final a = nodeActions(tree[1], tree, 2, const {});
      expect(a.canReveal, isFalse);
      expect(a.canDeepen, isFalse);
    });
  });
}