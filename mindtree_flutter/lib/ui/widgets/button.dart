import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'spinner.dart';

enum AppButtonVariant { primary, secondary, danger }
enum AppButtonSize { sm, lg }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool busy;
  final bool fullWidth;
  final IconData? icon;

  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.sm,
    this.busy = false,
    this.fullWidth = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLg = size == AppButtonSize.lg;
    final (Color bg, Color fg, bool outline) = switch (variant) {
      AppButtonVariant.primary => (scheme.primary, scheme.onPrimary, false),
      AppButtonVariant.secondary => (
          scheme.surfaceContainerHighest,
          scheme.onSurface,
          true,
        ),
      AppButtonVariant.danger => (AppColors.danger.withValues(alpha: 0.12), AppColors.error(context), false),
    };

    final child = busy
        ? Loader(size: LoaderSize.sm, color: fg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: isLg ? 18 : 14, color: fg),
                const SizedBox(width: 6),
              ],
              // Flexible: без него Text в Row получает неограниченную ширину,
              // не переносится и на телефоне вылезает за край кнопки
              // (RenderFlex overflow на 79/50 px у тулбара и панели графа).
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: outline ? null : bg,
          foregroundColor: fg,
          padding: EdgeInsets.symmetric(
            horizontal: isLg ? 20 : 14,
            vertical: isLg ? 14 : 10,
          ),
        ),
        child: fullWidth
            ? Center(child: child)
            : child,
      ),
    );
  }
}