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
          onPressed: () => context.go('/topic/graph'),
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
                      StatusBadge(c, variant: BadgeVariant.success),
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
                      StatusBadge(c, variant: BadgeVariant.warning),
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
              const SizedBox(height: 8),
              AppButton(
                'К графу',
                fullWidth: true,
                variant: AppButtonVariant.secondary,
                icon: Icons.account_tree_outlined,
                onPressed: () =>
                    context.go('/topic/graph'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
