import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/data/io/topic_file_gateway.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/topic_transfer_store.dart';
import 'package:mindtree_flutter/ui/screens/home_screen.dart';

/// Подменяет системные диалоги `file_selector`: в тестах платформенный канал
/// недоступен, поэтому фейк отвечает заранее заданным содержимым.
class FakeGateway extends TopicFileGateway {
  /// `null` — пользователь отменил диалог.
  final String? fileToPick;
  final SavedFile? saveResult;
  final List<({String name, String content})> saved = [];

  FakeGateway({this.fileToPick, this.saveResult});

  @override
  Future<String?> pickTopicFile() async => fileToPick;

  @override
  Future<SavedFile> saveTopicFile(String suggestedName, String content) async {
    saved.add((name: suggestedName, content: content));
    return saveResult ?? const SavedFile('/tmp/out.json');
  }
}

const _srcTopic = 'topic_src_widget';

/// Одноузловое дерево из двух уровней: корень + ребёнок.
List<KnowledgeNode> _tree() {
  final s = scopedSuffix(_srcTopic);
  return [
    KnowledgeNode(
      id: 'n1_root$s',
      topicId: _srcTopic,
      parentId: null,
      level: 1,
      label: 'Корень темы',
      oneLiner: 'Обзор.',
      details: 'Подробное описание корня.',
    ),
    KnowledgeNode(
      id: 'n2_child$s',
      topicId: _srcTopic,
      parentId: 'n1_root$s',
      level: 2,
      label: 'Раздел',
      oneLiner: 'Подраздел.',
      details: 'Подробное описание раздела.',
    ),
  ];
}

/// Валидный файл темы для импорта.
String _validTopicFile() => TopicFile(
  sourceTopicId: _srcTopic,
  exportedAt: '2026-01-01T00:00:00.000Z',
  topic: const TopicFileMeta(name: 'Импортированная тема'),
  nodes: _tree(),
).toJsonString();

/// Поднимает `HomeScreen` поверх in-memory БД. Если [seed] задан, БД создаётся
/// один раз и используется и для сидирования, и для провайдера — иначе тема
/// была бы засеяна в одну базу, а экран читал бы другую.
Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required FakeGateway gateway,
  Future<void> Function(MindtreeRepository repo)? seed,
}) async {
  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);
  if (seed != null) await seed(MindtreeRepository(db));

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) async => db),
      topicFileGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('импорт создаёт тему и подтверждает результат', (tester) async {
    final container = await _pumpHome(
      tester,
      gateway: FakeGateway(fileToPick: _validTopicFile()),
    );

    expect(find.text('Пока нет тем...'), findsOneWidget);

    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();

    // Тема появилась в списке и сохранилась в БД под новым id.
    expect(find.text('Импортированная тема'), findsOneWidget);
    final repo = await container.read(repositoryProvider.future);
    final topics = await repo.listTopics();
    expect(topics.map((t) => t.name), contains('Импортированная тема'));

    final imported = topics.firstWhere((t) => t.name == 'Импортированная тема');
    expect(imported.id, isNot(_srcTopic)); // не перезаписала исходную тему
    expect(await repo.listNodes(imported.id), hasLength(2));

    expect(find.textContaining('импортирована'), findsOneWidget);
  });

  testWidgets('битый файл показывает ошибку и не добавляет тему', (
    tester,
  ) async {
    final container = await _pumpHome(
      tester,
      gateway: FakeGateway(fileToPick: 'не json вовсе'),
    );

    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();

    final repo = await container.read(repositoryProvider.future);
    expect(await repo.listTopics(), isEmpty);
    expect(find.text('Пока нет тем...'), findsOneWidget);
    // Показывается конкретная причина, а не обёртка «не удалось импортировать».
    expect(find.textContaining('корректным JSON'), findsOneWidget);
  });

  testWidgets('отмена диалога импорта не показывает сообщение', (tester) async {
    await _pumpHome(tester, gateway: FakeGateway(fileToPick: null));

    await tester.tap(find.text('Импорт'));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет тем...'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('экспорт пишет файл и показывает путь', (tester) async {
    final gateway = FakeGateway(
      saveResult: const SavedFile('/tmp/mindtree-файл.json'),
    );
    await _pumpHome(
      tester,
      gateway: gateway,
      seed: (repo) => repo.insertTopicWithNodes(
        const Topic(id: _srcTopic, name: 'Математический анализ'),
        _tree(),
      ),
    );

    await tester.tap(find.byTooltip('Экспорт в файл'));
    await tester.pumpAndSettle();

    // Имя файла — безопасный slug, содержимое — валидный файл темы.
    expect(gateway.saved, hasLength(1));
    expect(gateway.saved.single.name, 'mindtree-математический-анализ.json');
    final parsed = TopicFile.fromJsonString(gateway.saved.single.content);
    expect(parsed.isValid, isTrue);
    expect(parsed.sourceTopicId, _srcTopic);
    expect(parsed.nodes, hasLength(2));

    expect(find.textContaining('Тема сохранена'), findsOneWidget);
    expect(find.textContaining('mindtree-файл.json'), findsOneWidget);
  });

  testWidgets('экспорт темы без узлов объясняет, почему не вышло', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await _pumpHome(
      tester,
      gateway: gateway,
      seed: (repo) => repo.insertTopicWithNodes(
        const Topic(id: 'topic_empty', name: 'Пустая тема'),
        const [],
      ),
    );

    await tester.tap(find.byTooltip('Экспорт в файл'));
    await tester.pumpAndSettle();

    expect(gateway.saved, isEmpty); // до диалога сохранения не дошли
    expect(find.textContaining('узлов'), findsOneWidget);
  });
}
