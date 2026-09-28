import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/domain/lib/short_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Итог импорта: созданная тема + предупреждения (например, обрезанный
/// `one_liner`). Предупреждения не блокируют импорт — пользователь должен
/// увидеть, что именно было поправлено.
class ImportResult {
  final Topic topic;
  final List<String> warnings;
  const ImportResult({required this.topic, this.warnings = const []});
}

/// Ошибка импорта с понятным пользователю сообщением (показывается в UI).
class TopicImportException implements Exception {
  final String message;
  const TopicImportException(this.message);
  @override
  String toString() => message;
}

/// Экспорт/импорт темы целиком (дерево знаний + метаданные).
///
/// Формат файла и правила валидации — в `topic_file.dart`. Здесь только
/// оркестрация: собрать файл из БД, разобрать файл, пере-скоупить id под новую
/// тему и атомарно записать.
class TopicTransfer {
  final MindtreeRepository repo;
  const TopicTransfer(this.repo);

  /// Собирает JSON-файл темы. Бросает [TopicImportException], если темы нет
  /// или в ней нет ни одного узла.
  Future<String> exportTopicJson(String topicId) async {
    final bundle = await repo.getTopicWithNodes(topicId);
    if (bundle == null) {
      throw const TopicImportException('Тема не найдена');
    }
    if (bundle.nodes.isEmpty) {
      throw const TopicImportException(
        'В теме ещё нет узлов — экспортировать нечего',
      );
    }

    final file = TopicFile(
      sourceTopicId: bundle.topic.id,
      exportedAt: DateTime.now().toIso8601String(),
      topic: TopicFileMeta(
        name: bundle.topic.name,
        goal: bundle.topic.goal,
        targetLevel: bundle.topic.targetLevel,
        timeBudgetMinutes: bundle.topic.timeBudgetMinutes,
      ),
      nodes: bundle.nodes,
    );
    return file.toJsonString();
  }

  /// Имя файла по умолчанию: `mindtree-<slug>.json`.
  static String suggestedFileName(String topicName) {
    final slug = topicName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .replaceAll(RegExp(r'-{2,}'), '-');
    final safe = (slug.isEmpty ? 'topic' : slug);
    return 'mindtree-$safe.json';
  }

  /// Разбирает файл и создаёт НОВУЮ тему с деревом.
  ///
  /// Порядок важен: сначала формат, потом семантика, потом пере-скоупинг и
  /// только затем запись — так что в БД не попадает ничего частичного.
  Future<ImportResult> importTopicJson(String json) async {
    final TopicFile file;
    try {
      file = TopicFile.fromJsonString(json);
    } on TopicFileFormatException catch (e) {
      throw TopicImportException(e.message);
    }

    if (!file.isValid) {
      throw TopicImportException(
        'Файл повреждён или не соответствует формату MindTree:\n'
        '• ${file.errors.join('\n• ')}',
      );
    }

    final id = topicId();
    // id узлов переезжают под новую тему: knowledge_nodes.id — глобальный PK,
    // и старые id уедут в конфликт с уже существующими узлами.
    final nodes = rescopeNodes(file.nodes, file.sourceTopicId, id);

    final topic = Topic(
      id: id,
      name: file.topic.name,
      goal: file.topic.goal,
      targetLevel: file.topic.targetLevel,
      timeBudgetMinutes: file.topic.timeBudgetMinutes,
      createdAt: DateTime.now().toIso8601String(),
    );

    await repo.insertTopicWithNodes(topic, nodes);
    return ImportResult(topic: topic, warnings: file.warnings);
  }
}
