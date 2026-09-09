import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/theme/app_theme.dart';
import 'package:mindtree_flutter/ui/widgets/badge.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';
import 'package:mindtree_flutter/ui/widgets/spinner.dart';

class TutorScreen extends ConsumerStatefulWidget {
  final String topicId;
  const TutorScreen({super.key, required this.topicId});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final ss = ref.read(sessionStoreProvider);
    final sessionId = ss.session?.id;
    await ref.read(tutorStoreProvider.notifier).send(
          widget.topicId,
          text,
          sessionId: sessionId,
        );
    _scrollToBottom();
  }

  void _resetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить диалог?'),
        content: const Text('Все сообщения будут удалены.'),
        actions: [
          AppButton(
            'Отмена',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppButton(
            'Сбросить',
            variant: AppButtonVariant.danger,
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.invalidate(tutorStoreProvider);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(tutorStoreProvider);
    final graph = ref.watch(graphStoreProvider);
    final topicName = graph.topicName ?? widget.topicId;

    return Column(
      children: [
        _buildHeader(topicName, ts),
        Expanded(child: _buildChat(ts)),
        _buildInput(ts),
      ],
    );
  }

  Widget _buildHeader(String topicName, TutorState ts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topicName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ts.timeRemainingMinutes != null)
                  Text(
                    '~${ts.timeRemainingMinutes} мин осталось',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted(context),
                        ),
                  ),
              ],
            ),
          ),
          AppButton(
            'Сбросить',
            variant: AppButtonVariant.danger,
            size: AppButtonSize.sm,
            icon: Icons.refresh,
            onPressed: _resetDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildChat(TutorState ts) {
    if (ts.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.support_agent,
                  size: 48, color: AppColors.textMuted(context)),
              const SizedBox(height: 12),
              Text(
                'Задайте вопрос по теме',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'AI-тьютор поможет разобраться в сложных понятиях.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted(context),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: ts.messages.length + (ts.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == ts.messages.length) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(ts.messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: isUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.5,
                ),
                child: FormattedText(msg.content),
              ),
            ),
            if (!isUser && msg.usedFallback) ...[
              const SizedBox(height: 4),
              StatusBadge('fallback', variant: BadgeVariant.warning),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Loader(size: LoaderSize.sm),
      ),
    );
  }

  Widget _buildInput(TutorState ts) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Введите вопрос...',
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            'Отправить',
            busy: ts.sending,
            onPressed: ts.sending ? null : _send,
          ),
        ],
      ),
    );
  }
}
