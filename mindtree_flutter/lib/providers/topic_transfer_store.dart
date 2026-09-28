import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mindtree_flutter/data/io/topic_file_gateway.dart';
import 'package:mindtree_flutter/data/io/topic_transfer.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';

/// Что показать пользователю после действия.
class TransferFeedback {
  final bool ok;
  final String message;
  const TransferFeedback.ok(this.message) : ok = true;
  const TransferFeedback.fail(this.message) : ok = false;
}

class TopicTransferState {
  /// `true`, пока идёт диалог/чтение/запись — кнопки блокируются.
  final bool busy;
  const TopicTransferState({this.busy = false});

  TopicTransferState copyWith({bool? busy}) =>
      TopicTransferState(busy: busy ?? this.busy);
}

final topicTransferProvider =
    StateNotifierProvider<TopicTransferController, TopicTransferState>(
      TopicTransferController.new,
    );

/// Системные диалоги выбора файлов. Отдельный провайдер, чтобы в тестах можно
/// было подменить шлюз и не поднимать платформенный канал `file_selector`.
final topicFileGatewayProvider = Provider<TopicFileGateway>(
  (ref) => const TopicFileGateway(),
);

/// Оркестрирует импорт/экспорт для UI: системный диалог → `TopicTransfer` →
/// обновление списка тем. Возвращает сообщение для показа пользователю, а не
/// бросает — UI-ошибки не должны ронять экран.
class TopicTransferController extends StateNotifier<TopicTransferState> {
  final Ref _ref;

  TopicTransferController(this._ref) : super(const TopicTransferState());

  TopicFileGateway get _gateway => _ref.read(topicFileGatewayProvider);

  Future<TopicTransfer?> _transfer() async {
    try {
      return TopicTransfer(await _ref.read(repositoryProvider.future));
    } catch (_) {
      return null;
    }
  }

  /// Экспорт темы. `null` — пользователь отменил диалог.
  Future<TransferFeedback?> exportTopic(
    String topicId,
    String topicName,
  ) async {
    final transfer = await _transfer();
    if (transfer == null) {
      return const TransferFeedback.fail('База данных недоступна');
    }

    state = state.copyWith(busy: true);
    try {
      final json = await transfer.exportTopicJson(topicId);
      final name = TopicTransfer.suggestedFileName(topicName);
      final saved = await _gateway.saveTopicFile(name, json);
      if (!saved.toDisk) return null; // отмена диалога
      return TransferFeedback.ok('Тема сохранена: ${saved.path}');
    } on TopicImportException catch (e) {
      return TransferFeedback.fail(e.message);
    } catch (e) {
      return TransferFeedback.fail('Не удалось экспортировать тему: $e');
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Импорт темы из файла. `null` — пользователь отменил выбор файла.
  Future<TransferFeedback?> importTopic() async {
    final transfer = await _transfer();
    if (transfer == null) {
      return const TransferFeedback.fail('База данных недоступна');
    }

    state = state.copyWith(busy: true);
    try {
      final json = await _gateway.pickTopicFile();
      if (json == null) return null; // отмена выбора файла

      final result = await transfer.importTopicJson(json);
      await _ref.read(topicStoreProvider.notifier).loadTopics();

      final buffer = StringBuffer('Тема «${result.topic.name}» импортирована');
      if (result.warnings.isNotEmpty) {
        buffer.write('\n\nПредупреждения:\n');
        for (final w in result.warnings) {
          buffer.write('• $w\n');
        }
      }
      return TransferFeedback.ok(buffer.toString());
    } on TopicImportException catch (e) {
      return TransferFeedback.fail(e.message);
    } catch (e) {
      return TransferFeedback.fail('Не удалось импортировать файл: $e');
    } finally {
      state = state.copyWith(busy: false);
    }
  }
}
