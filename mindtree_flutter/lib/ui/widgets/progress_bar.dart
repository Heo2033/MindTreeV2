import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProgressBar extends StatelessWidget {
  final double value;
  final String? label;

  const ProgressBar({
    super.key,
    required this.value,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    final pct = clamped / 100.0;
    final color = pct >= 0.9
        ? AppColors.success(context)
        : pct >= 0.6
            ? Theme.of(context).colorScheme.primary
            : pct >= 0.3
                ? AppColors.warning(context)
                : AppColors.error(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                '${clamped.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: math.min(1.0, pct),
            minHeight: 8,
            color: color,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}