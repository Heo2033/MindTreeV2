import '../models/knowledge_node.dart';

Map<String, List<KnowledgeNode>> buildChildrenMap(List<KnowledgeNode> nodes) {
  final map = <String, List<KnowledgeNode>>{};
  for (final node in nodes) {
    final pid = node.parentId;
    if (pid == null) continue;
    map.putIfAbsent(pid, () => []).add(node);
  }
  return map;
}

List<KnowledgeNode> readingOrder(List<KnowledgeNode> nodes) {
  final childrenMap = buildChildrenMap(nodes);
  final roots = nodes.where((n) => n.parentId == null).toList()
    ..sort((a, b) => a.level - b.level);

  final result = <KnowledgeNode>[];
  void visit(KnowledgeNode node) {
    result.add(node);
    final children = (childrenMap[node.id] ?? []).toList()
      ..sort((a, b) => a.estimatedTimeMinutes - b.estimatedTimeMinutes);
    for (final child in children) {
      visit(child);
    }
  }

  for (final root in roots) {
    visit(root);
  }
  return result;
}

List<({String id, String label, int level, List<String> children})> buildToc(List<KnowledgeNode> nodes) {
  final childrenMap = buildChildrenMap(nodes);
  return nodes
      .where((n) => n.level == 1 || n.level == 2)
      .map((n) => (
            id: n.id,
            label: n.label,
            level: n.level,
            children: (childrenMap[n.id] ?? []).map((c) => c.id).toList(),
          ))
      .toList();
}

Map<String, double> branchProgress(List<KnowledgeNode> nodes) {
  final childrenMap = buildChildrenMap(nodes);
  final totalCounts = <String, int>{};
  final masteredCounts = <String, int>{};

  ({int total, int mastered}) count(String nodeId) {
    if (totalCounts.containsKey(nodeId)) {
      return (total: totalCounts[nodeId]!, mastered: masteredCounts[nodeId]!);
    }
    final node = nodes.firstWhere((n) => n.id == nodeId);
    final children = childrenMap[nodeId] ?? [];

    late ({int total, int mastered}) res;
    if (children.isEmpty) {
      final total = node.importance > 0 ? 1 : 0;
      final mastered = node.state.wire == 'content_generated' ? 1 : 0;
      res = (total: total, mastered: mastered);
    } else {
      var total = 0;
      var mastered = 0;
      for (final child in children) {
        final c = count(child.id);
        total += c.total;
        mastered += c.mastered;
      }
      res = (total: total, mastered: mastered);
    }
    totalCounts[nodeId] = res.total;
    masteredCounts[nodeId] = res.mastered;
    return res;
  }

  final progress = <String, double>{};
  for (final node in nodes) {
    final c = count(node.id);
    progress[node.id] = c.total > 0 ? c.mastered / c.total : 0;
  }
  return progress;
}

List<String> nodePath(List<KnowledgeNode> nodes, String nodeId) {
  final byId = {for (final n in nodes) n.id: n};
  final path = <String>[];
  KnowledgeNode? current = byId[nodeId];
  var guard = 0;
  while (current != null && guard < 50) {
    path.insert(0, current.label);
    final pid = current.parentId;
    current = pid != null ? byId[pid] : null;
    guard++;
  }
  return path;
}

List<String> collectDescendantIds(List<KnowledgeNode> nodes, String nodeId) {
  final childrenMap = buildChildrenMap(nodes);
  final result = <String>[];
  final stack = [...(childrenMap[nodeId] ?? [])];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    result.add(node.id);
    stack.addAll(childrenMap[node.id] ?? []);
  }
  return result;
}
