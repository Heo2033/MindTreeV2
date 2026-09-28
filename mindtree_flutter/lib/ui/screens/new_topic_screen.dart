import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/providers/current_topic.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/inputs.dart';
import 'package:mindtree_flutter/ui/widgets/progress_bar.dart';

/// Создание темы: одна обязательная тема, реальный бюджет времени,
/// необязательные уточнения. После генерации — сразу диагностика,
/// чтобы понять исходный уровень, а не смотреть на пустой граф.
class NewTopicScreen extends ConsumerStatefulWidget {
  const NewTopicScreen({super.key});

  @override
  ConsumerState<NewTopicScreen> createState() => _NewTopicScreenState();
}

class _NewTopicScreenState extends ConsumerState<NewTopicScreen> {
  final _topicController = TextEditingController();
  final _notesController = TextEditingController();
  final _customBudgetController = TextEditingController(text: '45');

  String _goal = 'overview';
  String _level = 'solid_understanding';
  int _budgetMinutes = 30;
  bool _customBudget = false;
  bool _running = false;
  String? _error;

  static const int _minBudget = 5;
  static const int _maxBudget = 600;
  static const List<int> _budgetPresets = [15, 30, 60, 120];

  static const _goalOptions = <({String value, String label})>[
    (value: 'overview', label: 'Обзор'),
    (value: 'deep', label: 'Глубокое изучение'),
    (value: 'exam', label: 'Подготовка к экзамену'),
  ];

  static const _levelOptions = <({String value, String label})>[
    (value: 'awareness', label: 'Осведомлённость'),
    (value: 'basic_understanding', label: 'Базовое понимание'),
    (value: 'solid_understanding', label: 'Уверенное понимание'),
    (value: 'practical_application', label: 'Практика'),
    (value: 'advanced', label: 'Продвинутый'),
    (value: 'expert', label: 'Эксперт'),
  ];

  @override
  void dispose() {
    _topicController.dispose();
    _notesController.dispose();
    _customBudgetController.dispose();
    super.dispose();
  }

  /// Бюджет в минутах, реально уходящий в план.
  int get _effectiveBudget {
    if (!_customBudget) return _budgetMinutes;
    return int.tryParse(_customBudgetController.text.trim()) ?? 0;
  }

  bool get _budgetValid =>
      _effectiveBudget >= _minBudget && _effectiveBudget <= _maxBudget;

  bool get _canSubmit {
    return _topicController.text.trim().isNotEmpty && !_running && _budgetValid;
  }

  /// Запрос для дерева: тема плюс уточнения, если они есть.
  String _buildQuery() {
    final topic = _topicController.text.trim();
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return topic;
    return '$topic\n\nУточнения от пользователя: $notes';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _running = true);

    try {
      final topicNotifier = ref.read(topicStoreProvider.notifier);
      final graphNotifier = ref.read(graphStoreProvider.notifier);
      final budget = _effectiveBudget;
      final name = _topicController.text.trim();

      final topic = await topicNotifier.createTopic(
        name,
        goal: _goal,
        targetLevel: _level,
        timeBudgetMinutes: budget,
      );

      // Тема должна быть доступна экранам до смены маршрута.
      ref.read(currentTopicIdProvider.notifier).state = topic.id;
      graphNotifier.setTopicId(topic.id);
      await graphNotifier.generateTree(
        _buildQuery(),
        goal: _goal,
        level: _level,
        timeBudgetMinutes: budget,
      );

      if (!mounted) return;
      // Первым идёт диагностика: она задаёт стартовый уровень плана.
      context.go('/topic/check/diagnostic');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = ref.watch(
      graphStoreProvider.select((s) => s.pipeline),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая тема'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: () => context.go('/'),
                  child: Text(
                    '\u2190 Назад',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Что будем изучать?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Назовите тему одной фразой — план построим сами.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  ErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                  const SizedBox(height: 16),
                ],
                AppInput(
                  label: 'Тема',
                  controller: _topicController,
                  hint: 'например: Диффузионные модели',
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppInput(
                  label: 'Уточнения (необязательно)',
                  controller: _notesController,
                  hint: 'Что именно нужно: зачем, для какого уровня',
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                _TimeBudgetField(
                  presets: _budgetPresets,
                  minutes: _budgetMinutes,
                  custom: _customBudget,
                  customController: _customBudgetController,
                  valid: _budgetValid,
                  onPreset: (m) => setState(() {
                    _customBudget = false;
                    _budgetMinutes = m;
                  }),
                  onCustom: (v) => setState(() => _customBudget = v),
                  onCustomText: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                AppSelect(
                  label: 'Цель',
                  value: _goal,
                  options: _goalOptions,
                  onChanged: (v) => setState(() => _goal = v ?? _goal),
                ),
                const SizedBox(height: 16),
                AppSelect(
                  label: 'Целевой уровень',
                  value: _level,
                  options: _levelOptions,
                  onChanged: (v) => setState(() => _level = v ?? _level),
                ),
                const SizedBox(height: 24),
                if (_running && pipeline.running) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pipeline.message.isNotEmpty
                                ? pipeline.message
                                : 'Генерация...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (pipeline.stats != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Узлов: ${pipeline.stats!.total} · Глубина: ${pipeline.stats!.depth} · Листьев: ${pipeline.stats!.leaves}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textMuted(context),
                                  ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ProgressBar(
                            value: _pipelineProgress(pipeline.phase),
                            label: _pipelinePhaseLabel(pipeline.phase),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                AppButton(
                  'Построить план обучения',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _running,
                  icon: Icons.auto_awesome,
                  onPressed: _canSubmit ? _submit : null,
                ),
                if (!_budgetValid) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Бюджет времени: от $_minBudget до $_maxBudget минут',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _pipelineProgress(String phase) {
    switch (phase) {
      case 'structure':
        return 30;
      case 'validate':
      case 'repair':
        return 50;
      case 'content':
        return 80;
      case 'done':
        return 100;
      default:
        return 10;
    }
  }

  String _pipelinePhaseLabel(String phase) {
    switch (phase) {
      case 'structure':
        return 'Структура';
      case 'validate':
        return 'Проверка';
      case 'repair':
        return 'Исправление';
      case 'content':
        return 'Контент';
      case 'done':
        return 'Готово';
      default:
        return 'Инициализация';
    }
  }
}

/// Реальный выбор бюджета времени: пресеты или своё значение.
class _TimeBudgetField extends StatelessWidget {
  final List<int> presets;
  final int minutes;
  final bool custom;
  final TextEditingController customController;
  final bool valid;
  final ValueChanged<int> onPreset;
  final ValueChanged<bool> onCustom;
  final ValueChanged<String> onCustomText;

  const _TimeBudgetField({
    required this.presets,
    required this.minutes,
    required this.custom,
    required this.customController,
    required this.valid,
    required this.onPreset,
    required this.onCustom,
    required this.onCustomText,
  });

  @override
  Widget build(BuildContext context) {
    return AppField(
      label: 'Сколько времени есть',
      hint: 'План подстроится под бюджет: короткий путь до цели, '
          'а не бесконечный список тем.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in presets)
                ChoiceChip(
                  selected: !custom && minutes == m,
                  onSelected: (_) => onPreset(m),
                  label: Text(_formatMinutes(m)),
                  visualDensity: VisualDensity.compact,
                ),
              ChoiceChip(
                selected: custom,
                onSelected: onCustom,
                label: const Text('Другое'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            AppInput(
              label: 'Минут',
              controller: customController,
              keyboardType: TextInputType.number,
              onChanged: onCustomText,
              errorText: valid
                  ? null
                  : 'Введите целое число минут в допустимом диапазоне',
            ),
          ],
        ],
      ),
    );
  }

  static String _formatMinutes(int m) {
    if (m < 60) return '$m мин';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h ч' : '$h ч $rest мин';
  }
}
