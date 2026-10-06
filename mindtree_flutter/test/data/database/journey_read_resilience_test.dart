// Регрессия «Bad state: Too many elements» на чтении journey / learner model.
//
// Симптом (пользователь): после учебной сессии вкладка «Прогресс» падала с
// «Bad state: Too many elements».
//
// Причина: `MindtreeRepository.getJourneyForTopic` и `getLearnerModel` читали
// единственную строку через drift `getSingleOrNull()`, а внутри он делает
// `list.single` — на >1 строке это ровно то самое исключение. Дубли
// `learning_journeys` на одну тему оставляла старая сборка движка сессий
// (journey создавался на каждую сессию).
//
// Файл закрывает ЧТЕНИЕ на грязных данных (дубли уже в базе):
//   * `getJourneyForTopic` не бросает и отдаёт осмысленный journey;
//   * приоритет у journey, у которой ЕСТЬ вехи (там реальный прогресс);
//   * вех нет ни в одной строке → берётся самая свежая (createdAt DESC);
//   * journey для темы нет → null, без исключения;
//   * `getLearnerModel` на дублях отдаёт последнюю строку.
//
// Последняя группа файла — поиск незавершённой сессии темы (первый шаг фичи
// «resume после перезапуска приложения»): фильтр по статусу, выбор ровно
// одной сессии для UI и ДЕТЕРМИНИРОВАННЫЙ порядок при равных `startedAt`
// (startedAt DESC, затем id ASC — выбор не зависит от порядка строк SQLite).
//
// Тесты детерминированы: in-memory drift, никаких часов и никакого LLM.
// Время задаётся ЯВНО (`DateTime.utc(...)`), поэтому порядок строк не зависит
// от порядка вызовов внутри одного тика.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/milestone_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

const _topicId = 't1';

/// Вставляет journey напрямую в таблицу с заданным `createdAt`.
///
/// `repo.createJourney` ставит `createdAt = currentDateAndTime` (секундная
/// точность SQLite), поэтому две строки, созданные подряд, получили бы
/// одинаковую метку и порядок стал бы неопределённым. Для теста про порядок
/// метку задаём явно.
Future<void> _insertJourney(
  MindtreeDb db, {
  required String id,
  required DateTime createdAt,
  String topicId = _topicId,
}) {
  return db.into(db.learningJourneys).insert(
        LearningJourneysCompanion.insert(
          id: id,
          topicId: topicId,
          createdAt: Value(createdAt),
        ),
      );
}

/// Вставляет веху в указанный journey напрямую в таблицу.
///
/// Обход `repo.insertMilestones` сознателен: он не умеет задавать `journey_id`
/// (см. последний group этого файла про дефект привязки).
Future<void> _insertMilestone(
  MindtreeDb db, {
  required String id,
  required String journeyId,
  String level = 'basic_understanding',
  String title = 'Базовое понимание',
}) {
  return db.into(db.learningMilestones).insert(
        LearningMilestonesCompanion.insert(
          id: id,
          journeyId: journeyId,
          level: level,
          title: title,
        ),
      );
}

/// Вставляет сессию напрямую в таблицу с явными `startedAt` и `status`.
///
/// Обход `repo.createSession` обязателен: `Mappers.sessionToRow` НЕ передаёт
/// `startedAt` (колонка остаётся на default `currentDateAndTime`), поэтому
/// задать метку времени через доменную модель нельзя, а без явной метки
/// порядок строк в тесте зависел бы от системных часов.
Future<void> _insertSession(
  MindtreeDb db, {
  required String id,
  required String journeyId,
  required DateTime startedAt,
  SessionStatus status = SessionStatus.active,
  String topicId = _topicId,
}) {
  return db.into(db.learningSessions).insert(
        LearningSessionsCompanion.insert(
          id: id,
          journeyId: journeyId,
          topicId: topicId,
          startedAt: Value(startedAt),
          status: Value(status.raw),
        ),
      );
}

/// Снимает с `learner_models` ограничение `UNIQUE (user_id, topic_id)`.
///
/// В схеме UNIQUE есть, поэтому честными вставками дублей не создать — а
/// проверить устойчивость чтения надо именно на дублях. Пересоздание таблицы
/// без UNIQUE эмулирует БД, где дубль уже есть.
Future<void> _dropLearnerModelUnique(MindtreeDb db) async {
  await db.customStatement('ALTER TABLE learner_models RENAME TO learner_models__bak');
  await db.customStatement(
    'CREATE TABLE learner_models ('
    '"id" TEXT NOT NULL, '
    '"user_id" TEXT NOT NULL DEFAULT \'default\', '
    '"topic_id" TEXT NOT NULL, '
    '"overall_level" TEXT NOT NULL DEFAULT \'awareness\', '
    '"concept_masteries_json" TEXT NOT NULL DEFAULT \'[]\', '
    '"updated_at" INTEGER NOT NULL DEFAULT 0, '
    '"initial_overall_level" TEXT NOT NULL DEFAULT \'awareness\', '
    'PRIMARY KEY ("id"))',
  );
}

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
  });

  tearDown(() async {
    await db.close();
  });

  group('getJourneyForTopic: дубль journey на одну тему', () {
    test('две строки на тему не роняют чтение', () async {
      // Именно этот сценарий давал «Bad state: Too many elements».
      await _insertJourney(db, id: 'j_old', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_new', createdAt: DateTime.utc(2024, 6, 1));

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey, isNotNull);
      expect(journey!.topicId, _topicId);
    });

    test('дублей больше двух — тоже без исключения', () async {
      await _insertJourney(db, id: 'j1', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j2', createdAt: DateTime.utc(2024, 2, 1));
      await _insertJourney(db, id: 'j3', createdAt: DateTime.utc(2024, 3, 1));
      await _insertJourney(db, id: 'j4', createdAt: DateTime.utc(2024, 4, 1));

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey, isNotNull);
    });

    test('вех нет ни в одной строке → самая свежая (createdAt DESC)', () async {
      await _insertJourney(db, id: 'j_old', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_mid', createdAt: DateTime.utc(2024, 3, 1));
      await _insertJourney(db, id: 'j_new', createdAt: DateTime.utc(2024, 9, 1));

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey!.id, 'j_new');
      expect(journey.milestones, isEmpty);
    });

    test('journey с вехами побеждает более свежую без вех', () async {
      // Прогресс лежит в конкретной journey — потерять её нельзя, поэтому
      // приоритет у той, где вехи есть, даже если она создана раньше.
      await _insertJourney(db, id: 'j_with_ms', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_bare', createdAt: DateTime.utc(2030, 1, 1));
      await _insertMilestone(db, id: 'ms1', journeyId: 'j_with_ms');

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey!.id, 'j_with_ms');
      expect(journey.milestones.map((m) => m.id), ['ms1']);
    });

    test('у нескольких journey с вехами берётся самая свежая из них', () async {
      await _insertJourney(db, id: 'j_ms_old', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_ms_new', createdAt: DateTime.utc(2024, 5, 1));
      await _insertJourney(db, id: 'j_bare', createdAt: DateTime.utc(2030, 1, 1));
      await _insertMilestone(db, id: 'ms_old', journeyId: 'j_ms_old');
      await _insertMilestone(db, id: 'ms_new', journeyId: 'j_ms_new');

      final journey = await repo.getJourneyForTopic(_topicId);

      expect(journey!.id, 'j_ms_new');
      expect(journey.milestones.map((m) => m.id), ['ms_new']);
    });

    test('для темы без journey возвращается null, а не исключение', () async {
      final journey = await repo.getJourneyForTopic('темы-нет');

      expect(journey, isNull);
    });

    test('journey другой темы не подмешивается', () async {
      await repo.createTopic(const Topic(id: 't2', name: 'Другая тема'));
      await _insertJourney(db, id: 'j_t1', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(
        db,
        id: 'j_t2',
        createdAt: DateTime.utc(2030, 1, 1),
        topicId: 't2',
      );

      expect((await repo.getJourneyForTopic(_topicId))!.id, 'j_t1');
      expect((await repo.getJourneyForTopic('t2'))!.id, 'j_t2');
    });

    test('повторные чтения дублей стабильны (детерминированно)', () async {
      await _insertJourney(db, id: 'j_old', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_new', createdAt: DateTime.utc(2024, 6, 1));
      await _insertMilestone(db, id: 'ms1', journeyId: 'j_old');

      final first = await repo.getJourneyForTopic(_topicId);
      final second = await repo.getJourneyForTopic(_topicId);

      expect(first!.id, second!.id);
      expect(first.id, 'j_old');
    });
  });

  group('getLearnerModel: дубль learner model на пару (topicId, userId)', () {
    test('две строки на пару не роняют чтение, берётся последняя', () async {
      await _dropLearnerModelUnique(db);
      await db.into(db.learnerModels).insert(
            LearnerModelsCompanion.insert(
              id: 'lm_old',
              userId: const Value('default'),
              topicId: _topicId,
              overallLevel: const Value('awareness'),
              updatedAt: Value(DateTime.utc(2024, 1, 1)),
            ),
          );
      await db.into(db.learnerModels).insert(
            LearnerModelsCompanion.insert(
              id: 'lm_new',
              userId: const Value('default'),
              topicId: _topicId,
              overallLevel: const Value('expert'),
              updatedAt: Value(DateTime.utc(2030, 1, 1)),
            ),
          );

      final model = await repo.getLearnerModel(_topicId);

      expect(model, isNotNull, reason: 'дубли не должны ронять чтение');
      expect(model!.id, 'lm_new');
      expect(model.overallLevel.raw, 'expert');
    });

    test('единственная строка читается как раньше', () async {
      await repo.saveLearnerModel(const LearnerModel(
        id: 'lm1',
        userId: 'default',
        topicId: _topicId,
        overallLevel: MasteryLevel.solidUnderstanding,
      ));

      final model = await repo.getLearnerModel(_topicId);

      expect(model!.id, 'lm1');
      expect(model.overallLevel.raw, 'solid_understanding');
    });

    test('для темы без модели возвращается null, а не исключение', () async {
      expect(await repo.getLearnerModel('темы-нет'), isNull);
    });

    test('модель другого userId не подмешивается', () async {
      await _dropLearnerModelUnique(db);
      await db.into(db.learnerModels).insert(
            LearnerModelsCompanion.insert(
              id: 'lm_default',
              userId: const Value('default'),
              topicId: _topicId,
              overallLevel: const Value('awareness'),
            ),
          );
      await db.into(db.learnerModels).insert(
            LearnerModelsCompanion.insert(
              id: 'lm_other',
              userId: const Value('other'),
              topicId: _topicId,
              overallLevel: const Value('expert'),
            ),
          );

      expect(
          (await repo.getLearnerModel(_topicId, userId: 'default'))!.id, 'lm_default');
      expect((await repo.getLearnerModel(_topicId, userId: 'other'))!.id, 'lm_other');
    });
  });

  group('MilestoneEngine.generate: привязка вех к journey', () {
    test('РЕГРЕСС: вехи сохраняются с journey_id вызванной journey', () async {
      // Раньше `Mappers.milestoneToRow` жёстко ставил `journeyId: Value('')`
      // с пометкой «set by caller», а `MilestoneEngine.generate` его не
      // проставлял. Вехи, сгенерированные движком, НИКОГДА не были привязаны
      // к journey: `listMilestones(journeyId)` возвращал пусто, а правило
      // выбора «journey, у которой есть вехи» было недостижимо в бою.
      //
      // Зеркало: server/src/domain/MilestoneEngine.ts пишет journey_id в INSERT.
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: true),
      );
      final engine = MilestoneEngine(repo: repo, scheduler: scheduler);
      await _insertJourney(db, id: 'j1', createdAt: DateTime.utc(2024, 1, 1));

      final generated = await engine.generate('j1', _topicId);
      expect(generated, isNotEmpty);

      final rows = await db
          .customSelect('SELECT journey_id FROM learning_milestones')
          .get();
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.data['journey_id'], 'j1',
            reason: 'веха привязана к journey, ради которой её сгенерировали');
      }

      final listed = await repo.listMilestones('j1');
      expect(listed, isNotEmpty,
          reason: 'сгенерированные вехи видны у своей journey');
      expect(await repo.listMilestones('j_other'), isEmpty,
          reason: 'чужая journey не видит вех этой темы');
    });

    test('РЕГРЕСС: journey с вехами выбирается как актуальная при дублях', () async {
      // Правило выбора в getJourneyForTopic: при нескольких journey на тему
      // берётся та, у которой есть вехи — в ней лежит реальный прогресс.
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: true),
      );
      final engine = MilestoneEngine(repo: repo, scheduler: scheduler);

      // Старая journey без вех и свежая — обе на одну тему.
      await _insertJourney(db, id: 'j_old', createdAt: DateTime.utc(2024, 1, 1));
      await _insertJourney(db, id: 'j_new', createdAt: DateTime.utc(2024, 6, 1));
      await engine.generate('j_new', _topicId);

      final journey = await repo.getJourneyForTopic(_topicId);
      expect(journey, isNotNull);
      expect(journey!.id, 'j_new');
      expect(journey.milestones, isNotEmpty,
          reason: 'прогресс вех не теряется из-за дублей journey');
    });
  });

  // Первый шаг фичи «resume после перезапуска приложения»: сессия лежит
  // в БД, а UI после перезапуска её не находит (id сессии жил только в
  // памяти процесса). Нужен детерминированный поиск незавершённой сессии
  // темы — ровно одной, потому что показывать пользователю две нельзя.
  group('listUnfinishedSessionsForTopic: поиск незавершённой сессии', () {
    // Scoped-иды: `~`-суффикс + 8 hex, как у узлов дерева. Второй скоуп —
    // для сессий другой темы.
    const scope = '1a2b3c4d';
    const otherScope = '9f8e7d6c';
    const journeyId = 'journey_1~1a2b3c4d';
    const otherTopicId = 't2';

    setUp(() async {
      // Сессия ссылается на journey — создаём её честно, а не на «а вдруг».
      await _insertJourney(db, id: journeyId, createdAt: DateTime.utc(2024, 1, 1));
      await repo.createTopic(const Topic(id: otherTopicId, name: 'Другая тема'));
    });

    test('сессия со статусом active выдаётся', () async {
      await _insertSession(db,
          id: 'session_open~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 3, 10));

      final found = await repo.listUnfinishedSessionsForTopic(_topicId);

      expect(found.map((s) => s.id), ['session_open~$scope']);
      expect(found.single.status, SessionStatus.active);
      expect((await repo.latestUnfinishedSessionForTopic(_topicId))!.id,
          'session_open~$scope');
    });

    test('сессия со статусом completed не выдаётся', () async {
      await _insertSession(
        db,
        id: 'session_done~$scope',
        journeyId: journeyId,
        startedAt: DateTime.utc(2026, 3, 10),
        status: SessionStatus.completed,
      );

      expect(await repo.listUnfinishedSessionsForTopic(_topicId), isEmpty,
          reason: 'completed считается завершённой');
      expect(await repo.latestUnfinishedSessionForTopic(_topicId), isNull);
    });

    test('completed не вытесняет более старую активную сессию', () async {
      // Самая свежая строка — completed. Если бы выбор шёл по одной метке
      // времени без фильтра по статусу, UI предложил бы продолжить то, что
      // уже закончено, и потерял настоящую незавершённую сессию.
      await _insertSession(db,
          id: 'session_open~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 1, 10));
      await _insertSession(
        db,
        id: 'session_done~$scope',
        journeyId: journeyId,
        startedAt: DateTime.utc(2026, 3, 10),
        status: SessionStatus.completed,
      );

      final found = await repo.listUnfinishedSessionsForTopic(_topicId);

      expect(found.map((s) => s.id), ['session_open~$scope']);
    });

    test('контракт зафиксирован: abandoned тоже выдаётся (правило «!= completed»)', () async {
      // abandoned сейчас не пишется (единственная запись статуса — active при
      // создании). Тест фиксирует действующее правило, чтобы будущая запись
      // abandoned не изменила выбор молча.
      await _insertSession(
        db,
        id: 'session_dropped~$scope',
        journeyId: journeyId,
        startedAt: DateTime.utc(2026, 3, 10),
        status: SessionStatus.abandoned,
      );

      expect((await repo.listUnfinishedSessionsForTopic(_topicId)).map((s) => s.id),
          ['session_dropped~$scope']);
    });

    test('из нескольких незавершённых выбирается самая свежая по startedAt', () async {
      await _insertSession(db,
          id: 'session_old~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 1, 10));
      await _insertSession(db,
          id: 'session_mid~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 2, 10));
      await _insertSession(db,
          id: 'session_new~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 3, 10));

      final found = await repo.listUnfinishedSessionsForTopic(_topicId);

      expect(found.map((s) => s.id),
          ['session_new~$scope', 'session_mid~$scope', 'session_old~$scope']);
      expect((await repo.latestUnfinishedSessionForTopic(_topicId))!.id,
          'session_new~$scope');
    });

    test('при одинаковом startedAt порядок детерминирован (id asc)', () async {
      // Ключевой инвариант: выбор не должен зависеть от порядка строк в
      // SQLite. Вставляем ЗАВЕДОМО в обратном порядке — так тест падает,
      // если сортировка по id пропадёт (тогда вернётся порядок вставки).
      final at = DateTime.utc(2026, 2, 2);
      await _insertSession(db,
          id: 'session_c~$scope', journeyId: journeyId, startedAt: at);
      await _insertSession(db,
          id: 'session_a~$scope', journeyId: journeyId, startedAt: at);
      await _insertSession(db,
          id: 'session_b~$scope', journeyId: journeyId, startedAt: at);

      final byId = ['session_a~$scope', 'session_b~$scope', 'session_c~$scope'];
      final insertionOrder = ['session_c~$scope', 'session_a~$scope', 'session_b~$scope'];

      final found = await repo.listUnfinishedSessionsForTopic(_topicId);
      expect(found.map((s) => s.id).toList(), byId,
          reason: 'при равных startedAt выбор идёт по id asc');
      expect(found.map((s) => s.id).toList(), isNot(insertionOrder),
          reason: 'порядок вставки не является ответом');

      // Повторное чтение той же базы обязано дать тот же порядок.
      expect((await repo.listUnfinishedSessionsForTopic(_topicId)).map((s) => s.id).toList(),
          byId);
      expect((await repo.latestUnfinishedSessionForTopic(_topicId))!.id, 'session_a~$scope');
    });

    test('limit отдаёт ровно одну самую свежую сессию', () async {
      // Продуктовое правило: UI показывает одну незавершённую сессию на тему.
      await _insertSession(db,
          id: 'session_old~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 1, 10));
      await _insertSession(db,
          id: 'session_new~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 3, 10));

      expect(await repo.listUnfinishedSessionsForTopic(_topicId, limit: 1),
          hasLength(1));
      expect((await repo.listUnfinishedSessionsForTopic(_topicId, limit: 1)).single.id,
          'session_new~$scope');
    });

    test('сессий по теме нет — пустой список и null', () async {
      expect(await repo.listUnfinishedSessionsForTopic(_topicId), isEmpty);
      expect(await repo.latestUnfinishedSessionForTopic(_topicId), isNull);
    });

    test('незавершённые сессии другой темы не подмешиваются', () async {
      await _insertSession(db,
          id: 'session_t1~$scope', journeyId: journeyId, startedAt: DateTime.utc(2026, 1, 10));
      // Чужая сессия свежее нашей — иначе фильтр по теме проверялся бы по
      // дате, а не по topicId.
      await _insertSession(
        db,
        id: 'session_t2~$otherScope',
        journeyId: journeyId,
        topicId: otherTopicId,
        startedAt: DateTime.utc(2030, 1, 1),
      );

      expect((await repo.listUnfinishedSessionsForTopic(_topicId)).map((s) => s.id),
          ['session_t1~$scope']);
      expect((await repo.latestUnfinishedSessionForTopic(_topicId))!.id,
          'session_t1~$scope');
      expect((await repo.latestUnfinishedSessionForTopic(otherTopicId))!.id,
          'session_t2~$otherScope');
    });
  });
}
