// Разовая проверка паритета формата: печатает эталонный JSON файла темы.
// Запуск: dart run tool/topic_file_fixture.dart
import 'dart:io';

import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

const srcTopic = 'topic_src_aaaa';
const newTopic = 'topic_new_bbbb';

List<KnowledgeNode> tree() {
  final s = scopedSuffix(srcTopic);
  return [
    KnowledgeNode(
      id: 'n1_root$s',
      topicId: '',
      parentId: null,
      level: 1,
      label: 'Корень',
      oneLiner: 'Обзор темы.',
      details: 'Подробное описание Корня.',
      relations: [
        Relation(
          from: 'n1_root$s',
          to: 'n2_a$s',
          type: RelationType.dependsOn,
          label: 'часть',
        ),
      ],
      sequences: [
        Sequence(
          id: 'seq1',
          label: 'Путь',
          steps: [
            SequenceStep(conceptId: 'n2_a$s', order: 0, label: 'первый'),
            SequenceStep(conceptId: 'n4_b$s', order: 1),
          ],
        ),
      ],
    ),
    KnowledgeNode(
      id: 'n2_a$s',
      topicId: '',
      parentId: 'n1_root$s',
      level: 2,
      label: 'Ветка А',
      oneLiner: 'Описание А.',
      details: 'Подробное описание А.',
      conceptType: ConceptType.mechanism,
      analogy: 'Как шестерёнка.',
      leaf: false,
    ),
    KnowledgeNode(
      id: 'n3_a1$s',
      topicId: '',
      parentId: 'n2_a$s',
      level: 3,
      label: 'Лист А1',
      oneLiner: 'Описание А1.',
      details: 'Подробное описание А1.',
    ),
    KnowledgeNode(
      id: 'n4_b$s',
      topicId: '',
      parentId: 'n1_root$s',
      level: 2,
      label: 'Ветка Б',
      oneLiner: 'Описание Б.',
      details: 'Подробное описание Б.',
      sources: ['src-1'],
    ),
  ];
}

/// Дерево с заведомо длинным `one_liner` — нормализуется при разборе.
List<KnowledgeNode> treeWithLongOneLiner() {
  final s = scopedSuffix(srcTopic);
  return [
    KnowledgeNode(
      id: 'n1_root$s',
      topicId: '',
      parentId: null,
      level: 1,
      label: 'Корень',
      oneLiner: 'я' * 200,
      details: 'Подробное описание Корня.',
    ),
  ];
}

void main() {
  final file = TopicFile(
    sourceTopicId: srcTopic,
    exportedAt: '2026-01-01T00:00:00.000Z',
    topic: const TopicFileMeta(
      name: 'Математический анализ',
      timeBudgetMinutes: 90,
    ),
    nodes: tree(),
  );
  final text = file.toJsonString();

  // Валидный файл должен переживать разбор без изменений (идемпотентность).
  final again = TopicFile.fromJsonString(text).toJsonString();
  if (again != text) {
    stderr.writeln('DART: FAIL — второй проход валидного файла отличается');
    exit(1);
  }
  if (file.errors.isNotEmpty) {
    stderr.writeln('DART: FAIL — эталонное дерево невалидно: ${file.errors}');
    exit(1);
  }

  // Нормализация длинного one_liner: обрезка + предупреждение, не ошибка.
  final long = TopicFile.fromJsonString(
    TopicFile(
      sourceTopicId: srcTopic,
      exportedAt: '2026-01-01T00:00:00.000Z',
      topic: const TopicFileMeta(name: 'Длинный one_liner'),
      nodes: treeWithLongOneLiner(),
    ).toJsonString(),
  );
  if (long.errors.isNotEmpty || long.warnings.isEmpty) {
    stderr.writeln(
      'DART: FAIL — обрезка one_liner: '
      'errors=${long.errors} warnings=${long.warnings}',
    );
    exit(1);
  }
  if (long.nodes.single.oneLiner.length != kOneLinerMaxLength) {
    stderr.writeln('DART: FAIL — one_liner не обрезан');
    exit(1);
  }

  // Rescope тоже должен быть стабильным.
  final rescoped = rescopeNodes(
    TopicFile.fromJsonString(text).nodes,
    srcTopic,
    newTopic,
  );

  stdout.write(text);
  stderr.writeln(
    'DART OK: oneLiner=${long.nodes.single.oneLiner.length} '
    'warnings=${long.warnings} rescopedIds=${rescoped.map((e) => e.id).toList()}',
  );
}
