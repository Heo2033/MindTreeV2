import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

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

class FocusScreen extends ConsumerStatefulWidget {
  final String topicId;

  const FocusScreen({super.key, required this.topicId});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  String? _focusNodeId;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
      ref.read(learnerStoreProvider.notifier).load(widget.topicId);
    });
  }

  List<KnowledgeNode> _readingOrder(List<KnowledgeNode> nodes) {
    final byParent = <String?, List<KnowledgeNode>>{};
    for (final n in nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    final visited = <String>{};
    final order = <KnowledgeNode>[];
    void visit(KnowledgeNode n) {
      if (!visited.add(n.id)) return;
      order.add(n);
      for (final child in byParent[n.id] ?? const <KnowledgeNode>[]) {
        visit(child);
      }
    }

    for (final root in byParent[null] ?? const <KnowledgeNode>[]) {
      visit(root);
    }
    for (final n in nodes) {
      visit(n);
    }
    return order;
  }

  List<KnowledgeNode> _pathTo(
    List<KnowledgeNode> nodes,
    KnowledgeNode target,
  ) {
    final byId = {for (final n in nodes) n.id: n};
    final path = <KnowledgeNode>[];
    var current = target;
    while (true) {
      path.add(current);
      final parentId = current.parentId;
      final parent = parentId == null ? null : byId[parentId];
      if (parent == null || parent.id == current.id) break;
      current = parent;
    }
    return path.reversed.toList();
  }

  List<KnowledgeNode> _subtree(
    List<KnowledgeNode> order,
    KnowledgeNode focus,
  ) {
    final byParent = <String?, List<KnowledgeNode>>{};
    for (final n in order) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    final result = <KnowledgeNode>[];
    void collect(KnowledgeNode n) {
      result.add(n);
      for (final child in byParent[n.id] ?? const <KnowledgeNode>[]) {
        collect(child);
      }
    }

    collect(focus);
    return result;
  }

  void _setFocus(String? id) {
    setState(() => _focusNodeId = id);
  }

  Future<void> _startSession({String? nodeId}) async {
    final session = ref.read(sessionStoreProvider.notifier);
    setState(() => _starting = true);
    await session.createSession(widget.topicId, goal: 'deep');
    await session.startStudy(nodeId ?? _focusNodeId ?? '');
    if (!mounted) return;
    setState(() => _starting = false);
    context.go('/topic/session');
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);
    final learner = ref.watch(learnerStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (graph.loading && !graph.pipeline.running) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }
    if (graph.error != null &&
        graph.nodes.isEmpty &&
        !graph.pipeline.running) {
      return ErrorBanner(message: graph.error!, onDismiss: () {});
    }

    final order = _readingOrder(graph.nodes);
    final sections = order.where((n) => n.level == 2).toList();
    final focus = _byId(graph.nodes, _focusNodeId);
    final plan = focus == null
        ? <KnowledgeNode>[]
        : [
            ..._pathTo(graph.nodes, focus),
            ..._subtree(order, focus).where((n) => n.id != focus.id),
          ];
    final focusIndex = focus == null
        ? -1
        : plan.indexWhere((n) => n.id == focus.id).clamp(0, plan.length - 1);

    final weakIds = learner.weakConcepts.toSet();
    final weakInPlan = plan.where((n) => weakIds.contains(n.id)).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              topicName: graph.topicName ?? widget.topicId,
              onBack: () => context.go('/topic/graph'),
            ),
            Expanded(
              child: focus == null
                  ? _SectionPicker(sections: sections, onPick: _setFocus)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        _Breadcrumb(path: _pathTo(graph.nodes, focus)),
                        const SizedBox(height: 8),
                        _NavBar(
                          current: focus.label,
                          onPrev: focusIndex > 0
                              ? () => _setFocus(plan[focusIndex - 1].id)
                              : null,
                          onNext: focusIndex < plan.length - 1
                              ? () => _setFocus(plan[focusIndex + 1].id)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < plan.length; i++)
                          _PlanRow(
                            index: i,
                            node: plan[i],
                            isCurrent: plan[i].id == focus.id,
                            isWeak: weakIds.contains(plan[i].id),
                            onTap: () => _setFocus(plan[i].id),
                            onStartHere: () =>
                                _startSession(nodeId: plan[i].id),
                          ),
                        const SizedBox(height: 16),
                        if (weakInPlan.isNotEmpty) ...[
                          _WeakCard(weakInPlan: weakInPlan),
                          const SizedBox(height: 16),
                        ],
                        AppButton(
                          'Запустить сессию на весь раздел',
                          icon: Icons.play_arrow,
                          variant: AppButtonVariant.primary,
                          fullWidth: true,
                          busy: _starting,
                          onPressed: _starting ? null : () => _startSession(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Сессия пройдёт по плану чтения: ${plan.length} понятий, '
                          '≈ ${plan.fold<int>(0, (sum, n) => sum + n.estimatedTimeMinutes)} минут.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  KnowledgeNode? _byId(List<KnowledgeNode> nodes, String? id) {
    if (id == null) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  final String topicName;
  final VoidCallback onBack;

  const _Header({required this.topicName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Режим фокусировки',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  topicName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPicker extends StatelessWidget {
  final List<KnowledgeNode> sections;
  final ValueChanged<String> onPick;

  const _SectionPicker({required this.sections, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.adjust, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Выберите раздел для фокусировки',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'План чтения построится по поддереву раздела: путь к нему, '
                'сам раздел и все вложенные понятия.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Сначала постройте дерево знаний. Разделы появятся после '
              'генерации структуры.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final section in sections)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                title: Text(section.label),
                subtitle: section.oneLiner.isEmpty
                    ? null
                    : Text(
                        section.oneLiner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: AppButton(
                  'Выбрать',
                  size: AppButtonSize.sm,
                  onPressed: () => onPick(section.id),
                ),
                onTap: () => onPick(section.id),
              ),
            ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final List<KnowledgeNode> path;

  const _Breadcrumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < path.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            Text(
              path[i].label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: i == path.length - 1
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: i == path.length - 1
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final String current;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _NavBar({required this.current, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'К предыдущему',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'Текущий узел',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'К следующему',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  final int index;
  final KnowledgeNode node;
  final bool isCurrent;
  final bool isWeak;
  final VoidCallback onTap;
  final VoidCallback onStartHere;

  const _PlanRow({
    required this.index,
    required this.node,
    required this.isCurrent,
    required this.isWeak,
    required this.onTap,
    required this.onStartHere,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent ? scheme.primary : scheme.outlineVariant,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isCurrent ? scheme.primary : scheme.outline,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            node.label,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isWeak) ...[
                          const SizedBox(width: 6),
                          StatusBadge(
                            'Слабое',
                            variant: BadgeVariant.warning,
                            icon: Icons.report_problem_outlined,
                          ),
                        ],
                        if (node.contentLoaded) ...[
                          const SizedBox(width: 6),
                          StatusBadge(
                            'Готово',
                            variant: BadgeVariant.success,
                            icon: Icons.check_circle_outline,
                          ),
                        ],
                      ],
                    ),
                    if (node.oneLiner.isNotEmpty)
                      Text(
                        node.oneLiner,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    if (_conceptTypeLabel
                        .containsKey(node.conceptType?.raw))
                      Text(
                        _conceptTypeLabel[node.conceptType!.raw]!,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.primary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                'Сюда',
                icon: Icons.arrow_downward,
                size: AppButtonSize.sm,
                onPressed: onStartHere,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeakCard extends StatelessWidget {
  final List<KnowledgeNode> weakInPlan;

  const _WeakCard({required this.weakInPlan});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_outlined,
                  size: 18, color: AppColors.warn),
              const SizedBox(width: 8),
              Text(
                'Слабые места в разделе',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in weakInPlan)
                Chip(
                  label: Text(n.label),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Слабое — значит SRS-повторение назначено или уровень '
            'понимания ниже 0.5.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}