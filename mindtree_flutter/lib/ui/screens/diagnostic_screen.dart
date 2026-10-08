import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';
import 'package:mindtree_flutter/ui/widgets/topic_meta_bar.dart';

class DiagnosticScreen extends ConsumerStatefulWidget {
  final String topicId;
  const DiagnosticScreen({super.key, required this.topicId});

  @override
  ConsumerState<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends ConsumerState<DiagnosticScreen> {
  List<DiagnosticQuestion>? _questions;
  int _currentIndex = 0;
  int? _selectedOption;
  DiagnosticResult? _result;
  bool _loading = false;
  String? _error;
  final List<DiagnosticAnswer> _answers = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
    });
  }

  DiagnosticQuestion? get _currentQuestion {
    final q = _questions;
    if (q == null || _currentIndex >= q.length) return null;
    return q[_currentIndex];
  }

  int get _totalQuestions => _questions?.length ?? 0;

  Future<void> _startDiagnostic() async {
    setState(() {
      _loading = true;
      _error = null;
      _questions = null;
      _result = null;
      _currentIndex = 0;
      _answers.clear();
      _selectedOption = null;
    });
    try {
      final engine = ref.read(diagnosticEngineProvider);
      final questions = await engine.generate(widget.topicId);
      if (questions.isEmpty) {
        setState(() {
          _error = 'Не удалось сгенерировать вопросы.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _submitAnswer() async {
    final q = _currentQuestion;
    final selected = _selectedOption;
    if (q == null || selected == null) return;

    _answers.add(DiagnosticAnswer(
      questionId: q.id,
      nodeId: q.nodeId,
      selectedIndex: selected,
      correctIndex: q.correctIndex,
    ));

    if (_currentIndex + 1 >= _totalQuestions) {
      setState(() => _loading = true);
      try {
        final engine = ref.read(diagnosticEngineProvider);
        final result = await engine.evaluate(widget.topicId, _answers);
        setState(() {
          _result = result;
          _loading = false;
        });
      } catch (e) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } else {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Диагностика · ${graph.topicName ?? widget.topicId}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/topic/learn/graph'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Loader(size: LoaderSize.lg));
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ErrorBanner(message: _error!),
          const SizedBox(height: 16),
          AppButton('Повторить', onPressed: _startDiagnostic),
        ],
      );
    }
    if (_result != null) return _buildResult();
    if (_questions != null) return _buildQuestion();
    return _buildStartCard();
  }

  Widget _buildStartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.fact_check,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Диагностика уровня',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Определим ваш текущий уровень знаний по теме.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              'Начать диагностику',
              size: AppButtonSize.lg,
              fullWidth: true,
              icon: Icons.play_arrow,
              onPressed: _startDiagnostic,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _currentQuestion;
    if (q == null) return const SizedBox.shrink();
    final pct = _totalQuestions > 0
        ? (_currentIndex / _totalQuestions) * 100
        : 0.0;

    return Column(
      children: [
        ProgressBar(
          value: pct,
          label: '${_currentIndex + 1} / $_totalQuestions',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormattedText(q.question),
                    const SizedBox(height: 20),
                    for (var i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _selectedOption = i),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _selectedOption == i
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.3)
                                : null,
                            side: _selectedOption == i
                                ? BorderSide(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                : null,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(q.options[i]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    AppButton(
                      _currentIndex + 1 >= _totalQuestions
                          ? 'Завершить'
                          : 'Далее',
                      fullWidth: true,
                      onPressed: _selectedOption == null ? null : _submitAnswer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final graph = ref.watch(graphStoreProvider);
    final result = _result!;
    final pct = (result.score * 100).round();
    final levelRaw = result.currentLevel;
    final levelText = levelLabel[levelRaw] ?? levelRaw;

    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pct >= 60 ? Icons.check_circle : Icons.info_outline,
                size: 48,
                color: pct >= 60 ? AppColors.ok : AppColors.warning(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Диагностика завершена',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              StatusBadge(
                'Уровень: $levelText',
                variant: pct >= 60 ? BadgeVariant.success : BadgeVariant.info,
              ),
              const SizedBox(height: 16),
              Text(
                'Правильных ответов: $pct%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ProgressBar(value: pct.toDouble()),
              if (result.knownConcepts.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Известные понятия',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in result.knownConcepts)
                      StatusBadge(
                        _conceptLabel(graph, c),
                        variant: BadgeVariant.success,
                      ),
                  ],
                ),
              ],
              if (result.unknownConcepts.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Нужно изучить',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in result.unknownConcepts)
                      StatusBadge(
                        _conceptLabel(graph, c),
                        variant: BadgeVariant.warning,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              AppButton(
                'Пройти заново',
                fullWidth: true,
                icon: Icons.replay,
                onPressed: _startDiagnostic,
              ),
              const SizedBox(height: 16),
              // Шаг 8 аудита (Plan): что дальше, сколько займёт и почему
              // выбраны именно эти понятия — между результатом и «К графу».
              _buildPlanCard(),
              const SizedBox(height: 8),
              AppButton(
                'К графу',
                fullWidth: true,
                variant: AppButtonVariant.secondary,
                icon: Icons.account_tree_outlined,
                onPressed: () =>
                    context.go('/topic/learn/graph'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Подпись понятия для бейджей результата: технический id из движка
  /// заменяется на название из дерева, если оно уже загружено.
  String _conceptLabel(GraphState graph, String id) {
    for (final n in graph.nodes) {
      if (n.id == id && n.label.trim().isNotEmpty) return n.label.trim();
    }
    return id;
  }

  /// Карточка «Твой план»: цель, целевой уровень, оценка времени и причины
  /// выбранных понятий. Данные — из уже загруженной темы, активной сессии
  /// (план и её reasons) и самих вопросов диагностики.
  Widget _buildPlanCard() {
    final graph = ref.watch(graphStoreProvider);
    final session = ref.watch(sessionStoreProvider);
    final result = _result!;
    final known = result.knownConcepts.toSet().length;
    final checked = {...result.knownConcepts, ...result.unknownConcepts}.length;

    return _PlanCard(
      goal: goalText(graph.topic),
      targetLevel: targetLevelText(graph.topic),
      minutes: _planMinutes(graph, session),
      knownCount: known,
      checkedCount: checked,
      reasons: _planReasons(graph, session),
    );
  }

  /// Оценка времени плана. Приоритет источников: план уже существующей
  /// сессии темы → сумма оценок понятий, которые предстоит разобрать →
  /// бюджет темы. `null` — показывать нечего, бейдж не рисуется.
  int? _planMinutes(GraphState graph, SessionState session) {
    final active = session.session ?? session.resumable;
    if (active != null &&
        active.topicId == widget.topicId &&
        active.curriculum.totalEstimatedMinutes > 0) {
      return active.curriculum.totalEstimatedMinutes;
    }

    final unknown = _result!.unknownConcepts.toSet();
    final byNodes = graph.nodes
        .where((n) => unknown.contains(n.id))
        .fold<int>(0, (sum, n) => sum + n.estimatedTimeMinutes);
    if (byNodes > 0) return byNodes;

    final budget = graph.topic?.timeBudgetMinutes ?? 0;
    return budget > 0 ? budget : null;
  }

  /// «Почему выбраны эти понятия»: сначала reasons пунктов плана активной
  /// сессии, иначе — сам факт диагностики (на понятие не получилось ответить).
  List<_PlanReason> _planReasons(GraphState graph, SessionState session) {
    final labels = {for (final n in graph.nodes) n.id: n.label};

    final active = session.session ?? session.resumable;
    if (active != null && active.topicId == widget.topicId) {
      final fromPlan = <_PlanReason>[];
      for (final item in active.curriculum.items) {
        final reason = (item.reason ?? '').trim();
        if (reason.isEmpty) continue;
        final label = (item.label ?? labels[item.nodeId] ?? '').trim();
        if (label.isEmpty) continue;
        fromPlan.add(_PlanReason(label, reason));
      }
      if (fromPlan.isNotEmpty) return fromPlan;
    }

    final questionByNode = {
      for (final q in _questions ?? const <DiagnosticQuestion>[]) q.nodeId: q,
    };
    final reasons = <_PlanReason>[];
    final seen = <String>{};
    for (final id in _result!.unknownConcepts) {
      if (!seen.add(id)) continue;
      final label = (labels[id] ?? '').trim();
      if (label.isEmpty) continue;
      final question = (questionByNode[id]?.question ?? '').trim();
      reasons.add(_PlanReason(
        label,
        question.isNotEmpty
            ? 'Не получилось ответить на диагностике: «$question»'
            : 'Не получилось ответить на диагностике — разберём понятие первым.',
      ));
    }
    return reasons;
  }
}

/// Причина попадания понятия в план: подпись понятия и короткое объяснение.
class _PlanReason {
  final String label;
  final String text;

  const _PlanReason(this.label, this.text);
}

/// Компактная карточка «Твой план»: цель и уровень, оценка времени,
/// что уже освоено и почему выбраны эти понятия.
class _PlanCard extends StatelessWidget {
  final String? goal;
  final String? targetLevel;
  final int? minutes;
  final int knownCount;
  final int checkedCount;
  final List<_PlanReason> reasons;

  const _PlanCard({
    this.goal,
    this.targetLevel,
    this.minutes,
    this.knownCount = 0,
    this.checkedCount = 0,
    this.reasons = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Твой план',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (goal != null && goal!.isNotEmpty)
                StatusBadge('Цель: $goal', icon: Icons.flag_outlined),
              if (targetLevel != null && targetLevel!.isNotEmpty)
                StatusBadge(
                  'Целевой уровень: $targetLevel',
                  icon: Icons.school_outlined,
                ),
              if (minutes != null)
                StatusBadge('⏱ ≈ $minutes мин', icon: Icons.schedule),
            ],
          ),
          if (checkedCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Освоено $knownCount из $checkedCount проверенных понятий — '
              'стартуем с текущего уровня.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Почему выбраны эти понятия',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 6),
          if (reasons.isEmpty)
            Text(
              'Понятия выбраны по результатам диагностики.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason.label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      reason.text,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
