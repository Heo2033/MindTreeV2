import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/lib/grading.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/question_timer.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/answer_review.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';
import 'package:mindtree_flutter/ui/widgets/inputs.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

/// Измерения мастерства в порядке их показа в итогах. Тот же состав, что в
/// профиле обучающегося: `understanding / recall / application / transfer`.
const List<({String dim, String label})> masteryDimensions = [
  (dim: 'understanding', label: 'Понимание'),
  (dim: 'recall', label: 'Память'),
  (dim: 'application', label: 'Применение'),
  (dim: 'transfer', label: 'Перенос'),
];

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

  /// Отсчёт времени ответа. Заведён уже при показе экрана и перезапускается
  /// при старте каждого вопроса — в том числе при подхвате незавершённого
  /// теста из `_tryLoadExisting`, где раньше старт оставался `0` и в
  /// `assessment_attempts.time_spent_ms` уезжало epoch-мс (см. [QuestionTimer]).
  final _questionTimer = QuestionTimer();

  // Collect all answers before submit (like web FinalAssessment.tsx)
  final Map<String, String> _answers = {};
  final Map<String, bool> _results = {};
  List<String>? _gaps;

  /// Уровень мастерства и четыре измерения — из `LearnerModelService`, как и
  /// на экране профиля обучающегося. Экранных эвристик по score здесь больше
  /// нет: тест двигает модель через SRS, а витрина читает её же.
  String? _masteryLevel;
  List<double>? _dimensions;

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
      // Корень дефекта «Неправдоподобный замер времени»: тест подхвачен из БД,
      // минуя `_startAssessment`, и без этой строки таймер оставался бы
      // незаводным — первый ответ писал `now - 0` = epoch-мс (~1.8e12 ≈ 20
      // суток) в `assessment_attempts.time_spent_ms`. Вопрос снова показан —
      // отсчёт стартует от показа.
      _questionTimer.restart();
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
        // Новая попытка — сбрасываем аккумуляторы, чтобы в SRS и в списке
        // пробелов не уехали результаты прошлого прогона.
        _answers.clear();
        _results.clear();
        _gaps = null;
        _masteryLevel = null;
        _dimensions = null;
      });
      // Вопрос 1 показан — таймер стартует вместе с ним, а не «где-то раньше».
      _questionTimer.restart();
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
    // Прошедшее время от показа текущего вопроса: QuestionTimer не даёт
    // записать абсолютное время, если старт по какой-то причине не заведён.
    final timeMs = _questionTimer.elapsedMs();

    bool correct;
    String answer;
    if (_isMultipleChoice) {
      final selected = _selectedOption ?? -1;
      answer = selected.toString();
      correct = selected.toString() == q.correctAnswer;
    } else {
      answer = _answerController.text.trim();
      // Rubric-based heuristic grading for open-ended questions.
      correct = gradeOpenEnded(answer, rubric: q.explanation ?? '');
    }

    // Накапливаем БЕЗУСЛОВНО (вне зависимости от режима/длины теста):
    // финализация читает `_results`, чтобы увести ФАКТИЧЕСКИЙ результат
    // в SRS. Условная запись здесь означала бы «incorrect по умолчанию»
    // для пропущенных вопросов — тот же баг, что был в `quiz_screen`.
    _answers[q.id] = answer;
    _results[q.id] = correct;

    setState(() {
      _lastCorrect = correct;
      _showingFeedback = true;
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

  /// Heuristic grading for open-ended questions moved to
  /// [gradeOpenEnded] in `domain/lib/grading.dart` (детерминированная,
  /// покрыта unit-тестами).

  Future<void> _nextQuestion() async {
    setState(() {
      _showingFeedback = false;
      _selectedOption = null;
      _answerController.clear();
      _currentIndex++;
      if (_currentIndex >= _totalQuestions) _finished = true;
    });
    // Таймер следующего вопроса сбрасывается сразу и не ждёт async-записей
    // завершения (finalize/SRS): отсчёт идёт от показа вопроса.
    _questionTimer.restart();
    if (_currentIndex >= _totalQuestions) {
      final score = _totalQuestions > 0
          ? _correctCount / _totalQuestions
          : 0.0;
      // Все ref.read — до первого await: после dispose виджета ref
      // недоступен, а записи finalize/SRS должны дойти, даже если
      // пользователь уже ушёл с экрана (внутри setState ничего не await-им).
      final engine = ref.read(assessmentEngineProvider);
      final reviewScheduler = ref.read(reviewSchedulerProvider);
      final topicId = ref.read(graphStoreProvider).topic?.id ?? widget.topicId;
      // Пробелы — чисто экранный синхронный расчёт БЕЗ записей в БД,
      // поэтому считается сразу, но уже вне setState.
      _computeGaps();
      await engine.finalize(_assessment!.id, score);
      // Apply results to SRS (mirrors web: ReviewScheduler.onAnswered)
      await _applyResultsToSRS(reviewScheduler, topicId);
      // Мастерство читаем ТОЛЬКО после записи ответов в SRS: до этого в
      // модели ещё старые значения, и итоговый экран показал бы уровень,
      // который тест не двигал.
      await _loadMasteryFromModel(topicId);
    }
  }

  /// Применяет результаты теста к SRS learner model.
  ///
  /// Один цикл по фактически накопленным результатам (`_results`
  /// заполняется в `_checkAnswer` безусловно): качество уходит ровно тем,
  /// каким ответ был проверен. Каждый вызов awaited — read-modify-write
  /// всей строки `learner_models` в `LearnerModelService` без ожидания
  /// конфликтует сам с собой, и часть инкрементов теряется.
  Future<void> _applyResultsToSRS(
    ReviewScheduler reviewScheduler,
    String topicId,
  ) async {
    final assessment = _assessment;
    if (assessment == null) return;
    final nodeByQuestion = {
      for (final q in assessment.questions) q.id: q.nodeId,
    };
    for (final entry in _results.entries) {
      final nodeId = nodeByQuestion[entry.key];
      if (nodeId == null) continue;
      await reviewScheduler.onAnswered(
        topicId,
        nodeId,
        entry.value ? 'correct' : 'incorrect',
      );
    }
  }

  /// Список пробелов по результатам теста: понятия, где ответ был неверный.
  ///
  /// Только читает `graphStoreProvider` и пишет в экранный [_gaps] — в БД
  /// ничего не сохраняет, поэтому вызов синхронный и может идти до
  /// await-записей финиша. Уровень мастерства здесь НЕ считается: его даёт
  /// [LearnerModelService] (см. [_loadMasteryFromModel]).
  void _computeGaps() {
    final questions = _assessment!.questions;
    final graph = ref.read(graphStoreProvider);

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

  /// Среднее по измерениям мастерства — тот же состав, что в профиле
  /// обучающегося (understanding/recall/application/transfer).
  List<double>? _averageDimensions(List<ConceptProfile> profiles) {
    if (profiles.isEmpty) return null;
    double avg(double Function(ConceptProfile p) pick) =>
        profiles.map(pick).reduce((a, b) => a + b) / profiles.length;
    return [
      avg((p) => p.understanding),
      avg((p) => p.recall),
      avg((p) => p.application),
      avg((p) => p.transfer),
    ];
  }

  /// Читает уровень и измерения мастерства из модели обучающегося — того же
  /// источника, что и экран «Профиль обучающегося».
  ///
  /// Никаких записей не делает; любая ошибка (БД недоступна) гасится молча:
  /// счёт, пробелы и SRS от чтения не зависят.
  Future<void> _loadMasteryFromModel(String topicId) async {
    if (!mounted) return;
    try {
      final learner = ref.read(learnerModelProvider);
      final model = await learner.getModel(topicId);
      final profiles = await learner.getConceptProfiles(topicId);
      if (!mounted) return;
      setState(() {
        _masteryLevel = model.overallLevel.raw;
        _dimensions = _averageDimensions(profiles);
      });
    } catch (_) {
      // Мастерство не показываем — итоги теста остаются сортом и пробелами.
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(graphStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Итоговый тест · ${graph.topicName ?? widget.topicId}'),
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
                    context.go('/topic/learn/session'),
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
                        // Рубрика НЕ показывается до ответа: в ней ключевые
                        // элементы ответа — прямой спойлер открытого вопроса.
                        // Разбор (эталон/рубрика) открывается в [_buildFeedback].
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

  /// Разбор ответа: бейдж вердикта и эталон/рубрика — та же плашка, что в
  /// сессии у apply (см. [AnswerReview]).
  Widget _buildFeedback() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnswerReview(correct: _lastCorrect, question: _currentQuestion!),
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
        ? levelLabel[_masteryLevel!] ?? _masteryLevel!
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
              // Уровень мастерства — из модели обучающегося (тот же источник,
              // что на экране «Профиль обучающегося»), а не из score теста.
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
                      // Четыре измерения той же модели — видно, что именно
                      // росло: понимание, память, применение, перенос.
                      if (_dimensions != null) ...[
                        const SizedBox(height: 12),
                        for (var i = 0; i < masteryDimensions.length && i < _dimensions!.length; i++)
                          _DimensionRow(
                            label: masteryDimensions[i].label,
                            value: _dimensions![i],
                          ),
                      ],
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
                    context.go('/topic/learn/graph');
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
                    context.go('/topic/learn/graph'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка одного измерения мастерства в итогах теста.
class _DimensionRow extends StatelessWidget {
  final String label;
  final double value;

  const _DimensionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ProgressBar(
          value: value * 100,
          label: label,
        ),
      );
}
