import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';

void main() {
  group('scopeNodeIds', () {
    test('suffixes node ids with topic hash', () {
      final out = scopeNodeIds(
        const [NodeDraft(id: 'n1_root', title: 'Root')],
        'topic_abc',
      );
      final suffix = scopedSuffix('topic_abc');
      expect(out.single.id, 'n1_root$suffix');
    });

    test('remaps short parentId (n1 -> n1_root) to its scoped id', () {
      // Real LLM output: root id "n1_root", L2 children reference it as "n1".
      final out = scopeNodeIds(
        const [
          NodeDraft(id: 'n1_root', title: 'Root'),
          NodeDraft(id: 'n2_a', title: 'Child', parentId: 'n1'),
        ],
        'topic_abc',
      );
      final suffix = scopedSuffix('topic_abc');
      expect(out.where((n) => n.id == 'n2_a$suffix').single.parentId,
          'n1_root$suffix');
    });

    test('leaves ambiguous prefix unmapped instead of guessing', () {
      // Reference "n2" is a prefix of both n2_a and n2_b -> cannot disambiguate.
      final out = scopeNodeIds(
        const [
          NodeDraft(id: 'n1_root', title: 'Root'),
          NodeDraft(id: 'n2_a', title: 'Child A', parentId: 'n2'),
          NodeDraft(id: 'n2_b', title: 'Child B', parentId: 'n2'),
        ],
        'topic_abc',
      );
      expect(out.where((n) => n.id.startsWith('n2_a')).single.parentId, 'n2');
    });

    test('keeps full matching parentId unchanged', () {
      final out = scopeNodeIds(
        const [
          NodeDraft(id: 'n1_root', title: 'Root'),
          NodeDraft(id: 'n2_a', title: 'Child', parentId: 'n1_root'),
        ],
        'topic_abc',
      );
      final suffix = scopedSuffix('topic_abc');
      expect(out.where((n) => n.id == 'n2_a$suffix').single.parentId,
          'n1_root$suffix');
    });
  });

  group('repairDanglingParentIds', () {
    KnowledgeNode node(String id, String? parentId) => KnowledgeNode(
          id: id,
          topicId: 'topic_abc',
          parentId: parentId,
          level: parentId == null ? 1 : 2,
          label: id,
          oneLiner: '',
          details: '',
        );

    test('rewrites dangling short parentId to the scoped root id', () {
      final suffix = scopedSuffix('topic_abc');
      final fixed = repairDanglingParentIds([
        node('n1_root$suffix', null),
        node('n2_a$suffix', 'n1'),
      ]);
      expect(fixed.last.parentId, 'n1_root$suffix');
    });

    test('leaves a valid parentId untouched', () {
      final suffix = scopedSuffix('topic_abc');
      final fixed = repairDanglingParentIds([
        node('n1_root$suffix', null),
        node('n2_a$suffix', 'n1_root$suffix'),
      ]);
      expect(fixed.last.parentId, 'n1_root$suffix');
    });
  });
}