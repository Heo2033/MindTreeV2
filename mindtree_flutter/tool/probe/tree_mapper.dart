// Маппинг черновиков дерева в доменные узлы для probe.
//
// ВАЖНО: логика повторяет `_draftToNode` из `lib/providers/ui_stores.dart`.
// Probe не импортирует UI-стор (иначе он перестанет быть pure-Dart), поэтому
// отображение продублировано. При изменении полей здесь нужно синхронно
// править `_draftToNode` — иначе отчёт probe покажет не то дерево, которое
// сохранит приложение.

import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/primitives.dart';

/// Черновик узла → доменный узел, готовый к сохранению.
///
/// `canonicalDefinition` становится `oneLiner`, `details` на этом этапе пустой
/// (контент генерируется отдельным вызовом LLM).
KnowledgeNode draftToNode(NodeDraft d, String topicId) {
  return KnowledgeNode(
    id: d.id,
    topicId: topicId,
    parentId: d.parentId,
    level: d.level,
    label: d.title.trim(),
    oneLiner: d.canonicalDefinition ?? '',
    details: '',
    conceptType: ConceptType.fromString(d.conceptType),
    importance: d.importance ?? 0.5,
    difficulty: d.difficulty ?? 0.5,
    estimatedTimeMinutes: d.estimatedMinutes ?? 5,
    relations: (d.relations ?? [])
        .map((r) => Relation(
              from: r.from,
              to: r.to,
              type: RelationType.fromString(r.type),
              label: r.label,
            ))
        .toList(),
    state: NodeState.structureGenerated,
    contentLoaded: false,
    leaf: d.level >= 3,
  );
}

/// Пакетное отображение с сохранением порядка черновиков.
List<KnowledgeNode> draftsToNodes(List<NodeDraft> drafts, String topicId) =>
    [for (final d in drafts) draftToNode(d, topicId)];

/// Читает дерево в стабильном порядке обхода: по уровню, затем по id.
///
/// Отчёт обязан быть побайтово сравнимым между прогонами, поэтому порядок
/// не может зависеть от порядка строк в БД.
List<KnowledgeNode> sortNodesForReport(List<KnowledgeNode> nodes) {
  final sorted = [...nodes]..sort((a, b) {
      final byLevel = a.level.compareTo(b.level);
      return byLevel != 0 ? byLevel : a.id.compareTo(b.id);
    });
  return sorted;
}
