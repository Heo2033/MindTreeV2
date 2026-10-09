import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/adaptive.dart';
import 'package:mindtree_flutter/ui/nav/topic_nav.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/branch_switcher.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class TopicShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String topicId;

  /// Текущий путь внутри shell — для подсветки активного пункта раздела.
  final String location;

  const TopicShell({
    super.key,
    required this.navigationShell,
    required this.topicId,
    required this.location,
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
    final section = sectionForIndex(index);
    // Широкий экран — прежний вид: rail слева и ряд чипов под шапкой.
    // Узкий — нижняя панель разделов, чипы внутри тела экрана (у `bottom`
    // в AppBar фиксированная высота, перенос строк в нём не поместится).
    final wide = isWideLayout(context);
    final showBranches = section != null && section.hasSubNav;

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
              Flexible(
                child: Text(
                  topicName ?? widget.topicId,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (nodeCount > 0) ...[
                const SizedBox(width: 8),
                StatusBadge('$nodeCount узлов', variant: BadgeVariant.muted),
              ],
            ],
          ],
        ),
        bottom: wide && showBranches
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: BranchSwitcher(
                  section: section,
                  currentLocation: widget.location,
                ),
              )
            : null,
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) =>
                      widget.navigationShell.goBranch(i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in kTopicSectionsWithMore)
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
            )
          : Column(
              children: [
                if (showBranches)
                  BranchSwitcher(
                    section: section,
                    currentLocation: widget.location,
                  ),
                Expanded(child: widget.navigationShell),
              ],
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => widget.navigationShell.goBranch(i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final d in kTopicSectionsWithMore)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}
