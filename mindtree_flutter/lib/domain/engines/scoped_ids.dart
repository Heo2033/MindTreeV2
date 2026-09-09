import '../models/knowledge_node.dart';

/// Global de-duplication of node ids per topic.
///
/// The LLM prompt generates static ids (e.g. `n1_root`) that are identical
/// across topics. Because `knowledge_nodes.id` is the primary key of the whole
/// table, a second topic would silently fail to re-use an already-taken id
/// (e.g. the root `n1_root`) -> "missing root" and orphans.
///
/// Solution: on write we append a stable suffix derived from the topicId,
/// making ids unique across the DB, and rewrite internal references (parentId
/// and relations.from/to) that point to nodes of the same topic.

const String _suffixSeparator = "~";

/// Signature `~` + 8-hex hash of topicId.
String scopedSuffix(String topicId) {
  return '$_suffixSeparator${_hash8(topicId)}';
}

String scopeId(String rawId, String topicId) {
  final suffix = scopedSuffix(topicId);
  if (rawId.contains(suffix)) return rawId;
  return '$rawId$suffix';
}

/// A parsed relation record as emitted by structure-generation prompts.
typedef RawRelation = ({String from, String to, String type, String? label});

/// A minimal structural node draft produced by the generation engines.
class NodeDraft {
  final String id;
  final String title;
  final String? parentId;
  final int level;
  final String? canonicalDefinition;
  final String? semanticAxis;
  final String? conceptType;
  final List<String> forbiddenInterpretations;
  final List<RawRelation>? relations;
  final double? importance;
  final double? difficulty;
  final int? estimatedMinutes;
  final List<String> prerequisites;

  const NodeDraft({
    required this.id,
    required this.title,
    this.parentId,
    this.level = 1,
    this.canonicalDefinition,
    this.semanticAxis,
    this.conceptType,
    this.forbiddenInterpretations = const [],
    this.relations,
    this.importance,
    this.difficulty,
    this.estimatedMinutes,
    this.prerequisites = const [],
  });

  NodeDraft copyWith({
    String? id,
    String? title,
    String? Function()? parentId,
    int? level,
    String? Function()? canonicalDefinition,
    String? Function()? semanticAxis,
    String? Function()? conceptType,
    List<String>? forbiddenInterpretations,
    List<RawRelation>? relations,
    double? importance,
    double? difficulty,
    int? estimatedMinutes,
    List<String>? prerequisites,
  }) =>
      NodeDraft(
        id: id ?? this.id,
        title: title ?? this.title,
        parentId: parentId != null ? parentId() : this.parentId,
        level: level ?? this.level,
        canonicalDefinition: canonicalDefinition != null
            ? canonicalDefinition()
            : this.canonicalDefinition,
        semanticAxis:
            semanticAxis != null ? semanticAxis() : this.semanticAxis,
        conceptType: conceptType != null ? conceptType() : this.conceptType,
        forbiddenInterpretations:
            forbiddenInterpretations ?? this.forbiddenInterpretations,
        relations: relations ?? this.relations,
        importance: importance ?? this.importance,
        difficulty: difficulty ?? this.difficulty,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        prerequisites: prerequisites ?? this.prerequisites,
      );
}

List<NodeDraft> scopeNodeIds(List<NodeDraft> nodes, String topicId) {
  final suffix = scopedSuffix(topicId);
  final rawToScoped = <String, String>{};
  for (final n in nodes) {
    final id = n.id;
    if (id.isEmpty) continue;
    if (!rawToScoped.containsKey(id)) {
      rawToScoped[id] = id.contains(suffix) ? id : '$id$suffix';
    }
  }
  // Sorted raw ids for prefix matching: LLM prompts sometimes reference a
  // parent with a shortened id (e.g. "n1" for "n1_root"). Exact scoped lookup
  // then fails and the parent reference would dangle, silently breaking the
  // whole tree. Fall back to the unique raw id that starts with the reference.
  final sortedRawIds = rawToScoped.keys.toList()..sort();
  String remapId(String id) {
    if (id.isEmpty) return id;
    final mapped = rawToScoped[id];
    if (mapped != null) return mapped;
    String? best;
    for (final raw in sortedRawIds) {
      if (!raw.startsWith(id)) continue;
      if (best != null) return id; // ambiguous -> leave as-is
      best = rawToScoped[raw];
    }
    return best ?? id;
  }

  return nodes
      .where((n) => n.id.isNotEmpty)
      .map((n) {
        final id = remapId(n.id);
        final parentId =
            (n.parentId != null && n.parentId != n.id) ? remapId(n.parentId!) : null;
        final relations = n.relations?.map((r) {
          return (from: remapId(r.from), to: remapId(r.to), type: r.type, label: r.label);
        }).toList();
        return n.copyWith(
          id: id,
          parentId: () => parentId,
          relations: relations,
        );
      })
      .toList();
}

/// Resolve a possibly-shortened id to a real node id of the batch.
///
/// Tries an exact match first (already-scoped or full references) and falls
/// back to the unique id that starts with the reference (e.g. "n1" ->
/// "n1_root~hash"). Returns null when nothing (or more than one) matches.
String? resolveScopedId(String reference, Iterable<String> knownIds) {
  if (reference.isEmpty) return reference;
  if (knownIds.contains(reference)) return reference;
  String? best;
  for (final id in knownIds) {
    if (!id.startsWith(reference)) continue;
    if (best != null) return null; // ambiguous
    best = id;
  }
  return best;
}

/// Read-time repair for nodes persisted before shortened parent references
/// were handled: rewrites a dangling `parentId` (e.g. "n1") to the real node
/// id of the same batch (e.g. "n1_root~hash").
List<KnowledgeNode> repairDanglingParentIds(List<KnowledgeNode> nodes) {
  if (nodes.isEmpty) return nodes;
  final known = nodes.map((n) => n.id).toSet();
  var changed = false;
  final repaired = nodes.map((n) {
    final parent = n.parentId;
    if (parent == null || parent.isEmpty) return n;
    if (known.contains(parent)) return n;
    final resolved = resolveScopedId(parent, known);
    if (resolved == null || resolved == parent) return n;
    changed = true;
    return n.copyWith(parentId: () => resolved);
  }).toList();
  if (!changed) return nodes;
  return repaired;
}

/// Short deterministic hash (FNV-1a) -> 8 hex chars.
String _hash8(String input) {
  var hash = 0x811c9dc5;
  final bytes = input.codeUnits;
  for (var i = 0; i < bytes.length; i++) {
    hash ^= bytes[i];
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
