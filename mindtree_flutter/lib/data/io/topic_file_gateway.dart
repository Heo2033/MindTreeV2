import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'topic_transfer.dart';

/// Результат сохранения: куда именно лег файл.
class SavedFile {
  /// Абсолютный путь, если файл записан на диск.
  final String? path;

  /// `false`, если сохранение недоступно на платформе и пользователю нужно
  /// показать, куда он может скопировать файл вручную.
  final bool toDisk;
  const SavedFile(this.path, {this.toDisk = true});
}

/// Тонкий слой над системными диалогами выбора файлов.
///
/// Вся разборка/валидация/запись в БД живёт в `TopicTransfer` и покрыта
/// тестами; здесь только платформенные вызовы, которые в тестах не проверяются.
class TopicFileGateway {
  const TopicFileGateway();

  static const _typeGroup = XTypeGroup(
    label: 'MindTree',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
  );

  /// Открывает диалог выбора файла и читает его. `null` — пользователь отменил.
  Future<String?> pickTopicFile() async {
    final file = await openFile(acceptedTypeGroups: const [_typeGroup]);
    if (file == null) return null;
    return file.readAsString();
  }

  /// Сохраняет содержимое через системный диалог.
  ///
  /// На Android/iOS диалога «сохранить как» нет — там API бросает
  /// `UnimplementedError`. Вместо того чтобы ронять экспорт, пишем файл в
  /// каталог документов приложения и возвращаем путь: пользователь увидит его
  /// в сообщении (инвариант «fallback обязателен»).
  Future<SavedFile> saveTopicFile(String suggestedName, String content) async {
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [_typeGroup],
      );
      if (location == null) return SavedFile(null, toDisk: false);
      await File(location.path).writeAsString(content, flush: true);
      return SavedFile(location.path);
    } on UnimplementedError {
      final dir = await getApplicationDocumentsDirectory();
      final target = File('${dir.path}/$suggestedName');
      await target.writeAsString(content, flush: true);
      return SavedFile(target.path);
    } on FileSystemException catch (e) {
      throw TopicImportException('Не удалось сохранить файл: ${e.message}');
    }
  }
}
