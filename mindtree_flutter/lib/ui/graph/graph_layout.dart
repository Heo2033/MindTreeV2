import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:mindtree_flutter/domain/models/models.dart';

const double tau = math.pi * 2;

const double nodeW = 200;
const double nodeH = 80;
const double compactH = 34;
const double nodeGap = 48;
const double compactGap = 16;

const double l2RadiusMin = (nodeW + nodeH) / 2 + 120;
const double subRBase = 80;

/// Relation edge colors (ported from packages/graph/src/layout.ts).
const Map<RelationType, Color> relationColors = {
  RelationType.related: Color(0xFF64748B),
  RelationType.dependsOn: Color(0xFF3B82F6),
  RelationType.requires: Color(0xFFF97316),
  RelationType.exampleOf: Color(0xFF22C55E),
  RelationType.similarTo: Color(0xFF06B6D4),
  RelationType.contrastsWith: Color(0xFFEF4444),
  RelationType.causes: Color(0xFFA855F7),
  RelationType.enables: Color(0xFF14B8A6),
  RelationType.usedFor: Color(0xFFEAB308),
  RelationType.alternativeTo: Color(0xFFEC4899),
};

/// L2 subtree palette (ported from packages/graph/src/layout.ts).
const List<Color> branchColors = [
  Color(0xFF3B82F6),
  Color(0xFFEF4444),
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFFA855F7),
  Color(0xFF06B6D4),
  Color(0xFFEC4899),
  Color(0xFFEAB308),
  Color(0xFF14B8A6),
  Color(0xFF8B5CF6),
];

typedef GraphPoint = ({double x, double y});
typedef GraphNodeSize = ({double w, double h, double gap});
typedef GraphEdgeHandles = ({String sourceHandle, String targetHandle});

typedef GraphLayoutNode = ({
  String id,
  double x,
  double y,
  double w,
  double h,
  Color color,
  KnowledgeNode node,
  bool isCompact,
  bool canReveal,
  bool canDeepen,
});

typedef GraphLayoutEdge = ({
  String source,
  String target,
  String sourceHandle,
  String targetHandle,
  String kind,
  Color color,
  String? label,
});

typedef GraphLayout = ({List<GraphLayoutNode> nodes, List<GraphLayoutEdge> edges});

/// Width of a compact (L3+) card — grows with the label length.
double compactW(String label) {
  final textW = label.isEmpty ? 50.0 : label.length * 7.0;
  final w = 30 + textW;
  return math.max(72.0, math.min(300.0, w));
}

/// Level-based card size: L1/L2 are full cards, L3+ are compact.
GraphNodeSize nodeSize(int level, String? label) {
  if (level >= 3) {
    return (w: compactW(label ?? ''), h: compactH, gap: compactGap);
  }
  return (w: nodeW, h: nodeH, gap: nodeGap);
}

/// Pick bezier handles by dominant axis of displacement (ported from layout.ts).
GraphEdgeHandles getEdgeHandles(double sx, double sy, double tx, double ty) {
  final dx = tx - sx;
  final dy = ty - sy;
  final absDx = dx.abs();
  final absDy = dy.abs();
  if (absDy > absDx) {
    if (dy > 0) {
      return (sourceHandle: 'bottom', targetHandle: 'top');
    }
    return (sourceHandle: 'top', targetHandle: 'bottom');
  }
  if (dx > 0) {
    return (sourceHandle: 'right', targetHandle: 'left');
  }
  return (sourceHandle: 'left', targetHandle: 'right');
}

/// A node is visible when its level is below [visibleLevel] OR it (or any of
/// its ancestors) was explicitly revealed. Matching the web reference
/// (apps/web/src/stores/graphStore.ts -> isNodeVisible): a revealed node
/// exposes its whole subtree.
bool isGraphNodeVisible(
  KnowledgeNode node,
  List<KnowledgeNode> tree,
  int visibleLevel,
  Set<String> revealedNodes,
) {
  if (node.level <= visibleLevel) return true;
  // Walk up ancestors: if any of them was revealed, the node is visible.
  final byId = {for (final n in tree) n.id: n};
  KnowledgeNode? cur = node;
  var guard = 0;
  while (cur != null && guard < 50) {
    if (revealedNodes.contains(cur.id)) return true;
    final parentId = cur.parentId;
    cur = parentId != null ? byId[parentId] : null;
    guard++;
  }
  return false;
}

/// Whether the node has descendants that are not visible on the current
/// visibility window — i.e. a «Раскрыть» action would actually reveal
/// something. Mirrors the web graphStore.nodeHasHiddenChildren.
bool nodeHasHiddenChildren(
  KnowledgeNode node,
  List<KnowledgeNode> tree,
  int visibleLevel,
  Set<String> revealedNodes,
) {
  final byId = {for (final n in tree) n.id: n};
  final stack = <String>[];
  for (final n in tree) {
    if (n.parentId == node.id) stack.add(n.id);
  }
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    final child = byId[id];
    if (child == null) continue;
    if (!isGraphNodeVisible(child, tree, visibleLevel, revealedNodes)) {
      return true;
    }
    for (final n in tree) {
      if (n.parentId == id) stack.add(n.id);
    }
  }
  return false;
}

/// Per-node action hints computed the same way as the web Graph screen:
/// «Раскрыть» reveals already-generated hidden children, «Углубить» generates
/// the next level for a real leaf. Terminal nodes (max depth or expanded
/// leaves) get neither.
({bool canReveal, bool canDeepen}) nodeActions(
  KnowledgeNode node,
  List<KnowledgeNode> tree,
  int visibleLevel,
  Set<String> revealedNodes,
) {
  final hasChildren = tree.any((n) => n.parentId == node.id);
  final isTerminal = node.level >= 5 || (node.leaf && node.state == NodeState.expanded);
  final canReveal = !isTerminal &&
      hasChildren &&
      nodeHasHiddenChildren(node, tree, visibleLevel, revealedNodes);
  final canDeepen = !isTerminal && !hasChildren;
  return (canReveal: canReveal, canDeepen: canDeepen);
}

/// Nested radial "fan" layout of the knowledge tree.
///
/// Root sits in the center, L2 nodes share a ring whose radius grows with the
/// subtree spread, and every L3+ node becomes the local center of its own mini
/// radial fan. Positions are top-left corners of the cards (ReactFlow-style).
Map<String, GraphPoint> computeRadialPositions(List<KnowledgeNode> tree) {
  final result = <String, GraphPoint>{};
  if (tree.isEmpty) return result;

  final byId = {for (final n in tree) n.id: n};
  final childrenOf = <String, List<String>>{};
  for (final n in tree) {
    if (n.parentId != null) {
      childrenOf.putIfAbsent(n.parentId!, () => []).add(n.id);
    }
  }

  final roots = tree.where((n) => n.parentId == null).map((n) => n.id).toList();

  // Broken tree without roots: scatter by level around the center.
  if (roots.isEmpty) {
    final byLevel = <int, List<String>>{};
    for (final n in tree) {
      byLevel.putIfAbsent(n.level, () => []).add(n.id);
    }
    for (final entry in byLevel.entries) {
      final r = (entry.key - 1) * subRBase * 1.6 + subRBase;
      final total = math.max(entry.value.length, 1).toDouble();
      for (var i = 0; i < entry.value.length; i++) {
        final theta = (i / total) * tau;
        result[entry.value[i]] =
            (x: r * math.cos(theta), y: r * math.sin(theta));
      }
    }
    return result;
  }

  final kidsCount = <String, int>{};
  final maxW = <String, double>{};
  final leafCount = <String, int>{};

  ({double maxW, int leaves}) computeSubtree(String id) {
    final node = byId[id]!;
    final kids = childrenOf[id] ?? const <String>[];
    kidsCount[id] = kids.length;
    final own = nodeSize(node.level, node.label).w;
    if (kids.isEmpty) {
      maxW[id] = own;
      leafCount[id] = 1;
      return (maxW: own, leaves: 1);
    }
    var mw = own;
    var leaves = 0;
    for (final k in kids) {
      final sub = computeSubtree(k);
      mw = math.max(mw, sub.maxW);
      leaves += sub.leaves;
    }
    maxW[id] = mw;
    leafCount[id] = leaves;
    return (maxW: mw, leaves: leaves);
  }

  for (final r in roots) {
    computeSubtree(r);
  }

  // Radius of the common circle where all children of a node sit.
  double groupRadius(int lv, double mw, int leaves) {
    final clearance = compactGap + nodeW / 2 + mw / 2;
    final perLeaf = mw * 1.0 + compactGap;
    return math.max(
      clearance,
      subRBase + (lv - 2) * 40 + mw * 0.75 + (math.max(leaves, 1) - 1) * perLeaf,
    );
  }

  double radiusOf(String id) {
    final node = byId[id]!;
    return groupRadius(node.level, maxW[id] ?? 0, leafCount[id] ?? 1);
  }

  // Angular footprint of a subtree (radians) as seen from the parent.
  final needRad = <String, double>{};
  double computeNeed(String id) {
    final node = byId[id]!;
    final parent = node.parentId != null ? byId[node.parentId] : null;
    final rParent =
        parent != null ? radiusOf(parent.id) : radiusOf(id);
    final lc = leafCount[id] ?? 1;
    final mw = maxW[id] ?? 0;
    final own = nodeSize(node.level, node.label).w;
    final need = math.max((own + compactGap) / rParent, (lc * mw) / rParent);
    needRad[id] = need;
    return need;
  }

  // Bottom-up pass BEFORE placing nodes so sectors always have width.
  for (final r in roots) {
    computeNeed(r);
  }

  // Recursive placement with proportional angular sectors.
  void place(String id, double start, double end) {
    final node = byId[id]!;
    final parent = node.parentId != null ? byId[node.parentId] : null;
    final kids = childrenOf[id] ?? const <String>[];
    final pp = parent != null ? result[parent.id] : null;

    if (pp != null && parent != null && node.level >= 3) {
      final r = radiusOf(parent.id);
      final theta = (start + end) / 2;
      result[id] = (x: pp.x + r * math.cos(theta), y: pp.y + r * math.sin(theta));
    }

    if (kids.isEmpty) return;
    final span = end - start;
    final totalNeed =
        kids.fold<double>(0, (s, kid) => s + (needRad[kid] ?? 0.1));
    var cur = start;
    for (final kid in kids) {
      final share = ((needRad[kid] ?? 0.1) / totalNeed) * span;
      place(kid, cur, cur + share);
      cur += share;
    }
  }

  for (final r in roots) {
    result[r] = (x: 0, y: 0);
  }

  final l2nodes = tree.where((n) => n.level == 2).toList()
    ..sort((a, b) {
      final pa = a.parentId ?? '';
      final pb = b.parentId ?? '';
      if (pa != pb) return pa.compareTo(pb);
      return a.id.compareTo(b.id);
    });

  final n = l2nodes.length;
  if (n > 0) {
    var maxSubtreeArc = 0.0;
    for (final l2 in l2nodes) {
      final lc = leafCount[l2.id] ?? 1;
      final mw = maxW[l2.id] ?? nodeW;
      maxSubtreeArc = math.max(maxSubtreeArc, lc * (mw + compactGap));
    }
    final l2Radius = math.max(l2RadiusMin * math.sqrt(n), maxSubtreeArc / tau * 2.0);
    final sector = tau / n;
    double baseTheta(int i) => (i + 0.5) * sector;

    // Pre-compute L2 sectors with polar compression compensation.
    final l2Sectors = <String, ({double start, double end})>{};
    var totalSpan = 0.0;
    final rawSpans = <({String id, double span})>[];
    for (var i = 0; i < n; i++) {
      final theta = baseTheta(i);
      final polarFactor = 1 + 0.5 * math.sin(theta).abs();
      rawSpans.add((id: l2nodes[i].id, span: sector * polarFactor));
      totalSpan += sector * polarFactor;
    }
    var cur = 0.0;
    for (final raw in rawSpans) {
      final start = cur;
      final end = cur + (raw.span / totalSpan) * tau;
      l2Sectors[raw.id] = (start: start, end: end);
      cur = end;
    }

    for (var i = 0; i < n; i++) {
      final l2 = l2nodes[i];
      final theta = baseTheta(i);
      final s = l2Sectors[l2.id]!;
      result[l2.id] =
          (x: l2Radius * math.cos(theta), y: l2Radius * math.sin(theta));
      place(l2.id, s.start, s.end);
    }
  }

  return result;
}

/// Builds the layout: positions, branch colors, visible-node filtering and both
/// hierarchy and relation edges.
GraphLayout layoutGraph(
  List<KnowledgeNode> tree, {
  int visibleLevel = 2,
  Set<String> revealedNodes = const {},
}) {
  final visible = tree
      .where((n) => isGraphNodeVisible(n, tree, visibleLevel, revealedNodes))
      .toList();
  final positions = computeRadialPositions(visible);

  final byId = {for (final n in visible) n.id: n};
  final childrenOf = <String, List<String>>{};
  for (final n in visible) {
    if (n.parentId != null) {
      childrenOf.putIfAbsent(n.parentId!, () => []).add(n.id);
    }
  }

  final l2nodes = visible.where((n) => n.level == 2).toList()
    ..sort((a, b) {
      final pa = a.parentId ?? '';
      final pb = b.parentId ?? '';
      if (pa != pb) return pa.compareTo(pb);
      return a.id.compareTo(b.id);
    });

  // Assign a branch color to every L2 subtree and inherit it down the tree.
  final branchColor = <String, Color>{};
  for (var i = 0; i < l2nodes.length; i++) {
    final color = branchColors[i % branchColors.length];
    final stack = <String>[l2nodes[i].id];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      branchColor[id] = color;
      for (final k in childrenOf[id] ?? const <String>[]) {
        stack.add(k);
      }
    }
  }

  const neutral = Color(0xFF94A3B8);

  final graphNodes = <GraphLayoutNode>[];
  for (final node in visible) {
    final pos = positions[node.id] ?? (x: 0.0, y: 0.0);
    final size = nodeSize(node.level, node.label);
    final actions = nodeActions(node, tree, visibleLevel, revealedNodes);
    graphNodes.add((
      id: node.id,
      x: pos.x,
      y: pos.y,
      w: size.w,
      h: size.h,
      color: branchColor[node.id] ?? neutral,
      node: node,
      isCompact: node.level >= 3,
      canReveal: actions.canReveal,
      canDeepen: actions.canDeepen,
    ));
  }

  final graphEdges = <GraphLayoutEdge>[];
  final existingIds = <String>{};
  final nodeIds = visible.map((n) => n.id).toSet();

  for (final child in visible) {
    final parentId = child.parentId;
    if (parentId == null) continue;
    final sp = positions[parentId];
    final tp = positions[child.id];
    if (sp == null || tp == null) continue;
    final parent = byId[parentId];
    final ps = parent != null ? nodeSize(parent.level, parent.label) : nodeSize(1, null);
    final cs = nodeSize(child.level, child.label);
    final handles = getEdgeHandles(
      sp.x + ps.w / 2,
      sp.y + ps.h / 2,
      tp.x + cs.w / 2,
      tp.y + cs.h / 2,
    );
    graphEdges.add((
      source: parentId,
      target: child.id,
      sourceHandle: handles.sourceHandle,
      targetHandle: handles.targetHandle,
      kind: 'hierarchy',
      color: branchColor[child.id] ?? neutral,
      label: null,
    ));
    existingIds.add('$parentId-${child.id}');
  }

  for (final node in visible) {
    for (final rel in node.relations) {
      if (!nodeIds.contains(rel.from) || !nodeIds.contains(rel.to)) continue;
      final eid = 'rel:${rel.from}-${rel.to}';
      if (existingIds.contains(eid)) continue;
      final sp = positions[rel.from];
      final tp = positions[rel.to];
      if (sp == null || tp == null) continue;
      existingIds.add(eid);
      final fromNode = byId[rel.from];
      final toNode = byId[rel.to];
      final fs =
          fromNode != null ? nodeSize(fromNode.level, fromNode.label) : nodeSize(1, null);
      final ts = toNode != null ? nodeSize(toNode.level, toNode.label) : nodeSize(1, null);
      final handles = getEdgeHandles(
        sp.x + fs.w / 2,
        sp.y + fs.h / 2,
        tp.x + ts.w / 2,
        tp.y + ts.h / 2,
      );
      final color = relationColors[rel.type] ?? const Color(0xFF64748B);
      graphEdges.add((
        source: rel.from,
        target: rel.to,
        sourceHandle: handles.sourceHandle,
        targetHandle: handles.targetHandle,
        kind: 'relation',
        color: color,
        label: rel.label ?? rel.type.raw,
      ));
    }
  }

  return (nodes: graphNodes, edges: graphEdges);
}