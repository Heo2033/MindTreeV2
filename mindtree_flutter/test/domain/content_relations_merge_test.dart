// Регресс: контентная стадия не должна затирать структурные связи и не должна
// добавлять выдуманные цели.
//
// Дефект найден ревью реального экспорта (`tool/review`): в 58 связях 56
// указывали на несуществующие id, потому что `generateNodeContentFromDb`
// присваивал `relations: content.relations` — контентный промпт просил id
// других узлов, которых модель не знает, и структурные связи терялись.

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/primitives.dart' show RelationType;

void main() {
  const self = 'n2_a~1a2b3c4d';
  const known = {'n1_root~1a2b3c4d', self, 'n2_b~1a2b3c4d'};

  List<Relation> merge({List<Relation>? existing, List<Relation>? content}) =>
      KnowledgeGraphEngine.mergeContentRelations(
        existing: existing ?? const [],
        fromContent: content ?? const [],
        nodeId: self,
        knownIds: known,
      );

  test('структурные связи сохраняются, даже если контент вернул свои', () {
    final structural = [
      const Relation(from: self, to: 'n1_root~1a2b3c4d', type: RelationType.requires),
      const Relation(from: self, to: 'n2_b~1a2b3c4d', type: RelationType.contrastsWith),
    ];
    final result = merge(
      existing: structural,
      content: const [
        Relation(from: self, to: 'n9_ghost~deadbeef', type: RelationType.related),
      ],
    );
    expect(result.length, 2);
    expect(result.map((r) => r.to), containsAll(['n1_root~1a2b3c4d', 'n2_b~1a2b3c4d']));
  });

  test('цель вне дерева отбрасывается', () {
    final result = merge(
      content: const [
        Relation(from: self, to: 'n9_ghost~deadbeef', type: RelationType.related),
        Relation(from: self, to: 'n2_b~1a2b3c4d', type: RelationType.related),
      ],
    );
    expect(result.length, 1);
    expect(result.single.to, 'n2_b~1a2b3c4d');
  });

  test('from принудительно ведёт с текущего узла', () {
    final result = merge(
      content: const [
        // Модель могла подставить чужой from — связь повисла бы в воздухе.
        Relation(from: 'n1_root~1a2b3c4d', to: 'n2_b~1a2b3c4d', type: RelationType.related),
      ],
    );
    expect(result.single.from, self);
  });

  test('дубликат по (from,to,type) не добавляется дважды', () {
    final rel = Relation(from: self, to: 'n2_b~1a2b3c4d', type: RelationType.related);
    final result = merge(existing: [rel], content: [rel]);
    expect(result.length, 1);
  });

  test('одинаковые цели с разным типом связи сохраняются', () {
    final result = merge(
      content: const [
        Relation(from: self, to: 'n2_b~1a2b3c4d', type: RelationType.related),
        Relation(from: self, to: 'n2_b~1a2b3c4d', type: RelationType.contrastsWith),
      ],
    );
    expect(result.length, 2);
  });
}
