// Загрузчик учебных сессий из базы приложения.
//
// Файл закрывает `tool/review/session_loader.dart` на НАСТОЯЩЕМ файле SQLite:
// загрузчик копирует `mindtree.db` (+ `-wal`, `-shm`) во временный каталог и
// читает уже копию. Ни сети, ни LLM, ни ключей.
//
// ЧТО ФИКСИРУЕМ
//   1. Пустые и отсутствующие базы: что именно бросает загрузчик.
//   2. Минимальный валидный набор строк: `LoadedSession` собирается, `view` не
//      падает, проверки отрабатывают.
//   3. Битый JSON в JSON-колонках: сессия не роняет исключение, проблема
//      попадает в `warnings`.
//   4. Дефекты прожитой сессии: какие проверки `session_checks.dart` срабатывают
//      на данных, реально прочитанных из БД.
//   5. Снимок БД: незакрытая WAL-база читается, оригинал не меняется,
//      временный каталог копии убирается.
//   6. Детерминизм: два прогона одной базы дают одинаковые байты.
//   7. Устойчивость загрузчика: мусор вместо базы, дубли journey/learner_model
//      и битые записи не должны ронять ревью или молча терять данные.
//   8. БОЕВОЙ формат `activity_json` (`{"itemId", "steps"}`) и legacy-список:
//      как восстанавливается узел и флаг завершения. Отдельная группа —
//      именно на ней держался каскад ложных находок на боевых данных.
//
// ДЕТЕРМИНИЗМ. Все метки времени заданы явно, «сейчас» не используется.
// Порядок строк тоже не случаен: сам загрузчик сортирует
// (`startedAt DESC`, узлы по `level ASC`, события по `timestamp ASC`), а в
// фикстурах id ставятся так, чтобы порядок вставки совпадал с порядком чтения.
//
// ЧАСОВОЙ ПОЯС. Метки сессий заданы ЛОКАЛЬНЫМИ (`DateTime(2024, 5, 1, 10)`),
// а `detectedAt` мисконцепций — локальной строкой без смещения: ровно так их
// пишет приложение (`DateTime.now().toIso8601String()`). drift хранит
// `started_at` как epoch-секунды и читает через
// `DateTime.fromMillisecondsSinceEpoch` без `isUtc`, то есть возвращает
// локальное время с тем же настенным часом, что записали. Поэтому вхождение
// мисконцепции в окно сессии не зависит от TZ машины. С `DateTime.utc` такая
// фикстура ломалась бы на любой машине, чей TZ ≠ UTC: окно съехало бы на
// разницу поясов, а локальная строка `detectedAt` оказалась бы до его начала.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';

import '../../tool/review/finding.dart';
import '../../tool/review/session_checks.dart';
import '../../tool/review/session_loader.dart';

const String kTopicId = 't1';
const String kNodeId = 'n1';

/// Второй узел дерева. Нужен, чтобы отличить приоритет явного `nodeId` в
/// `activity_json` от резолва узла по `itemId` через план.
const String kSecondNodeId = 'n2';

const String kJourneyId = 'j1';
const String kSessionId = 's1';

/// Recall-шаг без дефектов — ровно в том JSON, который пишет движок сессий.
const String kRecallStepJson = '{"type":"recall","title":"Что такое остановка?",'
    '"options":["Верно: останавливается","Неверно: работает вечно"],'
    '"correctIndex":0,"userAnswer":"Верно: останавливается","correct":true,'
    '"feedback":"верно: это и есть определение остановки"}';

/// Apply-шаг без дефектов: есть инструкция и этал, ответ отличается от этала.
const String kApplyStepJson = '{"type":"apply","title":"Своими словами",'
    '"instruction":"Объясни своими словами, что такое остановка.",'
    '"bestAnswer":"Программа не завершится за конечное время.",'
    '"userAnswer":"Любая программа рано или поздно зависнет.","correct":true,'
    '"feedback":"верно, формулировка близка к эталону"}';

/// Активность без дефектов: пустой `nodeLabel` (проверяем подстановку из дерева).
const String kActivityJson = '[{"nodeId":"n1","isComplete":true,'
    '"steps":[$kRecallStepJson,$kApplyStepJson]}]';

/// Заведомо дефектная активность: только лекция, `isComplete == false`.
const String kLectureOnlyJson = '[{"nodeId":"n1","isComplete":false,'
    '"steps":[{"type":"explain","title":"Лекция","body":"Введение в тему."}]}]';

/// Recall-шаг БОЕВОГО blob'а: `status` проставлен — `ActivityStep.toJson`
/// сериализует его всегда (`status` ∈ pending|current|answered).
const String kBattleRecallJson = '{"type":"recall","title":"Что такое остановка?",'
    '"options":["Верно: останавливается","Неверно: работает вечно"],'
    '"correctIndex":0,"status":"answered","userAnswer":"Верно: останавливается",'
    '"correct":true,"feedback":"верно: это и есть определение остановки"}';

/// Apply-шаг боевого blob'а: есть инструкция и этал, ответ отличается от этала.
const String kBattleApplyJson = '{"type":"apply","title":"Своими словами",'
    '"instruction":"Объясни своими словами, что такое остановка.",'
    '"bestAnswer":"Программа не завершится за конечное время.",'
    '"status":"answered","userAnswer":"Любая программа рано или поздно зависнет.",'
    '"correct":true,"feedback":"верно, формулировка близка к эталону"}';

/// БОЕВОЙ формат `learning_sessions.activity_json`: ОДИН объект активности
/// `{"itemId", "steps"}` — ровно то, что пишет `learning_activity_service.dart`
/// (строки 68 и 305). Ни `nodeId`, ни `isComplete` в этот blob не попадают.
const String kBattleActivityJson =
    '{"itemId":"i1","steps":[$kBattleRecallJson,$kBattleApplyJson]}';

const String kCurriculumJson = '{"sessionId":"s1","items":['
    '{"id":"i1","nodeId":"n1","order":0,"type":"explain","estimatedMinutes":5,'
    '"status":"completed"}]}';

/// План из двух элементов: без второго элемента нельзя отличить резолв узла по
/// `itemId` от приоритета явного `nodeId` в blob'е.
const String kTwoItemCurriculumJson = '{"sessionId":"s1","items":['
    '{"id":"i1","nodeId":"n1","order":0,"type":"explain","estimatedMinutes":5,'
    '"status":"completed"},'
    '{"id":"i2","nodeId":"$kSecondNodeId","order":1,"type":"explain",'
    '"estimatedMinutes":5,"status":"pending"}]}';

const String kQuestionsJson = '[{"id":"q1","type":"recall","nodeId":"n1",'
    '"question":"Что такое остановка?",'
    '"options":["Верно: останавливается","Неверно: работает вечно"],'
    '"correctAnswer":"Верно: останавливается",'
    '"explanation":"верно: это и есть определение остановки"}]';

const String kConceptMasteriesJson = '[{"nodeId":"n1","understanding":0.8,'
    '"recall":0.6,"application":0.7,"transfer":0.4,"errors":['
    '{"nodeId":"n1","type":"mechanism_error",'
    '"description":"Путает остановку с бесконечным циклом","resolved":false,'
    // Внутри окна сессии фикстуры (01.05 10:00—10:30), поэтому атрибутируется.
    '"detectedAt":"2024-05-01T10:15:00"}]}]';

/// Тот же mastery, но БЕЗ мисконцепций: кейсы проверок не должны тонуть в
/// находке «мисконцепция без отработки».
const String kMasteryNoMisconceptionsJson = '[{"nodeId":"n1","understanding":0.8,'
    '"recall":0.6,"application":0.7,"transfer":0.4}]';

/// Описание мисконцепции, которой набиты все фикстуры окна атрибуции.
const String kMisconceptionText = 'Путает остановку с бесконечным циклом';

/// `concept_masteries` с ОДНОЙ мисконцепцией, зафиксированной в [detectedAt].
///
/// Метка времени — локальная строка без смещения, ровно как пишет приложение
/// (`DateTime.now().toIso8601String()`); `null` — мисконцепция без метки, её
/// невозможно отнести ни к одной сессии.
String _masteriesAt(String? detectedAt) {
  final stamp = detectedAt == null ? '' : ',"detectedAt":"$detectedAt"';
  return '[{"nodeId":"n1","understanding":0.8,"recall":0.6,"application":0.7,'
      '"transfer":0.4,"errors":[{"nodeId":"n1","type":"mechanism_error",'
      '"description":"$kMisconceptionText","resolved":false$stamp}]}]';
}

/// Вторая сессия той же темы: старт 01.05.2024 11:00 — то есть верхняя граница
/// окна первой сессии фикстуры. Завершённость задаётся [status].
LearningSessionsCompanion _secondSession(String status) =>
    LearningSessionsCompanion.insert(
      id: 's2',
      journeyId: kJourneyId,
      topicId: kTopicId,
      startedAt: Value(DateTime(2024, 5, 1, 11)),
      completedAt:
          Value(status == 'completed' ? DateTime(2024, 5, 1, 11, 30) : null),
      status: Value(status),
    );

/// Наполнение фикстуры: вставляет строки в свежую БД.
typedef SessionFill = Future<void> Function(MindtreeDb db);

/// Минимальный валидный набор строк одной прожитой сессии.
///
/// Создаёт всё, что читает `_loadOne`: тему, узел дерева, journey, веху,
/// сессию с планом и активностями, события, assessment с попыткой и
/// learner_model с mastery и мисконцепцией.
Future<void> fillFullSession(
  MindtreeDb db, {
  String sessionId = kSessionId,
  String activityJson = kActivityJson,
  String curriculumJson = kCurriculumJson,
  String questionsJson = kQuestionsJson,
  String conceptMasteriesJson = kConceptMasteriesJson,
  String status = 'completed',
  bool withLearnerModel = true,
  double? assessmentScore,
  bool attemptCorrect = true,
}) async {
  await db.into(db.topics).insert(TopicsCompanion.insert(
      id: kTopicId,
      name: 'Теорема остановки',
      timeBudgetMinutes: const Value(45)));
  await db.into(db.knowledgeNodes).insert(KnowledgeNodesCompanion.insert(
      id: kNodeId,
      topicId: kTopicId,
      label: 'Остановка',
      oneLiner: const Value('Не все программы завершаются.'),
      level: const Value(2),
      leaf: const Value(true)));
  await db.into(db.learningJourneys)
      .insert(LearningJourneysCompanion.insert(id: kJourneyId, topicId: kTopicId));
  await db.into(db.learningMilestones).insert(LearningMilestonesCompanion.insert(
      id: 'm1',
      journeyId: kJourneyId,
      level: 'basic_understanding',
      title: 'Базовое понимание'));
  await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
      id: sessionId,
      journeyId: kJourneyId,
      topicId: kTopicId,
      timeBudgetMinutes: const Value(45),
startedAt: Value(DateTime(2024, 5, 1, 10)),
      completedAt:
          Value(status == 'completed' ? DateTime(2024, 5, 1, 10, 30) : null),
      status: Value(status),
      activityJson: Value(activityJson),
      curriculumJson: Value(curriculumJson)));
  await db.into(db.learningEvents).insert(LearningEventsCompanion.insert(
      id: 'e1',
      sessionId: sessionId,
      type: 'activityStarted',
      nodeId: const Value(kNodeId),
      durationMs: const Value(60000)));
  await db.into(db.learningEvents).insert(LearningEventsCompanion.insert(
      id: 'e2',
      sessionId: sessionId,
      type: 'activityStepDone',
      nodeId: const Value(kNodeId),
      durationMs: const Value(45000)));
  await db.into(db.assessments).insert(AssessmentsCompanion.insert(
      id: 'a1',
      sessionId: Value(sessionId),
      questionsJson: Value(questionsJson),
      score: Value(assessmentScore)));
  await db.into(db.assessmentAttempts).insert(AssessmentAttemptsCompanion.insert(
      id: 'at1',
      assessmentId: 'a1',
      questionId: 'q1',
      answer: 'Верно: останавливается',
      correct: Value(attemptCorrect),
      timeSpentMs: const Value(30000),
      feedback: const Value('верно: это и есть определение остановки')));
  if (withLearnerModel) {
    await db.into(db.learnerModels).insert(LearnerModelsCompanion.insert(
        id: 'lm1', topicId: kTopicId, conceptMasteriesJson: Value(conceptMasteriesJson)));
  }
}

/// Создаёт настоящий файл базы во временном каталоге теста и наполняет его.
Future<String> writeDb(Directory dir, String name, SessionFill fill) async {
  final path = '${dir.path}${Platform.pathSeparator}$name';
  final db = MindtreeDb(NativeDatabase(File(path)));
  try {
    await fill(db);
  } finally {
    await db.close();
  }
  return path;
}

/// Коды находок в порядке выдачи — компактно для `expect`.
List<String> codesOf(Iterable<Finding> findings) =>
    <String>[for (final f in findings) f.code];

/// Warning'ы загрузчика, содержащие подстроку [part].
List<String> warningsWith(List<String> warnings, String part) =>
    <String>[for (final w in warnings) if (w.contains(part)) w];

/// Находки с указанным кодом — проверяем конкретный дефект.
List<Finding> withCode(List<Finding> findings, String code) =>
    <Finding>[for (final f in findings) if (f.code == code) f];

/// «код/серьёзность» в порядке выдачи — компактно для `expect`.
List<String> tagsOf(Iterable<Finding> findings) =>
    <String>[for (final f in findings) '${f.code}/${f.severity.name}'];

/// То же, но без `info`: «чистый» отчёт не должен содержать ничего другого.
List<String> problemTagsOf(Iterable<Finding> findings) => <String>[
      for (final f in findings)
        if (f.severity != FindingSeverity.info) '${f.code}/${f.severity.name}',
    ];

/// Только `info`-находки в порядке выдачи.
///
/// В БД нет снимка mastery «до» (`learner_models` хранит текущее состояние),
/// поэтому `checkMasteryDelta` на данных из базы честно выдаёт ровно одну info.
/// Проверять её надо явно: молча отфильтровать info значило бы не заметить
/// сломанную проверку, молча пропустить warn — потерять дефект обучения.
List<String> infoTagsOf(Iterable<Finding> findings) => <String>[
      for (final f in findings)
        if (f.severity == FindingSeverity.info) '${f.code}/${f.severity.name}',
    ];

/// Загрузка сессии + проверки — тот же путь, что у CLI (`_reviewSession`).
Future<List<Finding>> checksOf(String path, {String sessionId = kSessionId}) async {
  final loaded = await loadSession(dbPath: path, sessionId: sessionId);
  return runSessionChecks(loaded.view);
}

/// Каталоги копий, которые загрузчик создаёт в системной временной папке.
List<String> reviewTempDirs() => <String>[
      for (final e in Directory.systemTemp.listSync())
        if (e is Directory && e.path.contains('mindtree_review_')) e.path,
    ]..sort();

void main() {
  late Directory dir;

  // Тест открывает `MindtreeDb` много раз подряд (по фикстуре на кейс) —
  // гасим предупреждение drift про «несколько баз»: для тестов это ложный тревог.
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mindtree_review_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('пустые и отсутствующие базы', () {
    test('нет файла → SessionLoadException с подсказкой про --db', () async {
      final missing = '${dir.path}${Platform.pathSeparator}нет-такой.db';

      await expectLater(
        loadSessions(dbPath: missing),
        throwsA(isA<SessionLoadException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Файл базы не найден'), contains('--db')),
        )),
      );
    });

    test('пустой файл (0 байт) → пустой список, оригинал остаётся пустым', () async {
      final path = '${dir.path}${Platform.pathSeparator}пустая.db';
      File(path).writeAsBytesSync(const <int>[]);

      final sessions = await loadSessions(dbPath: path);

      expect(sessions, isEmpty);
      expect(File(path).lengthSync(), 0, reason: 'загрузчик не должен дописывать в оригинал');
    });

    test('в базе есть тема, но сессий нет → пустой список', () async {
      final path = await writeDb(dir, 'без-сессий.db', (db) async {
        await db.into(db.topics).insert(TopicsCompanion.insert(
            id: kTopicId, name: 'Теорема остановки', timeBudgetMinutes: const Value(45)));
      });

      expect(await loadSessions(dbPath: path), isEmpty);
    });

    test('несуществующий sessionId → SessionLoadException «не найдена в базе»', () async {
      final path = await writeDb(dir, 'сессии.db', fillFullSession);

      await expectLater(
        loadSession(dbPath: path, sessionId: 'нет-такой'),
        throwsA(isA<SessionLoadException>().having(
            (e) => e.message, 'message', contains('Сессия «нет-такой» не найдена'))),
      );
    });
  });

  group('минимальный валидный набор строк', () {
    late String path;

    setUp(() async {
      path = await writeDb(dir, 'полная.db', fillFullSession);
    });

    test('loadSession отдаёт ровно одну сессию с id, темой и статусом', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.sessionId, kSessionId);
      expect(loaded.topicId, kTopicId);
      expect(loaded.topicName, 'Теорема остановки');
      expect(loaded.view.status, 'completed');
      expect(loaded.view.completedAt, isNotEmpty);
      expect(loaded.view.timeBudgetMinutes, 45, reason: 'бюджет берётся из темы');
      expect(loaded.view.targetLevel, isNotEmpty);
    });

    test('узлы дерева и вехи темы попадают в контекст', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.nodes, hasLength(1));
      expect(loaded.nodes.single.label, 'Остановка');
      expect(loaded.nodes.single.oneLiner, 'Не все программы завершаются.');
      expect(loaded.milestones, hasLength(1));
      expect(loaded.milestones.single.level, 'basic_understanding');
      expect(loaded.nodeLabels, <String, String>{kNodeId: 'Остановка'});
    });

    test('план разобран, активности собраны, пустой nodeLabel подставлен', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.plannedNodeIds, <String>[kNodeId]);
      expect(loaded.view.activities, hasLength(1));
      final activity = loaded.view.activities.single;
      expect(activity.nodeId, kNodeId);
      expect(activity.isComplete, isTrue);
      expect(
        activity.nodeLabel,
        'Остановка',
        reason: 'в activity_json label пустой — подставляем label из дерева',
      );
      expect(activity.steps.map((s) => s.type), <String>[kStepRecall, kStepApply]);
    });

    test('тексты шага не теряются: инструкция, этал, ответ и фидбек', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);
      final apply = loaded.view.activities.single.steps.last;

      expect(apply.instruction, contains('своими словами'));
      expect(apply.bestAnswer, contains('не завершится'));
      expect(apply.userAnswer, contains('зависнет'));
      expect(apply.correct, isTrue);
      expect(apply.feedback, isNotEmpty);
      expect(
        apply.durationMs,
        0,
        reason: 'тайминга по шагам в БД нет — остаётся 0 (см. шапку загрузчика)',
      );
    });

    test('вопрос: correctIndex считается по тексту correctAnswer', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.questions, hasLength(1));
      final q = loaded.view.questions.single;
      expect(q.nodeId, kNodeId);
      expect(q.effectiveType, kStepRecall);
      expect(q.options, hasLength(2));
      expect(q.correctAnswer, 'Верно: останавливается');
      expect(q.correctIndex, 0);
      expect(q.userAnswer, 'Верно: останавливается', reason: 'ответ из assessment_attempts');
      expect(q.correct, isTrue);
      expect(q.timeSpentMs, 30000);
    });

    test('события идут по возрастанию времени', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.events, hasLength(2));
      expect(loaded.view.events.first.type, 'activityStarted');
      expect(loaded.view.events.last.type, 'activityStepDone');
      expect(loaded.view.events.last.durationMs, 45000);
    });

    test('mastery считается как среднее по четырём измерениям', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      // (0.8 + 0.6 + 0.7 + 0.4) / 4
      expect(loaded.view.masteryAfter, <String, double>{kNodeId: 0.625});
      expect(loaded.view.masteryBefore, isEmpty, reason: 'снимка «до» в БД нет');
    });

    test('мисконцепции собраны и привязаны к узлу', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.misconceptions, <String>['Путает остановку с бесконечным циклом']);
      expect(loaded.view.misconceptionsByNode,
          <String, String>{kNodeId: 'Путает остановку с бесконечным циклом'});
    });

    test('warnings: без learner_model чисто, с learner_model — про историю mastery', () async {
      final withModel = await loadSession(dbPath: path, sessionId: kSessionId);
      expect(warningsWith(withModel.warnings, 'История mastery'), hasLength(1));

      final withoutPath = await writeDb(dir, 'без-learner-model.db',
          (db) => fillFullSession(db, withLearnerModel: false));
      final withoutModel = await loadSession(dbPath: withoutPath, sessionId: kSessionId);

      expect(withoutModel.warnings, isEmpty);
      expect(withoutModel.view.masteryAfter, isEmpty);
    });

    test('здоровая сессия не даёт ни warn, ни fail', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);
      final findings = runSessionChecks(loaded.view);

      expect(
        codesOf(findings.where((f) => f.severity != FindingSeverity.info)),
        isEmpty,
        reason: 'находки: $findings',
      );
      // Единственная info — про отсутствие снимка mastery «до»: в БД его нет by
      // design, и это не должно выглядеть как плохое обучение.
      expect(infoTagsOf(findings), <String>['${SessionCheckCode.masteryDelta}/info']);
      expect(loaded.view.masteryBefore, isEmpty, reason: 'и правда неоткуда его взять');
    });

    test('toJson рендерится: машинный отчёт собирается без исключений', () async {
      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      final json = loaded.toJson();
      final view = json['view'] as Map<String, dynamic>;

      expect(json['sessionId'], kSessionId);
      expect(view['plannedNodeIds'], <String>[kNodeId]);
      expect((view['activities'] as List<dynamic>), hasLength(1));
      expect((view['questions'] as List<dynamic>), hasLength(1));
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('последние сессии: порядок startedAt DESC и limit', () async {
      final many = await writeDb(dir, 'много.db', (db) async {
        await fillFullSession(db);
        await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
            id: 's2',
            journeyId: kJourneyId,
            topicId: kTopicId,
            startedAt: Value(DateTime.utc(2024, 5, 3, 10)),
            status: const Value('completed')));
        await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
            id: 's0',
            journeyId: kJourneyId,
            topicId: kTopicId,
            startedAt: Value(DateTime.utc(2024, 4, 28, 10)),
            status: const Value('completed')));
      });

      final all = await loadSessions(dbPath: many);
      expect(all.map((s) => s.sessionId), <String>['s2', kSessionId, 's0']);

      final one = await loadSessions(dbPath: many, limit: 1);
      expect(one.map((s) => s.sessionId), <String>['s2']);
    });

    test('фильтр topicId отсекает чужие темы', () async {
      final two = await writeDb(dir, 'две-темы.db', (db) async {
        await fillFullSession(db);
        await db.into(db.topics)
            .insert(TopicsCompanion.insert(id: 't2', name: 'Другая тема'));
        await db.into(db.learningJourneys)
            .insert(LearningJourneysCompanion.insert(id: 'j2', topicId: 't2'));
        await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
            id: 's-чужая', journeyId: 'j2', topicId: 't2', status: const Value('completed')));
      });

      expect(await loadSessions(dbPath: two, topicId: 't2'),
          <Matcher>[isA<LoadedSession>().having((s) => s.sessionId, 'id', 's-чужая')]);
      expect(await loadSessions(dbPath: two, topicId: kTopicId),
          <Matcher>[isA<LoadedSession>().having((s) => s.sessionId, 'id', kSessionId)]);
      expect(await loadSessions(dbPath: two, topicId: 'нет-такой-темы'), isEmpty);
    });
  });

  // ─── Битый JSON в JSON-колонках ─────────────────────────────────────────────
  group('битый JSON в JSON-колонках', () {
    /// Все четыре JSON-колонки сессии — сломанный текст.
    Future<String> brokenDb(String name) => writeDb(
          dir,
          name,
          (db) => fillFullSession(
            db,
            activityJson: '{не json',
            curriculumJson: '}{',
            questionsJson: '[{',
            conceptMasteriesJson: '{слом',
          ),
        );

    test('все четыре колонки битые → сессия грузится, проблема в warnings', () async {
      final loaded = await loadSession(dbPath: await brokenDb('битые-колонки.db'), sessionId: kSessionId);

      expect(warningsWith(loaded.warnings, 'curriculum_json не разобран'), hasLength(1));
      expect(warningsWith(loaded.warnings, 'activity_json: битый JSON'), hasLength(1));
      expect(
          warningsWith(loaded.warnings, 'assessment.questions_json: битый JSON'),
          hasLength(1));
      expect(warningsWith(loaded.warnings, 'learner_model.concept_masteries: битый JSON'),
          hasLength(1));
      expect(
        loaded.warnings,
        hasLength(5),
        reason: '4 битые колонки + предупреждение о недоступной истории mastery',
      );
    });

    test('битые данные не роняют view: списки пустые, отчёт рендерится', () async {
      final loaded = await loadSession(dbPath: await brokenDb('битые-колонки-2.db'), sessionId: kSessionId);

      expect(loaded.view.plannedNodeIds, isEmpty, reason: 'план не разобран');
      expect(loaded.view.activities, isEmpty);
      expect(loaded.view.questions, isEmpty);
      expect(loaded.view.masteryAfter, isEmpty);
      expect(loaded.view.misconceptions, isEmpty);
      // Единственная находка — «нет mastery ПОСЛЕ»: неполные данные не должны
      // выглядеть как плохое обучение.
      expect(tagsOf(runSessionChecks(loaded.view)),
          <String>['${SessionCheckCode.masteryDelta}/info']);
      expect(() => jsonEncode(loaded.toJson()), returnsNormally);
    });

    test('битый curriculum не стирает активности и вопросы', () async {
      final path = await writeDb(dir, 'битый-план.db',
          (db) => fillFullSession(db, curriculumJson: '}{'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(warningsWith(loaded.warnings, 'curriculum_json не разобран'), hasLength(1));
      expect(loaded.view.plannedNodeIds, isEmpty);
      expect(loaded.view.activities, hasLength(1), reason: 'план и активности — разные колонки');
      expect(loaded.view.questions, hasLength(1));
      expect(loaded.view.masteryAfter, isNotEmpty);
    });

    test('битый activity_json не стирает вопросы', () async {
      final path = await writeDb(dir, 'битая-активность.db',
          (db) => fillFullSession(db, activityJson: '{не json'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(warningsWith(loaded.warnings, 'activity_json: битый JSON'), hasLength(1));
      expect(loaded.view.activities, isEmpty);
      expect(loaded.view.questions, hasLength(1));
    });

    test('битый questions_json не стирает активности и mastery', () async {
      final path = await writeDb(dir, 'битые-вопросы.db',
          (db) => fillFullSession(db, questionsJson: '[{'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(warningsWith(loaded.warnings, 'assessment.questions_json: битый JSON'),
          hasLength(1));
      expect(loaded.view.questions, isEmpty);
      expect(loaded.view.activities, hasLength(1));
      expect(loaded.view.masteryAfter, <String, double>{kNodeId: 0.625});
    });
  });

  // ─── Проверки ловят дефекты прожитой сессии ─────────────────────────────────
  group('runSessionChecks ловит дефекты данных из БД', () {
    // По умолчанию mastery без мисконцепций: иначе каждый кейс дополнительно
    // ловил бы `session_misconception_without_remediation` и мешал проверить
    // именно свой дефект.
    Future<String> db(
      String name, {
      String activityJson = kActivityJson,
      String curriculumJson = kCurriculumJson,
      String questionsJson = kQuestionsJson,
      String status = 'completed',
      double? assessmentScore,
      bool attemptCorrect = true,
    }) =>
        writeDb(
          dir,
          name,
          (raw) => fillFullSession(
            raw,
            activityJson: activityJson,
            curriculumJson: curriculumJson,
            questionsJson: questionsJson,
            status: status,
            conceptMasteriesJson: kMasteryNoMisconceptionsJson,
            assessmentScore: assessmentScore,
            attemptCorrect: attemptCorrect,
          ),
        );

    // `learner_models` хранит только текущее состояние мастерства, поэтому
    // `masteryBefore` у загрузчика всегда пуст и `checkMasteryDelta` выдаёт info
    // «нет снимка ДО». Это недостаток данных, а не дефект обучения: assert'им
    // его явно, чтобы в кейс не проскочила никакая другая info и не пришлось
    // фильтровать находки «на всякий случай».
    List<String> tagsFromDb(List<Finding> findings) {
      expect(infoTagsOf(findings), <String>['${SessionCheckCode.masteryDelta}/info'],
          reason: 'единственная допустимая info из БД — про снимок mastery «до»:\n'
              '${findings.map((f) => f.toString()).join('\n')}');
      return problemTagsOf(findings);
    }

    test('пустая сессия без шагов → ни warn, ни fail (только info про снимок mastery)',
        () async {
      final findings = await checksOf(await db('пусто.json', activityJson: '[]'));

      expect(findings, hasLength(1),
          reason: 'сессия без активностей — это «ничего не прошли», а не плохое обучение:\n'
              '${findings.map((f) => f.toString()).join('\n')}');
      expect(tagsFromDb(findings), isEmpty);
      expect(findings.single.message, contains('Нет снимка мастерства ДО'));
    });

    test('активность без recall/apply → session_step_mix (warn)', () async {
      final findings = await checksOf(await db('лекция.json', activityJson: kLectureOnlyJson));
      final hit = withCode(findings, SessionCheckCode.stepMix);

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.stepMix}/warn']);
      expect(hit.single.nodeId, kNodeId);
      expect(hit.single.data?['stepTypes'], <String>[kStepExplain]);
    });

    test('активность с пустым списком шагов → выпадает с warning, а не ловит step_mix',
        () async {
      // Раньше такая активность доезжала до проверок и давала
      // `session_step_mix`. По новому контракту судить о прохождении не по
      // чему, поэтому она выпадает из отчёта, а потеря видна в warnings.
      final loaded = await loadSession(
        dbPath: await db(
          'без-шагов.json',
          activityJson: '{"itemId":"i1","steps":[]}',
        ),
        sessionId: kSessionId,
      );

      expect(loaded.view.activities, isEmpty);
      expect(loaded.view.allSteps, isEmpty, reason: 'ни одного шага не осталось');
      expect(
        warningsWith(loaded.warnings, 'activity_json: у активности нет шагов'),
        hasLength(1),
      );
      expect(
        warningsWith(loaded.warnings, 'у активности не нашёлся узел'),
        isEmpty,
        reason: 'itemId «i1» разрешается через план — узел потерян не из-за него',
      );
      expect(tagsFromDb(runSessionChecks(loaded.view)), isEmpty,
          reason: 'выпавшая активность не должна превращаться в каскад находок');
    });

    test('активность на узле вне плана → session_activity_node_unknown (fail)', () async {
      final findings = await checksOf(await db(
        'чужой-узел.json',
        activityJson: '[{"nodeId":"n-alien","isComplete":true,"steps":['
            '{"type":"recall","title":"Проверка","options":["да","нет"],'
            '"correctIndex":0,"userAnswer":"да","correct":true,"feedback":"верно"}]}]',
      ));
      final hit = withCode(findings, SessionCheckCode.activityNodeUnknown);

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.activityNodeUnknown}/fail']);
      expect(hit.single.nodeId, 'n-alien');
      expect(hit.single.data?['knownCount'], 1, reason: 'в плане один узел — n1');
    });

    test('recall без correctIndex → session_recall_options (fail)', () async {
      final findings = await checksOf(await db(
        'recall-без-этала.json',
        activityJson: '[{"nodeId":"n1","isComplete":true,"steps":['
            '{"type":"recall","title":"Проверка","options":["да","нет"],'
            '"userAnswer":"да","correct":true,"feedback":"верно"}]}]',
      ));
      final hit = withCode(findings, SessionCheckCode.recallOptions);

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.recallOptions}/fail']);
      expect(hit.single.message, contains('не задан correctIndex'));
    });

    test('recall с correctIndex вне диапазона → session_recall_options (fail)', () async {
      final findings = await checksOf(await db(
        'recall-мимо.json',
        activityJson: '[{"nodeId":"n1","isComplete":true,"steps":['
            '{"type":"recall","title":"Проверка","options":["да","нет"],'
            '"correctIndex":5,"userAnswer":"да","correct":true,"feedback":"верно"}]}]',
      ));
      final hit = withCode(findings, SessionCheckCode.recallOptions);

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.recallOptions}/fail']);
      expect(hit.single.data?['correctIndex'], 5);
    });

    test('apply без инструкции и этала → session_apply_contract (fail ×2)', () async {
      final findings = await checksOf(await db(
        'apply-голый.json',
        activityJson: '[{"nodeId":"n1","isComplete":true,"steps":['
            '{"type":"apply","title":"Голый apply","userAnswer":"какой-то ответ",'
            '"correct":true,"feedback":"ок"}]}]',
      ));
      final hit = withCode(findings, SessionCheckCode.applyContract);

      expect(tagsFromDb(findings), <String>[
        '${SessionCheckCode.applyContract}/fail',
        '${SessionCheckCode.applyContract}/fail',
      ]);
      expect(hit.first.message, contains('пустая инструкция'));
      expect(hit.last.message, contains('нет эталонного ответа'));
    });

    test('этал apply дословно повторяет инструкцию → session_apply_degenerate (warn)',
        () async {
      const text = 'Объясни своими словами что такое остановка';
      final findings = await checksOf(await db(
        'этал-как-инструкция.json',
        activityJson: '[{"nodeId":"n1","isComplete":true,"steps":['
            '{"type":"apply","title":"Этал = инструкция","instruction":"$text",'
            '"bestAnswer":"$text"}]}]',
      ));

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.applyDegenerate}/warn']);
      expect(withCode(findings, SessionCheckCode.applyDegenerate).single.message,
          contains('дословно совпадает с инструкцией'));
    });

    test('apply-вопрос без correctIndex/эталона → session_question_shallow (warn)',
        () async {
      final findings = await checksOf(await db(
        'apply-вопрос.json',
        questionsJson: '[{"id":"q1","type":"application","nodeId":"n1","question":'
            '"Приведи пример программы, которая не останавливается."}]',
      ));
      final hit = withCode(findings, SessionCheckCode.questionShallow);

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.questionShallow}/warn']);
      expect(hit.single.nodeId, kNodeId);
      expect(hit.single.message, contains('без эталонного ответа'));
    });

    test('этал вопроса не совпал ни с одним вариантом → correctIndex == null + warn',
        () async {
      // Вопрос q2 без попытки: фидбек берётся из `explanation` и он пустоподобный,
      // поэтому проверка глубины срабатывает, а не молчит на связке.
      final loaded = await loadSession(
        dbPath: await db(
          'этал-не-из-вариантов.json',
          questionsJson: '[{"id":"q2","type":"recall","nodeId":"n1",'
              '"question":"Что такое остановка?","options":["да","нет"],'
              '"correctAnswer":"возможно","explanation":"Ну вот как-то так"}]',
        ),
        sessionId: kSessionId,
      );
      final question = loaded.view.questions.single;

      expect(question.correctIndex, isNull,
          reason: 'этала нет среди вариантов — сравнивать не с чем');
      expect(question.hasOptions, isTrue, reason: 'варианты есть, вопрос закрытый');
      // Правильный вариант не определён — это дефект данных, а не shallow-фидбек
      // (раньше тест ждал questionShallow и пропускал настоящую проблему).
      final findings = runSessionChecks(loaded.view);
      final hit = withCode(findings, SessionCheckCode.questionAnswerUnresolved);
      expect(tagsFromDb(findings),
          <String>['${SessionCheckCode.questionAnswerUnresolved}/warn']);
      expect(hit.single.message, contains('correctAnswer не совпал ни с одним'));
    });

    test('незавершённый статус при незавершённых шагах → session_completion (warn ×2)',
        () async {
      final answered = [
        for (var i = 0; i < kEnoughAnswersForCompletion; i++)
          '{"type":"apply","title":"Задача $i",'
              '"instruction":"Опиши остановку своими словами",'
              '"bestAnswer":"Программа не завершится за конечное время",'
              '"userAnswer":"Ответ ученика номер $i","correct":true,'
              '"feedback":"верно"}',
      ].join(',');
      final findings = await checksOf(await db(
        'не-завершена.json',
        status: 'active',
        activityJson: '[{"nodeId":"n1","isComplete":false,"steps":[$answered]}]',
      ));
      final hit = withCode(findings, SessionCheckCode.completion);

      expect(tagsFromDb(findings), <String>[
        '${SessionCheckCode.completion}/warn',
        '${SessionCheckCode.completion}/warn',
      ]);
      expect(hit.first.message, contains('просто статус не переключили'));
      expect(hit.first.data?['answeredSteps'], kEnoughAnswersForCompletion);
      expect(hit.last.message, contains('isComplete == false'));
    });

    test('шаг с ответом, но без вердикта → session_answer_not_scored (warn)', () async {
      final findings = await checksOf(await db(
        'без-вердикта.json',
        activityJson: '[{"nodeId":"n1","isComplete":true,"steps":['
            '{"type":"apply","title":"Без вердикта",'
            '"instruction":"Опиши остановку своими словами",'
            '"bestAnswer":"Программа не завершится за конечное время",'
            '"userAnswer":"Ответ ученика","feedback":"близко"}]}]',
      ));

      expect(tagsFromDb(findings), <String>['${SessionCheckCode.answerNotScored}/warn']);
      expect(withCode(findings, SessionCheckCode.answerNotScored).single.message,
          contains('correct == null'));
    });

    test('здоровая фикстура из БД не даёт ни warn, ни fail', () async {
      final findings = await checksOf(await db('здоровая.db'));

      expect(tagsFromDb(findings), isEmpty,
          reason: 'дефектов нет — находок быть не должно, ни кроме info:\n'
              '${findings.map((f) => f.toString()).join('\n')}');
    });
  });

  // ─── Боевой формат activity_json ────────────────────────────────────────────
  // Приложение пишет в `learning_sessions.activity_json` НЕ массив, а ОДИН объект
  // активности: `{"itemId": "<id элемента curriculum>", "steps": [...]}`
  // (`learning_activity_service.dart`, строки 68 и 305). Ни `nodeId`, ни
  // `isComplete` в этот blob не попадают. Раньше загрузчик брал `nodeId` только
  // из самого blob'а, и на боевых данных каскадом шли ложные находки: 6 ×
  // `session_activity_node_unknown` уровня fail и десятки
  // `session_misconception_without_remediation`.
  //
  // Контракт, который здесь закрепляется:
  //   * `nodeId` = явный `nodeId` из blob'а, иначе `itemId` через план;
  //   * неразрешимый узел или активность без шагов → выпадение из отчёта с
  //     warning'ом (а не каскад находок по пустому `nodeId`);
  //   * `isComplete` = явный флаг из blob'а, иначе «все шаги отвечены».
  group('боевой формат activity_json: {itemId, steps}', () {
    /// Тема с двумя узлами в дереве и двумя элементами в плане: без второго
    /// узла нельзя отличить приоритет явного `nodeId` от резолва по `itemId`.
    Future<LoadedSession> load(String name, String activityJson) async {
      final path = await writeDb(dir, name, (raw) async {
        await fillFullSession(
          raw,
          activityJson: activityJson,
          curriculumJson: kTwoItemCurriculumJson,
          conceptMasteriesJson: kMasteryNoMisconceptionsJson,
        );
        await raw.into(raw.knowledgeNodes).insert(KnowledgeNodesCompanion.insert(
            id: kSecondNodeId,
            topicId: kTopicId,
            label: 'Бесконечный цикл',
            oneLiner: const Value('Программа может крутиться вечно.'),
            level: const Value(3),
            leaf: const Value(true)));
      });
      return loadSession(dbPath: path, sessionId: kSessionId);
    }

    test('itemId резолвится в nodeId элемента плана: label из дерева, ложных находок нет',
        () async {
      final loaded = await load('боевой-формат.db', kBattleActivityJson);

      expect(loaded.view.activities, hasLength(1));
      final activity = loaded.view.activities.single;
      expect(activity.nodeId, kNodeId,
          reason: 'в blob нет nodeId — резолвим itemId «i1» через curriculum_json');
      expect(activity.nodeLabel, 'Остановка',
          reason: 'label подтягивается из дерева темы, а не из JSON активности');
      expect(activity.steps.map((s) => s.type), <String>[kStepRecall, kStepApply]);
      expect(warningsWith(loaded.warnings, 'activity_json'), isEmpty);

      // Главное ради этого фикса: ложных session_activity_node_unknown быть
      // не должно, иначе на боевых базах ревью утонет в них.
      final findings = runSessionChecks(loaded.view);
      expect(withCode(findings, SessionCheckCode.activityNodeUnknown), isEmpty);
      expect(problemTagsOf(findings), isEmpty, reason: 'находки: $findings');
      expect(infoTagsOf(findings),
          <String>['${SessionCheckCode.masteryDelta}/info']);
    });

    test('явный nodeId в blob важнее itemId из плана', () async {
      final loaded = await load(
        'приоритет-nodeId.json',
        '{"nodeId":"$kSecondNodeId","itemId":"i1","steps":[$kBattleRecallJson]}',
      );

      expect(loaded.view.activities, hasLength(1));
      final activity = loaded.view.activities.single;
      expect(activity.nodeId, kSecondNodeId,
          reason: 'itemId «i1» вёл бы на n1 — явный nodeId важнее');
      expect(activity.nodeId, isNot(kNodeId));
      expect(activity.nodeLabel, 'Бесконечный цикл');
      expect(
        withCode(runSessionChecks(loaded.view), SessionCheckCode.activityNodeUnknown),
        isEmpty,
        reason: 'оба узла есть в плане — разрешённый через blob узел тоже известен',
      );
    });

    test('itemId, которого нет в плане → активности нет, warning с activity_json и itemId',
        () async {
      final loaded = await load(
        'чужой-itemId.json',
        '{"itemId":"i-не-из-плана","steps":[$kBattleRecallJson]}',
      );

      expect(loaded.view.activities, isEmpty,
          reason: 'активность без узла проверкам только мешает — выпадает');
      final hit =
          warningsWith(loaded.warnings, 'activity_json: у активности не нашёлся узел');
      expect(hit, hasLength(1));
      expect(hit.single, contains('i-не-из-плана'),
          reason: 'в warning обязателен сам itemId — иначе потеря не диагностируется');
      expect(warningsWith(loaded.warnings, 'у активности нет шагов'), isEmpty,
          reason: 'шаги у активности были — предупреждение другое');

      final findings = runSessionChecks(loaded.view);
      expect(withCode(findings, SessionCheckCode.activityNodeUnknown), isEmpty,
          reason: 'выпавшая активность не должна превращаться в каскад находок');
      expect(problemTagsOf(findings), isEmpty, reason: 'находки: $findings');
    });

    test('isComplete выводится из шагов: все answered → активность завершена', () async {
      final loaded = await load('все-отвечены.json', kBattleActivityJson);

      final activity = loaded.view.activities.single;
      expect(activity.steps, hasLength(2));
      expect(activity.isComplete, isTrue,
          reason: 'у обоих шагов status = answered');
    });

    test('частично отвеченные шаги → активность не завершена', () async {
      final loaded = await load(
        'частично-отвечены.json',
        '{"itemId":"i1","steps":[$kBattleRecallJson,'
        '{"type":"apply","title":"Своими словами",'
        '"instruction":"Объясни своими словами, что такое остановка.",'
        '"bestAnswer":"Программа не завершится за конечное время.",'
        '"status":"current"}]}',
      );

      final activity = loaded.view.activities.single;
      expect(activity.isComplete, isFalse,
          reason: 'apply ещё в статусе current — активность не пройдена');
      expect(activity.stepsOfType(kStepApply).single.userAnswer, isNull);
    });

    test('шаги без status: отвеченность по userAnswer/correct (legacy-выгрузка)',
        () async {
      // В боевом blob `status` есть у каждого шага, но в выгрузках его может не
      // быть: тогда шаг отвечен, если есть непустой ответ ИЛИ выставлен вердикт.
      final withAnswers = await load(
        'без-status-ответы.json',
        '[{"itemId":"i1","steps":['
        '{"type":"recall","title":"Проверка","options":["да","нет"],'
        '"correctIndex":0,"userAnswer":"да","correct":true,"feedback":"верно"},'
        '{"type":"explain","title":"Лекция","body":"Коротко о главном",'
        '"userAnswer":"прочитал","correct":true}]}]',
      );
      final withPending = await load(
        'без-status-неотвечен.json',
        '[{"itemId":"i1","steps":['
        '{"type":"recall","title":"Проверка","options":["да","нет"],'
        '"correctIndex":0,"userAnswer":"да","correct":true,"feedback":"верно"},'
        '{"type":"explain","title":"Лекция","body":"Коротко о главном"}]}]',
      );

      expect(withAnswers.view.activities.single.isComplete, isTrue,
          reason: 'у обоих шагов есть ответ или вердикт');
      expect(withPending.view.activities.single.isComplete, isFalse,
          reason: 'шаг без ответа и вердикта считается неотвеченным');
    });

    test('явный isComplete в blob не переопределяется выводом из шагов', () async {
      final loaded = await load(
        'явный-isComplete.json',
        '[{"itemId":"i1","isComplete":true,"steps":['
        '{"type":"explain","title":"Лекция","body":"Коротко о главном",'
        '"status":"pending"}]},'
        '{"itemId":"i2","isComplete":false,"steps":[$kBattleRecallJson]}]',
      );

      expect(loaded.view.activities, hasLength(2));
      expect(loaded.view.activities.first.isComplete, isTrue,
          reason: 'явный true при pending-шаге — флаг из данных главнее вывода');
      expect(loaded.view.activities.last.isComplete, isFalse,
          reason: 'явный false при отвеченном шаге — вывод его не переопределяет');
    });

    test('legacy-формат (список активностей) разбирается тем же кодом', () async {
      final loaded = await load(
        'legacy-список.json',
        '[{"nodeId":"$kSecondNodeId","steps":[$kBattleRecallJson]},'
        '{"itemId":"i1","steps":[$kBattleApplyJson]}]',
      );

      expect(loaded.view.activities.map((a) => a.nodeId),
          <String>[kSecondNodeId, kNodeId],
          reason: 'и явный nodeId, и резолв по itemId работают и в списке');
      expect(loaded.view.activities.map((a) => a.nodeLabel),
          <String>['Бесконечный цикл', 'Остановка']);
      expect(loaded.view.allSteps, hasLength(2));
      expect(warningsWith(loaded.warnings, 'activity_json'), isEmpty);
    });
  });

  // ─── Детерминизм ───────────────────────────────────────────────────────────
  group('детерминизм', () {
    test('два прогона одной базы дают побайтово одинаковый toJson', () async {
      final path = await writeDb(dir, 'детерминизм-1.db', fillFullSession);

      final first = await loadSession(dbPath: path, sessionId: kSessionId);
      final second = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
    });

    test('два прогона дают идентичные находки: порядок, тексты и data', () async {
      final path = await writeDb(dir, 'детерминизм-2.db',
          (db) => fillFullSession(db, activityJson: kLectureOnlyJson));

      final first = await checksOf(path);
      final second = await checksOf(path);

      expect(jsonEncode(<Object>[for (final f in second) f.toJson()]),
          jsonEncode(<Object>[for (final f in first) f.toJson()]));
      expect(second, isNotEmpty, reason: 'кейс должен что-то находить');
    });

    test('warnings стабильны между прогонами', () async {
      final path = await writeDb(dir, 'детерминизм-3.db', (db) => fillFullSession(
            db,
            activityJson: '{не json',
            curriculumJson: '}{',
            questionsJson: '[{',
          ));

      final first = await loadSession(dbPath: path, sessionId: kSessionId);
      final second = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(second.warnings, first.warnings);
      expect(first.warnings, isNotEmpty);
    });

    test('порядок сессий и limit стабильны между прогонами', () async {
      final path = await writeDb(dir, 'детерминизм-4.db', (db) async {
        await fillFullSession(db);
        for (final day in <String>['2024-05-02', '2024-05-03', '2024-05-04']) {
          await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
              id: 's-$day',
              journeyId: kJourneyId,
              topicId: kTopicId,
              startedAt: Value(DateTime.parse(day)),
              status: const Value('completed')));
        }
      });

      final first = await loadSessions(dbPath: path, limit: 2);
      final second = await loadSessions(dbPath: path, limit: 2);

      expect(first.map((s) => s.sessionId), <String>['s-2024-05-04', 's-2024-05-03'],
          reason: 'свежие сверху, limit режет хвост');
      expect(second.map((s) => s.sessionId), first.map((s) => s.sessionId));
      expect(jsonEncode(<Object>[for (final s in second) s.toJson()]),
          jsonEncode(<Object>[for (final s in first) s.toJson()]));
    });
  });

  // ─── Снимок БД ─────────────────────────────────────────────────────────────
  group('окно атрибуции мисконцепций к сессии', () {
    // `learner_models` уникален по (userId, topicId) — строка одна на тему, так
    // что привязки к сессии в БД нет. Загрузчик выводит её из окна
    // [startedAt, completedAt ?? старт следующей сессии темы). Без этого все
    // мисконцепции темы доставались каждой её сессии (18 ложных находок на
    // боевой БД). Ниже — границы этого окна.

    /// Вторая сессия той же темы — окно первой закрывается 01.05 11:00.
    Future<void> fillWithSecondSession(
      MindtreeDb db, {
      String conceptMasteriesJson = kConceptMasteriesJson,
      String secondStatus = 'active',
    }) async {
      await fillFullSession(
        db,
        conceptMasteriesJson: conceptMasteriesJson,
        status: 'active',
      );
      await db.into(db.learningSessions).insert(_secondSession(secondStatus));
    }

    test('мисконцепция внутри окна попадает в сессию', () async {
      final path = await writeDb(dir, 'в-окне.db', (db) => fillFullSession(
            db,
            status: 'active',
            conceptMasteriesJson: _masteriesAt('2024-05-01T10:15:00'),
          ));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.misconceptions, <String>[kMisconceptionText]);
      expect(warningsWith(loaded.warnings, 'вне окна сессии'), isEmpty);
      expect(warningsWith(loaded.warnings, 'без detectedAt'), isEmpty);
    });

    test('мисконцепция позже следующей сессии темы не достаётся первой', () async {
      final path = await writeDb(
          dir,
          'соседняя.db',
          (db) => fillWithSecondSession(
                db,
                conceptMasteriesJson: _masteriesAt('2024-05-01T12:00:00'),
              ));

      final first = await loadSession(dbPath: path, sessionId: kSessionId);
      final second = await loadSession(dbPath: path, sessionId: 's2');

      expect(first.view.misconceptions, isEmpty,
          reason: 'мисконцепция зафиксирована уже после старта следующей сессии');
      expect(second.view.misconceptions, <String>[kMisconceptionText]);
      // Верхняя граница выведена из старта соседней сессии, а не бесконечна.
      final warned = warningsWith(first.warnings, 'вне окна сессии');
      expect(warned, hasLength(1));
      expect(warned.single, contains('01.05.2024 11:00'));
    });

    test('последняя сессия темы: верхней границы нет (∞)', () async {
      final path = await writeDb(dir, 'последняя.db', (db) => fillFullSession(
            db,
            status: 'active',
            conceptMasteriesJson: _masteriesAt('2024-06-01T10:15:00'),
          ));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.misconceptions, <String>[kMisconceptionText]);
      expect(warningsWith(loaded.warnings, 'вне окна сессии'), isEmpty);
    });

    test('границы окна: на старте входит, на старте следующей — уже нет', () async {
      // Ровно на `startedAt` первой сессии.
      final atStart = await writeDb(dir, 'на-старте.db', (db) => fillFullSession(
            db,
            status: 'active',
            conceptMasteriesJson: _masteriesAt('2024-05-01T10:00:00'),
          ));
      // Ровно на `startedAt` следующей сессии: верхняя граница исключена.
      final atNext = await writeDb(
          dir,
          'на-старте-соседней.db',
          (db) => fillWithSecondSession(
                db,
                conceptMasteriesJson: _masteriesAt('2024-05-01T11:00:00'),
              ));

      expect((await loadSession(dbPath: atStart, sessionId: kSessionId)).view.misconceptions,
          <String>[kMisconceptionText], reason: 'нижняя граница включена');
      expect((await loadSession(dbPath: atNext, sessionId: kSessionId)).view.misconceptions,
          isEmpty, reason: 'верхняя граница исключена');
      expect((await loadSession(dbPath: atNext, sessionId: 's2')).view.misconceptions,
          <String>[kMisconceptionText], reason: 'нижняя граница следующей включена');
    });

    test('completedAt важнее старта следующей сессии', () async {
      // Сессия закрылась в 11:30, следующая началась в 11:00: окно всё равно
      // закрывается в 11:30 — явное завершение авторитетнее соседа.
      final path = await writeDb(dir, 'completed-важнее.db', (db) async {
        await db.into(db.topics).insert(TopicsCompanion.insert(
            id: kTopicId, name: 'Теорема остановки', timeBudgetMinutes: const Value(45)));
        await db.into(db.knowledgeNodes).insert(KnowledgeNodesCompanion.insert(
            id: kNodeId,
            topicId: kTopicId,
            label: 'Остановка',
            oneLiner: const Value('Не все программы завершаются.'),
            level: const Value(2),
            leaf: const Value(true)));
        await db.into(db.learningJourneys)
            .insert(LearningJourneysCompanion.insert(id: kJourneyId, topicId: kTopicId));
        await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
            id: kSessionId,
            journeyId: kJourneyId,
            topicId: kTopicId,
            startedAt: Value(DateTime(2024, 5, 1, 10)),
            completedAt: Value(DateTime(2024, 5, 1, 11, 30)),
            status: const Value('completed'),
            activityJson: const Value(kActivityJson),
            curriculumJson: const Value(kCurriculumJson)));
        await db.into(db.learningSessions).insert(_secondSession('active'));
        await db.into(db.learnerModels).insert(LearnerModelsCompanion.insert(
            id: 'lm1',
            topicId: kTopicId,
            conceptMasteriesJson: Value(_masteriesAt('2024-05-01T11:15:00'))));
      });

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.misconceptions, <String>[kMisconceptionText],
          reason: '11:15 попадает в [10:00, 11:30), хотя сосед начался в 11:00: '
              'значит верхняя граница — собственный completedAt, а не старт соседа');
      // Сессии в реальности пересеклись (первая закрылась в 11:30, вторая
      // началась в 11:00), поэтому окна перекрываются и мисконцепция видна
      // обеим. Это честнее, чем отбрасывать её по границе соседа.
      expect((await loadSession(dbPath: path, sessionId: 's2')).view.misconceptions,
          <String>[kMisconceptionText],
          reason: '11:15 попадает и в окно соседа [11:00, …)');
    });

    test('без detectedAt мисконцепция не достаётся, но потеря видна', () async {
      final path = await writeDb(dir, 'без-detectedAt.db', (db) => fillFullSession(
            db,
            status: 'active',
            conceptMasteriesJson: _masteriesAt(null),
          ));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.misconceptions, isEmpty);
      expect(loaded.view.misconceptionsByNode, isEmpty);
      expect(warningsWith(loaded.warnings, 'без detectedAt'), hasLength(1));
    });

    test('checkMisconceptionRemediation по-прежнему ловит неотработанную', () async {
      // Лекция вместо apply: узел есть, отработки нет → warn должен остаться.
      final path = await writeDb(dir, 'не-отработана.db', (db) => fillFullSession(
            db,
            activityJson: kLectureOnlyJson,
            conceptMasteriesJson: _masteriesAt('2024-05-01T10:15:00'),
          ));

      final findings = await checksOf(path);

      expect(
        tagsOf(withCode(findings, SessionCheckCode.misconceptionWithoutRemediation)),
        <String>['${SessionCheckCode.misconceptionWithoutRemediation}/warn'],
      );
    });

    test('warnings детерминированы: два прогона дают одинаковый список', () async {
      final path = await writeDb(
          dir,
          'детерминизм-окна.db',
          (db) => fillWithSecondSession(
                db,
                conceptMasteriesJson: _masteriesAt('2024-05-01T12:00:00'),
              ));

      final first = await loadSession(dbPath: path, sessionId: kSessionId);
      final second = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(second.warnings, first.warnings);
    });
  });

  group('снимок БД: оригинал не трогаем', () {
    test('WAL: сессия, записанная только в -wal, видна загрузчику', () async {
      final path = '${dir.path}${Platform.pathSeparator}wal.db';
      final db = MindtreeDb(NativeDatabase(File(path)));
      try {
        await db.customStatement('PRAGMA journal_mode=WAL');
        await fillFullSession(db);
        // Усекаем WAL, чтобы следующая вставка осталась ТОЛЬКО в -wal: так
        // проверяется, что копируются оба файла, а не один main.
        await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
        await db.into(db.learningSessions).insert(LearningSessionsCompanion.insert(
            id: 's2',
            journeyId: kJourneyId,
            topicId: kTopicId,
            startedAt: Value(DateTime.utc(2024, 5, 5, 10)),
            status: const Value('completed')));

        final loaded = await loadSessions(dbPath: path);

        expect(loaded.map((s) => s.sessionId), <String>['s2', kSessionId]);
      } finally {
        await db.close();
      }
    });

    test('после загрузки байты оригинала не меняются', () async {
      final path = await writeDb(dir, 'неизменна.db', fillFullSession);
      final before = File(path).readAsBytesSync();

      await loadSession(dbPath: path, sessionId: kSessionId);

      expect(File(path).readAsBytesSync(), before);
    });

    test('временный каталог копии удаляется', () async {
      final path = await writeDb(dir, 'уборка.db', fillFullSession);
      final before = reviewTempDirs();

      await loadSession(dbPath: path, sessionId: kSessionId);

      expect(reviewTempDirs(), before,
          reason: 'копия БД не должна оставаться в системной временной папке');
    });
  });

  // ─── Устойчивость загрузчика ───────────────────────────────────────────────
  // Регрессы от 02.10.2026: раньше каждый из этих случаев ронял ревью или
  // молча терял данные. Теперь это требование, а не описание проблемы.
  group('устойчивость загрузчика (исправлено)', () {
    test('мусор вместо SQLite → SessionLoadException с подсказкой про --db', () async {
      final path = '${dir.path}${Platform.pathSeparator}мусор.db';
      File(path).writeAsStringSync('это не база SQLite, а длинный текст подряд');

      // CLI ловит только SessionLoadException (bin/mindtree_review.dart), поэтому
      // пользователь должен получить строку с подсказкой, а не стектрейс.
      await expectLater(loadSessions(dbPath: path), throwsA(isA<SessionLoadException>()));
      try {
        await loadSessions(dbPath: path);
        fail('ожидалась SessionLoadException');
      } on SessionLoadException catch (e) {
        expect(e.message, contains('--db'));
      }
    });

    test('две journey на одну тему → берём последнюю и предупреждаем', () async {
      final path = await writeDb(dir, 'две-journey.db', (db) async {
        await fillFullSession(db);
        // Заведомо свежее, чем дефолтное `currentDateAndTime` первой journey.
        await db.into(db.learningJourneys).insert(LearningJourneysCompanion.insert(
            id: 'j2', topicId: kTopicId, createdAt: Value(DateTime.utc(2099, 6, 1))));
      });

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.warnings.where((w) => w.contains('learning_journeys')), isNotEmpty);
      // У j2 нет milestones, поэтому список пустой — главное, не исключение.
      expect(loaded.milestones, isEmpty);
    });

    test('два learner_models на одну тему → берём последний по updatedAt', () async {
      final path = await writeDb(dir, 'два-learner-model.db', (db) async {
        await fillFullSession(db);
        await db.into(db.learnerModels).insert(LearnerModelsCompanion.insert(
            id: 'lm2',
            topicId: kTopicId,
            userId: const Value('другой'),
            conceptMasteriesJson:
                const Value('[{"nodeId":"n1","understanding":0.4}]'),
            updatedAt: Value(DateTime.utc(2099, 6, 1))));
      });

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.warnings.where((w) => w.contains('learner_models')), isNotEmpty);
      // Среднее по четырём измерениям: 0.4 у одного, нули у остальных.
      expect(loaded.view.masteryAfter[kNodeId], closeTo(0.1, 1e-9),
          reason: 'актуальная модель — последняя по updatedAt');
    });

    test('вопрос без id → сессия грузится, вопрос пропущен с предупреждением',
        () async {
      final path = await writeDb(dir, 'вопрос-без-id.db',
          (db) => fillFullSession(db, questionsJson: '[{"nodeId":"n1"}]'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.questions, isEmpty);
      expect(warningsWith(loaded.warnings, 'Вопрос'), isNotEmpty);
    });

    test('conceptMastery без nodeId → сессия грузится, запись пропущена', () async {
      final path = await writeDb(dir, 'mastery-без-node.db',
          (db) => fillFullSession(db, conceptMasteriesJson: '[{"understanding":0.5}]'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.masteryAfter, isEmpty);
      expect(warningsWith(loaded.warnings, 'concept_mastery'), isNotEmpty);
    });

    test('activity_json не массив → активности пустые, но потеря видна', () async {
      final path = await writeDb(dir, 'activity-не-массив.db',
          (db) => fillFullSession(db, activityJson: '{"steps":[]}'));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.activities, isEmpty);
      expect(warningsWith(loaded.warnings, 'activity_json'), isNotEmpty,
          reason: 'потеря активностей не должна быть молчаливой');
    });

    test('оценка assessments.score сверяется с долей верных попыток', () async {
      // Ответ буквально совпадает с эталом, а в БД correct == false и score == 0.
      final path = await writeDb(dir, 'score-противоречие.db',
          (db) => fillFullSession(db, assessmentScore: 0, attemptCorrect: false));

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);
      final question = loaded.view.questions.single;

      expect(question.userAnswer, question.correctAnswer,
          reason: 'ответ ученика буквально равен эталону');
      expect(question.correct, isFalse, reason: 'вердикт в БД: неверно');
      expect(loaded.view.assessments.single.recordedScore, 0);
      expect(loaded.view.assessments.single.actualRatio, 0);
      // Главное: такой ответ портит mastery, и это must-fix, не warn.
      expect(
        withCode(runSessionChecks(loaded.view),
            SessionCheckCode.verdictContradictsAnswer),
        isNotEmpty,
        reason: 'ответ равен эталону, но correct == false — ревью обязано кричать',
      );
    });

    test('балл оценки расходится с долей верных попыток', () async {
      // Три попытки, две верные (2/3), а в базе score = 0.9 — расхождение 0.23.
      final path = await writeDb(dir, 'score-расхождение.db', (db) async {
        await fillFullSession(db, assessmentScore: 0.9, attemptCorrect: true);
        await db.into(db.assessmentAttempts).insert(AssessmentAttemptsCompanion.insert(
            id: 'at2',
            assessmentId: 'a1',
            questionId: 'q2',
            answer: 'неверный вариант',
            correct: Value(false)));
        await db.into(db.assessmentAttempts).insert(AssessmentAttemptsCompanion.insert(
            id: 'at3',
            assessmentId: 'a1',
            questionId: 'q3',
            answer: 'ещё один правильный',
            correct: Value(true)));
      });

      final loaded = await loadSession(dbPath: path, sessionId: kSessionId);

      expect(loaded.view.assessments.single.attempts, 3);
      expect(loaded.view.assessments.single.correctAttempts, 2);
      expect(
        withCode(runSessionChecks(loaded.view), SessionCheckCode.scoreMismatch),
        isNotEmpty,
      );
    });
  });
}
