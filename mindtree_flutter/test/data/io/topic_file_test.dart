import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/data/io/topic_transfer.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

const _topicA = 'topic_src_aaaa';

/// Плоский список из `nestNodes` обратно — для проверок без файлов.
List<KnowledgeNode> _roundTrip(List<KnowledgeNode> flat) {
  final json = TopicFile(
    sourceTopicId: _topicA,
    topic: const TopicFileMeta(name: 'Тема'),
    nodes: flat,
  ).toJson();
  return TopicFile.fromJson(json).nodes;
}

KnowledgeNode _n(
  String id,
  String? parentId,
  int level,
  String label, {
  String oneLiner = 'Краткое определение.',
  List<Relation> relations = const [],
  List<Sequence> sequences = const [],
}) => KnowledgeNode(
  id: id,
  topicId: '',
  parentId: parentId,
  level: level,
  label: label,
  oneLiner: oneLiner,
  details: 'Подробное описание $label.',
  relations: relations,
  sequences: sequences,
);

/// Дерево из 3 уровней: root -> a -> a1, root -> b.
List<KnowledgeNode> _tree3() {
  final s = scopedSuffix(_topicA);
  return [
    _n(
      'n1_root$s',
      null,
      1,
      'Корень',
      oneLiner: 'Обзор темы.',
      relations: [
        Relation(
          from: 'n1_root$s',
          to: 'n2_a$s',
          type: RelationType.related,
          label: 'часть',
        ),
      ],
      sequences: [
        Sequence(
          id: 'seq1',
          label: 'Путь',
          steps: [
            SequenceStep(conceptId: 'n2_a$s', order: 0, label: 'первый'),
            SequenceStep(conceptId: 'n4_b$s', order: 1, label: 'второй'),
          ],
        ),
      ],
    ),
    _n('n2_a$s', 'n1_root$s', 2, 'Ветка А'),
    _n('n3_a1$s', 'n2_a$s', 3, 'Лист А1'),
    _n('n4_b$s', 'n1_root$s', 2, 'Ветка Б'),
  ];
}

void main() {
  group('TopicFile — round-trip', () {
    test('плоский → JSON → плоский сохраняет все поля узлов', () {
      final original = _tree3();
      final result = _roundTrip(original);

      expect(result.length, original.length);
      for (var i = 0; i < original.length; i++) {
        final a = original[i];
        final b = result[i];
        expect(b.id, a.id);
        expect(b.parentId, a.parentId);
        expect(b.level, a.level);
        expect(b.label, a.label);
        expect(b.oneLiner, a.oneLiner);
        expect(b.details, a.details);
        expect(b.relations.length, a.relations.length);
        expect(b.sequences.length, a.sequences.length);
      }
    });

    test('relations и sequences переживают round-trip без потерь', () {
      final result = _roundTrip(_tree3());
      final root = result.first;

      expect(root.relations.single.from, root.id);
      expect(root.relations.single.to, result[1].id);
      expect(root.relations.single.label, 'часть');
      expect(root.sequences.single.steps.length, 2);
      expect(root.sequences.single.steps.first.conceptId, result[1].id);
      expect(root.sequences.single.steps.last.conceptId, result[3].id);
    });

    test('в файле дерево вложенное: у корня есть children, у листа пусто', () {
      final json = TopicFile(
        sourceTopicId: _topicA,
        topic: const TopicFileMeta(name: 'Тема'),
        nodes: _tree3(),
      ).toJson();

      final root =
          (json['tree']! as Map<String, dynamic>)['nodes'].first
              as Map<String, dynamic>;
      final children = root['children']! as List;
      expect(children.length, 2);

      final leaf = children.first as Map<String, dynamic>;
      final leafChild =
          (leaf['children']! as List).first as Map<String, dynamic>;
      expect(leafChild['children'], isEmpty);
      expect(leafChild['leaf'], isTrue);
    });

    test(
      'в узлах файла нет topicId / parentId / level — они из вложенности',
      () {
        final json = TopicFile(
          sourceTopicId: _topicA,
          topic: const TopicFileMeta(name: 'Тема'),
          nodes: _tree3(),
        ).toJson();

        final root =
            (json['tree']! as Map<String, dynamic>)['nodes'].first
                as Map<String, dynamic>;
        expect(root.containsKey('topicId'), isFalse);
        expect(root.containsKey('parentId'), isFalse);
        expect(root.containsKey('level'), isFalse);
      },
    );

    test('конверт несёт format/version/source/topic', () {
      final json = TopicFile(
        sourceTopicId: _topicA,
        topic: const TopicFileMeta(
          name: 'Математический анализ',
          timeBudgetMinutes: 90,
        ),
        nodes: _tree3(),
      ).toJson();

      expect(json['format'], kTopicFileFormat);
      expect(json['version'], kTopicFileVersion);
      expect((json['source']! as Map)['topicId'], _topicA);
      expect((json['topic']! as Map)['name'], 'Математический анализ');
      expect((json['topic']! as Map)['timeBudgetMinutes'], 90);
    });

    test('toJsonString даёт валидный JSON, читаемый обратно', () {
      final text = TopicFile(
        sourceTopicId: _topicA,
        topic: const TopicFileMeta(name: 'Тема'),
        nodes: _tree3(),
      ).toJsonString();

      final parsed = TopicFile.fromJsonString(text);
      expect(parsed.isValid, isTrue);
      expect(parsed.nodes.length, 4);
    });
  });

  group('TopicFile — отказ на некорректном файле', () {
    String wrap(String body) =>
        '{"format":"mindtree.topic","version":1,'
        '"source":{"topicId":"t"},"topic":{"name":"X"},$body}';

    test('чужой format', () {
      expect(
        () => TopicFile.fromJsonString('{"format":"other","version":1}'),
        throwsA(isA<TopicFileFormatException>()),
      );
    });

    test('версия из будущего', () {
      expect(
        () => TopicFile.fromJsonString(
          '{"format":"mindtree.topic","version":999,"topic":{"name":"X"},'
          '"tree":{"nodes":[{"id":"a"}]}}',
        ),
        throwsA(
          predicate(
            (e) => e is TopicFileFormatException && e.message.contains('999'),
          ),
        ),
      );
    });

    test('пустое дерево', () {
      expect(
        () => TopicFile.fromJsonString(wrap('"tree":{"nodes":[]}')),
        throwsA(
          predicate(
            (e) =>
                e is TopicFileFormatException &&
                e.message.contains('tree.nodes'),
          ),
        ),
      );
    });

    test('пустое имя темы', () {
      expect(
        () => TopicFile.fromJsonString(
          '{"format":"mindtree.topic","version":1,"topic":{"name":"  "},'
          '"tree":{"nodes":[{"id":"a"}]}}',
        ),
        throwsA(isA<TopicFileFormatException>()),
      );
    });

    test('не JSON', () {
      expect(
        () => TopicFile.fromJsonString('не json вовсе'),
        throwsA(isA<TopicFileFormatException>()),
      );
    });
  });

  group('validateImport', () {
    TopicFile fileOf(List<KnowledgeNode> nodes) => TopicFile(
      sourceTopicId: _topicA,
      topic: const TopicFileMeta(name: 'X'),
      nodes: nodes,
    );

    test('корректное дерево — без ошибок', () {
      expect(validateImport(fileOf(_tree3())), isEmpty);
    });

    test('два корня — ошибка', () {
      final s = scopedSuffix(_topicA);
      final errors = validateImport(
        fileOf([
          _n('a$s', null, 1, 'Первый корень'),
          _n('b$s', null, 1, 'Второй корень'),
        ]),
      );
      expect(errors.join(' '), contains('корней'));
    });

    test('висячий parentId — ошибка', () {
      final s = scopedSuffix(_topicA);
      final errors = validateImport(
        fileOf([
          _n('a$s', null, 1, 'Корень'),
          _n('b$s', 'нет_такого$s', 2, 'Сирота'),
        ]),
      );
      expect(errors.join(' '), contains('родител'));
    });

    test('цикл — ошибка', () {
      final s = scopedSuffix(_topicA);
      final errors = validateImport(
        fileOf([_n('a$s', 'b$s', 2, 'A'), _n('b$s', 'a$s', 2, 'B')]),
      );
      expect(errors, isNotEmpty);
    });

    test('дубликаты id — ошибка', () {
      final s = scopedSuffix(_topicA);
      final errors = validateImport(
        fileOf([_n('a$s', null, 1, 'Корень'), _n('a$s', 'a$s', 2, 'Дубль')]),
      );
      expect(errors.join(' '), contains('Дублирующиеся id'));
    });

    test('пустой label — ошибка', () {
      final s = scopedSuffix(_topicA);
      final errors = validateImport(
        fileOf([_n('a$s', null, 1, 'Корень'), _n('b$s', 'a$s', 2, '   ')]),
      );
      expect(errors.join(' '), contains('пустым названием'));
    });

    test('one_liner > 120 символов — обрезка и предупреждение, не ошибка', () {
      final s = scopedSuffix(_topicA);
      final long = 'я' * 200;
      final json = TopicFile(
        sourceTopicId: _topicA,
        topic: const TopicFileMeta(name: 'X'),
        nodes: [
          _n('a$s', null, 1, 'Корень'),
          _n('b$s', 'a$s', 2, 'Ветка', oneLiner: long),
        ],
      ).toJson();

      final parsed = TopicFile.fromJson(json);
      expect(parsed.isValid, isTrue);
      expect(parsed.warnings.join(' '), contains('one_liner'));
      expect(parsed.nodes[1].oneLiner.length, kOneLinerMaxLength);
    });
  });

  group('rescopeNodes', () {
    test('id, parentId, relations и sequences переезжают под новую тему', () {
      const newTopic = 'topic_new_bbbb';
      final s = scopedSuffix(_topicA);
      final n = scopedSuffix(newTopic);
      final result = rescopeNodes(_tree3(), _topicA, newTopic);

      final ids = result.map((e) => e.id).toSet();
      expect(ids.every((id) => id.endsWith(n)), isTrue);
      expect(ids.contains('n1_root$n'), isTrue);
      expect(ids.contains('n1_root$s'), isFalse);

      // parentId указывает на пере-скоупленный id
      final branch = result.firstWhere((e) => e.label == 'Ветка А');
      expect(ids.contains(branch.parentId), isTrue);

      // relations переписаны
      final root = result.firstWhere((e) => e.label == 'Корень');
      expect(ids.contains(root.relations.single.from), isTrue);
      expect(ids.contains(root.relations.single.to), isTrue);

      // sequences.steps[].conceptId переписаны
      for (final st in root.sequences.single.steps) {
        expect(ids.contains(st.conceptId), isTrue);
      }

      // topicId проставлен, уровни сохранены
      expect(result.every((e) => e.topicId == newTopic), isTrue);
      expect(result.map((e) => e.level).toList(), [1, 2, 3, 2]);
    });

    test('ссылка на неизвестный узел не роняет и не теряется', () {
      const newTopic = 'topic_new_cccc';
      final s = scopedSuffix(_topicA);
      final nodes = [
        _n(
          'a$s',
          null,
          1,
          'Корень',
          relations: [
            Relation(from: 'a$s', to: 'чужак$s', type: RelationType.related),
          ],
        ),
      ];

      final result = rescopeNodes(nodes, _topicA, newTopic);
      expect(result.single.relations.single.to, 'чужак$s');
    });

    test('пустой список — пустой результат', () {
      expect(rescopeNodes(const [], _topicA, 'topic_x'), isEmpty);
    });
  });

  group('репозиторий: транзакционная вставка', () {
    late MindtreeDb db;
    late MindtreeRepository repo;
    late TopicTransfer transfer;

    setUp(() async {
      db = MindtreeDb(NativeDatabase.memory());
      repo = MindtreeRepository(db);
      transfer = TopicTransfer(repo);
    });

    tearDown(() async {
      await db.close();
    });

    test('экспорт → импорт даёт идентичное дерево под новым id', () async {
      final src = _tree3().map((n) => n.copyWith(topicId: _topicA)).toList();
      await repo.insertTopicWithNodes(
        const Topic(id: _topicA, name: 'Математический анализ'),
        src,
      );

      final json = await transfer.exportTopicJson(_topicA);
      final result = await transfer.importTopicJson(json);

      final imported = await repo.listNodes(result.topic.id);
      expect(imported.length, src.length);
      // структура совпадает, id пере-скоуплены, но форма те же
      expect(
        imported.map((n) => n.level).toList(),
        src.map((n) => n.level).toList(),
      );
      expect(
        imported.map((n) => n.label).toList(),
        src.map((n) => n.label).toList(),
      );
      expect(imported.every((n) => n.topicId == result.topic.id), isTrue);
      // обе темы живы
      expect((await repo.listTopics()).length, 2);
    });

    test('импорт дважды одного файла не падает на конфликте id', () async {
      final src = _tree3().map((n) => n.copyWith(topicId: _topicA)).toList();
      await repo.insertTopicWithNodes(
        const Topic(id: _topicA, name: 'Тема'),
        src,
      );
      final json = await transfer.exportTopicJson(_topicA);

      await transfer.importTopicJson(json);
      await transfer.importTopicJson(
        json,
      ); // второй раз — id уже пере-скоуплены

      expect((await repo.listTopics()).length, 3);
    });

    test('транзакция откатывается: конфликт id не оставляет тему', () async {
      // Занять id узла чужой темой, затем вставить тему с узлом-дубликатом.
      // Вставка темы идёт ПЕРВОЙ, падать будет на узле — значит откатиться
      // должна и тема тоже (иначе осталась бы тема без содержимого).
      const taken = 'n1_root~ffffffff';
      await repo.insertTopicWithNodes(
        const Topic(id: 'topic_other', name: 'Другая'),
        [_n(taken, null, 1, 'Занятый').copyWith(topicId: 'topic_other')],
      );
      final before = (await repo.listTopics()).length;

      await expectLater(
        repo.insertTopicWithNodes(
          const Topic(id: 'topic_new_dddd', name: 'Конфликт темы'),
          [
            _n(
              'own_root~00000000',
              null,
              1,
              'Свой узел',
            ).copyWith(topicId: 'topic_new_dddd'),
            _n(
              taken,
              'own_root~00000000',
              2,
              'Дубль узла',
            ).copyWith(topicId: 'topic_new_dddd'),
          ],
        ),
        throwsA(anything),
      );

      // Ни темы, ни её узлов в базе нет.
      expect(await repo.getTopic('topic_new_dddd'), isNull);
      expect(await repo.listNodes('topic_new_dddd'), isEmpty);
      expect((await repo.listTopics()).length, before);
    });

    test('битый файл не создаёт ничего', () async {
      final before = (await repo.listTopics()).length;
      await expectLater(
        transfer.importTopicJson('{"format":"wrong"}'),
        throwsA(isA<TopicImportException>()),
      );
      expect((await repo.listTopics()).length, before);
    });

    test('файл с двумя корнями отклоняется с понятным сообщением', () async {
      final s = scopedSuffix(_topicA);
      final file = TopicFile(
        sourceTopicId: _topicA,
        topic: const TopicFileMeta(name: 'Два корня'),
        nodes: [_n('a$s', null, 1, 'Первый'), _n('b$s', null, 1, 'Второй')],
      );
      // Два корня выживают в JSON как два элемента в tree.nodes — импорт
      // обязан их отвергнуть, а не молча склеить.
      await expectLater(
        transfer.importTopicJson(file.toJsonString()),
        throwsA(
          predicate(
            (e) => e is TopicImportException && e.message.contains('корней'),
          ),
        ),
      );
      expect((await repo.listTopics()).isEmpty, isTrue);
    });

    test('экспорт пустой темы даёт понятную ошибку', () async {
      await repo.createTopic(const Topic(id: 'topic_empty', name: 'Пустая'));
      await expectLater(
        transfer.exportTopicJson('topic_empty'),
        throwsA(
          predicate(
            (e) => e is TopicImportException && e.message.contains('узлов'),
          ),
        ),
      );
    });

    test('экспорт несуществующей темы даёт понятную ошибку', () async {
      await expectLater(
        transfer.exportTopicJson('topic_missing'),
        throwsA(
          predicate(
            (e) =>
                e is TopicImportException && e.message.contains('не найдена'),
          ),
        ),
      );
    });

    test('suggestedFileName даёт безопасное имя .json', () {
      expect(
        TopicTransfer.suggestedFileName('Математический анализ'),
        'mindtree-математический-анализ.json',
      );
      expect(TopicTransfer.suggestedFileName('  ///  '), 'mindtree-topic.json');
      expect(TopicTransfer.suggestedFileName('C++ / Rust'), endsWith('.json'));
    });
  });
}
