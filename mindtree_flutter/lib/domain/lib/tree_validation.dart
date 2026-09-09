import '../models/knowledge_node.dart';

/// Validates tree shape: exactly one root, all parents exist, no cycles.
bool validateTreeShape(List<KnowledgeNode> nodes) {
  if (nodes.isEmpty) return false;
  final ids = {for (final n in nodes) n.id};
  final roots = nodes.where((n) => n.parentId == null).toList();
  if (roots.length != 1) return false;

  for (final n in nodes) {
    if (n.parentId != null && !ids.contains(n.parentId)) return false;
  }

  final visited = <String>{};
  final inStack = <String>{};
  final byId = {for (final n in nodes) n.id: n};

  bool dfs(String id) {
    if (inStack.contains(id)) return false;
    if (visited.contains(id)) return true;
    inStack.add(id);
    visited.add(id);
    final node = byId[id];
    if (node?.parentId != null && !dfs(node!.parentId!)) return false;
    inStack.remove(id);
    return true;
  }

  for (final n in nodes) {
    if (!dfs(n.id)) return false;
  }

  return true;
}
