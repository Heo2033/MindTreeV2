import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/ui/adaptive.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';

const double _minZoom = 0.05;
const double _maxZoom = 8.0;

/// Минимальный читаемый размер подписи на экране (logical px) и потолок
/// компенсации кегля, чтобы карточка не разрасталась втрое.
const double _minReadableFont = 11;
const double _maxFontBoost = 3.0;

/// Минимальный тач-таргет узла на экране (logical px), когда он уменьшен
/// масштабом; до этого размера hit-test расширяется за границы карточки.
const double _minTouchTarget = 44.0;

/// Максимальное расширение hit-test с одной стороны (logical px).
const double _maxHitSlop = 24.0;


/// Interactive knowledge-tree canvas: pan (drag) + zoom (pinch / mouse wheel),
/// bezier edges and rounded-rect node cards drawn with a [CustomPainter].
class GraphCanvas extends StatefulWidget {
  final List<GraphLayoutNode> nodes;
  final List<GraphLayoutEdge> edges;
  final String? selectedNodeId;
  final Set<String> busyNodeIds;
  final void Function(String nodeId) onNodeTap;
  final void Function(String nodeId) onNodeLongPress;
  final void Function(String nodeId)? onNodeExpand;
  final void Function(String nodeId)? onNodeDeepen;
  final bool showLegend;
  final double? zoomLevel;
  final ValueChanged<double>? onZoomChanged;
  final bool showMiniMap;

  const GraphCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.busyNodeIds = const {},
    required this.onNodeTap,
    required this.onNodeLongPress,
    this.onNodeExpand,
    this.onNodeDeepen,
    this.showLegend = false,
    this.zoomLevel,
    this.onZoomChanged,
    this.showMiniMap = true,
  });

  @override
  State<GraphCanvas> createState() => GraphCanvasState();
}

/// Screen-space view state: the fixed fit transform (centering) plus the base
/// scale that maps world coordinates into the viewport.
class _View {
  final Offset fit;
  final double base;

  const _View(this.fit, this.base);

  Offset screenToGesture(Offset screen) => (screen - fit) / base;
}

/// A hover action chip: «Раскрыть» (reveal) or «Углубить» (deepen).
typedef _ActionChip = ({String action, Rect rect});

/// Hover UI for one node: optional one-liner popover (compact cards) followed
/// by the action chips. Shared by the painter and the hit-test so both always
/// agree on geometry.
typedef _HoverLayout = ({Rect? popover, List<_ActionChip> chips});

/// World-space layout of the hover UI for a node. Chips and the popover are
/// only created when the node actually has an action to offer.
_HoverLayout _hoverLayoutFor(GraphLayoutNode node) {
  var y = node.y + node.h + 8;
  Rect? popover;
  if (node.isCompact && node.node.oneLiner.isNotEmpty) {
    popover = Rect.fromLTWH(node.x, y, 200, 44);
    y += 52;
  }
  final chips = <_ActionChip>[];
  if (node.canReveal) {
    chips.add((action: 'reveal', rect: Rect.fromLTWH(node.x, y, 96, 22)));
    y += 28;
  }
  if (node.canDeepen) {
    chips.add((action: 'deepen', rect: Rect.fromLTWH(node.x, y, 96, 22)));
    y += 28;
  }
  return (popover: popover, chips: chips);
}

/// Центр хэндла узла в мировых координатах. Общая для hit-test и painter,
/// чтобы геометрия рёбер совпадала.
Offset _handleCenter(GraphLayoutNode n, String handle) {
  final rect = Rect.fromLTWH(n.x, n.y, n.w, n.h);
  switch (handle) {
    case 'bottom':
      return Offset(rect.center.dx, rect.bottom);
    case 'top':
      return Offset(rect.center.dx, rect.top);
    case 'right':
      return Offset(rect.right, rect.center.dy);
    default:
      return Offset(rect.left, rect.center.dy);
  }
}

Offset _outward(String handle, double bend) {
  switch (handle) {
    case 'bottom':
      return Offset(0, bend);
    case 'top':
      return Offset(0, -bend);
    case 'right':
      return Offset(bend, 0);
    default:
      return Offset(-bend, 0);
  }
}

Path _bezier(Offset s, Offset t, String sourceHandle, String targetHandle) {
  final dx = (t.dx - s.dx).abs();
  final dy = (t.dy - s.dy).abs();
  final dist = math.sqrt(dx * dx + dy * dy);
  final bend = math.max(28.0, math.min(120.0, dist * 0.35));
  final c1 = s + _outward(sourceHandle, bend);
  final c2 = t + _outward(targetHandle, bend);
  return Path()
    ..moveTo(s.dx, s.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, t.dx, t.dy);
}

class GraphCanvasState extends State<GraphCanvas> {
  final Matrix4 _gesture = Matrix4.identity();
  _View? _view;
  String? _hoveredId;
  String? _hoveredEdgeId;

  /// Hovered relation-edge id (debug/test hook; same lifecycle as hover UI).
  @visibleForTesting
  String? get debugHoveredEdgeId => _hoveredEdgeId;

  /// World → экранные координаты **в системе канваса** (без учёта позиции
  /// канваса на экране); для глобальных добавьте offset канваса. Тест-хук.
  @visibleForTesting
  Offset debugWorldToScreen(Offset world) => _worldToScreen(world);

  Matrix4? _startGesture;
  Offset _startFocal = Offset.zero;

  double _translate(Matrix4 m) => m.storage[12];
  double _scaleOf(Matrix4 m) => m.getMaxScaleOnAxis();

  Offset _inverseTransform(Matrix4 m, Offset p) {
    final s = _scaleOf(m);
    if (s == 0) return p;
    return Offset((p.dx - _translate(m)) / s, (p.dy - _transY(m)) / s);
  }

  double _transY(Matrix4 m) => m.storage[13];

  /// World coordinates -> screen, using the same transform as the painter
  /// (if (baseScale) translate(fit) scale(base) transform(gesture)).
  Offset _worldToScreen(Offset world) {
    final view = _view;
    if (view == null) return world;
    final s = _scaleOf(_gesture);
    final t = Offset(_translate(_gesture), _transY(_gesture));
    return view.fit + (world * s + t) * view.base;
  }

  GraphLayoutNode? _hoveredNode() {
    final id = _hoveredId;
    if (id == null) return null;
    for (final n in widget.nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _onHover(PointerHoverEvent event) {
    final hit = _hitTest(event.localPosition);
    final id = hit?.id;
    if (id != _hoveredId) setState(() => _hoveredId = id);

    // Подсветка relation-рёбер (зеркало web hoveredEdgeId): только когда
    // курсор не над узлом, чтобы чипы и ребро не конфликтовали.
    if (hit == null) {
      final view = _view;
      if (view == null) return;
      final p = view.screenToGesture(event.localPosition);
      final w = _inverseTransform(_gesture, p);
      final edgeId = _hitTestEdge(w);
      if (edgeId != _hoveredEdgeId) setState(() => _hoveredEdgeId = edgeId);
    } else if (_hoveredEdgeId != null) {
      setState(() => _hoveredEdgeId = null);
    }
  }

  void _onHoverExit(PointerExitEvent event) {
    setState(() {
      _hoveredId = null;
      _hoveredEdgeId = null;
    });
  }

  void _onTapUp(TapUpDetails d) {
    final hovered = _hoveredNode();
    if (hovered != null) {
      for (final chip in _hoverLayoutFor(hovered).chips) {
        final screen = Rect.fromCenter(
          center: _worldToScreen(chip.rect.center),
          width: chip.rect.width * _scaleOf(_gesture) * (_view?.base ?? 1),
          height: chip.rect.height * _scaleOf(_gesture) * (_view?.base ?? 1),
        );
        if (screen.contains(d.localPosition)) {
          if (chip.action == 'reveal') {
            widget.onNodeExpand?.call(hovered.id);
          } else {
            widget.onNodeDeepen?.call(hovered.id);
          }
          return;
        }
      }
    }
    final hit = _hitTest(d.localPosition);
    if (hit != null) widget.onNodeTap(hit.id);
  }

  Rect _bounds() {
    if (widget.nodes.isEmpty) return Rect.fromLTWH(-100, -100, 200, 200);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in widget.nodes) {
      minX = math.min(minX, n.x);
      minY = math.min(minY, n.y);
      maxX = math.max(maxX, n.x + n.w);
      maxY = math.max(maxY, n.y + n.h);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _baseScale(Size size, Rect bbox) {
    final longest = math.max(bbox.width, bbox.height);
    if (longest <= 0) return 0.5;
    return math.max(0.15, math.min(1.0, size.shortestSide / (longest * 1.6)));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startGesture = _gesture.clone();
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final view = _view;
    final start = _startGesture;
    if (view == null || start == null) return;
    final t0 = Offset(_translate(start), _transY(start));
    final s0 = _scaleOf(start);
    final p0 = view.screenToGesture(_startFocal);
    final p1 = view.screenToGesture(d.localFocalPoint);
    final s1 = (s0 * d.scale).clamp(_minZoom, _maxZoom);
    final ratio = s1 / s0;
    final t1 = p1 - (p0 - t0) * ratio;
    _gesture.setIdentity();
    _gesture[0] = s1;
    _gesture[5] = s1;
    _gesture[12] = t1.dx;
    _gesture[13] = t1.dy;
    setState(() {});
  }

  void _zoomAt(Offset focal, double factor) {
    final view = _view;
    if (view == null) return;
    final s0 = _scaleOf(_gesture);
    final t0 = Offset(_translate(_gesture), _transY(_gesture));
    final p0 = view.screenToGesture(focal);
    final s1 = (s0 * factor).clamp(_minZoom, _maxZoom);
    final world = (p0 - t0) / s0;
    final t1 = p0 - world * s1;
    _gesture.setIdentity();
    _gesture[0] = s1;
    _gesture[5] = s1;
    _gesture[12] = t1.dx;
    _gesture[13] = t1.dy;
    setState(() {});
    widget.onZoomChanged?.call(s1);
  }

  /// Zoom in/out from the center of the canvas.
  void zoomBy(double factor) {
    final view = _view;
    if (view == null) return;
    final center = Offset(
      _view!.fit.dx / _view!.base + 200, // approximate center
      _view!.fit.dy / _view!.base + 150,
    );
    _zoomAt(center, factor);
  }

  /// Reset to fit view.
  void fitView() {
    _gesture.setIdentity();
    setState(() {});
    widget.onZoomChanged?.call(1.0);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15;
    _zoomAt(event.localPosition, factor);
  }

  GraphLayoutNode? _hitTest(Offset screenPoint) {
    final view = _view;
    if (view == null) return null;
    final p = view.screenToGesture(screenPoint);
    final w = _inverseTransform(_gesture, p);
    // Мировые → экранные единицы: нужны для расширения тач-зоны, когда узел
    // на экране меньше минимального тач-таргета (частый случай на телефоне).
    final scale = view.base * _scaleOf(_gesture);
    for (final n in widget.nodes.reversed) {
      var left = n.x;
      var top = n.y;
      var right = n.x + n.w;
      var bottom = n.y + n.h;
      if (scale > 0) {
        if (n.w * scale < _minTouchTarget) {
          final grow = math.min(
                _maxHitSlop,
                (_minTouchTarget - n.w * scale) / 2,
              ) /
              scale;
          left -= grow;
          right += grow;
        }
        if (n.h * scale < _minTouchTarget) {
          final grow = math.min(
                _maxHitSlop,
                (_minTouchTarget - n.h * scale) / 2,
              ) /
              scale;
          top -= grow;
          bottom += grow;
        }
      }
      if (w.dx >= left &&
          w.dx <= right &&
          w.dy >= top &&
          w.dy <= bottom) {
        return n;
      }
    }
    return null;
  }

  /// Hit-test relation-рёбер в мировых координатах: первый relation-edge,
  /// ближе которого к курсору ~9 world units (аналог interactionWidth=24 в web).
  String? _hitTestEdge(Offset worldPoint) {
    final byId = {for (final n in widget.nodes) n.id: n};
    for (final e in widget.edges) {
      if (e.kind != 'relation') continue;
      final source = byId[e.source];
      final target = byId[e.target];
      if (source == null || target == null) continue;
      final s = _handleCenter(source, e.sourceHandle);
      final t = _handleCenter(target, e.targetHandle);
      final path = _bezier(s, t, e.sourceHandle, e.targetHandle);
      if (_distanceToPath(path, worldPoint) <= 9) return e.id;
    }
    return null;
  }

  /// Минимальное расстояние от точки до кривой (аппроксимация полилинией).
  double _distanceToPath(Path path, Offset point, {int samples = 24}) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return double.infinity;
    final metric = metrics.first;
    var best = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / samples);
      if (tangent == null) continue;
      final d = (tangent.position - point).distance;
      if (d < best) best = d;
    }
    return best;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final hit = _hitTest(d.localPosition);
    if (hit != null) widget.onNodeLongPress(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bbox = _bounds();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final base = _baseScale(size, bbox);
        final fit = size.center(Offset.zero) - bbox.center * base;
        _view = _View(fit, base);

        return ClipRect(
          child: MouseRegion(
            onHover: _onHover,
            onExit: _onHoverExit,
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onDoubleTapDown: (d) => _zoomAt(d.localPosition, 1.4),
                onLongPressStart: _onLongPressStart,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: CustomPaint(
                  size: size,
                  painter: _GraphPainter(
                    nodes: widget.nodes,
                    edges: widget.edges,
                    selectedNodeId: widget.selectedNodeId,
                    busyNodeIds: widget.busyNodeIds,
                    hoveredNodeId: _hoveredId,
                    hoveredEdgeId: _hoveredEdgeId,
                    gesture: _gesture,
                    fit: fit,
                    baseScale: base,
                    // На узком экране подписи компенсируются по масштабу
                    // (иначе при подгонке дерева кегль падает до 3–4 px);
                    // широкий экран рисуется как раньше.
                    compensateText: size.width < kWideBreakpoint,
                    showLegend: widget.showLegend,
                    background: scheme.surfaceContainerHighest,
                    surface: scheme.surface,
                    text: scheme.onSurface,
                    subtext: scheme.onSurfaceVariant,
                    grid: scheme.outlineVariant.withValues(alpha: 0.35),
                    ok: AppColors.ok,
                    warn: AppColors.warn,
                    selected: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphLayoutNode> nodes;
  final List<GraphLayoutEdge> edges;
  final String? selectedNodeId;
  final Set<String> busyNodeIds;
  final String? hoveredNodeId;
  final String? hoveredEdgeId;
  final Matrix4 gesture;
  final Offset fit;
  final double baseScale;
  final bool showLegend;

  /// Компенсировать ли кегль подписей при уменьшении масштаба (узкий экран).
  final bool compensateText;

  final Color background;
  final Color surface;
  final Color text;
  final Color subtext;
  final Color grid;
  final Color ok;
  final Color warn;
  final Color selected;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.selectedNodeId,
    required this.busyNodeIds,
    required this.hoveredNodeId,
    required this.hoveredEdgeId,
    required this.gesture,
    required this.fit,
    required this.baseScale,
    required this.showLegend,
    required this.compensateText,
    required this.background,
    required this.surface,
    required this.text,
    required this.subtext,
    required this.grid,
    required this.ok,
    required this.warn,
    required this.selected,
  });

  Map<String, GraphLayoutNode> get _byId => {for (final n in nodes) n.id: n};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final gridPaint = Paint()..color = grid;
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.1, gridPaint);
      }
    }

    canvas.save();
    canvas.translate(fit.dx, fit.dy);
    canvas.scale(baseScale);
    canvas.transform(gesture.storage);

    final byId = _byId;
    for (final e in edges) {
      _paintEdge(canvas, e, byId);
    }
    for (final n in nodes) {
      _paintNode(canvas, n);
    }
    _paintHoverUI(canvas);
    canvas.restore();

    if (showLegend) {
      _paintLegend(canvas, size);
    }
  }

  // ---- Edges ----

  void _paintEdge(
    Canvas canvas,
    GraphLayoutEdge e,
    Map<String, GraphLayoutNode> byId,
  ) {
    final source = byId[e.source];
    final target = byId[e.target];
    if (source == null || target == null) return;
    final s = _handleCenter(source, e.sourceHandle);
    final t = _handleCenter(target, e.targetHandle);
    final path = _bezier(s, t, e.sourceHandle, e.targetHandle);

    if (e.kind == 'relation') {
      final highlighted = e.id == hoveredEdgeId;
      final paint = Paint()
        ..color = e.color.withValues(alpha: highlighted ? 1.0 : 0.55)
        ..strokeWidth = highlighted ? 3 : 1.25
        ..style = PaintingStyle.stroke;
      _dashPath(canvas, path, paint, dash: 5, gap: 4);
      _paintArrow(canvas, path, e.color.withValues(alpha: highlighted ? 1.0 : 0.85));
      // Always show label for relation edges (not just on hover)
      if (e.label != null && e.label!.isNotEmpty) {
        _paintEdgeLabel(canvas, path, e.label!, e.color);
      }
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = e.color.withValues(alpha: 0.85)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _dashPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist = end + gap;
      }
    }
  }

  void _paintArrow(Canvas canvas, Path path, Color color) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) return;
    final pos = tangent.position;
    final dir = tangent.angle;
    final tip = pos;
    final back = pos - Offset(math.cos(dir), math.sin(dir)) * 9;
    final perpL = pos - Offset(math.cos(dir + math.pi / 2), math.sin(dir + math.pi / 2)) * 4;
    final perpR = pos - Offset(math.cos(dir - math.pi / 2), math.sin(dir - math.pi / 2)) * 4;
    final triangle = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + (perpL.dx - pos.dx), back.dy + (perpL.dy - pos.dy))
      ..lineTo(back.dx + (perpR.dx - pos.dx), back.dy + (perpR.dy - pos.dy))
      ..close();
    canvas.drawPath(triangle, Paint()..color = color);
  }

  void _paintEdgeLabel(Canvas canvas, Path path, String label, Color color) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length / 2);
    if (tangent == null) return;
    final center = tangent.position;

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: _font(10),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 10,
      height: tp.height + 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, rect.topLeft + const Offset(5, 2.5));
  }

  // ---- Nodes ----

  void _paintNode(Canvas canvas, GraphLayoutNode n) {
    final rect = Rect.fromLTWH(n.x, n.y, n.w, n.h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    final isSelected = n.id == selectedNodeId;

    if (isSelected) {
      final halo = RRect.fromRectAndRadius(
        rect.inflate(5),
        const Radius.circular(11),
      );
      canvas.drawRRect(
        halo,
        Paint()
          ..color = selected.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    canvas.drawRRect(rrect, Paint()..color = surface);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isSelected ? selected : n.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.6,
    );

    final dotColor = n.node.contentLoaded
        ? ok
        : n.node.oneLiner.isNotEmpty
            ? subtext
            : warn;
    if (n.node.state == NodeState.failed ||
        n.node.state == NodeState.invalid) {
      canvas.drawCircle(
        rect.topRight - const Offset(8, 8),
        3,
        Paint()..color = const Color(0xFFDC2626),
      );
    }

    if (n.isCompact) {
      _drawCompactNode(canvas, n, rect, dotColor);
    } else {
      _drawFullNode(canvas, n, rect, dotColor);
    }
  }

  void _drawCompactNode(Canvas canvas, GraphLayoutNode n, Rect rect, Color dot) {
    // Текст компенсируется по масштабу и может вырасти за пределы карточки —
    // обрезаем по её границам, чтобы не наезжать на соседей.
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawCircle(
      Offset(rect.left + 11, rect.center.dy),
      3,
      Paint()..color = dot,
    );
    final maxW = math.max(16.0, rect.width - 28);
    final label = _fittedLabel(
      n.node.label,
      fontSize: _font(12),
      color: text.withValues(alpha: 0.95),
      fontWeight: FontWeight.w600,
      maxLines: 1,
      maxWidth: maxW,
      maxHeight: rect.height - 2,
    );
    label.paint(
      canvas,
      Offset(rect.left + 20, rect.center.dy - label.height / 2),
    );
    canvas.restore();
  }

  void _drawFullNode(Canvas canvas, GraphLayoutNode n, Rect rect, Color dot) {
    // См. _drawCompactNode: компенсированный кегль обрезается карточкой.
    canvas.save();
    canvas.clipRect(rect);
    final left = rect.left + 10;
    final top = rect.top + 8;
    canvas.drawCircle(Offset(left + 5, top + 6), 3.5, Paint()..color = dot);

    final label = _fittedLabel(
      n.node.label,
      fontSize: _font(13),
      color: text,
      fontWeight: FontWeight.w700,
      maxLines: 2,
      maxWidth: rect.width - 40,
      maxHeight: rect.height - 14, // поля 8 сверху + 6 снизу
    );
    label.paint(canvas, Offset(left + 14, top));

    if (n.node.oneLiner.isNotEmpty) {
      final oy = top + label.height + 3;
      final remaining = rect.bottom - 6 - oy;
      // Подпись вписываем в оставшуюся высоту (не рисуем только огрызок
      // меньше 8 px — заголовок важнее).
      if (remaining > 8) {
        final oneLiner = _fittedLabel(
          n.node.oneLiner,
          fontSize: _font(11),
          color: subtext,
          maxLines: 2,
          maxWidth: rect.width - 24,
          maxHeight: remaining,
        );
        oneLiner.paint(canvas, Offset(left + 14, oy));
      }
    }
    canvas.restore();
  }

  TextPainter _makeText(
    String text, {
    required double fontSize,
    required Color color,
    FontWeight? fontWeight,
    int? maxLines,
    String? ellipsis,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight ?? FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );
  }

  /// Подпись, вписанная в карточку узла. Компенсация кегля по масштабу
  /// ([_font]) поднимает шрифт вплоть до ×3 — если узлу на экране мало,
  /// текст резался границами карточки и «не влезал». Здесь кегль дополнительно
  /// ограничивается высотой карточки: если не влез — уменьшаем пропорционально
  /// и перерисовываем (текст всегда целиком внутри узла).
  TextPainter _fittedLabel(
    String text, {
    required double fontSize,
    required Color color,
    FontWeight? fontWeight,
    required int maxLines,
    required double maxWidth,
    required double maxHeight,
  }) {
    TextPainter make(double size) => _makeText(
          text,
          fontSize: size,
          color: color,
          fontWeight: fontWeight,
          maxLines: maxLines,
          ellipsis: '…',
        );
    var label = make(fontSize);
    label.layout(maxWidth: maxWidth);
    if (label.height > maxHeight && label.height > 0) {
      label = make(fontSize * (maxHeight / label.height));
      label.layout(maxWidth: maxWidth);
    }
    return label;
  }

  /// Экранный масштаб: мировые координаты → logical px на экране.
  double get _screenScale => baseScale * gesture.getMaxScaleOnAxis();

  /// Кегль подписи с компенсацией масштаба.
  ///
  /// Дерево подгоняется под экран, поэтому на телефоне карточка часто
  /// занимает 0.2–0.4 от своей мировой ширины, и фиксированные 11–13 px
  /// превращаются в 3–4 px на экране. Компенсация поднимает кегль так,
  /// чтобы на экране было не меньше [_minReadableFont], но не более чем
  /// в [_maxFontBoost] раз (дальше пользователь зумит).
  double _font(double fontSize) {
    if (!compensateText) return fontSize;
    final eff = _screenScale;
    if (eff <= 0 || eff >= 1) return fontSize;
    return math.min(_minReadableFont / eff, fontSize * _maxFontBoost);
  }

  void _paintHoverUI(Canvas canvas) {
    final hoveredId = hoveredNodeId;
    if (hoveredId == null) return;
    GraphLayoutNode? hovered;
    for (final n in nodes) {
      if (n.id == hoveredId) {
        hovered = n;
        break;
      }
    }
    if (hovered == null) return;
    final layout = _hoverLayoutFor(hovered);
    if (layout.chips.isEmpty && layout.popover == null) return;

    final chipBg = surface;
    final chipBorder = selected.withValues(alpha: 0.7);

    if (layout.popover != null) {
      final r = layout.popover!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()..color = surface.withValues(alpha: 0.96),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()
          ..color = subtext.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final oneLiner = _makeText(
        hovered.node.oneLiner,
        fontSize: 11,
        color: subtext,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: r.width - 12);
      oneLiner.paint(canvas, r.topLeft + const Offset(6, 6));
    }

    for (final chip in layout.chips) {
      final busy = busyNodeIds.contains(hovered.id);
      final rrect = RRect.fromRectAndRadius(chip.rect, const Radius.circular(6));
      canvas.drawRRect(rrect, Paint()..color = busy ? chipBorder : chipBg);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = chipBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final labelText = busy
          ? 'Генерирую…'
          : chip.action == 'reveal'
              ? 'Раскрыть'
              : 'Углубить';
      final label = _makeText(
        labelText,
        fontSize: 11,
        color: chip.action == 'reveal' ? selected : ok,
        fontWeight: FontWeight.w600,
      )..layout(maxWidth: chip.rect.width - 12);
      label.paint(
        canvas,
        Offset(
          chip.rect.left + (chip.rect.width - label.width) / 2,
          chip.rect.top + (chip.rect.height - label.height) / 2,
        ),
      );
    }
  }

  void _paintLegend(Canvas canvas, Size size) {
    const rowH = 18.0;
    final branchColors = <Color>[];
    for (final n in nodes) {
      if (!branchColors.contains(n.color) && branchColors.length < 6) {
        branchColors.add(n.color);
      }
    }
    if (branchColors.isEmpty) return;
    final width = 150.0;
    final height = 28 + rowH * branchColors.length + 8;
    final origin = Offset(12, size.height - height - 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, width, height),
        const Radius.circular(10),
      ),
      Paint()..color = surface.withValues(alpha: 0.92),
    );
    final title = _makeText(
      'Ветки',
      fontSize: 11,
      color: text,
      fontWeight: FontWeight.w700,
    )..layout();
    title.paint(canvas, origin + const Offset(10, 8));
    var y = origin.dy + 26;
    for (var i = 0; i < branchColors.length; i++) {
      canvas.drawCircle(
        Offset(origin.dx + 16, y + 3),
        4,
        Paint()..color = branchColors[i],
      );
      final t = _makeText('Ветка ${i + 1}', fontSize: 11, color: subtext)..layout();
      t.paint(canvas, Offset(origin.dx + 26, y));
      y += rowH;
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.busyNodeIds != busyNodeIds ||
        oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.hoveredEdgeId != hoveredEdgeId ||
        oldDelegate.gesture != gesture ||
        oldDelegate.fit != fit ||
        oldDelegate.baseScale != baseScale ||
        oldDelegate.compensateText != compensateText ||
        oldDelegate.showLegend != showLegend;
  }
}