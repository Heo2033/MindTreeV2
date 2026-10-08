import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/current_topic.dart';
import 'package:mindtree_flutter/providers/topic_transfer_store.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/labels.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/error_banner.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(topicStoreProvider.notifier).loadTopics());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(topicStoreProvider);
    final transfer = ref.watch(topicTransferProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('MindTree')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'MindTree',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Адаптивный движок обучения',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted(context),
                      ),
                ),
                const SizedBox(height: 20),
                // `Wrap`, а не `Row`: три кнопки с длинными подписями не
                // помещались в maxWidth 600 и давали RenderFlex overflow на
                // узких экранах. Wrap переносит кнопки на следующую строку
                // вместо обрезки.
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      'Настройки провайдера',
                      variant: AppButtonVariant.secondary,
                      icon: Icons.settings_outlined,
                      onPressed: () => context.go('/settings'),
                    ),
                    AppButton(
                      '+ Новая тема',
                      icon: Icons.add_circle_outline,
                      onPressed: () => context.go('/new'),
                    ),
                    AppButton(
                      transfer.busy ? '…' : 'Импорт',
                      variant: AppButtonVariant.secondary,
                      icon: Icons.file_open_outlined,
                      onPressed: transfer.busy ? null : _importTopic,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (state.loading) const Center(child: Loader()),
                if (state.error != null) ...[
                  ErrorBanner(message: state.error!),
                  const SizedBox(height: 12),
                ],
                if (!state.loading && state.topics.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined,
                                size: 48, color: AppColors.textMuted(context)),
                            const SizedBox(height: 12),
                            Text(
                              'Пока нет тем...',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: AppColors.textMuted(context)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Создайте первую тему, чтобы начать обучение',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textMuted(context)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: state.topics.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final topic = state.topics[index];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            ref.read(currentTopicIdProvider.notifier).state = topic.id;
                            // Возврат в существующую тему — это «продолжить
                            // учиться», а не повторная диагностика.
                            context.go('/topic/learn/focus');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        topic.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          StatusBadge(
                                            levelLabel[topic.targetLevel.raw] ??
                                                topic.targetLevel.raw,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Цель: ${goalLabel[topic.goal.raw] ?? topic.goal.raw}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors.textMuted(context),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Экспорт в файл',
                                  icon: const Icon(Icons.save_alt_outlined, size: 20),
                                  onPressed: transfer.busy
                                      ? null
                                      : () => _exportTopic(topic),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _confirmDelete(context, topic),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importTopic() async {
    final feedback =
        await ref.read(topicTransferProvider.notifier).importTopic();
    if (feedback != null && mounted) _showFeedback(feedback);
  }

  Future<void> _exportTopic(Topic topic) async {
    final feedback = await ref
        .read(topicTransferProvider.notifier)
        .exportTopic(topic.id, topic.name);
    if (feedback != null && mounted) _showFeedback(feedback);
  }

  void _showFeedback(TransferFeedback feedback) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(feedback.message),
        backgroundColor:
            feedback.ok ? null : Theme.of(context).colorScheme.error,
        duration: Duration(seconds: feedback.ok ? 4 : 8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _confirmDelete(BuildContext context, dynamic topic) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить тему?'),
        content: Text('Удалить тему «${topic.name}»?'),
        actions: [
          AppButton(
            'Отмена',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppButton(
            'Удалить',
            variant: AppButtonVariant.danger,
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(topicStoreProvider.notifier).removeTopic(topic.id);
            },
          ),
        ],
      ),
    );
  }
}
