// Регрессия бага «Bad state: Too many elements» на вкладке «Прогресс».
//
// Симптом (пользователь): прошёл учебную сессию, переключился на вкладку
// «Прогресс» (`ui/screens/analytics_screen.dart`) → `Bad state: Too many
// elements`.
//
// Корень: `LearningSessionEngine.create` при `journeyId == null` ВСЕГДА вызывал
// `repo.createJourney(...)`. UI (`providers/ui_stores.dart`) `journeyId` не
// передаёт, поэтому каждая сессия создавала НОВЫЙ journey для той же темы.
// После второй сессии в `learningJourneys` было две строки на один `topicId`,
// а `getJourneyForTopic` читал через `getSingleOrNull()` (внутри drift это
// `list.single`) → падение на экранах «Прогресс» и «Вехи».
//
// Закрывает главный инвариант фикса: ОДИН journey на тему, независимо от
// количества сессий. Движок — настоящий `LearningSessionEngine`, собранный
// фабрикой `buildEngines` (единственная точка обвязки по AGENTS.md), LLM
// заглушен детерминированным `FakeLlm` из `tool/probe/fake_llm.dart` —
// ни сети, ни ключей, ни Random() в пути.
//
// Плюс интеграция с экраном прогресса: `AnalyticsService.topicMetrics` на
// теме, где отработала сессия, не должна падать.
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _rootId = 'n1_topic~$_scope';

/// Число строк `learning_journeys` на тему — прямой признак бага.
Future<int> _journeyRows(MindtreeDb db, [String topicId = _topicId]) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM learning_journeys WHERE topic_id = ?',
        variables: [Variable<String>(topicId)],
      )
      .getSingle();
  return row.read<int>('c');
}

/// Учебные узлы уровня 2 — именно они попадают в план сессии.
KnowledgeNode _child(int i) => KnowledgeNode(
      id: 'n2_topic_$i~$_scope',
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие $i',
      oneLiner: 'Суть понятия $i в одном предложении.',
      details: 'Подробности понятия $i.',
      estimatedTimeMinutes: 5,
    );

/// Корень темы. Не попадает в план, но нужен для дерева.
KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзорная тема раздела.',
      details: 'Подробности корня.',
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    final fake = FakeLlm();
    engines = buildEngines(
      repo: repo,
      configProvider: () =>
          const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
      schedulerConfig: const SchedulerConfig(
        maxRPM: 100000,
        maxRPD: 100000,
        maxConcurrency: 1,
        maxRetries: 0,
      ),
      llmCall: (cfg, prompt, {model, temperature, seed}) async =>
          fake.invoke(cfg, prompt, model: model, temperature: temperature),
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([_root(), _child(1), _child(2), _child(3)]);
  });

  tearDown(() async {
    await db.close();
  });

  CreateSessionInput input({String? journeyId}) => CreateSessionInput(
        journeyId: journeyId,
        topicId: _topicId,
        goal: 'понимание',
        timeBudgetMinutes: 30,
      );

  group('Инвариант: один journey на тему (корень бага)', () {
    test('первая сессия создаёт ровно один journey', () async {
      final session = await engines.session.create(input());

      expect(await _journeyRows(db), 1);
      expect(session.journeyId, isNotEmpty);
      expect(await repo.getJourneyForTopic(_topicId), isNotNull);
    });

    test('две сессии подряд дают ОДНУ journey-строку', () async {
      // Ключевая регрессия: раньше здесь появлялось 2 строки, и
      // getJourneyForTopic падал с «Bad state: Too many elements».
      await engines.session.create(input());
      await engines.session.create(input());

      expect(await _journeyRows(db), 1,
          reason: 'вторая сессия обязана переиспользовать journey темы');
    });

    test('вторая сессия ссылается на тот же journeyId', () async {
      final first = await engines.session.create(input());
      final second = await engines.session.create(input());

      expect(second.journeyId, first.journeyId);
      // Id самих сессий, наоборот, разные — это норм.
      expect(second.id, isNot(first.id));
    });

    test('пять сессий подряд — всё ещё одна journey-строка', () async {
      for (var i = 0; i < 5; i++) {
        await engines.session.create(input());
      }

      expect(await _journeyRows(db), 1);
    });

    test('после сессий чтение journey не падает', () async {
      // Пользовательский сценарий: отучился, открыл «Прогресс».
      await engines.session.create(input());
      await engines.session.create(input());

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey, isNotNull);
      expect(journey!.id, (await repo.getJourneyForTopic(_topicId))!.id);
    });

    test('journey темы не зависит от числа сессий другой темы', () async {
      await repo.createTopic(const Topic(id: 't2', name: 'Другая тема'));
      await engines.session.create(input());
      await engines.session.create(CreateSessionInput(
        topicId: 't2',
        goal: 'понимание',
        timeBudgetMinutes: 30,
      ));

      expect(await _journeyRows(db, _topicId), 1);
      expect(await _journeyRows(db, 't2'), 1,
          reason: 'у каждой темы свой journey');
    });
  });

  group('Явный journeyId: поведение не изменилось', () {
    test('переданный journeyId не создаёт новую journey', () async {
      final journey = await repo.createJourney('j_explicit', _topicId);

      final session = await engines.session.create(input(journeyId: 'j_explicit'));

      expect(await _journeyRows(db), 1);
      expect(session.journeyId, journey.id);
    });

    test('явный journeyId переиспользуется на второй сессии тоже', () async {
      await repo.createJourney('j_explicit', _topicId);

      await engines.session.create(input(journeyId: 'j_explicit'));
      await engines.session.create(input(journeyId: 'j_explicit'));

      expect(await _journeyRows(db), 1);
    });

    test('явный journeyId при уже существующей journey темы не плодит дубль',
        () async {
      // На теме уже есть journey от первой сессии; пользователь явно просит
      // конкретную — новых journey на тему создаваться не должно.
      await engines.session.create(input());
      await repo.createJourney('j_explicit', _topicId);

      await engines.session.create(input(journeyId: 'j_explicit'));

      expect(await _journeyRows(db), 2,
          reason: 'две строки — это ожидаемо: старая от первой сессии + явно '
              'запрошенная; третья появиться не должна');
    });

    test('явный journeyId несуществующей journey принимается как есть',
        () async {
      // ФАКТИЧЕСКОЕ поведение фикса: явный journeyId НЕ валидируется на
      // существование — движок берёт его дословно. Проверка существования
      // (`repo.getJourney`) в `create` отсутствует.
      //
      // Последствие: сессия может сослаться на journey, которой нет в БД.
      // Это не роняет «Прогресс», потому что `AnalyticsService` считает по
      // `listSessionsForTopic` (по topicId), а не по journey. Но такая
      // сессия выпадает из journey-выгрузок и при `onDelete: cascade`
      // по теме остаётся сиротой. Прод НЕ трогаем.
      final session =
          await engines.session.create(input(journeyId: 'j_не_существует'));

      expect(session.journeyId, 'j_не_существует');
      // Journey на тему при этом не создаётся — движок доверяет входному id.
      expect(await _journeyRows(db), 0);
      // Сессия всё равно видна в разборе сессий по теме: FK выключен, а
      // «Прогресс» считает по topicId, не проходя через journey.
      expect(await repo.listSessionsForTopic(_topicId), hasLength(1));
      final metrics = await engines.analytics.topicMetrics(_topicId);
      expect(metrics, isNotNull, reason: '«Прогресс» не падает на dangling journey_id');
      expect(metrics!.topicId, _topicId);
    });

    test('явный journeyId другой темы не плодит journey темы', () async {
      await repo.createTopic(const Topic(id: 't2', name: 'Другая тема'));
      await repo.createJourney('j_t2', 't2');

      final session =
          await engines.session.create(input(journeyId: 'j_t2'));

      expect(session.journeyId, 'j_t2');
      expect(await _journeyRows(db, _topicId), 0,
          reason: 'journey чужой темы не должен создаваться у нашей');
      expect(await _journeyRows(db, 't2'), 1);
    });
  });

  group('Интеграция: вкладка «Прогресс» после сессии', () {
    test('topicMetrics работает после одной сессии', () async {
      // AnalyticsService.topicMetrics → getJourneyForTopic + getLearnerModel:
      // именно эти два чтения роняли экран.
      await engines.session.create(input());

      final metrics = await engines.analytics.topicMetrics(_topicId);

      expect(metrics, isNotNull);
      expect(metrics!.topicId, _topicId);
      expect(metrics.topicName, 'Теорема остановки');
    });

    test('topicMetrics работает после двух сессий подряд', () async {
      // Точный пользовательский сценарий: «прошёл сессию, посмотрел прогресс».
      await engines.session.create(input());
      await engines.session.create(input());

      final metrics = await engines.analytics.topicMetrics(_topicId);

      expect(metrics, isNotNull);
      expect(metrics!.topicId, _topicId);
    });

    test('topicMetrics после пройденного пункта плана не падает', () async {
      final session = await engines.session.create(input());
      final item = session.curriculum.items.first;
      await engines.session.markItemCompleted(session.id, item.id, nodeId: item.nodeId);

      final metrics = await engines.analytics.topicMetrics(_topicId);

      expect(metrics, isNotNull);
      expect(metrics!.conceptCount, greaterThan(0),
          reason: 'пройденный пункт должен попасть в мастери');
    });

    test('summary() по всем темам работает после сессий', () async {
      // summary() тоже зовёт getJourneyForTopic для каждой темы.
      await engines.session.create(input());
      await engines.session.create(input());

      final summary = await engines.analytics.summary();

      expect(summary.topics, hasLength(1));
      expect(summary.totals.totalSessions, 2);
    });

    test('topicMetrics для темы без сессий не падает', () async {
      final metrics = await engines.analytics.topicMetrics(_topicId);

      expect(metrics, isNotNull);
      expect(metrics!.studyMinutes, 0);
    });

    test('topicMetrics для несуществующей темы возвращает null', () async {
      expect(await engines.analytics.topicMetrics('нет-такой'), isNull);
    });

    test('пять сессий подряд — экран прогресса всё ещё жив', () async {
      for (var i = 0; i < 5; i++) {
        await engines.session.create(input());
      }

      expect(await _journeyRows(db), 1);
      expect(await engines.analytics.topicMetrics(_topicId), isNotNull);
    });
  });

  group('Регрессия на грязной базе: движок не плодит новый дубль', () {
    test('при уже существующем дубле journey сессия не добавляет третью',
        () async {
      // Эмулируем базу, доставшуюся от старой сборки: две journey на тему.
      await db.into(db.learningJourneys).insert(
            LearningJourneysCompanion.insert(
              id: 'j_legacy_1',
              topicId: _topicId,
              createdAt: Value(DateTime.utc(2024, 1, 1)),
            ),
          );
      await db.into(db.learningJourneys).insert(
            LearningJourneysCompanion.insert(
              id: 'j_legacy_2',
              topicId: _topicId,
              createdAt: Value(DateTime.utc(2024, 6, 1)),
            ),
          );

      final session = await engines.session.create(input());

      expect(await _journeyRows(db), 2,
          reason: 'движок переиспользует существующий journey и не плодит новый');
      expect(['j_legacy_1', 'j_legacy_2'], contains(session.journeyId));
    });

    test('на грязной базе сессия и экран прогресса работают вместе', () async {
      await db.into(db.learningJourneys).insert(
            LearningJourneysCompanion.insert(
              id: 'j_legacy_1',
              topicId: _topicId,
              createdAt: Value(DateTime.utc(2024, 1, 1)),
            ),
          );
      await db.into(db.learningJourneys).insert(
            LearningJourneysCompanion.insert(
              id: 'j_legacy_2',
              topicId: _topicId,
              createdAt: Value(DateTime.utc(2024, 6, 1)),
            ),
          );

      await engines.session.create(input());
      await engines.session.create(input());

      expect(await engines.analytics.topicMetrics(_topicId), isNotNull);
      expect(await engines.analytics.summary(), isNotNull);
      expect(await _journeyRows(db), 2);
    });
  });
}





