import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BadgeVariant { info, success, warning, muted, danger }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  const StatusBadge(
    this.label, {
    super.key,
    this.variant = BadgeVariant.info,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (variant) {
      BadgeVariant.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
      BadgeVariant.success => (AppColors.ok.withValues(alpha: 0.14), AppColors.success(context)),
      BadgeVariant.warning => (AppColors.warn.withValues(alpha: 0.16), AppColors.warning(context)),
      BadgeVariant.muted => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      BadgeVariant.danger => (AppColors.danger.withValues(alpha: 0.12), AppColors.error(context)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            // В узких контейнерах (Flexible/Expanded) подпись обрезается
            // многоточием, а не вылезает за бейдж.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}