import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/engines/feedback_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Scheduler-заглушка: отдаёт заданный JSON ответа на шаг «apply»
/// (или падает, если [fail]). Ответ идёт через настоящий parseFn — так
/// тест проверяет ровно тот путь, что и живой scheduler.
class _StubScheduler extends TreeScheduler {
  int calls = 0;
  final Map<String, dynamic> response;
  final bool fail;

  _StubScheduler({this.response = const {}, this.fail = false})
      : super(configProvider: () => const llm_client.LLMConfig(isMock: true));

  @override
  Future<ExecuteResult<T>> execute<T>(
    String operation,
    String Function() promptFn,
    T Function(String raw) parseFn, {
    String? cacheKey,
    List<String>? nodeIds,
    String? promptVersion,
    String? model,
    double? temperature,
  }) async {
    calls++;
    if (fail) throw Exception('LLM down (test)');
    final raw = jsonEncode(response);
    return ExecuteResult<T>(
      result: parseFn(raw),
      llmResult: llm_client.LLMResult(text: raw),
    );
  }
}

const _nodeId = 'n1~abcdef01';

const _reference = 'Производная показывает скорость изменения функции: '
    'сначала берут приращения, потом отношение и переходят к пределу.';

const _instruction = 'Объясните своими словами, что такое производная, '
    'и приведите пример.';

const _userAnswer = 'Производная показывает скорость изменения функции: '
    'берут приращения.';

KnowledgeNode _node() => KnowledgeNode(
      id: _nodeId,
      topicId: 't1',
      parentId: null,
      level: 1,
      label: 'Производная',
      oneLiner: 'Предел отношения приращения функции к приращению аргумента.',
      details: 'Подробное объяснение производной для теста.',
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late _StubScheduler scheduler;
  late LearningSessionEngine engine;

  /// Сервис поверх нужного scheduler: путь `answer` зовёт LLM сам.
  /// Оценку ответа делает `FeedbackEngine` — тот же движок, что в приложении.
  LearningActivityService withScheduler(_StubScheduler sch) =>
      LearningActivityService(
        engine: engine,
        repo: repo,
        scheduler: sch,
        feedback: FeedbackEngine(repo: repo, scheduler: sch),
      );

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    scheduler = _StubScheduler();
    engine = LearningSessionEngine(
      repo: repo,
      scheduler: scheduler,
      learnerModel: LearnerModelService(repo),
      reviewScheduler: ReviewScheduler(repo),
      eventBus: EventBus(repo),
      curriculumEngine: CurriculumEngine(repo: repo, scheduler: scheduler),
      assessmentEngine: AssessmentEngine(repo: repo, scheduler: scheduler),
    );
    await repo.createTopic(
      const Topic(id: 't1', name: 'Математический анализ'),
    );
    await repo.createJourney('j1', 't1');
    await repo.insertNodes([_node()]);
  });

  tearDown(() async {
    await db.close();
  });

  /// Сессия с одним готовым шагом «apply»: LLM зовётся ровно один раз —
  /// на оценку ответа, без генерации шагов.
  Future<void> seedApplySession(String sessionId) async {
    final step = ActivityStep(
      type: 'apply',
      title: 'Применяем на практике',
      instruction: _instruction,
      bestAnswer: _reference,
      status: 'pending',
    );
    await repo.createSession(LearningSession(
      id: sessionId,
      journeyId: 'j1',
      topicId: 't1',
      curriculum: Curriculum(
        sessionId: sessionId,
        items: [
          CurriculumItem(
            id: 'i1',
            nodeId: _nodeId,
            label: 'Производная',
            order: 0,
            estimatedMinutes: 5,
          ),
        ],
      ),
      activityJson: jsonEncode({
        'itemId': 'i1',
        'steps': [step.toJson()],
      }),
    ));
  }

  /// Поле данных события `activity_answer` (в т.ч. отсутствующее → `null`).
  Future<Object?> eventField(String sessionId, String key) async {
    final events = await repo.listEvents(sessionId);
    final ev = events.firstWhere(
      (e) => e.type == LearningEventType.activityAnswer,
    );
    return ev.data[key];
  }

  /// Score из события `activity_answer`: наружу вердикт уходит только туда.
  Future<double?> answerScore(String sessionId) async {
    final raw = await eventField(sessionId, 'score');
    return raw is num ? raw.toDouble() : null;
  }

  /// Мисконцепции концепта — то, что реально легло в модель ученика.
  Future<List<Misconception>> misconceptionsOf(
    String nodeId,
    String topicId,
  ) async =>
      (await LearnerModelService(repo).getConceptProfile(nodeId, topicId))?.errors ??
      const <Misconception>[];

  group('FeedbackEngine.evaluateApply: санитизация ответа LLM', () {
    test('ответ без ключа feedback получает фидбек из эвристики по эталону',
        () async {
      await seedApplySession('s1');
      // Раньше модель могла вернуть корректный JSON без `feedback` — и
      // вердикт уезжал в БД с feedback='' (ревью: session_feedback_missing).
      final noFeedback = _StubScheduler(response: {'assessment': 'correct'});

      final activity =
          await withScheduler(noFeedback).answer('s1', 0, _userAnswer);

      final step = activity.steps.first;
      expect(step.correct, isTrue); // вердикт из assessment сохранён
      expect(step.feedback, isNotEmpty);
      expect(step.feedback, heuristicApplyFeedback(_reference, _userAnswer));
      expect(noFeedback.calls, 1);
    });

    test('пустой (пробельный) feedback так же заменяется эвристикой', () async {
      await seedApplySession('s1');
      final blank = _StubScheduler(
        response: {'assessment': 'partial', 'feedback': '   '},
      );

      final activity = await withScheduler(blank).answer('s1', 0, _userAnswer);

      expect(activity.steps.first.feedback,
          heuristicApplyFeedback(_reference, _userAnswer));
    });

    test('мусорный assessment даёт нейтральный partial, а не score 0.0',
        () async {
      await seedApplySession('s1');
      // «Верно» не из контракта: без санитизации это ложный вердикт
      // «неверно» с нулём в score.
      final junk = _StubScheduler(
        response: {'assessment': 'Верно', 'feedback': 'Ответ принят.'},
      );

      final activity = await withScheduler(junk).answer('s1', 0, _userAnswer);

      final step = activity.steps.first;
      expect(step.correct, isFalse); // не correct, но и не «ошибка»
      expect(step.feedback, 'Ответ принят.');
      expect(await answerScore('s1'), 0.5);
    });

    test('assessment с лишними пробелами не ломает вердикт', () async {
      await seedApplySession('s1');
      final spaced = _StubScheduler(
        response: {'assessment': 'correct ', 'feedback': 'Всё верно.'},
      );

      final activity = await withScheduler(spaced).answer('s1', 0, _userAnswer);

      expect(activity.steps.first.correct, isFalse);
      expect(await answerScore('s1'), 0.5);
    });

    test('нормальный успешный ответ ведёт себя как раньше', () async {
      await seedApplySession('s1');
      final ok = _StubScheduler(
        response: {
          'assessment': 'correct',
          'feedback': 'Верно: вы назвали смысл и привели пример.',
        },
      );

      final activity = await withScheduler(ok).answer('s1', 0, _userAnswer);

      final step = activity.steps.first;
      expect(step.correct, isTrue);
      expect(step.feedback, 'Верно: вы назвали смысл и привели пример.');
      expect(step.status, 'answered');
      expect(await answerScore('s1'), 1.0);
    });

    test('верный incorrect сохраняет отрицательный вердикт', () async {
      await seedApplySession('s1');
      final bad = _StubScheduler(
        response: {
          'assessment': 'incorrect',
          'feedback': 'Вы описали скорость, но не объяснили предел.',
        },
      );

      final activity = await withScheduler(bad).answer('s1', 0, 'не знаю');

      expect(activity.steps.first.correct, isFalse);
      expect(await answerScore('s1'), 0.0);
    });

test('падение LLM: correct == null и непустой детерминированный фидбек',
        () async {
      await seedApplySession('s1');
      final down = _StubScheduler(fail: true);

      final activity = await withScheduler(down).answer('s1', 0, _userAnswer);

      final step = activity.steps.first;
      // Отказ инфраструктуры — не вердикт по ответу: шаг не помечается ни
      // верным, ни неверным (correct == null → бейдж «Принято» и в
      // deriveCompletionQuality нет свидетельства «ошибки»).
      expect(step.correct, isNull);
      expect(step.feedback, isNotEmpty);
      expect(step.feedback, heuristicApplyFeedback(_reference, _userAnswer));
      // Score не выдумывается: в событии его нет вовсе.
      expect(await answerScore('s1'), isNull);
      expect(await eventField('s1', 'evaluated'), isFalse);
    });

    test('падение LLM не заводит ни mastery, ни мисконцепций', () async {
      await seedApplySession('s1');

      await withScheduler(_StubScheduler(fail: true)).answer('s1', 0, _userAnswer);

      // Пустой ответ ученика не должен оставить после себя след в модели:
      // раньше здесь появлялась запись application=0.5 и мисконцепция `careless`.
      expect(
        await LearnerModelService(repo).getConceptProfile(_nodeId, 't1'),
        isNull,
      );
      expect(await misconceptionsOf(_nodeId, 't1'), isEmpty);
    });
  });
}