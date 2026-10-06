import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/feedback_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _nodeId = 'n1~abc12345';

/// Детерминированный fake-транспорт: activity feedback можно переопределить
/// (вердикт, падение), всё остальное — стандартный `FakeLlm`.
class _FeedbackLlm {
  final FakeLlm fake = FakeLlm();
  Map<String, dynamic>? feedbackResult;
  bool failFeedback = false;

  /// Маркер feedback-промпта — общий с `PromptKind.activityFeedback`
  /// (см. `tool/probe/fake_llm.dart`).
  static const _feedbackMarker = 'Оцениваешь свободный ответ ученика';

  Future<llm_client.LLMResult> invoke(
    llm_client.LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) async {
    if (prompt.contains(_feedbackMarker)) {
      if (failFeedback) throw Exception('llm unavailable (test)');
      final result = feedbackResult ??
          {
            'assessment': 'partial',
            'feedback': 'Ход мысли верный, но не хватает конкретики.',
            'misconception': null,
          };
      return llm_client.LLMResult(
        text: jsonEncode(result),
        usage: const llm_client.LLMUsage(inputTokens: 1, outputTokens: 1),
      );
    }
    return fake.invoke(
      cfg,
      prompt,
      model: model,
      temperature: temperature,
      seed: seed,
    );
  }
}

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;
  late _FeedbackLlm llm;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    llm = _FeedbackLlm();
    engines = buildEngines(
      repo: repo,
      configProvider: () => const llm_client.LLMConfig(
        isMock: true,
        temperature: 0,
        numCtx: 16384,
      ),
      schedulerConfig: const SchedulerConfig(
        maxRPM: 100000,
        maxRPD: 100000,
        maxConcurrency: 1,
        maxRetries: 0,
      ),
      llmCall: (cfg, prompt, {model, temperature, seed}) =>
          llm.invoke(cfg, prompt, model: model, temperature: temperature, seed: seed),
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([
      KnowledgeNode(
        id: _nodeId,
        topicId: _topicId,
        parentId: null,
        level: 1,
        label: 'Теорема остановки',
        oneLiner: 'Однозначное утверждение о свойствах итеративных вычислений.',
        details: 'Подробности корня.',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<LearningSession> newSession() =>
      engines.session.create(CreateSessionInput(
        topicId: _topicId,
        goal: 'overview',
        timeBudgetMinutes: 15,
      ));

  /// Индекс шага `apply` в свежей активности (explain=0, example=1, recall=2).
  Future<LearningActivity> ensureAndApply(String sessionId) async {
    final activity = await engines.activity.ensureActivity(sessionId);
    expect(activity.steps.map((s) => s.type),
        ['explain', 'example', 'recall', 'apply']);
    return activity;
  }

  Future<ConceptProfile?> profile() =>
      engines.learnerModel.getConceptProfile(_nodeId, _topicId);

  Future<Object?> eventField(String sessionId, String key) async {
    final events = await repo.listEvents(sessionId);
    final ev = events.firstWhere(
      (e) => e.type == LearningEventType.activityAnswer,
    );
    return ev.data[key];
  }

  group('FeedbackEngine через activity.answer', () {
    test('apply верный: application/understanding растут на 0.5, SRS растёт',
        () async {
      llm.feedbackResult = {
        'assessment': 'correct',
        'feedback': 'Верно, применение названо.',
        'misconception': null,
      };
      final session = await newSession();
      await ensureAndApply(session.id);

      final answered =
          await engines.activity.answer(session.id, 3, 'применяем понятие к задаче');

      expect(answered.steps[3].correct, isTrue);
      final p = await profile();
      expect(p, isNotNull);
      expect(p!.application, closeTo(0.5, 1e-9));
      expect(p.understanding, closeTo(0.5, 1e-9));
      // Не измеренные измерения не выдуманы.
      expect(p.recall, 0);
      expect(p.transfer, 0);
      expect(p.srsInterval, greaterThan(0));
      expect(p.errors, isEmpty);
    });

    test('apply неверный: applicationFailure, careless не пишется', () async {
      // Сначала верный ответ: интервал 1, application 0.5.
      llm.feedbackResult = {
        'assessment': 'correct',
        'feedback': 'Верно.',
        'misconception': null,
      };
      final s1 = await newSession();
      await ensureAndApply(s1.id);
      await engines.activity.answer(s1.id, 3, 'правильное применение');

      // Новый проход по тому же концепту: неверный ответ обнуляет SRS.
      llm.feedbackResult = {
        'assessment': 'incorrect',
        'feedback': 'Это не применение понятия.',
        'misconception': null,
      };
      final s2 = await newSession();
      await ensureAndApply(s2.id);
      final answered =
          await engines.activity.answer(s2.id, 3, 'не то применение');

      expect(answered.steps[3].correct, isFalse);
      final p = await profile();
      expect(p, isNotNull);
      expect(p!.srsInterval, 0, reason: 'неверный ответ сбрасывает интервал');
      expect(p.application, closeTo(0.25, 1e-9));
      expect(p.errors.map((e) => e.type),
          [MisconceptionType.applicationFailure]);
      expect(p.errors.map((e) => e.description).single, isNotEmpty);
    });

    test('LLM недоступен: модель, SRS и мисконцепции не трогаются', () async {
      // Накопим модель и SRS реальным верным ответом.
      llm.feedbackResult = {
        'assessment': 'correct',
        'feedback': 'Верно.',
        'misconception': null,
      };
      final s1 = await newSession();
      await ensureAndApply(s1.id);
      await engines.activity.answer(s1.id, 3, 'правильное применение');
      final before = await profile();
      expect(before!.srsInterval, greaterThan(0));

      // Отказ инфраструктуры: смотрим, что не сломалось.
      llm.failFeedback = true;
      final s2 = await newSession();
      await ensureAndApply(s2.id);
      final answered =
          await engines.activity.answer(s2.id, 3, 'ответ не по существу');

      final after = await profile();
      expect(after!.application, before.application);
      expect(after.understanding, before.understanding);
      expect(after.srsInterval, before.srsInterval);
      expect(after.errors, isEmpty);
      // Activity-step честно «не оценено», без score в событии.
      expect(answered.steps[3].correct, isNull);
      expect(answered.steps[3].feedback, isNotEmpty);
      expect(await eventField(s2.id, 'evaluated'), isFalse);
      expect((await repo.listEvents(s2.id))
          .firstWhere((e) => e.type == LearningEventType.activityAnswer)
          .data
          .containsKey('score'), isFalse);
    });

    test('partial от живого LLM: SRS нейтрален, incomplete вместо careless',
        () async {
      // Верный ответ: interval 1, application 0.5.
      llm.feedbackResult = {
        'assessment': 'correct',
        'feedback': 'Верно.',
        'misconception': null,
      };
      final s1 = await newSession();
      await ensureAndApply(s1.id);
      await engines.activity.answer(s1.id, 3, 'правильное применение');

      // Ещё один верный: interval 3 (SM-2 1→3), application 0.75.
      final s2 = await newSession();
      await ensureAndApply(s2.id);
      await engines.activity.answer(s2.id, 3, 'снова правильное применение');
      final seeded = await profile();
      expect(seeded!.srsInterval, 3);

      // Частично верный: SRS не двигается (не 0 и не 6), evidence пишется.
      llm.feedbackResult = null; // FakeLlm-дефолт: partial + misconception.
      final s3 = await newSession();
      await ensureAndApply(s3.id);
      final answered =
          await engines.activity.answer(s3.id, 3, 'ход мысли верный, нет примера');

      expect(answered.steps[3].correct, isFalse);
      final p = await profile();
      expect(p!.srsInterval, 3,
          reason: 'partial — это «не совсем верно», а не ошибка и не повторение');
      expect(p.application, closeTo(0.625, 1e-9),
          reason: 'evidence за partial всё же пишется: 0.75+0.5 → 0.5');
      expect(p.errors.map((e) => e.type), [MisconceptionType.incomplete]);
      expect(p.errors.map((e) => e.type), isNot(contains(MisconceptionType.careless)));
    });

    test('recall верный: recall/understanding растут, SRS растёт', () async {
      final session = await newSession();
      final activity = await ensureAndApply(session.id);
      final step = activity.steps[2];
      final chosen = step.correctIndex.toString();

      final answered = await engines.activity.answer(session.id, 2, chosen);

      expect(answered.steps[2].correct, isTrue);
      final p = await profile();
      expect(p!.recall, closeTo(0.5, 1e-9));
      expect(p.understanding, closeTo(0.5, 1e-9));
      expect(p.application, 0);
      expect(p.srsInterval, greaterThan(0));
      expect(p.errors, isEmpty);
    });

    test('recall неверный: recall 0 и интервал сброшен, confused без careless',
        () async {
      final s1 = await newSession();
      var activity = await ensureAndApply(s1.id);
      await engines.activity
          .answer(s1.id, 2, activity.steps[2].correctIndex.toString());
      final seeded = await profile();
      expect(seeded!.srsInterval, greaterThan(0));

      final s2 = await newSession();
      activity = await ensureAndApply(s2.id);
      final wrong =
          activity.steps[2].correctIndex == 0 ? '1' : '0';
      final answered = await engines.activity.answer(s2.id, 2, wrong);

      expect(answered.steps[2].correct, isFalse);
      final p = await profile();
      expect(p!.srsInterval, 0, reason: 'ошибка обнуляет интервал');
      expect(p.recall, closeTo(0.25, 1e-9));
      expect(p.errors.map((e) => e.type), [MisconceptionType.confused]);
      expect(
        p.errors.map((e) => e.type),
        isNot(contains(MisconceptionType.careless)),
        reason: 'шаг активности знает тип ошибки точнее, чем careless',
      );
    });
  });

  group('FeedbackEngine без вариантов', () {
    test('recall без вариантов: не оценено, модель не трогается', () async {
      final result = await engines.feedback.evaluateRecall(
        _topicId,
        'Теорема остановки',
        _nodeId,
        'Теорема остановки',
        const RecallStepInput(),
        0,
      );
      expect(result.evaluated, isFalse);
      expect(result.quality, kQualityUnevaluated);
      expect(result.feedback, isNotEmpty);
      expect(await profile(), isNull);
    });
  });
}