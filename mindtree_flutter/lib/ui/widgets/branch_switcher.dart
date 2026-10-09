import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/ui/adaptive.dart';
import 'package:mindtree_flutter/ui/nav/topic_nav.dart';

/// Ряд переключения между пунктами одного раздела темы.
///
/// Раздел вынесен из топа в боковую навигацию, поэтому его соседей нужно
/// держать в один клик от любого экрана.
///
/// На широком экране — один горизонтальный ряд (со скроллом на случай
/// узкого окна); на узком — чипы переносятся на новые строки, без
/// горизонтального скролла и с тач-таргетом не меньше 44.
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

  Widget _chip(BuildContext context, TopicNavItem item, {required bool wide}) {
    final theme = Theme.of(context);
    final active = _isActive(item);
    return ChoiceChip(
      selected: active,
      onSelected: (_) => context.go(item.path),
      avatar: Icon(
        active ? item.selectedIcon : item.icon,
        size: 18,
      ),
      label: Text(
        item.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      ),
      // Узкий экран: не ужимаем чип и добавляем вертикальный отступ,
      // чтобы высота тач-таргета была не меньше 44.
      visualDensity: wide ? VisualDensity.compact : VisualDensity.standard,
      labelPadding: wide
          ? null
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!section.hasSubNav) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideBreakpoint;
        if (wide) {
          // Один ряд со скроллом — прежнее поведение десктопа.
          return SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final item in section.items)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _chip(context, item, wide: true),
                  ),
              ],
            ),
          );
        }
        // Узкий экран: перенос в несколько строк, без горизонтального скролла.
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in section.items)
                _chip(context, item, wide: false),
            ],
          ),
        );
      },
    );
  }
}
