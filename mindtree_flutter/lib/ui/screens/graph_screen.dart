import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/graph/graph_canvas.dart';
import 'package:mindtree_flutter/ui/graph/graph_layout.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

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
  final Set<String> _expanding = {};
  final Set<String> _generating = {};

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(graphStoreProvider);
    final notifier = ref.read(graphStoreProvider.notifier);

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

    return Column(
      children: [
        _Toolbar(
          topicName: state.topicName ?? widget.topicId,
          levelLabel: levelLabel[state.topic?.targetLevel.raw] ?? 'Понятие',
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
                nodes: layout.nodes,
                edges: layout.edges,
                selectedNodeId: _selectedId,
                busyNodeIds: _expanding,
                showLegend: _showLegend,
                onNodeTap: _onNodeTap,
                onNodeExpand: _onExpand,
                onNodeDeepen: _onExpand,
                onNodeLongPress: (id) {
                  context.go('/topic/focus');
                },
              ),
              if (state.pipeline.running)
                _PipelineOverlay(
                  phase: state.pipeline.phase,
                  message: state.pipeline.message,
                  stats: state.pipeline.stats,
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
                context.go('/topic/focus'),
            onClose: () => setState(() => _selectedId = null),
          ),
        if (selected != null) const SizedBox(height: 8),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final String topicName;
  final String levelLabel;
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
    required this.levelLabel,
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
              StatusBadge(levelLabel, icon: Icons.school_outlined),
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
                  'Сгенерировать контент',
                  icon: Icons.auto_awesome,
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.sm,
                  busy: generating,
                  onPressed: onGenerate,
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