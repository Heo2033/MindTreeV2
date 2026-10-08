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

/// Создание темы: тема, необязательные уточнения, цель и целевой уровень.
/// Бюджет времени здесь НЕ спрашивается: «уровень × минуты» даёт ложное
/// обещание «стать экспертом за 30 минут». Сколько времени есть — вопрос
/// на входе в сессию/веху (пикер `showTimeBudgetPicker`). После генерации —
/// сразу диагностика, чтобы понять исходный уровень, а не смотреть на пустой
/// граф.
class NewTopicScreen extends ConsumerStatefulWidget {
  const NewTopicScreen({super.key});

  @override
  ConsumerState<NewTopicScreen> createState() => _NewTopicScreenState();
}

class _NewTopicScreenState extends ConsumerState<NewTopicScreen> {
  final _topicController = TextEditingController();
  final _notesController = TextEditingController();

  String _goal = 'overview';
  String _level = 'solid_understanding';
  bool _running = false;
  String? _error;

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
    super.dispose();
  }

  bool get _canSubmit {
    return _topicController.text.trim().isNotEmpty && !_running;
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
      final name = _topicController.text.trim();

      final topic = await topicNotifier.createTopic(
        name,
        goal: _goal,
        targetLevel: _level,
      );

      // Тема должна быть доступна экранам до смены маршрута.
      ref.read(currentTopicIdProvider.notifier).state = topic.id;
      graphNotifier.setTopicId(topic.id);
      await graphNotifier.generateTree(
        _buildQuery(),
        goal: _goal,
        level: _level,
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
