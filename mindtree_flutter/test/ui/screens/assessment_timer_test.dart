import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/lib/time_plausibility.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/final_assessment_screen.dart';
import 'package:mindtree_flutter/ui/screens/quiz_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';
const _n2 = 'n2~ab02';

/// Регрессия дефекта «Неправдоподобный замер времени»
/// (`tool/review/session_checks.dart`, `checkStepDuration`).
///
/// Боевой симптом: в `assessment_attempts.time_spent_ms` попадало
/// `DateTime.now().millisecondsSinceEpoch` ≈ 1.8e12 мс (≈ 20 суток). Причина —
/// экраны держали `int _startedAt = 0` и заводили таймер только в успешной
/// ветке генерации теста, поэтому любой путь, где вопрос показан без генерации,
/// писал `now - 0`. Реальный такой путь — подхват незавершённого итогового
/// теста в `_tryLoadExisting` (initState): таймер оставался нетронутым.
///
/// Тест фиксирует инвариант: время ответа всегда считается от показа вопроса и
/// не может равняться абсолютному (epoch-мс) времени.
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Assessment-движок без LLM и БД: запоминает `timeMs` каждой записи.
class _CapturingAssessmentEngine extends AssessmentEngine {
  _CapturingAssessmentEngine(MindtreeRepository repo)
      : super(
          repo: repo,
          scheduler: TreeScheduler(
            configProvider: () => const llm_client.LLMConfig(isMock: true),
          ),
        );

  /// Замеры, дошедшие до `recordAttempt` (по порядку ответов).
  final List<int> recordedTimeMs = [];

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
      id: 'asmt_new',
      sessionId: 'generated',
      type: AssessmentType.quiz,
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
  }) async {
    recordedTimeMs.add(timeMs);
  }

  @override
  Future<void> finalize(String assessmentId, double score) async {}
}

/// Незавершённый итоговый тест в БД — то, что `_tryLoadExisting` подхватывает
/// при открытии экрана минуя генерацию.
Assessment _unfinishedFinalAssessment() => const Assessment(
      id: 'asmt_existing',
      sessionId: 's1',
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
      ],
    );

/// Узлы с готовым контентом — иначе `_startQuiz` не соберёт вопросы.
GraphState _graphState() => const GraphState(
      topicId: _topicId,
      topicName: 'Матан',
      nodes: [
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

/// Замер обязан быть длительностью, а не epoch-мс.
void _expectPlausible(int timeMs) {
  expect(timeMs, greaterThanOrEqualTo(0));
  expect(
    timeMs,
    lessThan(kImplausibleDurationMs),
    reason: 'time_spent_ms должен быть длительностью ответа; до фикса здесь '
        'было DateTime.now().millisecondsSinceEpoch ≈ 1.8e12 мс (20 суток)',
  );
  // Тест отвечает сразу, поэтому и «обычный» потолок в минуту не должен
  // падать: с таймером от показа вопроса здесь единицы миллисекунд.
  expect(timeMs, lessThan(60 * 1000));
}

void main() {
  group('итоговый тест: подхват незавершённой попытки', () {
    testWidgets(
        'первый ответ после _tryLoadExisting пишет длительность, '
        'а не epoch-время', (tester) async {
      final db = MindtreeDb(NativeDatabase.memory());
      final repo = MindtreeRepository(db);
      addTearDown(db.close);

      // Незавершённый тест уже лежит в БД — экран подхватит его в initState.
      await repo.createAssessment(_unfinishedFinalAssessment());

      final engine = _CapturingAssessmentEngine(repo);
      final container = ProviderContainer(overrides: [
        graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
        assessmentEngineProvider.overrideWith((ref) => engine),
        // Экран читает репозиторий при старте (поиск незавершённого теста).
        repositoryProvider.overrideWith((ref) async => repo),
      ]);
      addTearDown(container.dispose);

      // Репозиторий должен быть готов ДО первого кадра: в приложении он
      // открыт на загрузке, а `_tryLoadExisting` читает `.valueOrNull`
      // синхронно в своём microtask.
      await container.read(repositoryProvider.future);

      container.read(graphStoreProvider.notifier).state = _graphState();
      container.read(sessionStoreProvider.notifier).state = SessionState(
        session: const LearningSession(
          id: 's1',
          journeyId: 'j1',
          topicId: _topicId,
          goal: 'overview',
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: FinalAssessmentScreen(topicId: _topicId)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Тест подхвачен без генерации — вопрос сразу на экране.
      expect(find.text('Что такое производная?'), findsOneWidget);

      await tester.tap(find.text('Вариант Б'));
      await tester.pump();
      await tester.tap(find.text('Проверить'));
      await tester.pumpAndSettle();

      expect(engine.recordedTimeMs, hasLength(1));
      _expectPlausible(engine.recordedTimeMs.single);
    });
  });

  group('quiz: первый вопрос после генерации', () {
    testWidgets('время ответа — длительность от показа вопроса',
        (tester) async {
      final db = MindtreeDb(NativeDatabase.memory());
      final repo = MindtreeRepository(db);
      addTearDown(db.close);

      final engine = _CapturingAssessmentEngine(repo);
      final container = ProviderContainer(overrides: [
        graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
        assessmentEngineProvider.overrideWith((ref) => engine),
        repositoryProvider.overrideWith((ref) async => repo),
      ]);
      addTearDown(container.dispose);

      await container.read(repositoryProvider.future);
      container.read(graphStoreProvider.notifier).state = _graphState();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: QuizScreen(topicId: _topicId)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Начать тест'));
      await tester.pumpAndSettle();
      expect(find.text('Что такое производная?'), findsOneWidget);

      await tester.tap(find.text('Вариант Б'));
      await tester.pump();
      await tester.tap(find.text('Проверить'));
      await tester.pumpAndSettle();

      expect(engine.recordedTimeMs, hasLength(1));
      _expectPlausible(engine.recordedTimeMs.single);

      // Второй вопрос: таймер перезапускается от его показа, а не копится.
      await tester.tap(find.text('Следующий вопрос'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вариант А'));
      await tester.pump();
      await tester.tap(find.text('Проверить'));
      await tester.pumpAndSettle();

      expect(engine.recordedTimeMs, hasLength(2));
      _expectPlausible(engine.recordedTimeMs.last);
    });
  });
}
