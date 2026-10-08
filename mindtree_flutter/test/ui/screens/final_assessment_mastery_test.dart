// Регрессия: в итогах теста уровень и измерения мастерства берутся из модели
// обучающегося — того же источника, что и экран «Профиль обучающегося».
//
// Раньше экран рисовал свой `masteryLabels` по проценту ответов и не показывал
// измерения вовсе, из-за чего итоговый тест расходился с профилем.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/final_assessment_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';

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
      const Assessment(
        id: 'asmt_final',
        sessionId: 'final_t1',
        type: AssessmentType.final_,
        startedAt: '2026-01-01T00:00:00.000',
        questions: [
          AssessmentQuestion(
            id: 'q1',
            nodeId: _n1,
            question: 'Что такое производная?',
            options: ['Вариант А', 'Вариант Б'],
            correctAnswer: '1',
            explanation: 'Скорость изменения функции в точке.',
          ),
        ],
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

Future<(ProviderContainer, MindtreeRepository)> _container() async {
  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = MindtreeRepository(db);

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
  return (container, repo);
}

void main() {
  testWidgets(
      'итоги: уровень и четыре измерения берутся из модели обучающегося',
      (tester) async {
    final (container, repo) = await _container();
    final learner = LearnerModelService(repo);
    await learner.raiseOverallLevel(
      _topicId,
      MasteryLevel.basicUnderstanding,
      asInitial: true,
    );
    await learner.raiseOverallLevel(
      _topicId,
      MasteryLevel.solidUnderstanding,
    );
    await learner.recordEvidence(_topicId, _n1, const {
      'understanding': 1.0,
      'recall': 1.0,
      'application': 1.0,
      'transfer': 1.0,
    });

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

    await tester.tap(find.text('Вариант Б'));
    await tester.pump();
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Верно'), findsOneWidget);

    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    // Мастерство читается асинхронно после записи ответов в SRS.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Итоговый тест завершён!'), findsOneWidget);
    expect(find.text('Достигнутый уровень'), findsOneWidget);
    // Уровень из модели, а не из процента ответов.
    expect(find.text('Уверенное понимание'), findsOneWidget);
    // Четыре измерения той же модели, что и в профиле обучающегося.
    expect(find.text('Понимание'), findsOneWidget);
    expect(find.text('Память'), findsOneWidget);
    expect(find.text('Применение'), findsOneWidget);
    expect(find.text('Перенос'), findsOneWidget);
  });
}
