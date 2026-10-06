import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/final_assessment_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';
const _n2 = 'n2~ab02';

/// Регрессия: записи финиша итогового теста (`finalize` + цикл
/// `ReviewScheduler.onAnswered`) обязаны идти с `await` и вне `setState`.
///
/// `LearnerModelService` пишет mastery/SRS read-modify-write ВСЕЙ строки
/// `learner_models`, поэтому не-awaited вызовы в цикле конфликтуют и часть
/// инкрементов теряется.
///
/// Тест детерминирован без таймеров: каждый вызов «зависает» на Completer,
/// который завершает только тест. Отсюда:
///  * после финиша начат ровно ОДИН вызов — цикл реально ждёт записи;
///  * следующий вызов появляется только после завершения предыдущего;
///  * к концу теста счётчик завершённых вызовов равен числу вызовов.
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Assessment-движок без LLM: фиксированный тест из двух закрытых вопросов,
/// `finalize` — рукопожатие через Completer (см. комментарий к тесту).
class _FakeAssessmentEngine extends AssessmentEngine {
  _FakeAssessmentEngine(MindtreeRepository repo)
      : super(
          repo: repo,
          scheduler: TreeScheduler(
            configProvider: () => const llm_client.LLMConfig(isMock: true),
          ),
        );

  /// Сколько раз вошли в `finalize` — заполняется синхронно при вызове.
  int finalizeEntered = 0;

  /// Сколько раз `finalize` реально завершился (после `await`).
  int finalizeCompleted = 0;

  final List<Completer<void>> _pending = [];

  void completeFinalize() => _pending.removeAt(0).complete();

  @override
  Future<Assessment> generate(
    String sessionId,
    String topicId,
    List<AssessmentItem> items, {
    AssessmentType type = AssessmentType.final_,
    int questionCount = 6,
    bool includeApplication = true,
  }) async {
    return const Assessment(
      id: 'asmt_final',
      sessionId: 'final_т1',
      type: AssessmentType.final_,
      startedAt: '2026-01-01T00:00:00.000',
      questions: [
        AssessmentQuestion(
          id: 'q1',
          nodeId: _n1,
          question: 'Что такое производная?',
          options: ['Вариант А', 'Вариант Б', 'Вариант В'],
          correctAnswer: '1',
          explanation: 'Скорость изменения функции в точке.',
        ),
        AssessmentQuestion(
          id: 'q2',
          nodeId: _n2,
          question: 'Что такое интеграл?',
          options: ['Вариант А', 'Вариант Б', 'Вариант В'],
          correctAnswer: '1',
          explanation: 'Площадь под кривой.',
        ),
      ],
    );
  }

  @override
  Future<void> recordAttempt(
    String assessmentId,
    String questionId,
    String answer,
    bool correct,
    int timeMs, {
    String? feedback,
  }) async {}

  @override
  Future<void> finalize(String assessmentId, double score) async {
    finalizeEntered++;
    final completer = Completer<void>();
    _pending.add(completer);
    await completer.future;
    finalizeCompleted++;
  }
}

/// SRS-приёмник: вызовы фиксируются СИНХРОННО в теле `onAnswered`
/// (async-тело выполняется до первого `await`), а сам future завершается
/// только когда тест вызовет [completeNext] — так видно, что цикл экрана
/// ждёт каждую запись.
class _CapturingReviewScheduler extends ReviewScheduler {
  _CapturingReviewScheduler(super.repo);

  final List<({String topicId, String nodeId, String quality})> calls = [];
  final List<Completer<void>> _pending = [];

  /// Сколько вызовов реально завершено (future отдана экрану выполненной).
  int completed = 0;

  bool get hasPending => _pending.isNotEmpty;

  void completeNext() => _pending.removeAt(0).complete();

  @override
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {
    calls.add((topicId: topicId, nodeId: nodeId, quality: quality));
    final completer = Completer<void>();
    _pending.add(completer);
    await completer.future;
    completed++;
  }
}

/// Активная сессия — иначе на стартовой карточке нет кнопки запуска теста.
LearningSession _session() => LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      goal: 'overview',
    );

void main() {
  testWidgets(
      'финиш: correct/incorrect уходят в SRS по одному, в порядке вопросов, '
      'с await (finalize → цикл onAnswered)', (tester) async {
    final db = MindtreeDb(NativeDatabase.memory());
    final repo = MindtreeRepository(db);
    addTearDown(db.close);

    final engine = _FakeAssessmentEngine(repo);
    final srs = _CapturingReviewScheduler(repo);

    final container = ProviderContainer(overrides: [
      graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
      assessmentEngineProvider.overrideWith((ref) => engine),
      reviewSchedulerProvider.overrideWith((ref) => srs),
      // Экран читает репозиторий при старте (поиск незавершённого теста) —
      // переопределяем, чтобы тест не трогал настоящий файл БД.
      repositoryProvider.overrideWith((ref) async => repo),
    ]);
    addTearDown(container.dispose);

    container.read(graphStoreProvider.notifier).state = const GraphState(
      topicId: _topicId,
      topicName: 'Матан',
      nodes: [
        // contentLoaded: true — иначе `_startAssessment` не соберёт вопросы.
        KnowledgeNode(
          id: _n1,
          topicId: _topicId,
          parentId: null,
          level: 1,
          label: 'Производная',
          oneLiner: 'Предел отношения приращений.',
          details: 'Подробное определение производной.',
          contentLoaded: true,
        ),
        KnowledgeNode(
          id: _n2,
          topicId: _topicId,
          parentId: null,
          level: 1,
          label: 'Интеграл',
          oneLiner: 'Накопленная сумма бесконечно малых приращений.',
          details: 'Определение интеграла через сумму.',
          contentLoaded: true,
        ),
      ],
    );
    container.read(sessionStoreProvider.notifier).state =
        SessionState(session: _session());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: FinalAssessmentScreen(topicId: _topicId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Начать итоговый тест'));
    await tester.pumpAndSettle();
    expect(find.text('Что такое производная?'), findsOneWidget);

    // Вопрос 1: правильный вариант (correctAnswer == '1').
    await tester.tap(find.text('Вариант Б'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Верно'), findsOneWidget);

    await tester.tap(find.text('Следующий вопрос'));
    await tester.pumpAndSettle();

    // Вопрос 2: неверный вариант.
    await tester.tap(find.text('Вариант А'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Неверно'), findsOneWidget);
    expect(find.text('Правильный ответ: Вариант Б'), findsOneWidget);

    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    expect(find.text('Итоговый тест завершён!'), findsOneWidget);

    // 1) `finalize` awaited: экран завис на нём, SRS-цикл ещё НЕ начат.
    //    (Без await оба вызова `onAnswered` ушли бы синхронно в тот же
    //    момент, что и `finalize`.)
    expect(engine.finalizeEntered, 1);
    expect(engine.finalizeCompleted, 0);
    expect(srs.calls, isEmpty);

    // 2) Завершили finalize — пошла первая запись в SRS, и только она:
    //    цикл ждёт её завершения.
    engine.completeFinalize();
    await tester.pumpAndSettle();
    expect(engine.finalizeCompleted, 1);
    expect(srs.calls, hasLength(1));
    expect(srs.completed, 0);

    // 3) Разрешаем записи по одной: новая запись стартует только после
    //    завершения предыдущей и завершается ровно один раз.
    var started = 1;
    while (srs.hasPending) {
      expect(srs.calls.length, started,
          reason: 'следующая запись не должна стартовать раньше '
              'завершения текущей');
      srs.completeNext();
      await tester.pumpAndSettle();
      expect(srs.completed, started,
          reason: 'каждая запись должна завершиться ровно один раз');
      started = srs.calls.length;
    }

    // 4) К моменту, когда метод финиша дошёл до конца, все записи уже
    //    завершены — ровно по разу и в порядке вопросов.
    expect(engine.finalizeCompleted, 1);
    expect(srs.completed, 2);
    expect(srs.calls, [
      (topicId: _topicId, nodeId: _n1, quality: 'correct'),
      (topicId: _topicId, nodeId: _n2, quality: 'incorrect'),
    ]);
  });
}
