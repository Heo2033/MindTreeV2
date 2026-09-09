import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class TopicShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String topicId;

  const TopicShell({
    super.key,
    required this.navigationShell,
    required this.topicId,
  });

  @override
  ConsumerState<TopicShell> createState() => _TopicShellState();
}

class _TopicShellState extends ConsumerState<TopicShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
    });
  }

  static const _destinations = <({IconData icon, IconData selectedIcon, String label})>[
    (icon: Icons.account_tree_outlined, selectedIcon: Icons.account_tree, label: 'Граф'),
    (icon: Icons.center_focus_weak_outlined, selectedIcon: Icons.center_focus_strong, label: 'Фокус'),
    (icon: Icons.play_circle_outline, selectedIcon: Icons.play_circle, label: 'Сессия'),
    (icon: Icons.quiz_outlined, selectedIcon: Icons.quiz, label: 'Тест'),
    (icon: Icons.support_agent, selectedIcon: Icons.support_agent, label: 'Репетитор'),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Модель'),
    (icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check, label: 'Диагностика'),
    (icon: Icons.flag_outlined, selectedIcon: Icons.flag, label: 'Путь'),
    (icon: Icons.replay, selectedIcon: Icons.replay, label: 'Повторение'),
    (icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'Метрики'),
    (icon: Icons.task_alt, selectedIcon: Icons.task_alt, label: 'Итоговый тест'),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.topicId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('MindTree')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Тема не выбрана',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('К списку тем'),
              ),
            ],
          ),
        ),
      );
    }
    final index = widget.navigationShell.currentIndex;
    final graphState = ref.watch(graphStoreProvider);
    final topicName = graphState.topicName;
    final nodeCount = graphState.nodes.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () => context.go('/'),
              child: Text(
                '\u2190 Темы',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            if (graphState.loading && topicName == null)
              const Loader(size: LoaderSize.sm)
            else ...[
              Text(topicName ?? widget.topicId),
              if (nodeCount > 0) ...[
                const SizedBox(width: 8),
                StatusBadge('$nodeCount узлов', variant: BadgeVariant.muted),
              ],
            ],
          ],
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => widget.navigationShell.goBranch(i),
            labelType: NavigationRailLabelType.all,
            scrollable: true,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }
}
