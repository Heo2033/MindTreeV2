// Разбор ответа (quiz и итоговый тест) — общий виджет `AnswerReview`.
//
// Две регрессии, которые он закрывает:
//  1. открытый вопрос спойлерился ДО ответа: рубрика (`explanation`)
//     показывалась прямо над полем ввода как «Рекомендация для проверки»;
//  2. эталон ответа (`referenceAnswer`) вообще не доходил до пользователя —
//     после проверки оставалась только короткая рубрика.
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
import 'package:mindtree_flutter/ui/screens/quiz_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';

const _reference =
    'Производная — это предел отношения приращений к аргументу в точке.';
// Сознательно без точной фразы из эталона: тесты ищут их раздельно.
const _rubric = 'Проверяй: предел, приращения, аргумент и скорость изменения.';

/// Открытый вопрос с эталоном и рубрикой — единственный вопрос теста.
const _openQuestion = AssessmentQuestion(
  id: 'q1',
  nodeId: _n1,
  question: 'Объясни, что такое производная.',
  referenceAnswer: _reference,
  explanation: _rubric,
);

class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

class _FakeAssessmentEngine extends AssessmentEngine {
  _FakeAssessmentEngine(MindtreeRepository repo)
      : super(
          repo: repo,
          scheduler: TreeScheduler(
            configProvider: () => const llm_client.LLMConfig(isMock: true),
          ),
        );

  @override
  Future<Assessment> generate(
    String sessionId,
    String topicId,
    List<AssessmentItem> items, {
    AssessmentType type = AssessmentType.final_,
    int questionCount = 6,
    bool includeApplication = true,
  }) async =>
      Assessment(
        id: 'asmt_$topicId',
        sessionId: 's_$topicId',
        type: type,
        startedAt: '2026-01-01T00:00:00.000',
        questions: const [_openQuestion],
      );

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
  Future<void> finalize(String assessmentId, double score) async {}
}

class _NoopReviewScheduler extends ReviewScheduler {
  _NoopReviewScheduler(super.repo);

  @override
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {}
}

Future<ProviderContainer> _container(MindtreeRepository repo) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    assessmentEngineProvider.overrideWith((ref) => _FakeAssessmentEngine(repo)),
    reviewSchedulerProvider.overrideWith((ref) => _NoopReviewScheduler(repo)),
    repositoryProvider.overrideWith((ref) async => repo),
  ]);
  addTearDown(container.dispose);

  container.read(graphStoreProvider.notifier).state = const GraphState(
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
    ],
  );
  container.read(sessionStoreProvider.notifier).state = SessionState(
    session: LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      goal: 'overview',
    ),
  );
  return container;
}

/// Отвечает на единственный открытый вопрос заведомым пустословием: ни один
/// термин рубрики не находится → `gradeOpenEnded` детерминированно даёт false.
Future<void> _answerWrongly(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'абракадабра');
  await tester.tap(find.text('Проверить'));
  await tester.pumpAndSettle();
}

/// Рубрика на экране (или её нет).
Finder _rubricFinder() =>
    find.textContaining('Проверяй', findRichText: true);

/// Эталон на экране (или его нет).
Finder _referenceFinder() =>
    find.textContaining('предел отношения приращений', findRichText: true);

void main() {
  testWidgets(
      'итоговый тест: рубрика не спойлерит открытый вопрос до ответа, '
      'после проверки виден эталонный ответ', (tester) async {
    final db = MindtreeDb(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await _container(MindtreeRepository(db));

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
    expect(find.text('Объясни, что такое производная.'), findsOneWidget);

    // До ответа ни рубрики, ни её заголовка — иначе это готовый ответ.
    expect(find.text('Рекомендация для проверки'), findsNothing);
    expect(
      _rubricFinder(),
      findsNothing,
      reason: 'рубрика до ответа — прямой спойлер открытого вопроса',
    );
    expect(find.text('Эталонный ответ'), findsNothing);

    await _answerWrongly(tester);

    expect(find.text('Неверно'), findsOneWidget);
    expect(find.text('Эталонный ответ'), findsOneWidget);
    expect(
      _referenceFinder(),
      findsOneWidget,
      reason: 'эталон показывается целиком, а не только рубрика',
    );
    expect(find.text('Критерии проверки'), findsOneWidget);
    expect(_rubricFinder(), findsOneWidget);
  });

  testWidgets('quiz: разбор открытого вопроса — эталон и критерии проверки',
      (tester) async {
    final db = MindtreeDb(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await _container(MindtreeRepository(db));

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
    expect(find.text('Объясни, что такое производная.'), findsOneWidget);
    expect(find.text('Эталонный ответ'), findsNothing);
    expect(_rubricFinder(), findsNothing);

    await _answerWrongly(tester);

    expect(find.text('Неверно'), findsOneWidget);
    expect(find.text('Эталонный ответ'), findsOneWidget);
    expect(_referenceFinder(), findsOneWidget);
    expect(find.text('Критерии проверки'), findsOneWidget);
    expect(_rubricFinder(), findsOneWidget);
  });
}
