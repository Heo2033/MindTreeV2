import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/lib/grading.dart';
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

class QuizScreen extends ConsumerStatefulWidget {
  final String topicId;
  const QuizScreen({super.key, required this.topicId});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  Assessment? _assessment;
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _showingFeedback = false;
  bool _lastCorrect = false;
  bool _finished = false;
  bool _loading = false;
  String? _error;
  String _mode = 'learning'; // 'learning' | 'exam' (как в web Quiz.tsx)
  final _answerController = TextEditingController();
  int? _selectedOption;
  int _startedAt = 0;

  // Аккумуляторы ответов текущей попытки: в режиме «Экзамен» питают разбор
  // в конце, в обоих режимах — факт. результаты для SRS (`_applyQuizResultsToSRS`).
  final Map<String, String> _examAnswers = {};
  final Map<String, bool> _examResults = {};

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
    });
  }

  AssessmentQuestion? get _currentQuestion {
    final q = _assessment?.questions;
    if (q == null || _currentIndex >= q.length) return null;
    return q[_currentIndex];
  }

  int get _totalQuestions => _assessment?.questions.length ?? 0;

  Future<void> _startQuiz() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = ref.read(assessmentEngineProvider);
    final graph = ref.read(graphStoreProvider);
    final nodes = graph.nodes;
    if (nodes.isEmpty) {
      setState(() {
        _error = 'Нет узлов для теста. Сначала сгенерируйте граф.';
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
        _error = 'Нет изученных понятий для теста.';
        _loading = false;
      });
      return;
    }
    try {
      final assessment = await engine.generate(
        'quiz_${widget.topicId}_${DateTime.now().microsecondsSinceEpoch}',
        widget.topicId,
        items,
        type: AssessmentType.quiz,
        questionCount: items.length.clamp(3, 8),
      );
      setState(() {
        _assessment = assessment;
        _currentIndex = 0;
        _correctCount = 0;
        _showingFeedback = false;
        _finished = false;
        _loading = false;
        // Новая попытка — сбрасываем аккумуляторы, чтобы в SRS и разбор
        // не уехали результаты прошлого прогона.
        _examAnswers.clear();
        _examResults.clear();
      });
      _startedAt = DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool get _isMultipleChoice =>
      _currentQuestion?.options != null &&
      _currentQuestion!.options!.isNotEmpty;

  void _checkAnswer() {
    final q = _currentQuestion;
    if (q == null) return;
    final engine = ref.read(assessmentEngineProvider);
    final timeMs = DateTime.now().millisecondsSinceEpoch - _startedAt;

    bool correct;
    String answer;
    if (q.options != null && q.options!.isNotEmpty) {
      final selected = _selectedOption ?? -1;
      answer = selected.toString();
      correct = selected.toString() == q.correctAnswer;
    } else {
      answer = _answerController.text.trim();
      // Открытый вопрос оценивается по рубрике (explanation) детерминированно,
      // как в `final_assessment_screen`. Раньше здесь стояло
      // `correct = answer.isNotEmpty`, то есть ЛЮБОЙ непустой ответ засчитывался
      // как верный: размытые вопросы на понимание раздували mastery и SRS.
      correct = gradeOpenEnded(answer, rubric: q.explanation ?? '');
    }

    // Накопляем в обоих режимах: в «Обучении» карты не показываются
    // пользователю (результат виден по `_lastCorrect`, разбор — только в
    // экзамене), но финализация читает их, чтобы увести факт. результат
    // в SRS. Раньше запись была под `if (_mode == 'exam')` — и обучение
    // всегда уходило в SRS как `incorrect`.
    _examAnswers[q.id] = answer;
    _examResults[q.id] = correct;

    setState(() {
      _lastCorrect = correct;
      _showingFeedback = _mode == 'learning'; // Only show feedback in learning mode
      if (correct) _correctCount++;
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

  Future<void> _nextQuestion() async {
    setState(() {
      _showingFeedback = false;
      _selectedOption = null;
      _answerController.clear();
      _currentIndex++;
      if (_currentIndex >= _totalQuestions) _finished = true;
    });
    // Таймер следующего вопроса сбрасывается сразу и не ждёт async-записей
    // завершения (finalize/SRS).
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    if (_currentIndex >= _totalQuestions) {
      final score = _totalQuestions > 0
          ? _correctCount / _totalQuestions
          : 0.0;
      // Все ref.read — до первого await: после dispose виджета ref
      // недоступен, а записи SRS должны дойти, даже если пользователь
      // уже ушёл с экрана (внутри setState ничего не await-им).
      final engine = ref.read(assessmentEngineProvider);
      final reviewScheduler = ref.read(reviewSchedulerProvider);
      final topicId = ref.read(graphStoreProvider).topic?.id ?? widget.topicId;
      await engine.finalize(_assessment!.id, score);
      // SRS integration: apply quiz results to learner model
      await _applyQuizResultsToSRS(reviewScheduler, topicId);
    }
  }

  /// Apply quiz results to SRS learner model.
  ///
  /// Один цикл по фактически накопленным результатам (`_examResults`
  /// заполняется в `_checkAnswer` в обоих режимах): качество уходит ровно
  /// тем, каким ответ был проверен. Вопрос без записи в аккумуляторе
  /// в SRS не попадает — «неверно по умолчанию» здесь не бывает.
  Future<void> _applyQuizResultsToSRS(
    ReviewScheduler reviewScheduler,
    String topicId,
  ) async {
    final assessment = _assessment;
    if (assessment == null) return;
    final nodeByQuestion = {
      for (final q in assessment.questions) q.id: q.nodeId,
    };
    for (final entry in _examResults.entries) {
      final nodeId = nodeByQuestion[entry.key];
      if (nodeId == null) continue;
      await reviewScheduler.onAnswered(
        topicId,
        nodeId,
        entry.value ? 'correct' : 'incorrect',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Тест · ${graph.topicName ?? widget.topicId}'),
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
          AppButton('Повторить', onPressed: _startQuiz),
        ],
      );
    }
    if (_finished) return _buildSummary();
    if (_assessment == null) return _buildStartCard();
    return _buildQuestion();
  }

  Widget _buildStartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.quiz, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Тест по теме',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Проверьте свои знания по изученным понятиям.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Mode toggle (как в web Quiz.tsx)
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Обучение'),
                    selected: _mode == 'learning',
                    onSelected: (_) => setState(() => _mode = 'learning'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Экзамен'),
                    selected: _mode == 'exam',
                    onSelected: (_) => setState(() => _mode = 'exam'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _mode == 'learning'
                  ? 'Сразу видите объяснение после каждого ответа.'
                  : 'Результаты и объяснения — только в конце.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted(context),
                  ),
            ),
            const SizedBox(height: 16),
            AppButton(
              'Начать тест',
              size: AppButtonSize.lg,
              fullWidth: true,
              icon: Icons.play_arrow,
              onPressed: _startQuiz,
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
                      else
                        _buildFreeText(q),
                      const SizedBox(height: 16),
                      AppButton(
                        'Проверить',
                        fullWidth: true,
                        onPressed: _isMultipleChoice && _selectedOption == null
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

  Widget _buildFreeText(AssessmentQuestion q) {
    return AppTextarea(
      label: 'Ваш ответ',
      controller: _answerController,
      hint: 'Введите ответ...',
      minLines: 3,
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
          _currentIndex + 1 >= _totalQuestions ? 'Завершить тест' : 'Следующий вопрос',
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

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                score >= 0.7 ? Icons.emoji_events : Icons.info_outline,
                size: 48,
                color: score >= 0.7
                    ? AppColors.ok
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Тест завершён!',
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
                      color: score >= 0.7
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
              const SizedBox(height: 8),
              StatusBadge(
                score >= 0.7 ? 'Отличный результат' : 'Есть над чем поработать',
                variant: score >= 0.7 ? BadgeVariant.success : BadgeVariant.warning,
              ),
              const SizedBox(height: 24),
              ProgressBar(value: pct.toDouble()),
              const SizedBox(height: 24),
              // Exam mode review: expandable question details (как в web Quiz.tsx)
              if (_mode == 'exam' && _examResults.isNotEmpty) ...[
                _buildExamReview(),
                const SizedBox(height: 16),
              ],
              AppButton(
                'Пройти заново',
                fullWidth: true,
                icon: Icons.replay,
                onPressed: _startQuiz,
              ),
              const SizedBox(height: 8),
              AppButton(
                'К графу',
                fullWidth: true,
                variant: AppButtonVariant.secondary,
                icon: Icons.account_tree_outlined,
                onPressed: () => context.go('/topic/learn/graph'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Exam mode review: expandable list of all questions with correct/incorrect indicators.
  Widget _buildExamReview() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Разбор ответов',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final q in _assessment!.questions) ...[
          ExpansionTile(
            leading: Icon(
              _examResults[q.id] == true ? Icons.check_circle : Icons.cancel,
              color: _examResults[q.id] == true ? AppColors.ok : AppColors.danger,
              size: 20,
            ),
            title: Text(
              q.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.explanation != null && q.explanation!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          q.explanation!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (q.options != null && q.options!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Правильный ответ: ${q.options![int.tryParse(q.correctAnswer ?? '0') ?? 0]}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ok,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
