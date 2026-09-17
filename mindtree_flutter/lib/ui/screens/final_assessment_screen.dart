import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
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

const Map<String, String> masteryLabels = {
  'awareness': 'Ознакомление',
  'basic_understanding': 'Базовое понимание',
  'solid_understanding': 'Устойчивое понимание',
  'practical_application': 'Практическое применение',
  'advanced': 'Продвинутый',
  'expert': 'Эксперт',
};

class FinalAssessmentScreen extends ConsumerStatefulWidget {
  final String topicId;
  const FinalAssessmentScreen({super.key, required this.topicId});

  @override
  ConsumerState<FinalAssessmentScreen> createState() =>
      _FinalAssessmentScreenState();
}

class _FinalAssessmentScreenState extends ConsumerState<FinalAssessmentScreen> {
  Assessment? _assessment;
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _showingFeedback = false;
  bool _lastCorrect = false;
  bool _finished = false;
  bool _loading = false;
  String? _error;
  final _answerController = TextEditingController();
  int? _selectedOption;
  int _startedAt = 0;

  // Collect all answers before submit (like web FinalAssessment.tsx)
  final Map<String, String> _answers = {};
  final Map<String, bool> _results = {};
  List<String>? _gaps;
  String? _masteryLevel;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final graph = ref.read(graphStoreProvider.notifier);
      if (ref.read(graphStoreProvider).topicId != widget.topicId) {
        graph.loadTopic(widget.topicId);
      }
      _tryLoadExisting();
    });
  }

  AssessmentQuestion? get _currentQuestion {
    final q = _assessment?.questions;
    if (q == null || _currentIndex >= q.length) return null;
    return q[_currentIndex];
  }

  int get _totalQuestions => _assessment?.questions.length ?? 0;

  bool get _isMultipleChoice =>
      _currentQuestion?.options != null &&
      _currentQuestion!.options!.isNotEmpty;

  Future<void> _tryLoadExisting() async {
    final ss = ref.read(sessionStoreProvider);
    final sessionId = ss.session?.id;
    if (sessionId == null) return;
    final repo = ref.read(repositoryProvider).valueOrNull;
    if (repo == null) return;
    final existing = await repo.latestAssessmentForSession(sessionId, 'final');
    if (existing != null && existing.completedAt == null) {
      setState(() {
        _assessment = existing;
      });
    }
  }

  Future<void> _startAssessment() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = ref.read(assessmentEngineProvider);
    final graph = ref.read(graphStoreProvider);
    final nodes = graph.nodes;
    if (nodes.isEmpty) {
      setState(() {
        _error = 'Нет узлов для теста.';
        _loading = false;
      });
      return;
    }
    final items = nodes
        .where((n) => n.contentLoaded)
        .take(20)
        .map((n) => AssessmentItem(
              nodeId: n.id,
              label: n.label,
              oneLiner: n.oneLiner,
              details: n.details,
            ))
        .toList();
    if (items.isEmpty) {
      setState(() {
        _error = 'Нет изученных понятий.';
        _loading = false;
      });
      return;
    }
    try {
      final assessment = await engine.generate(
        'final_${widget.topicId}_${DateTime.now().microsecondsSinceEpoch}',
        widget.topicId,
        items,
        type: AssessmentType.final_,
        questionCount: items.length.clamp(4, 10),
      );
      setState(() {
        _assessment = assessment;
        _currentIndex = 0;
        _correctCount = 0;
        _showingFeedback = false;
        _finished = false;
        _loading = false;
      });
      _startedAt = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _checkAnswer() {
    final q = _currentQuestion;
    if (q == null) return;
    final engine = ref.read(assessmentEngineProvider);
    final timeMs = DateTime.now().millisecondsSinceEpoch - _startedAt;

    bool correct;
    String answer;
    if (_isMultipleChoice) {
      final selected = _selectedOption ?? -1;
      answer = selected.toString();
      correct = selected.toString() == q.correctAnswer;
    } else {
      answer = _answerController.text.trim();
      // Rubric-based heuristic grading for open-ended questions.
      // Mirrors web: check if explanation/rubric keywords are present.
      correct = _gradeOpenEnded(answer, q);
    }

    setState(() {
      _lastCorrect = correct;
      _showingFeedback = true;
      if (correct) _correctCount++;
      _answers[q.id] = answer;
      _results[q.id] = correct;
    });

    engine.recordAttempt(
      _assessment!.id,
      q.id,
      answer,
      correct,
      timeMs,
      feedback: q.explanation,
    );
  }

  /// Heuristic grading for open-ended questions (explanation/diagnosis/application/transfer).
  /// Checks if the answer contains key concepts from the rubric/explanation field.
  bool _gradeOpenEnded(String answer, AssessmentQuestion q) {
    if (answer.isEmpty) return false;
    final rubric = q.explanation ?? '';
    if (rubric.isEmpty) return true; // Fallback: no rubric = accept

    // Extract key terms from rubric (words > 3 chars, Cyrillic/Latin)
    final rubricWords = rubric
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toSet();

    if (rubricWords.isEmpty) return answer.length > 10; // Fallback

    final answerLower = answer.toLowerCase();
    final matched = rubricWords.where((w) => answerLower.contains(w)).length;
    final threshold = rubricWords.length * 0.3; // 30% совпадений = верно

    return matched >= threshold;
  }

  void _nextQuestion() {
    setState(() {
      _showingFeedback = false;
      _selectedOption = null;
      _answerController.clear();
      _currentIndex++;
      if (_currentIndex >= _totalQuestions) {
        _finished = true;
        final score = _totalQuestions > 0
            ? _correctCount / _totalQuestions
            : 0.0;
        ref.read(assessmentEngineProvider).finalize(_assessment!.id, score);
        // Apply results to SRS (mirrors web: ReviewScheduler.onAnswered)
        _applyResultsToSRS();
        // Compute mastery level and gaps (как в web FinalAssessment.tsx)
        _computeMasteryAndGaps();
      }
    });
    _startedAt = DateTime.now().millisecondsSinceEpoch;
  }

  /// Применяет результаты теста к SRS learner model.
  void _applyResultsToSRS() {
    final reviewScheduler = ref.read(reviewSchedulerProvider);
    final topic = ref.read(graphStoreProvider).topic;
    final topicId = topic?.id ?? widget.topicId;
    for (final entry in _results.entries) {
      final questionId = entry.key;
      final correct = entry.value;
      // Find the corresponding question
      final question = _assessment!.questions.where((q) => q.id == questionId).firstOrNull;
      if (question != null) {
        reviewScheduler.onAnswered(
          topicId,
          question.nodeId,
          correct ? 'correct' : 'incorrect',
        );
      }
    }
  }

  /// Вычисляет уровень мастерства и список слабых мест по результатам теста.
  void _computeMasteryAndGaps() {
    final questions = _assessment!.questions;
    final score = _totalQuestions > 0 ? _correctCount / _totalQuestions : 0.0;
    final graph = ref.read(graphStoreProvider);
    final topic = graph.topic;
    final targetLevel = topic?.targetLevel ?? MasteryLevel.basicUnderstanding;

    // Mastery level mapping (mirrors web: score-based progression)
    String mastery;
    if (score >= 0.9) {
      mastery = targetLevel.index + 1 < MasteryLevel.order.length
          ? MasteryLevel.order[min(targetLevel.index + 1, MasteryLevel.order.length - 1)].raw
          : targetLevel.raw;
    } else if (score >= 0.7) {
      mastery = targetLevel.raw;
    } else if (score >= 0.5) {
      mastery = targetLevel.index > 0
          ? MasteryLevel.order[max(targetLevel.index - 1, 0)].raw
          : MasteryLevel.awareness.raw;
    } else {
      mastery = MasteryLevel.awareness.raw;
    }
    _masteryLevel = mastery;

    // Gaps list: nodes with wrong answers
    final gapLabels = <String>[];
    for (final q in questions) {
      if (_results[q.id] == false) {
        final node = graph.nodes.where((n) => n.id == q.nodeId).firstOrNull;
        if (node != null && !gapLabels.contains(node.label)) {
          gapLabels.add(node.label);
        }
      }
    }
    _gaps = gapLabels;
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Итоговый тест · ${graph.topicName ?? widget.topicId}'),
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
          AppButton('Повторить', onPressed: _startAssessment),
        ],
      );
    }
    if (_finished) return _buildSummary();
    if (_assessment != null) return _buildQuestion();
    return _buildStartCard();
  }

  Widget _buildStartCard() {
    final ss = ref.watch(sessionStoreProvider);
    final hasSession =
        ss.session != null && ss.session!.status == SessionStatus.active;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.task_alt,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Итоговый тест',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasSession
                  ? 'Проверьте итоговые знания после завершения сессии.'
                  : 'Начните сессию, чтобы пройти итоговый тест по изученным понятиям.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (hasSession)
              AppButton(
                'Начать итоговый тест',
                size: AppButtonSize.lg,
                fullWidth: true,
                icon: Icons.play_arrow,
                onPressed: _startAssessment,
              )
            else
              AppButton(
                'Перейти к сессии',
                size: AppButtonSize.lg,
                fullWidth: true,
                variant: AppButtonVariant.secondary,
                icon: Icons.play_circle_outline,
                onPressed: () =>
                    context.go('/topic/session'),
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
                    StatusBadge(
                      typeLabel[q.type.wire] ?? q.type.wire,
                    ),
                    const SizedBox(height: 16),
                    FormattedText(q.question),
                    const SizedBox(height: 20),
                    if (_showingFeedback)
                      _buildFeedback()
                    else ...[
                      if (_isMultipleChoice)
                        _buildOptions(q)
                      else ...[
                        if (q.explanation != null && q.explanation!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Рекомендация для проверки',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppColors.textMuted(context),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  q.explanation!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textMuted(context),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        AppTextarea(
                          label: 'Ваш ответ',
                          controller: _answerController,
                          hint: 'Введите ответ своими словами...',
                          minLines: 3,
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        'Проверить',
                        fullWidth: true,
                        onPressed: (_isMultipleChoice && _selectedOption == null)
                            ? null
                            : _checkAnswer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptions(AssessmentQuestion q) {
    return Column(
      children: [
        for (var i = 0; i < q.options!.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => setState(() => _selectedOption = i),
              style: OutlinedButton.styleFrom(
                backgroundColor: _selectedOption == i
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3)
                    : null,
                side: _selectedOption == i
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(q.options![i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFeedback() {
    final q = _currentQuestion!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBadge(
          _lastCorrect ? 'Верно' : 'Неверно',
          variant: _lastCorrect ? BadgeVariant.success : BadgeVariant.danger,
        ),
        if (!_lastCorrect && _isMultipleChoice && q.correctAnswer != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Правильный ответ: ${q.options![int.tryParse(q.correctAnswer!) ?? 0]}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        if (q.explanation != null && q.explanation!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: FormattedText(q.explanation!),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(
          _currentIndex + 1 >= _totalQuestions ? 'Завершить' : 'Следующий вопрос',
          fullWidth: true,
          icon: _currentIndex + 1 >= _totalQuestions ? Icons.check : Icons.arrow_forward,
          onPressed: _nextQuestion,
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final score = _totalQuestions > 0 ? _correctCount / _totalQuestions : 0.0;
    final pct = (score * 100).round();
    final reachedTarget = pct >= 70;
    final graph = ref.read(graphStoreProvider);
    final topicName = graph.topicName ?? widget.topicId;
    final masteryLabel = _masteryLevel != null
        ? masteryLabels[_masteryLevel!] ?? _masteryLevel!
        : null;

    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                reachedTarget ? Icons.emoji_events : Icons.info_outline,
                size: 48,
                color: reachedTarget
                    ? AppColors.ok
                    : AppColors.warning(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Итоговый тест завершён!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$pct% правильных ответов',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: reachedTarget
                          ? AppColors.ok
                          : AppColors.warning(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '$_correctCount из $_totalQuestions вопросов',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Mastery level (как в web)
              if (masteryLabel != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: reachedTarget
                        ? AppColors.ok.withValues(alpha: 0.1)
                        : AppColors.warning(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: reachedTarget
                          ? AppColors.ok.withValues(alpha: 0.3)
                          : AppColors.warning(context).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Достигнутый уровень',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textMuted(context),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        masteryLabel,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: reachedTarget
                                  ? AppColors.ok
                                  : AppColors.warning(context),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Gaps list «Что стоит повторить» (как в web)
              if (_gaps != null && _gaps!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.report_problem_outlined, size: 16, color: AppColors.warning(context)),
                          const SizedBox(width: 6),
                          Text(
                            'Что стоит повторить',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _gaps!.map((label) => Chip(
                          label: Text(label),
                          labelStyle: Theme.of(context).textTheme.labelSmall,
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              StatusBadge(
                reachedTarget ? 'Цель достигнута' : 'Нужно больше практики',
                variant:
                    reachedTarget ? BadgeVariant.success : BadgeVariant.warning,
              ),
              const SizedBox(height: 20),
              ProgressBar(value: pct.toDouble()),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тема: $topicName',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Вопросов: $_totalQuestions',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted(context),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Expand tree option при pass (как в web)
              if (reachedTarget && _totalQuestions > 0)
                AppButton(
                  'Раскрыть дерево глубже',
                  fullWidth: true,
                  icon: Icons.unfold_more,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    ref.read(graphStoreProvider.notifier).autoExpandVisible();
                    context.go('/topic/graph');
                  },
                ),
              if (reachedTarget && _totalQuestions > 0) const SizedBox(height: 8),
              AppButton(
                'Повторить',
                fullWidth: true,
                icon: Icons.replay,
                onPressed: _startAssessment,
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
