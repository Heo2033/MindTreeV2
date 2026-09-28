import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/ui/nav/topic_nav.dart';

/// Ряд переключения между пунктами одного раздела темы.
///
/// Раздел вынесен из топа в боковую навигацию, поэтому его соседей нужно
/// держать в один клик от любого экрана.
class BranchSwitcher extends StatelessWidget {
  final TopicSectionDef section;
  final String currentLocation;

  const BranchSwitcher({
    super.key,
    required this.section,
    required this.currentLocation,
  });

  /// Пути разделов уникальны и не являются суффиксами друг друга,
  /// поэтому сверка по хвосту работает и для полного URI, и для
  /// location конкретной ветки shell.
  bool _isActive(TopicNavItem item) {
    final loc = currentLocation.split('?').first;
    return loc == item.path || loc.endsWith(item.path);
  }

  @override
  Widget build(BuildContext context) {
    if (!section.hasSubNav) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final item in section.items) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: _isActive(item),
                onSelected: (_) => context.go(item.path),
                avatar: Icon(
                  _isActive(item) ? item.selectedIcon : item.icon,
                  size: 18,
                ),
                label: Text(item.label),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight:
                      _isActive(item) ? FontWeight.w700 : FontWeight.w500,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
