import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class LearnerModelScreen extends ConsumerStatefulWidget {
  final String topicId;
  const LearnerModelScreen({super.key, required this.topicId});

  @override
  ConsumerState<LearnerModelScreen> createState() => _LearnerModelScreenState();
}

class _LearnerModelScreenState extends ConsumerState<LearnerModelScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(learnerStoreProvider.notifier).load(widget.topicId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ls = ref.watch(learnerStoreProvider);
    final graph = ref.watch(graphStoreProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              Text(
                'Профиль обучающегося',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                graph.topicName ?? widget.topicId,
                variant: BadgeVariant.muted,
              ),
              const Spacer(),
              if (ls.loading) const Loader(size: LoaderSize.sm),
            ],
          ),
        ),
        Expanded(child: _buildBody(ls)),
      ],
    );
  }

  Widget _buildBody(LearnerState ls) {
    if (ls.loading && ls.model == null) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }
    if (ls.error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBanner(
          message: ls.error!,
          onDismiss: () =>
              ref.read(learnerStoreProvider.notifier).load(widget.topicId),
        ),
      );
    }

    final model = ls.model;
    final masteryPct = model != null
        ? (model.overallLevel.index / 5 * 100).round()
        : 0;
    final levelText =
        levelLabel[model?.overallLevel.raw ?? 'awareness'] ?? 'Ознакомление';
    final targetText = ref.read(graphStoreProvider).topic?.targetLevel != null
        ? levelLabel[ref.read(graphStoreProvider).topic!.targetLevel.raw] ?? ''
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMasteryCard(masteryPct, levelText, targetText),
          const SizedBox(height: 16),
          if (ls.profiles.isNotEmpty) _buildProfilesSection(ls),
          if (ls.weakConcepts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildWeakSection(ls),
          ],
          if (ls.dueConcepts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDueSection(ls),
          ],
          if (ls.profiles.isEmpty && !ls.loading)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_outlined,
                        size: 48, color: AppColors.textMuted(context)),
                    const SizedBox(height: 12),
                    Text(
                      'Нет данных об обучении',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textMuted(context),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Начните сессию, чтобы начать отслеживать прогресс.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted(context),
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMasteryCard(int masteryPct, String levelText, String targetText) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Общий уровень',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                StatusBadge(levelText),
              ],
            ),
            const SizedBox(height: 12),
            ProgressBar(
              value: masteryPct.toDouble(),
              label: 'Прогресс к мастерству',
            ),
            if (targetText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Цель: $targetText',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfilesSection(LearnerState ls) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Профили концептов',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            for (final p in ls.profiles) ...[
              _buildProfileTile(p),
              if (p != ls.profiles.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(dynamic p) {
    final masteryPct = (p.masteryScore * 100).round();
    final statusVariant = masteryPct >= 80
        ? BadgeVariant.success
        : masteryPct >= 50
            ? BadgeVariant.info
            : BadgeVariant.warning;
    final statusText = masteryPct >= 80
        ? 'Освоено'
        : masteryPct >= 50
            ? 'В процессе'
            : 'Начальный';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                p.nodeId,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            StatusBadge(statusText, variant: statusVariant),
          ],
        ),
        const SizedBox(height: 6),
        ProgressBar(
          value: masteryPct.toDouble(),
          label: '$masteryPct%',
        ),
        if (p.lastReviewedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Повторено: ${p.lastReviewedAt}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildWeakSection(LearnerState ls) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 18, color: AppColors.warning(context)),
                const SizedBox(width: 6),
                Text(
                  'Слабые понятия',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final c in ls.weakConcepts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $c',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueSection(LearnerState ls) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Пора повторить',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final c in ls.dueConcepts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $c',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            AppButton(
              'Перейти к повторению',
              size: AppButtonSize.sm,
              icon: Icons.replay,
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  context.go('/topic/review'),
            ),
          ],
        ),
      ),
    );
  }
}
