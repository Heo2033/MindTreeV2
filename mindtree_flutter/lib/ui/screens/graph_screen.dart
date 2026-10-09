import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/adaptive.dart';
import 'package:mindtree_flutter/ui/graph/graph_canvas.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';
import 'package:mindtree_flutter/ui/widgets/topic_meta_bar.dart';

const Map<String, String> _phaseLabel = {
  'structure': 'Структурирование темы',
  'structure-l2': 'Генерация разделов (L2)',
  'structure-l3': 'Генерация подразделов (L3)',
  'expand': 'Развёртывание дерева',
  'validate': 'Проверка полноты',
  'repair': 'Исправление пробелов',
  'content': 'Генерация содержимого',
  'done': 'Готово',
};

const Map<String, String> _conceptTypeLabel = {
  'topic': 'Тема',
  'concept': 'Понятие',
  'component': 'Компонент',
  'mechanism': 'Механизм',
  'process': 'Процесс',
  'property': 'Свойство',
  'rule': 'Правило',
  'method': 'Метод',
  'example': 'Пример',
};

class GraphScreen extends ConsumerStatefulWidget {
  final String topicId;

  const GraphScreen({super.key, required this.topicId});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  String? _selectedId;
  bool _showLegend = false;
  bool _hiddenPanelOpen = true;
  final Set<String> _expanding = {};
  final Set<String> _generating = {};
  final Set<String> _revealingHidden = {};
  final GlobalKey<GraphCanvasState> _canvasKey = GlobalKey<GraphCanvasState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
    });
  }

  KnowledgeNode? _selectedNode(GraphState state) {
    final id = _selectedId;
    if (id == null) return null;
    for (final n in state.nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _onNodeTap(String id) {
    setState(() => _selectedId = id);
  }

  void _onExpand(String id) {
    setState(() => _expanding.add(id));
    ref.read(graphStoreProvider.notifier).expandNode(id).whenComplete(() {
      if (mounted) setState(() => _expanding.remove(id));
    });
  }

  void _onGenerate(String id) {
    setState(() => _generating.add(id));
    ref.read(graphStoreProvider.notifier).generateContent(id).whenComplete(() {
      if (mounted) setState(() => _generating.remove(id));
    });
  }

  void _onRevealHidden(String id) {
    setState(() => _revealingHidden.add(id));
    ref.read(graphStoreProvider.notifier).expandNode(id).whenComplete(() {
      if (mounted) setState(() => _revealingHidden.remove(id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(graphStoreProvider);
    final notifier = ref.read(graphStoreProvider.notifier);
    final session = ref.watch(sessionStoreProvider);

    if (state.loading && !state.pipeline.running) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }

    if (state.error != null && state.nodes.isEmpty && !state.pipeline.running) {
      return ErrorBanner(message: state.error!, onDismiss: () {});
    }

    final layout = layoutGraph(
      state.nodes,
      visibleLevel: state.visibleLevel,
      revealedNodes: state.revealedNodes,
    );
    final hiddenCount = state.nodes.length - layout.nodes.length;
    final selected = _selectedNode(state);
    final selectedActions = selected != null
        ? nodeActions(selected, state.nodes, state.visibleLevel, state.revealedNodes)
        : null;

    // Узлы, у которых есть скрытые ещё не показанные подразделы — кандидаты
    // панели «Есть подразделы», как в web Graph.tsx (canDeepen).
    final deepenCandidates = state.nodes.where((n) {
      final a = nodeActions(n, state.nodes, state.visibleLevel, state.revealedNodes);
      return a.canReveal;
    }).toList();

    return Column(
      children: [
        _Toolbar(
          topicName: state.topicName ?? widget.topicId,
          goal: goalText(state.topic),
          level: targetLevelText(state.topic),
          time: topicTimeLabel(session, widget.topicId),
          visibleCount: layout.nodes.length,
          hiddenCount: hiddenCount,
          showLegend: _showLegend,
          generating: selected != null && _generating.contains(selected.id),
          onToggleLegend: () => setState(() => _showLegend = !_showLegend),
          onExpandLevel: () {
            setState(() => _selectedId = null);
            notifier.autoExpandVisible();
          },
          onGenerateAll: () {
            final ids = state.nodes
                .where((n) => n.state == NodeState.structureGenerated)
                .map((n) => n.id)
                .toList();
            setState(() => _generating.addAll(ids));
            for (final id in ids) {
              notifier.generateContent(id).whenComplete(() {
                if (mounted) setState(() => _generating.remove(id));
              });
            }
          },
          onRefresh: () => notifier.loadTopic(widget.topicId),
        ),
        Expanded(
          child: Stack(
            children: [
              GraphCanvas(
                key: _canvasKey,
                nodes: layout.nodes,
                edges: layout.edges,
                selectedNodeId: _selectedId,
                busyNodeIds: _expanding,
                showLegend: _showLegend,
                onNodeTap: _onNodeTap,
                onNodeExpand: _onExpand,
                onNodeDeepen: _onExpand,
                onNodeLongPress: (id) {
                  context.go('/topic/learn/focus');
                },
              ),
              // Controls: zoom in/out/fit (как web Controls)
              Positioned(
                bottom: 16,
                right: 16,
                child: _GraphControls(
                  onZoomIn: () => _canvasKey.currentState?.zoomBy(1.3),
                  onZoomOut: () => _canvasKey.currentState?.zoomBy(1 / 1.3),
                  onFit: () => _canvasKey.currentState?.fitView(),
                ),
              ),
              // MiniMap (как web ReactFlow MiniMap). На узком экране он
              // занимает слишком много места поверх дерева — прячем.
              if (layout.nodes.isNotEmpty && isWideLayout(context))
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: _MiniMap(nodes: layout.nodes, edges: layout.edges),
                ),
              // Панель «Есть подразделы» — узлы со скрытыми детьми (web Graph.tsx)
              if (deepenCandidates.isNotEmpty)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _HiddenNodesPanel(
                    nodes: deepenCandidates,
                    hiddenCount: hiddenCount,
                    visibleLevel: state.visibleLevel,
                    open: _hiddenPanelOpen,
                    busyId: _revealingHidden.isEmpty
                        ? null
                        : _revealingHidden.first,
                    onToggle: () => setState(() => _hiddenPanelOpen = !_hiddenPanelOpen),
                    onReveal: _onRevealHidden,
                  ),
                ),
              if (state.pipeline.running)
                _PipelineOverlay(
                  phase: state.pipeline.phase,
                  message: state.pipeline.message,
                  stats: state.pipeline.stats,
                ),
              if (state.contentFilling)
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Loader(size: LoaderSize.sm),
                        const SizedBox(width: 8),
                        Text(
                          'Заполнение контента…',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (layout.nodes.isEmpty && !state.pipeline.running)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Дерево знаний ещё не построено',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Постройте дерево понятий, чтобы начать изучение темы.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (selected != null)
          _DetailPanel(
            node: selected,
            canReveal: selectedActions?.canReveal ?? false,
            canDeepen: selectedActions?.canDeepen ?? false,
            expanding: _expanding.contains(selected.id),
            generating: _generating.contains(selected.id),
            onExpand: () => _onExpand(selected.id),
            onGenerate: () => _onGenerate(selected.id),
            onOpenFocus: () =>
                context.go('/topic/learn/focus'),
            onClose: () => setState(() => _selectedId = null),
          ),
        if (selected != null) const SizedBox(height: 8),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final String topicName;
  final String? goal;
  final String? level;
  final String? time;
  final int visibleCount;
  final int hiddenCount;
  final bool showLegend;
  final bool generating;
  final VoidCallback onToggleLegend;
  final VoidCallback onExpandLevel;
  final VoidCallback onGenerateAll;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.topicName,
    required this.goal,
    required this.level,
    required this.time,
    required this.visibleCount,
    required this.hiddenCount,
    required this.showLegend,
    required this.generating,
    required this.onToggleLegend,
    required this.onExpandLevel,
    required this.onGenerateAll,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  topicName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              ),
              IconButton(
                tooltip: showLegend ? 'Скрыть легенду' : 'Показать легенду',
                icon: Icon(showLegend ? Icons.layers : Icons.layers_outlined),
                onPressed: onToggleLegend,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Шаг 9 аудита (§81): цель, уровень и время — в шапке графа.
              ...topicMetaBadges(goal: goal, level: level, time: time),
              StatusBadge(
                hiddenCount > 0
                    ? 'Видно $visibleCount / ${visibleCount + hiddenCount}'
                    : '$visibleCount узлов',
                icon: Icons.visibility_outlined,
              ),
              AppButton(
                'Показать следующий уровень',
                icon: Icons.expand_more,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: onExpandLevel,
              ),
              AppButton(
                'Сгенерировать содержимое',
                icon: generating ? null : Icons.auto_awesome,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                busy: generating,
                onPressed: onGenerateAll,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineOverlay extends StatelessWidget {
  final String phase;
  final String message;
  final TreeStats? stats;

  const _PipelineOverlay({
    required this.phase,
    required this.message,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (stats != null && (stats!.total) > 0)
        ? math.min(100, stats!.depth / 5 * 100).round()
        : null;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        width: math.min(440, MediaQuery.sizeOf(context).width - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _phaseLabel[phase] ?? 'Построение дерева',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (stats != null) ...[
              const SizedBox(height: 8),
              Text(
                'Узлов: ${stats!.total} · Глубина: ${stats!.depth} · Листьев: ${stats!.leaves}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (pct != null) ...[
              const SizedBox(height: 8),
              ProgressBar(value: pct.toDouble(), label: '$pct%'),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final KnowledgeNode node;
  final bool canReveal;
  final bool canDeepen;
  final bool expanding;
  final bool generating;
  final VoidCallback onExpand;
  final VoidCallback onGenerate;
  final VoidCallback onOpenFocus;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.node,
    required this.canReveal,
    required this.canDeepen,
    required this.expanding,
    required this.generating,
    required this.onExpand,
    required this.onGenerate,
    required this.onOpenFocus,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeLabel =
        _conceptTypeLabel[node.conceptType?.raw] ?? 'Понятие';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              StatusBadge(typeLabel, icon: Icons.category_outlined),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Закрыть',
                icon: const Icon(Icons.close),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (node.oneLiner.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              node.oneLiner,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ProgressBar(
                  value: (node.importance * 100).clamp(0, 100).toDouble(),
                  label: 'Важность ${(node.importance * 100).round()}%',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ProgressBar(
                  value: (node.difficulty * 100).clamp(0, 100).toDouble(),
                  label: 'Сложность ${(node.difficulty * 100).round()}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canReveal)
                AppButton(
                  'Раскрыть ветку',
                  icon: Icons.unfold_more,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  busy: expanding,
                  onPressed: onExpand,
                ),
              if (canDeepen)
                AppButton(
                  'Углубить ветку',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  busy: expanding,
                  onPressed: onExpand,
                ),
              if (!node.contentLoaded)
                AppButton(
                  generating ? 'Генерация…' : 'Сгенерировать контент',
                  icon: generating ? null : Icons.auto_awesome,
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.sm,
                  busy: generating,
                  onPressed: generating ? null : onGenerate,
                ),
               AppButton(
                'Фокус',
                icon: Icons.center_focus_strong,
                size: AppButtonSize.sm,
                onPressed: onOpenFocus,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Панель «Есть подразделы» — список узлов со скрытыми детьми (web Graph.tsx).
class _HiddenNodesPanel extends StatelessWidget {
  final List<KnowledgeNode> nodes;
  final int hiddenCount;
  final int visibleLevel;
  final bool open;
  final String? busyId;
  final VoidCallback onToggle;
  final void Function(String id) onReveal;

  const _HiddenNodesPanel({
    required this.nodes,
    required this.hiddenCount,
    required this.visibleLevel,
    required this.open,
    required this.busyId,
    required this.onToggle,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Есть подразделы (${nodes.length})',
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (hiddenCount > 0 && visibleLevel < 5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Text(
                  'Скрыто $hiddenCount узл.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          if (open) ...[
            const Divider(height: 1),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 288),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: nodes.length,
                  itemBuilder: (context, i) {
                    final n = nodes[i];
                    final busy = busyId == n.id;
                    return InkWell(
                      onTap: () => onReveal(n.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                n.label,
                                style: text.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: busy ? null : () => onReveal(n.id),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.primary,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  busy ? '…' : 'Раскрыть',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zoom/fit controls overlay (как web Controls + ReactFlow).
class _GraphControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _GraphControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Приблизить',
            icon: const Icon(Icons.zoom_in, size: 20),
            onPressed: onZoomIn,
            visualDensity: VisualDensity.compact,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Вместить',
            icon: const Icon(Icons.fit_screen, size: 20),
            onPressed: onFit,
            visualDensity: VisualDensity.compact,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Отдалить',
            icon: const Icon(Icons.zoom_out, size: 20),
            onPressed: onZoomOut,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// MiniMap overlay — показывает обзор всего дерева с индикатором viewport.
/// Mirrors web ReactFlow MiniMap.
class _MiniMap extends StatelessWidget {
  final List<GraphLayoutNode> nodes;
  final List<GraphLayoutEdge> edges;

  const _MiniMap({
    required this.nodes,
    required this.edges,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (nodes.isEmpty) return const SizedBox.shrink();

    // Compute world bounds
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in nodes) {
      if (n.x < minX) minX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.x + n.w > maxX) maxX = n.x + n.w;
      if (n.y + n.h > maxY) maxY = n.y + n.h;
    }
    const pad = 50.0;
    minX -= pad; minY -= pad;
    maxX += pad; maxY += pad;
    final worldW = maxX - minX;
    final worldH = maxY - minY;

    const mapW = 180.0;
    const mapH = 120.0;
    final s = math.min(mapW / worldW, mapH / worldH);
    final offX = (mapW - worldW * s) / 2;
    final offY = (mapH - worldH * s) / 2;

    return Container(
      width: mapW + 8,
      height: mapH + 8,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: CustomPaint(
        size: const Size(mapW, mapH),
        painter: _MiniMapPainter(
          nodes: nodes,
          edges: edges,
          minX: minX, minY: minY,
          scale: s, offX: offX, offY: offY,
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final List<GraphLayoutNode> nodes;
  final List<GraphLayoutEdge> edges;
  final double minX, minY, scale, offX, offY;

  _MiniMapPainter({
    required this.nodes,
    required this.edges,
    required this.minX, required this.minY,
    required this.scale, required this.offX, required this.offY,
  });

  double _sx(double x) => (x - minX) * scale + offX;
  double _sy(double y) => (y - minY) * scale + offY;

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final e in edges) {
      final src = nodes.where((n) => n.id == e.source).firstOrNull;
      final tgt = nodes.where((n) => n.id == e.target).firstOrNull;
      if (src == null || tgt == null) continue;
      edgePaint.color = e.color.withValues(alpha: 0.3);
      canvas.drawLine(
        Offset(_sx(src.x + src.w / 2), _sy(src.y + src.h / 2)),
        Offset(_sx(tgt.x + tgt.w / 2), _sy(tgt.y + tgt.h / 2)),
        edgePaint,
      );
    }

    for (final n in nodes) {
      nodePaint.color = n.color;
      canvas.drawRect(
        Rect.fromLTWH(_sx(n.x), _sy(n.y), n.w * scale, n.h * scale),
        nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}