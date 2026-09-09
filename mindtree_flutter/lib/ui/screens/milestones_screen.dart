import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class MilestonesScreen extends ConsumerStatefulWidget {
  final String topicId;

  const MilestonesScreen({super.key, required this.topicId});

  @override
  ConsumerState<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends ConsumerState<MilestonesScreen> {
  LearningJourney? _journey;
  bool _loading = true;
  bool _generating = false;
  bool _starting = false;
  String? _error;

  MindtreeRepository? get _repo =>
      ref.read(repositoryProvider).valueOrNull;

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
      final repo = _repo;
      if (repo == null) {
        if (mounted) setState(() { _loading = false; _error = 'Репозиторий недоступен'; });
        return;
      }
      final journey = await repo.getJourneyForTopic(widget.topicId);
      if (mounted) {
        setState(() {
          _journey = journey;
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

  String _shortId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'jr_${ts.substring(ts.length - 8)}';
  }

  Future<void> _generate() async {
    final repo = _repo;
    if (repo == null) return;
    final engine = ref.read(milestoneEngineProvider);
    setState(() => _generating = true);
    try {
      String journeyId = _journey?.id ?? '';
      if (journeyId.isEmpty) {
        final created = await repo.createJourney(_shortId(), widget.topicId);
        journeyId = created.id;
      }
      await engine.generate(journeyId, widget.topicId);
      final updated = await repo.getJourneyForTopic(widget.topicId);
      if (mounted) {
        setState(() {
          _journey = updated;
          _generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _generating = false;
        });
      }
    }
  }

  Future<void> _markStatus(LearningMilestone m, MilestoneStatus status) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final updated = LearningMilestone(
        id: m.id,
        level: m.level,
        title: m.title,
        description: m.description,
        capabilities: m.capabilities,
        estimatedHours: m.estimatedHours,
        status: status,
        alternativePaths: m.alternativePaths,
      );
      await repo.updateMilestone(updated);
      final journey = await repo.getJourneyForTopic(widget.topicId);
      if (mounted) setState(() => _journey = journey);
    } catch (_) {}
  }

  Future<void> _startSession(String? milestoneId) async {
    final session = ref.read(sessionStoreProvider.notifier);
    setState(() => _starting = true);
    await session.createSession(
      widget.topicId,
      goal: 'milestone',
      milestoneId: milestoneId,
    );
    await session.startStudy('');
    if (!mounted) return;
    setState(() => _starting = false);
    context.go('/topic/session');
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ErrorBanner(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            AppButton('Повторить', onPressed: _load),
          ],
        ),
      );
    }

    final milestones = _journey?.milestones ?? [];
    final activeMilestone = milestones.where((m) => m.status == MilestoneStatus.active).firstOrNull;
    final completedCount =
        milestones.where((m) => m.status == MilestoneStatus.completed).length;
    final progressPct =
        milestones.isEmpty ? 0.0 : completedCount / milestones.length * 100;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              topicName: graph.topicName ?? widget.topicId,
              onBack: () => context.go('/topic/graph'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  if (milestones.isEmpty)
                    _EmptyState(
                      generating: _generating,
                      onGenerate: _generate,
                    )
                  else ...[
                    _ProgressCard(
                      activeTitle: activeMilestone?.title ?? 'Нет активной вехи',
                      completedCount: completedCount,
                      total: milestones.length,
                      progressPct: progressPct,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Вехи',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final m in milestones)
                      _MilestoneRow(
                        milestone: m,
                        isActive: m.status == MilestoneStatus.active,
                        onMarkActive: () =>
                            _markStatus(m, MilestoneStatus.active),
                        onMarkCompleted: () =>
                            _markStatus(m, MilestoneStatus.completed),
                        onStartSession: () => _startSession(m.id),
                        starting: _starting,
                      ),
                    const SizedBox(height: 16),
                    AppButton(
                      'Создать новые вехи',
                      icon: Icons.auto_awesome,
                      variant: AppButtonVariant.secondary,
                      fullWidth: true,
                      busy: _generating,
                      onPressed: _generating ? null : _generate,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String topicName;
  final VoidCallback onBack;

  const _Header({required this.topicName, required this.onBack});

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
                  'Контрольные точки',
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

class _EmptyState extends StatelessWidget {
  final bool generating;
  final VoidCallback onGenerate;

  const _EmptyState({required this.generating, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Вехи ещё не созданы',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Контрольные точки помогают отслеживать прогресс: от первых '
            'шагов до уверенного владения темой.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          AppButton(
            'Сгенерировать вехи',
            icon: Icons.auto_awesome,
            variant: AppButtonVariant.primary,
            busy: generating,
            onPressed: generating ? null : onGenerate,
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final String activeTitle;
  final int completedCount;
  final int total;
  final double progressPct;

  const _ProgressCard({
    required this.activeTitle,
    required this.completedCount,
    required this.total,
    required this.progressPct,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Активная веха',
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            activeTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ProgressBar(
            value: progressPct,
            label: '$completedCount / $total завершено',
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final LearningMilestone milestone;
  final bool isActive;
  final VoidCallback onMarkActive;
  final VoidCallback onMarkCompleted;
  final VoidCallback onStartSession;
  final bool starting;

  const _MilestoneRow({
    required this.milestone,
    required this.isActive,
    required this.onMarkActive,
    required this.onMarkCompleted,
    required this.onStartSession,
    required this.starting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusLabel = milestone.status == MilestoneStatus.completed
        ? 'Завершено'
        : milestone.status == MilestoneStatus.active
            ? 'Активно'
            : 'Ожидает';
    final statusVariant = milestone.status == MilestoneStatus.completed
        ? BadgeVariant.success
        : milestone.status == MilestoneStatus.active
            ? BadgeVariant.info
            : BadgeVariant.muted;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Уровень: ${levelLabel[milestone.level.raw] ?? milestone.level.raw}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
                ),
                StatusBadge(statusLabel, variant: statusVariant, icon: Icons.flag),
              ],
            ),
            if (milestone.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                milestone.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (milestone.capabilities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Вы сможете:',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in milestone.capabilities)
                    Chip(
                      label: Text(cap),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '≈ ${milestone.estimatedHours.toStringAsFixed(1)} часов',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  'Запустить сессию',
                  icon: Icons.play_arrow,
                  size: AppButtonSize.sm,
                  busy: starting && isActive,
                  onPressed: (starting && isActive) ? null : onStartSession,
                ),
                if (milestone.status == MilestoneStatus.notStarted)
                  AppButton(
                    'Сделать активной',
                    icon: Icons.flag,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: onMarkActive,
                  ),
                if (milestone.status == MilestoneStatus.active)
                  AppButton(
                    'Завершить',
                    icon: Icons.check_circle_outline,
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.sm,
                    onPressed: onMarkCompleted,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}