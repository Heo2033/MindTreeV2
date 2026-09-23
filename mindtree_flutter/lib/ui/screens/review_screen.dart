import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final String topicId;

  const ReviewScreen({super.key, required this.topicId});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<_ReviewCard> _cards = [];
  int _index = 0;
  bool _showBack = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scheduler = ref.read(reviewSchedulerProvider);
      final graph = ref.read(graphStoreProvider);
      if (graph.topicId != widget.topicId) {
        await ref.read(graphStoreProvider.notifier).loadTopic(widget.topicId);
      }
      final nodes = ref.read(graphStoreProvider).nodes;
      final nodeMap = {for (final n in nodes) n.id: n};
      final upcoming = await scheduler.upcomingReviews(widget.topicId, limit: 50);

      final cards = <_ReviewCard>[];
      for (final entry in upcoming) {
        final node = nodeMap[entry.nodeId];
        if (node == null) continue;
        cards.add(_ReviewCard(
          nodeId: node.id,
          label: node.label,
          oneLiner: node.oneLiner,
          details: node.details,
          dueAt: entry.dueAt,
        ));
      }

      if (mounted) {
        setState(() {
          _cards = cards;
          _index = 0;
          _showBack = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  bool get _hasMore => _index < _cards.length;

  _ReviewCard? get _current => _hasMore ? _cards[_index] : null;

  Future<void> _answer(String quality) async {
    final card = _current;
    if (card == null || _busy) return;
    setState(() => _busy = true);
    try {
      final scheduler = ref.read(reviewSchedulerProvider);
      await scheduler.onAnswered(widget.topicId, card.nodeId, quality);
    } catch (e) {
      // Не «сжигаем» карточку и не теряем ответ: повторение остаётся в списке,
      // пользователь видит ошибку и может повторить оценку ещё раз.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось сохранить ответ: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _showBack = false;
      _index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            AppButton('Повторить', onPressed: _load),
          ],
        ),
      );
    }

    if (_cards.isEmpty) {
      return _EmptyView(
        topicName: graph.topicName ?? widget.topicId,
        onGoToGraph: () => context.go('/topic/graph'),
        onGoBack: () => context.go('/topic/graph'),
      );
    }

    final total = _cards.length;
    final done = math.min(_index, total);
    final pct = total > 0 ? (done / total * 100).round() : 0;

    return SafeArea(
      child: Column(
        children: [
          _ReviewHeader(
            topicName: graph.topicName ?? widget.topicId,
            onBack: () => context.go('/topic/graph'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: ProgressBar(
              value: pct.toDouble(),
              label: '$done / $total',
            ),
          ),
          Expanded(
            child: _hasMore
                ? _Flashcard(
                    card: _current!,
                    showBack: _showBack,
                    onFlip: () => setState(() => _showBack = !_showBack),
                  )
                : _DoneView(
                    topicName: graph.topicName ?? widget.topicId,
                    total: total,
                    onGoToGraph: () =>
                        context.go('/topic/graph'),
                  ),
          ),
          if (_hasMore)
            _AnswerBar(
              busy: _busy,
              onAgain: () => _answer('again'),
              onCorrect: () => _answer('correct'),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ReviewCard {
  final String nodeId;
  final String label;
  final String oneLiner;
  final String details;
  final String? dueAt;

  const _ReviewCard({
    required this.nodeId,
    required this.label,
    required this.oneLiner,
    required this.details,
    this.dueAt,
  });
}

class _ReviewHeader extends StatelessWidget {
  final String topicName;
  final VoidCallback onBack;

  const _ReviewHeader({required this.topicName, required this.onBack});

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
                  'Интервальное повторение',
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

class _Flashcard extends StatelessWidget {
  final _ReviewCard card;
  final bool showBack;
  final VoidCallback onFlip;

  const _Flashcard({
    required this.card,
    required this.showBack,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFlip,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: showBack ? _back(context) : _front(context),
      ),
    );
  }

  Widget _front(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('front'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.question_mark_rounded, size: 40, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            card.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (card.oneLiner.isNotEmpty)
            Text(
              card.oneLiner,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 16),
          Text(
            'Нажмите, чтобы увидеть ответ',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _back(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('back'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lightbulb_outline, size: 22, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                card.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (card.details.isNotEmpty)
            Text(
              card.details,
              textAlign: TextAlign.center,
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Text(
              'Подробности ещё не сгенерированы',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          const SizedBox(height: 16),
          Text(
            'Оцените ответ кнопками ниже',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _AnswerBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onAgain;
  final VoidCallback onCorrect;

  const _AnswerBar({
    required this.busy,
    required this.onAgain,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              'Повторить снова',
              icon: Icons.refresh,
              variant: AppButtonVariant.danger,
              busy: busy,
              onPressed: busy ? null : onAgain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppButton(
              'Знаю',
              icon: Icons.check,
              variant: AppButtonVariant.primary,
              busy: busy,
              onPressed: busy ? null : onCorrect,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final String topicName;
  final int total;
  final VoidCallback onGoToGraph;

  const _DoneView({
    required this.topicName,
    required this.total,
    required this.onGoToGraph,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.ok.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline, size: 56, color: AppColors.ok),
            ),
            const SizedBox(height: 20),
            Text(
              'Повторение завершено!',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Вы повторили $total поняти${_noun(total)}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            AppButton(
              'Вернуться к графу',
              icon: Icons.account_tree_outlined,
              onPressed: onGoToGraph,
            ),
          ],
        ),
      ),
    );
  }

  String _noun(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'е';
    if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return 'я';
    return 'й';
  }
}

class _EmptyView extends StatelessWidget {
  final String topicName;
  final VoidCallback onGoToGraph;
  final VoidCallback onGoBack;

  const _EmptyView({
    required this.topicName,
    required this.onGoToGraph,
    required this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: AppColors.ok),
            const SizedBox(height: 20),
            Text(
              'Повторять пока нечего',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Все понятия темы «$topicName» ещё не готовы или ещё не '
              'наступило время повторения.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            AppButton(
              'Вернуться к графу',
              icon: Icons.account_tree_outlined,
              onPressed: onGoToGraph,
            ),
            const SizedBox(height: 8),
            AppButton(
              'Назад',
              icon: Icons.arrow_back,
              variant: AppButtonVariant.secondary,
              onPressed: onGoBack,
            ),
          ],
        ),
      ),
    );
  }
}