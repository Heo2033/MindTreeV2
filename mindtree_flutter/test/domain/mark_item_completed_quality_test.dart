// Интеграционный регресс бага «Завершить концепт всегда засчитывает верный ответ».
//
// `LearningSessionEngine.markItemCompleted` жёстко дефолтил `quality` в
// 'correct', а UI его не передавал → «Завершить концефт» всегда давал
// +0.15 recall / +0.1 understanding и продлевал интервал SRS независимо от
// ответов ученика на шаги концепта.
//
// Тест проверяет РЕАЛЬНЫЙ вызов движка: в сессию кладётся строка
// `activity_json` той же формы, что пишет `LearningActivityService._persistSteps`
// (`{'itemId': ..., 'steps': [...]}`), и дальше:
//   • ошибочный шаг  → `onAnswered(..., 'again')` (интервал 0, ease ниже,
//     ложная мисконцепция `careless` НЕ пишется);
//   • все верные      → `onAnswered(..., 'correct')` (интервал растёт,
//     мастерство подрастает);
//   • явный quality   → escape hatch, вызывающий решает сам.
//
// БД — `NativeDatabase.memory()`, LLM — детерминированный `FakeLlm` из
// `tool/probe/fake_llm.dart`: ни сети, ни ключей, ни Random() в пути.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _rootId = 'n1_topic~$_scope';

/// SRS-приёмник: пишет вызовы как есть, семантику `onAnswered` не меняет
/// (тот же приём, что в `test/ui/screens/quiz_screen_srs_test.dart`).
class _CapturingReviewScheduler extends ReviewScheduler {
  _CapturingReviewScheduler(super.repo);

  final List<({String topicId, String nodeId, String quality})> calls = [];

  /// Что движок передал как свидетельства по измерениям. Закрытие пункта плана
  /// — не ответ, поэтому здесь всегда пустая карта (см. `markItemCompleted`).
  final List<Map<String, double>?> evidences = [];

  @override
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {
    calls.add((topicId: topicId, nodeId: nodeId, quality: quality));
    evidences.add(evidence);
  }
}

KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзорная тема раздела.',
      details: 'Подробности корня.',
    );

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

ActivityStep _step(String type, {bool? correct}) => ActivityStep(
      type: type,
      title: 'Шаг $type',
      status: 'answered',
      correct: correct,
    );

/// Blob той же формы, что пишет `LearningActivityService._persistSteps`.
String _blob(String itemId, List<ActivityStep> steps) => jsonEncode({
      'itemId': itemId,
      'steps': [for (final s in steps) s.toJson()],
    });

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;
  late _CapturingReviewScheduler capturing;

  /// Движок с тем же графом, что у приложения, но с пишущим SRS-приёмником.
  late LearningSessionEngine engine;

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
    capturing = _CapturingReviewScheduler(repo);
    engine = LearningSessionEngine(
      repo: repo,
      scheduler: engines.scheduler,
      learnerModel: engines.learnerModel,
      reviewScheduler: capturing,
      eventBus: engines.events,
      curriculumEngine: engines.curriculum,
      assessmentEngine: engines.assessment,
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([_root(), _child(1), _child(2), _child(3)]);
  });

  tearDown(() async {
    await db.close();
  });

  CreateSessionInput input() => CreateSessionInput(
        topicId: _topicId,
        goal: 'понимание',
        timeBudgetMinutes: 30,
      );

  /// Сессия с первым пунктом плана и blob активности, собранным из [steps]
  /// (та же форма, что у `LearningActivityService._persistSteps`).
  Future<({LearningSession session, CurriculumItem item})> sessionWithSteps(
    List<ActivityStep> steps,
  ) async {
    final session = await engines.session.create(input());
    final item = session.curriculum.items.first;
    await repo.updateSession(session.copyWith(
      activityJson: () => _blob(item.id, steps),
    ));
    return (session: session, item: item);
  }

  /// Сессия с произвольным (в т.ч. битым) содержимым `activity_json`.
  Future<({LearningSession session, CurriculumItem item})> sessionWithRawBlob(
    String blob,
  ) async {
    final session = await engines.session.create(input());
    final item = session.curriculum.items.first;
    await repo.updateSession(session.copyWith(activityJson: () => blob));
    return (session: session, item: item);
  }

  group('markItemCompleted: качество выводится из шагов активности', () {
    test('ошибочный шаг → onAnswered с again', () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('explain', correct: null),
        _step('recall', correct: true),
        _step('apply', correct: false),
      ]);

      await engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      expect(capturing.calls, [
        (topicId: _topicId, nodeId: item.nodeId, quality: 'again'),
      ]);
    });

    test('все шаги верные → onAnswered с correct', () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('explain', correct: null),
        _step('example', correct: null),
        _step('recall', correct: true),
        _step('apply', correct: true),
      ]);

      await engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      expect(capturing.calls, [
        (topicId: _topicId, nodeId: item.nodeId, quality: 'correct'),
      ]);
    });

    test('только read-шаги (correct == null) → correct, а не again', () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('explain', correct: null),
        _step('example', correct: null),
      ]);

      await engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      expect(capturing.calls.single.quality, 'correct');
    });

    test('концепт без активности → correct и НЕ бросает (прежнее поведение)',
        () async {
      // Активность не запускалась: в БД blob не записан, а колонка по
      // умолчанию хранит '[]'. Данных нет — ошибки тоже нет, поэтому
      // поведение прежнее: 'correct'.
      final s = await engines.session.create(input());
      final item = s.curriculum.items.first;

      await expectLater(
        engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId),
        completes,
      );
      expect(capturing.calls.single.quality, 'correct');
    });

    test('пустая строка activityJson → correct, без исключения', () async {
      final (session: s, item: item) = await sessionWithRawBlob('');

      await expectLater(
        engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId),
        completes,
      );
      expect(capturing.calls.single.quality, 'correct');
    });

    test('мусор в activityJson → correct, без исключения', () async {
      final (session: s, item: item) = await sessionWithRawBlob('{не json');

      await expectLater(
        engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId),
        completes,
      );
      expect(capturing.calls.single.quality, 'correct');
    });

    test('явный quality — escape hatch: вызывающий решает сам', () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('recall', correct: true),
      ]);

      await engine.markItemCompleted(s.id, item.id,
          nodeId: item.nodeId, quality: 'incorrect');

      expect(capturing.calls.single.quality, 'incorrect',
          reason: 'явно переданное качество не перебивается выводом');
    });

    test('без nodeId SRS не трогаем вовсе', () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('recall', correct: false),
      ]);

      await engine.markItemCompleted(s.id, item.id);

      expect(capturing.calls, isEmpty);
    });
  });

  group('markItemCompleted: публичное поведение не изменилось', () {
    test('пункт помечен завершённым, индекс сдвинут, activityJson очищен',
        () async {
      final (session: s, item: item) = await sessionWithSteps([
        _step('recall', correct: false),
      ]);

      await engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      final after = await repo.getSession(s.id);
      expect(after!.curriculum.items.first.status, CurriculumItemStatus.completed);
      expect(after.currentIndex, 1);
      expect(after.activityJson, '[]',
          reason: 'blob активности стирается — в колонке остаётся дефолт БД');
    });

    test('несуществующая сессия — тихий выход', () async {
      await expectLater(
        engine.markItemCompleted('s_нет~$_scope', 'ci_нет~$_scope'),
        completes,
      );
      expect(capturing.calls, isEmpty);
    });
  });

  group('Реальный ReviewScheduler: состояние мастерства и SRS', () {
    test('ошибочный шаг → интервал сброшен, мастерство НЕ растёт', () async {
      // Здесь движок настоящий (engines.session), т.е. работает
      // ReviewScheduler.onAnswered. Главное отличие 'again' от прежнего
      // 'correct': мастерство не раздувается (+0.15 recall / +0.1
      // understanding больше не капает) и интервал сбрасывается.
      final s = await engines.session.create(input());
      final item = s.curriculum.items.first;
      await repo.updateSession(s.copyWith(
        activityJson: () => _blob(item.id, [
          _step('explain', correct: null),
          _step('recall', correct: false),
        ]),
      ));

      await engines.session
          .markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      final profile =
          await engines.learnerModel.getConceptProfile(item.nodeId, _topicId);
      expect(profile, isNotNull);
      expect(profile!.srsInterval, 0, reason: 'интервал обязан сброситься');
      expect(profile.srsEase, lessThan(2.5));
      expect(profile.recall, 0, reason: 'ошибка не должна повышать recall');
      expect(profile.understanding, 0);
    });

    test('again НЕ пишет ложную мисконцепцию careless', () async {
      // `again` означает «нужен повтор скоро» (ошибка на шаге при изучении
      // концепта), а НЕ «небрежный ответ на карточке повторения».
      // Раньше ReviewScheduler писал misconception в ветке `else` — для любого
      // quality != 'correct'; теперь только для 'incorrect'
      // (review_scheduler.dart — и синхронно server/src/domain/ReviewScheduler.ts).
      final s = await engines.session.create(input());
      final item = s.curriculum.items.first;
      await repo.updateSession(s.copyWith(
        activityJson: () => _blob(item.id, [_step('recall', correct: false)]),
      ));

      await engines.session
          .markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      final profile =
          await engines.learnerModel.getConceptProfile(item.nodeId, _topicId);
      expect(profile!.errors, isEmpty,
          reason: 'again — это «повтор скоро», а не выдуманная ошибка');
      expect(profile.srsInterval, 0, reason: 'интервал сброшен: нужен повтор');
    });

    test('явный incorrect по-прежнему пишет мисконцепцию', () async {
      final s = await engines.session.create(input());
      final item = s.curriculum.items.first;

      await engines.session.markItemCompleted(s.id, item.id,
          nodeId: item.nodeId, quality: 'incorrect');

      final profile =
          await engines.learnerModel.getConceptProfile(item.nodeId, _topicId);
      expect(profile!.errors.map((e) => e.type), [MisconceptionType.careless]);
    });

    test('все верные → интервал вырос, мастерство НЕ выросло', () async {
      final s = await engines.session.create(input());
      final item = s.curriculum.items.first;
      await repo.updateSession(s.copyWith(
        activityJson: () => _blob(item.id, [
          _step('recall', correct: true),
          _step('apply', correct: true),
        ]),
      ));

      await engines.session
          .markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      final profile =
          await engines.learnerModel.getConceptProfile(item.nodeId, _topicId);
      expect(profile, isNotNull);
      expect(profile!.srsInterval, greaterThan(0));
      expect(profile.srsEase, greaterThan(2.5));
      // Закрытие пункта плана — не ответ: измерения за эти шаги уже записал
      // FeedbackEngine. Раньше кнопка «Завершить концепт» давала ещё и
      // +0.15 recall / +0.1 understanding «за сам факт закрытия».
      expect(profile.recall, 0);
      expect(profile.understanding, 0);
      expect(profile.errors, isEmpty);
    });

    test('закрытие концепта передаёт пустые свидетельства', () async {
      final s = await engine.create(input());
      final item = s.curriculum.items.first;
      await engine.markItemCompleted(s.id, item.id, nodeId: item.nodeId);

      expect(capturing.calls.single.quality, 'correct');
      expect(capturing.evidences.single, isEmpty,
          reason: 'у закрытия пункта плана нет свидетельств по измерениям');
    });
  });
}
