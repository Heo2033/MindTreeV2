import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';
import 'package:mindtree_flutter/ui/widgets/inputs.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String topicId;
  const SessionScreen({super.key, required this.topicId});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  String _goal = 'overview';
  int _timeBudget = 30;
  bool _showPlan = true;

  static const _goalOptions = <({String value, String label})>[
    (value: 'overview', label: 'Обзор'),
    (value: 'deep', label: 'Глубокое изучение'),
    (value: 'exam', label: 'Подготовка к экзамену'),
  ];

  static const _timeOptions = <({String value, String label})>[
    (value: '15', label: '15 мин'),
    (value: '30', label: '30 мин'),
    (value: '45', label: '45 мин'),
    (value: '60', label: '60 мин'),
    (value: '90', label: '90 мин'),
  ];

  SessionNotifier get _session => ref.read(sessionStoreProvider.notifier);
  SessionState get _sessionState => ref.watch(sessionStoreProvider);
  GraphState get _graphState => ref.watch(graphStoreProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(graphStoreProvider.notifier).loadTopic(widget.topicId);
      final ss = ref.read(sessionStoreProvider);
      if (ss.session == null || ss.session!.status != SessionStatus.active) {
        ref.read(sessionStoreProvider.notifier).reset();
      } else {
        ref.read(sessionStoreProvider.notifier).loadCurrent();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ss = ref.watch(sessionStoreProvider);

    if (ss.loading && ss.session == null) {
      return const Center(child: Loader());
    }
    if (ss.error != null && ss.session == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBanner(
          message: ss.error!,
          onDismiss: () => _session.reset(),
        ),
      );
    }

    final hasActiveSession =
        ss.session != null && ss.session!.status == SessionStatus.active;

    if (!hasActiveSession) {
      return _buildStartCard();
    }
    return _buildActiveSession(ss);
  }

  Widget _buildStartCard() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Сессия \u00b7 ${_graphState.topicName ?? widget.topicId}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 20),
                  AppSelect(
                    label: 'Цель',
                    value: _goal,
                    options: _goalOptions,
                    onChanged: (v) => setState(() => _goal = v ?? _goal),
                  ),
                  const SizedBox(height: 16),
                  AppField(
                    label: 'Время',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final opt in _timeOptions)
                          ChoiceChip(
                            label: Text(opt.label),
                            selected: _timeBudget.toString() == opt.value,
                            onSelected: (_) => setState(
                              () => _timeBudget = int.parse(opt.value),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    'Начать сессию',
                    size: AppButtonSize.lg,
                    fullWidth: true,
                    icon: Icons.play_circle_outline,
                    busy: _sessionState.loading,
                    onPressed: () => _session.createSession(
                      widget.topicId,
                      goal: _goal,
                      timeBudget: _timeBudget,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSession(SessionState ss) {
    final session = ss.session!;
    final items = session.curriculum.items;
    final completedCount =
        items.where((i) => i.status == CurriculumItemStatus.completed).length;
    final totalItems = items.isEmpty ? 1 : items.length;
    final progress = completedCount / totalItems;
    final eta = ss.adaptive?.eta;

    return Column(
      children: [
        _buildSessionHeader(ss, session, completedCount, items.length, eta),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showPlan) _buildPlan(session, ss),
                const SizedBox(height: 16),
                if (ss.activity != null)
                  _buildActivityStep(ss)
                else if (ss.currentItem != null)
                  _buildStudyPrompt(ss)
                else if (progress >= 1.0)
                  _buildAllComplete(ss)
                else
                  _buildWaitingForActivity(ss),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionHeader(
    SessionState ss,
    LearningSession session,
    int completed,
    int total,
    SessionEta? eta,
  ) {
    final pct = total > 0 ? (completed / total) * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(goalLabel[session.goal] ?? session.goal),
              const SizedBox(width: 8),
              Text(
                '$completed/$total концептов',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (eta != null) ...[
                const SizedBox(width: 8),
                StatusBadge(
                  '\u23f1 ${eta.remainingMinutesMin}\u2013${eta.remainingMinutesMax} мин',
                  variant: eta.pace == PaceClass.faster
                      ? BadgeVariant.success
                      : eta.pace == PaceClass.slower
                          ? BadgeVariant.warning
                          : BadgeVariant.info,
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showPlan = !_showPlan),
                child: Text(
                  _showPlan ? 'Скрыть план' : 'Показать план',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              AppButton(
                'Завершить',
                variant: AppButtonVariant.danger,
                size: AppButtonSize.sm,
                onPressed: _finalizeSession,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgressBar(value: pct),
        ],
      ),
    );
  }

  Widget _buildPlan(LearningSession session, SessionState ss) {
    final items = session.curriculum.items;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'План сессии',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            for (final item in items) ...[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: item.status == CurriculumItemStatus.completed
                    ? const Icon(Icons.check_circle, color: AppColors.ok, size: 20)
                    : item.id == ss.currentItem?.id
                        ? Icon(Icons.play_circle,
                            color: Theme.of(context).colorScheme.primary, size: 20)
                        : Icon(Icons.radio_button_unchecked,
                            color: AppColors.textMuted(context), size: 20),
                title: Text(
                  item.label ?? item.nodeId,
                  style: TextStyle(
                    fontWeight:
                        item.id == ss.currentItem?.id ? FontWeight.w600 : FontWeight.normal,
                    decoration: item.status == CurriculumItemStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${typeLabel[item.type.raw] ?? item.type.raw} \u00b7 ${item.estimatedMinutes}\u2044м',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
                trailing: item.reason != null
                    ? SizedBox(
                        width: 120,
                        child: Text(
                          item.reason!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted(context),
                              ),
                        ),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudyPrompt(SessionState ss) {
    final item = ss.currentItem!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.label ?? item.nodeId,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              typeLabel[item.type.raw] ?? item.type.raw,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
            const SizedBox(height: 16),
            AppButton(
              'Изучать',
              fullWidth: true,
              icon: Icons.play_arrow,
              busy: ss.loading,
              onPressed: () => _session.startStudy(item.nodeId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityStep(SessionState ss) {
    final activity = ss.activity!;
    final stepIndex = ss.answeredStepView ?? activity.currentStep;
    if (stepIndex < 0 || stepIndex >= activity.steps.length) {
      return _buildActivityComplete(ss);
    }
    final step = activity.steps[stepIndex];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  activity.nodeLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                _buildBreadcrumb(activity),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              step.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (step.body != null) ...[
              FormattedText(step.body!),
              const SizedBox(height: 16),
            ],
            if (step.isAnswered && ss.answeredStepView != null)
              _buildFeedback(step)
            else ...[
              if (step.type == 'recall' && step.options != null)
                _buildRecallOptions(step, activity, stepIndex)
              else if (step.type == 'apply')
                _buildApplyInput(step, activity, stepIndex)
              else
                _buildContinueButton(step, activity, stepIndex),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(LearningActivity activity) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < activity.steps.length; i++) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activity.steps[i].isAnswered
                  ? AppColors.ok
                  : i == activity.currentStep
                      ? Theme.of(context).colorScheme.primary
                      : AppColors.textMuted(context).withValues(alpha: 0.3),
            ),
          ),
          if (i < activity.steps.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildRecallOptions(ActivityStep step, LearningActivity activity, int stepIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (step.instruction != null) ...[
          Text(step.instruction!),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < (step.options?.length ?? 0); i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _session.answerStep(stepIndex, i.toString()),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(step.options![i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildApplyInput(ActivityStep step, LearningActivity activity, int stepIndex) {
    return _ApplyInputWidget(
      instruction: step.instruction,
      placeholder: step.placeholder,
      onSubmit: (answer) => _session.answerStep(stepIndex, answer),
    );
  }

  Widget _buildContinueButton(ActivityStep step, LearningActivity activity, int stepIndex) {
    return AppButton(
      'Продолжить',
      fullWidth: true,
      onPressed: () => _session.answerStep(stepIndex, ''),
    );
  }

  Widget _buildFeedback(ActivityStep step) {
    final isCorrect = step.correct == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBadge(
          isCorrect ? 'Верно' : 'Есть ошибки',
          variant: isCorrect ? BadgeVariant.success : BadgeVariant.danger,
        ),
        if (step.feedback != null && step.feedback!.isNotEmpty) ...[
          const SizedBox(height: 12),
          FormattedText(step.feedback!),
        ],
        if (step.bestAnswer != null && !isCorrect) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Лучший ответ:',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
                const SizedBox(height: 4),
                FormattedText(step.bestAnswer!),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(
          'Далее',
          fullWidth: true,
          onPressed: () => _advanceStep(),
        ),
      ],
    );
  }

  Widget _buildActivityComplete(SessionState ss) {
    final activity = ss.activity!;
    final allStepsAnswered = activity.steps.every((s) => s.isAnswered);
    if (!allStepsAnswered) {
      return _buildActivityStep(ss);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StatusBadge('Концепт проработан', variant: BadgeVariant.success),
            const SizedBox(height: 16),
            AppButton(
              'Завершить концепт',
              fullWidth: true,
              icon: Icons.check,
              busy: ss.loading,
              onPressed: () => _completeCurrentConcept(ss),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllComplete(SessionState ss) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.celebration,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Все концепты изучены!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Формируем итоговый тест...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
            const SizedBox(height: 20),
            AppButton(
              'Перейти к итоговому тесту',
              size: AppButtonSize.lg,
              fullWidth: true,
              busy: ss.loading,
              onPressed: _finalizeSession,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForActivity(SessionState ss) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Loader(),
            const SizedBox(height: 12),
            Text(
              'Подготовка активности...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _advanceStep() {
    final activity = _sessionState.activity;
    if (activity == null) return;
    final nextStep = activity.currentStep + 1;
    if (nextStep < activity.steps.length) {
      _session.answerStep(nextStep, '');
    }
  }

  Future<void> _completeCurrentConcept(SessionState ss) async {
    final item = ss.currentItem;
    if (item == null) return;
    final stepsCorrect = ss.activity?.steps
            .where((s) => s.isAnswered && s.correct == true)
            .length ??
        0;
    final totalSteps = ss.activity?.steps.length ?? 1;
    final quality = totalSteps > 0 && stepsCorrect / totalSteps >= 0.5
        ? 'correct'
        : 'incorrect';

    await _session.completeConcept(
      item.id,
      nodeId: item.nodeId,
      quality: quality,
    );

    final updated = ref.read(sessionStoreProvider);
    final allDone = updated.currentItem == null;
    if (allDone) {
      _finalizeSession();
    }
  }

  Future<void> _finalizeSession() async {
    final assessmentId = await _session.finalize();
    if (!mounted) return;
    if (assessmentId != null) {
      context.go('/topic/final');
    }
  }
}

class _ApplyInputWidget extends StatefulWidget {
  final String? instruction;
  final String? placeholder;
  final ValueChanged<String> onSubmit;

  const _ApplyInputWidget({
    this.instruction,
    this.placeholder,
    required this.onSubmit,
  });

  @override
  State<_ApplyInputWidget> createState() => _ApplyInputWidgetState();
}

class _ApplyInputWidgetState extends State<_ApplyInputWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.instruction != null) ...[
          Text(widget.instruction!),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: widget.placeholder ?? 'Введите ответ...',
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          'Проверить',
          fullWidth: true,
          onPressed: () {
            final answer = _controller.text.trim();
            if (answer.isNotEmpty) widget.onSubmit(answer);
          },
        ),
      ],
    );
  }
}
