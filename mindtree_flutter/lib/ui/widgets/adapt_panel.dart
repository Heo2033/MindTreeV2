import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import '../theme/app_theme.dart';
import 'badge.dart';
import 'button.dart';
import 'formatted_text.dart';
import 'spinner.dart';

/// Выбор остатка времени для пересборки плана: null — «по остатку бюджета».
class _ReplanChoice {
  final int? minutes;
  const _ReplanChoice(this.minutes);
}

/// Текстовые результаты Adapt (упрощение, глубина, база) показываются на
/// месте понятия — в карточке шага, а не под кнопками панели: результат
/// должен стоять рядом с текстом, который меняет. Статусные (skip/replan)
/// остаются в панели — там только бейджи и обновлённый план.
bool isInlineAdaptResult(AdaptResult result) =>
    result is AdaptSimplifyResult ||
    result is AdaptDepthResult ||
    result is AdaptPrerequisiteResult;

/// Фаза чтения объяснения: что можно адаптировать и где показывается
/// результат. Определяется по текущему шагу активности либо по состоянию
/// «до активности» (`activity == null`) — см. [adaptPhaseOf].
enum AdaptPhase {
  /// Понятие выбрано, изучение ещё не начато: контент генерируется
  /// just-in-time по «Изучать» (§61), поэтому упрощать нечего — только
  /// skip/replan, инлайн-результата нет.
  beforeActivity,

  /// Шаг «Объяснение»: полный набор, результат подменяет тело шага.
  explain,

  /// Шаг «Пример» (и карточка «Концепт проработан»): текст, который меняет
  /// панель, здесь менять нечего — только skip/replan, текстовых результатов
  /// нет.
  example,

  /// Шаг с вопросом: панель скрыта целиком, чтобы кнопки не подмешивали
  /// объяснения в тест.
  question,
}

/// Фаза текущего состояния сессии — от неё зависит набор кнопок панели и
/// место показа текстового результата (см. session_screen).
AdaptPhase adaptPhaseOf(SessionState ss) {
  final activity = ss.activity;
  if (activity == null) return AdaptPhase.beforeActivity;
  final stepIndex = ss.answeredStepView ?? activity.currentStep;
  if (stepIndex < 0 || stepIndex >= activity.steps.length) {
    // Все шаги пройдены: карточка «Концепт проработан», текста больше нет.
    return AdaptPhase.example;
  }
  return adaptPhaseOfStep(activity.steps[stepIndex]);
}

/// Фаза одного шага активности.
AdaptPhase adaptPhaseOfStep(ActivityStep step) {
  if (step.type == 'recall' ||
      step.type == 'apply' ||
      (step.options?.isNotEmpty ?? false) ||
      step.placeholder != null) {
    return AdaptPhase.question;
  }
  return step.type == 'example' ? AdaptPhase.example : AdaptPhase.explain;
}

/// Панель действий Adapt (§80) над текущим понятием сессии.
///
/// Пять действий в одном компактном блоке там, где пользователь работает
/// с понятием: «объясни проще», «из чего складывается», «знаю, пропустить»,
/// глубина подачи и пересборка плана под остаток времени. Одно нажатие —
/// одно действие; статусные результаты (skip/replan) показываются карточкой
/// прямо здесь, текстовые — на месте понятия (см. [AdaptResultBody]).
///
/// Набор кнопок и сам факт показа зависят от [AdaptPhase]: на шаге с вопросом
/// панель скрыта целиком, на «Примере» остаются только skip/replan.
///
/// Панель намеренно не несёт логики: всё идёт через [sessionStoreProvider]
/// (методы `SessionNotifier.adapt*`), движок недоступен экрану напрямую.
class AdaptPanel extends ConsumerWidget {
  const AdaptPanel({super.key});

  static const Map<ContentDepth, String> _depthLabel = {
    ContentDepth.overview: 'Обзор',
    ContentDepth.standard: 'Обычно',
    ContentDepth.deep: 'Глубже',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ss = ref.watch(sessionStoreProvider);
    final item = ss.currentItem;
    if (item == null) return const SizedBox.shrink();

    // Фаза чтения объяснения: на шаге с вопросом панель скрыта целиком —
    // иначе кнопки работают даже в тесте и подмешивают объяснения в ответ.
    final phase = adaptPhaseOf(ss);
    if (phase == AdaptPhase.question) return const SizedBox.shrink();

    // «Объясни проще»/«Из чего складывается» и глубина меняют текст
    // объяснения — он есть только на шаге «Объяснение». До активности
    // контент ещё не сгенерирован (just-in-time, §61), на «Примере» текст
    // менять нечего: там только skip/replan.
    final textActions = phase == AdaptPhase.explain;

    final theme = Theme.of(context);
    final adapt = ss.adapt;
    final busy = adapt.busy;
    final notifier = ref.read(sessionStoreProvider.notifier);
    final label = item.label ?? item.nodeId;
    final running = adapt.running;
    final result = adapt.result;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Что ещё можно сделать',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Текущее понятие: $label',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (textActions) ...[
                  AppButton(
                    'Объясни проще',
                    icon: Icons.lightbulb_outline,
                    busy: running == AdaptAction.simplify,
                    onPressed:
                        busy ? null : () => notifier.adaptSimplify(),
                  ),
                  AppButton(
                    'Из чего складывается',
                    variant: AppButtonVariant.secondary,
                    icon: Icons.account_tree_outlined,
                    busy: running == AdaptAction.prerequisite,
                    onPressed:
                        busy ? null : () => notifier.adaptPrerequisites(),
                  ),
                ],
                AppButton(
                  'Знаю, пропустить',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.skip_next,
                  busy: running == AdaptAction.skip,
                  onPressed: busy ? null : () => notifier.adaptSkip(),
                ),
                AppButton(
                  'Успеваю только…',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.timer_outlined,
                  busy: running == AdaptAction.replan,
                  onPressed: busy
                      ? null
                      : () => _chooseRemainingTime(context, notifier, ss),
                ),
              ],
            ),
            if (textActions) ...[
              const SizedBox(height: 12),
              Text(
                'Насколько подробно:',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted(context),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final depth in ContentDepth.values)
                    ChoiceChip(
                      label: Text(_depthLabel[depth] ?? depth.raw),
                      selected: depth == _selectedDepth(result),
                      onSelected: adapt.busy
                          ? null
                          : (_) => _selectDepth(
                                depth,
                                notifier: notifier,
                                result: result,
                              ),
                    ),
                ],
              ),
            ],
            if (running != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Loader(size: LoaderSize.sm),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _runningLabel(running),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Статусные результаты (skip/replan) — здесь же, в панели;
            // текстовые рендерятся на месте понятия, см. isInlineAdaptResult.
            if (result != null && !isInlineAdaptResult(result)) ...[
              const SizedBox(height: 12),
              AdaptResultBody(
                result: result,
                onDismiss: notifier.clearAdaptResult,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Нажатие чипа глубины — это ещё и возврат: глубина, равная текущей
  /// («Обычно» при любом активном результате без глубины), убирает результат
  /// и возвращает исходный текст — без нового запроса. Другая глубина —
  /// обычная смена подачи.
  static void _selectDepth(
    ContentDepth depth, {
    required SessionNotifier notifier,
    required AdaptResult? result,
  }) {
    final current =
        result is AdaptDepthResult ? result.depth : ContentDepth.standard;
    if (result != null && depth == current) {
      notifier.clearAdaptResult();
    } else {
      notifier.adaptDepth(depth);
    }
  }

  /// Какая глубина подачи выбрана сейчас: последний запрос либо «Обычно»
  /// (подача по умолчанию — цель самой сессии).
  static ContentDepth _selectedDepth(AdaptResult? result) =>
      result is AdaptDepthResult ? result.depth : ContentDepth.standard;

  static String _runningLabel(AdaptAction action) => switch (action) {
        AdaptAction.simplify => 'Готовим объяснение…',
        AdaptAction.prerequisite => 'Смотрим, из чего понятие собирается…',
        AdaptAction.skip => 'Отмечаем понятие…',
        AdaptAction.changeDepth => 'Меняем подачу…',
        AdaptAction.replan => 'Пересобираем план…',
      };

  /// Сколько времени осталось: остаток бюджета сессии либо минуты,
  /// которые пользователь знает сам. Остаток берётся из существующего
  /// состояния сессии (бюджет и ETA) — новых источников не появляется.
  Future<void> _chooseRemainingTime(
    BuildContext context,
    SessionNotifier notifier,
    SessionState ss,
  ) async {
    final eta = ss.adaptive?.eta;
    final budget = ss.session?.timeBudgetMinutes;
    final theme = Theme.of(context);

    final picked = await showDialog<_ReplanChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Сколько времени осталось?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'План уменьшится до того, что реально успеешь сделать.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (budget != null)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const _ReplanChoice(null)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'По остатку бюджета',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (eta != null)
                    Text(
                      'Прошло ${eta.elapsedMinutes} мин из $budget мин',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          for (final minutes in const [10, 15, 30, 45])
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ReplanChoice(minutes)),
              child: Text('$minutes мин'),
            ),
        ],
      ),
    );

    if (picked == null || !context.mounted) return;
    await notifier.adaptReplan(remainingMinutes: picked.minutes);
  }
}

/// Содержимое результата Adapt-действия: заголовок, честные пометки (в т.ч.
/// «сохранённый вариант», когда LLM недоступна) и текст без жаргона движка —
/// тексты собираются здесь, `reasons` домена на экран не выносятся.
///
/// Публичный виджет: текстовые результаты (упрощение/глубина/база)
/// рендерятся на месте понятия — в карточке шага (см. session_screen), а не
/// в панели, чтобы результат стоял рядом с текстом, который меняет.
/// Статусные (skip/replan) остаются в панели с крестиком закрытия.
class AdaptResultBody extends StatelessWidget {
  /// Показываемый результат.
  final AdaptResult result;

  /// «Вернуть обычное объяснение» (для глубины — «Вернуть исходный текст»):
  /// сброс результата, карточка возвращается к исходному тексту. Кнопка
  /// рисуется только когда колбэк задан.
  final VoidCallback? onReset;

  /// Крестик закрытия — панель использует для статусных результатов.
  final VoidCallback? onDismiss;

  const AdaptResultBody({
    required this.result,
    this.onReset,
    this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badges = _badges(context, result);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title(result),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  tooltip: 'Скрыть',
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: badges),
          ],
          const SizedBox(height: 8),
          ..._content(context, result),
          if (onReset != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                _resetLabel(result),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: onReset,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Подпись сброса: для глубины — явный возврат к исходному тексту (имя
  /// чипа тут путается с чипом «Обычно»), для остальных — возврат к обычному
  /// объяснению.
  static String _resetLabel(AdaptResult result) =>
      result is AdaptDepthResult
          ? 'Вернуть исходный текст'
          : 'Вернуть обычное объяснение';

  static String _title(AdaptResult result) => switch (result) {
        AdaptSimplifyResult() => 'Объяснение проще',
        AdaptDepthResult(:final depth) => switch (depth) {
            ContentDepth.overview => 'Короткий обзор',
            ContentDepth.standard => 'Обычное объяснение',
            ContentDepth.deep => 'Подробное объяснение',
          },
        AdaptPrerequisiteResult() => 'Из чего складывается',
        AdaptSkipResult() => 'Знаю, пропустить',
        AdaptReplanResult() => 'План на оставшееся время',
        _ => 'Результат',
      };

  static List<Widget> _badges(BuildContext context, AdaptResult result) {
    return switch (result) {
      // Честная пометка: LLM недоступна, показан сохранённый текст узла.
      AdaptSimplifyResult(:final source) when source == AdaptSource.stored =>
        const [
          StatusBadge(
            'Сохранённый вариант',
            variant: BadgeVariant.muted,
            icon: Icons.save_outlined,
          ),
        ],
      AdaptDepthResult(:final source) when source == AdaptSource.stored =>
        const [
          StatusBadge(
            'Сохранённый вариант',
            variant: BadgeVariant.muted,
            icon: Icons.save_outlined,
          ),
        ],
      AdaptSkipResult(:final changed, :final masteryScore) => [
        changed
            ? const StatusBadge(
                'Отмечено',
                variant: BadgeVariant.success,
                icon: Icons.check_circle_outline,
              )
            : const StatusBadge(
                'Уже отмечено',
                variant: BadgeVariant.muted,
                icon: Icons.check_circle_outline,
              ),
        if (changed && masteryScore != null)
          StatusBadge(
            'Понимание ${(masteryScore * 100).round()}%',
            variant: BadgeVariant.info,
          ),
      ],
      AdaptReplanResult(:final remainingMinutes, :final eta) => [
        StatusBadge('⏱ $remainingMinutes мин', variant: BadgeVariant.info),
        if (eta.totalItems > 0)
          StatusBadge(
            '⏱ ${eta.remainingMinutesMin}\u2013${eta.remainingMinutesMax} мин',
            variant: eta.pace == PaceClass.faster
                ? BadgeVariant.success
                : eta.pace == PaceClass.slower
                    ? BadgeVariant.warning
                    : BadgeVariant.info,
          ),
      ],
      _ => const <Widget>[],
    };
  }

  static List<Widget> _content(BuildContext context, AdaptResult result) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted(context),
    );

    return switch (result) {
      AdaptSimplifyResult(:final source, :final text, :final analogy) => [
          if (source == AdaptSource.stored)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'ИИ сейчас недоступен — показываем текст, который уже есть.',
                style: muted,
              ),
            ),
          if (text.isNotEmpty) FormattedText(text),
          if (analogy != null && analogy.isNotEmpty) ...[
            const SizedBox(height: 8),
            _analogy(context, analogy),
          ],
        ],
      AdaptDepthResult(:final source, :final text, :final analogy) => [
          if (source == AdaptSource.stored)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'ИИ сейчас недоступен — показываем текст, который уже есть.',
                style: muted,
              ),
            ),
          if (text.isNotEmpty) FormattedText(text),
          if (analogy != null && analogy.isNotEmpty) ...[
            const SizedBox(height: 8),
            _analogy(context, analogy),
          ],
        ],
      final AdaptPrerequisiteResult prereq => _prerequisite(context, prereq),
      AdaptSkipResult(:final changed) => [
          Text(
            changed
                ? 'Понятие отмечено изученным: план обновился, вернёмся к нему '
                    'повторением, чтобы не забылось.'
                : 'Это понятие уже отмечено — ничего не изменилось.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      AdaptReplanResult(:final kept, :final deferred) => _replan(
          context,
          kept: kept,
          deferred: deferred,
        ),
      _ => [Text(result.text, style: theme.textTheme.bodyMedium)],
    };
  }

  static List<Widget> _prerequisite(
    BuildContext context,
    AdaptPrerequisiteResult prereq,
  ) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted(context),
    );

    if (prereq.prerequisites.isEmpty) {
      return [
        Text(
          'Обязательной базы нет — понятие можно изучать само по себе.',
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }

    final missingLabels = [
      for (final p in prereq.prerequisites)
        if (prereq.missingNodeIds.contains(p.nodeId)) p.label,
    ];

    return [
      for (final p in prereq.prerequisites) ...[
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              p.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            StatusBadge(
              p.studied ? 'Изучено' : 'Ещё не разбирали',
              variant: p.studied ? BadgeVariant.success : BadgeVariant.muted,
            ),
            if (p.mastery != null)
              Text(
                'Понимание ${(p.mastery! * 100).round()}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted(context),
                ),
              ),
          ],
        ),
        if (p.oneLiner.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(p.oneLiner, style: muted),
          )
        else
          const SizedBox(height: 8),
      ],
      if (missingLabels.isNotEmpty)
        Text(
          'Сначала стоит понять: ${missingLabels.join(', ')}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.warning(context),
            fontWeight: FontWeight.w600,
          ),
        )
      else
        Text(
          'База уже разобрана — можно переходить к понятию.',
          style: muted,
        ),
    ];
  }

  static List<Widget> _replan(
    BuildContext context, {
    required List<CurriculumItem> kept,
    required List<CurriculumItem> deferred,
  }) {
    final theme = Theme.of(context);
    final pending = [
      for (final i in kept)
        if (i.status != CurriculumItemStatus.completed) i,
    ];
    String labelOf(CurriculumItem i) => i.label ?? '';

    return [
      Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Осталось сделать (${pending.length}):',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted(context),
            ),
          ),
          for (final i in pending)
            Chip(
              label: Text(labelOf(i), style: theme.textTheme.labelSmall),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
      if (deferred.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Не влезло в остаток времени (${deferred.length}):',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted(context),
              ),
            ),
            for (final i in deferred)
              Chip(
                label: Text(
                  labelOf(i),
                  style: theme.textTheme.labelSmall?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ] else ...[
        const SizedBox(height: 8),
        Text(
          'Ничего не отложено — всё укладывается в остаток времени.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted(context),
          ),
        ),
      ],
    ];
  }

  static Widget _analogy(BuildContext context, String analogy) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              analogy,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
