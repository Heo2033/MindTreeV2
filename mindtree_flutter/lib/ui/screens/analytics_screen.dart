import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  final String topicId;
  const AnalyticsScreen({super.key, required this.topicId});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  TopicMetrics? _metrics;
  List<LearningSession> _sessions = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final analytics = ref.read(analyticsServiceProvider);
      final repo = ref.read(repositoryProvider).valueOrNull;
      final metrics = await analytics.topicMetrics(widget.topicId);
      final sessions = repo != null
          ? await repo.listSessionsForTopic(widget.topicId)
          : <LearningSession>[];
      if (mounted) {
        setState(() {
          _metrics = metrics;
          _sessions = sessions;
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

  @override
  Widget build(BuildContext context) {
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
                'Аналитика',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              // Flexible: длинное название темы обрезается многоточием,
              // а не выталкивает строку за край экрана.
              Flexible(
                child: StatusBadge(
                  graph.topicName ?? widget.topicId,
                  variant: BadgeVariant.muted,
                ),
              ),
              const Spacer(),
              if (_loading) const Loader(size: LoaderSize.sm),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _metrics == null) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorBanner(message: _error!),
            const SizedBox(height: 12),
            AppButton('Повторить', onPressed: _load),
          ],
        ),
      );
    }
    if (_metrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights,
                  size: 48, color: AppColors.textMuted(context)),
              const SizedBox(height: 12),
              Text(
                'Нет данных для аналитики',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Начните сессию обучения, чтобы увидеть метрики.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return _buildMetrics(_metrics!);
  }

  Widget _buildMetrics(TopicMetrics m) {
    final levelText = levelLabel[m.currentLevel.raw] ?? m.currentLevel.raw;
    final targetText = levelLabel[m.targetLevel.raw] ?? m.targetLevel.raw;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCards(m),
          const SizedBox(height: 16),
          _buildLearningGainCard(m),
          const SizedBox(height: 16),
          _buildLevelCard(m, levelText, targetText),
          const SizedBox(height: 16),
          _buildMasteryDistribution(m),
          const SizedBox(height: 16),
          if (_sessions.isNotEmpty) _buildSessionsList(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(TopicMetrics m) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Понятий',
            value: '${m.conceptCount}',
            icon: Icons.category_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Время',
            value: '${m.studyMinutes} мин',
            icon: Icons.timer_outlined,
          ),
        ),
      ],
    );
  }

  /// Ключевая метрика продукта — Learning Gain / Time: сколько уровней
  /// понимания прибавилось с момента старта и сколько в среднем это стоит
  /// по времени.
  ///
  /// Период — те же `studyMinutes` экрана (сумма достоверных замеров времени
  /// занятий, неправдоподобные записи в `AnalyticsService` отфильтрованы):
  /// новых источников данных карточка не заводит.
  Widget _buildLearningGainCard(TopicMetrics m) {
    final gain = m.learningGain.round();
    final hasTime = m.studyMinutes > 0;
    final gainPositive = gain > 0;

    final String value;
    final String caption;
    if (!gainPositive) {
      value = 'Пока без прироста';
      caption = !hasTime
          ? 'Нет замеров времени занятий — метрика появится после занятий.'
          : 'За ${m.studyMinutes} мин занятий уровень понимания не вырос.';
    } else {
      value = '+${_levelsPlural(gain)} понимания';
      if (!hasTime) {
        caption = 'Нет замеров времени занятий — темп посчитать нельзя.';
      } else {
        // learningGainPerMinute посчитан как «уровней за час»
        // (gain / часы занятий), минут на уровень — обратная величина.
        final perHour = m.learningGainPerMinute.toStringAsFixed(1).replaceAll('.', ',');
        // Потолок снизу — «~0 мин на уровень» на крошечной выборке
        // смысла не имеет.
        final minutesPerLevel =
            (m.studyMinutes / gain).round().clamp(1, 100000).toInt();
        caption = 'За ${m.studyMinutes} мин занятий — ~$minutesPerLevel мин '
            'на уровень ($perHour уровня в час).';
      }
    }

    final valueColor = gainPositive
        ? Theme.of(context).colorScheme.primary
        : AppColors.textMuted(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Прирост понимания и время',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                // Период метрики — те же данные, что в карточке «Время».
                StatusBadge('${m.studyMinutes} мин', variant: BadgeVariant.muted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.trending_up, size: 20, color: valueColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: valueColor,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCard(TopicMetrics m, String levelText, String targetText) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Прогресс уровня',
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
              value: m.meanMastery * 100,
              label: 'Среднее освоение: ${(m.meanMastery * 100).round()}%',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Цель: $targetText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
                const Spacer(),
                if (m.masteryReached)
                  const StatusBadge('Достигнута', variant: BadgeVariant.success)
                else
                  const StatusBadge('В пути', variant: BadgeVariant.info),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasteryDistribution(TopicMetrics m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Метрики',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'Запоминание',
              value: m.immediateRecall,
            ),
            _MetricRow(
              label: 'Отложенное',
              value: m.delayedRecall,
            ),
            _MetricRow(
              label: 'Применение',
              value: m.applicationAccuracy,
            ),
            _MetricRow(
              label: 'Перенос',
              value: m.transferAccuracy,
            ),
            const Divider(height: 20),
            _MetricRow(
              label: 'Завершение сессий',
              value: m.sessionCompletion,
            ),
            _MetricRow(
              label: 'Прогресс вех',
              value: m.milestoneProgression,
            ),
            if (m.timeToTargetMinutes != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Время до цели: ~${m.timeToTargetMinutes} мин',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsList() {
    final sorted = List<LearningSession>.from(_sessions)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сессии',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            for (final s in sorted.take(10))
              _buildSessionTile(s),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTile(LearningSession s) {
    final statusVariant = s.status == SessionStatus.completed
        ? BadgeVariant.success
        : s.status == SessionStatus.active
            ? BadgeVariant.info
            : BadgeVariant.muted;
    final statusText = s.status == SessionStatus.completed
        ? 'Завершена'
        : s.status == SessionStatus.active
            ? 'Активна'
            : 'Брошена';
    final total = s.curriculum.items.length;
    final completed = s.curriculum.items
        .where((i) => i.status == CurriculumItemStatus.completed)
        .length;

    final dateStr = s.startedAt.isNotEmpty
        ? (DateTime.tryParse(s.startedAt)
                ?.toLocal()
                .toString()
                .substring(0, 16)
                .replaceAll('T', ' ') ??
            '—')
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  '$completed/$total концептов · ${goalLabel[s.goal] ?? s.goal}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
              ],
            ),
          ),
          StatusBadge(statusText, variant: statusVariant),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.textMuted(context)),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Русская форма «уровень / уровня / уровней» для метрики прироста.
String _levelsPlural(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final String word;
  if (mod10 == 1 && mod100 != 11) {
    word = 'уровень';
  } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    word = 'уровня';
  } else {
    word = 'уровней';
  }
  return '$n $word';
}

class _MetricRow extends StatelessWidget {
  final String label;
  final double value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
