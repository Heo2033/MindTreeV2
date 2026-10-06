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
import 'package:mindtree_flutter/ui/screens/quiz_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~ab01';
const _n2 = 'n2~ab02';

/// Регрессия: в режиме «Обучение» (по умолчанию) фактический результат
/// ответа обязан уходить в SRS как `correct`/`incorrect` по своему значению.
///
/// Старый код накапливал `_examResults` только в экзамене, а финализация
/// в learning-режиме читала пустую карту → КАЖДЫЙ вопрос уходил
/// в `ReviewScheduler.onAnswered` как `incorrect`: сброс интервала SRS
/// и ложная мисконцепция даже при 100% правильных ответах.
class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Assessment-движок без LLM и без БД: отдаёт фиксированный тест из двух
/// закрытых вопросов, побочки записи — no-op.
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
  }) async {
    return const Assessment(
      id: 'asmt_quiz',
      sessionId: 'quiz_т1',
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
  }) async {}

  @override
  Future<void> finalize(String assessmentId, double score) async {}
}

/// SRS-приёмник: пишет вызовы как есть, семантику `onAnswered` не меняет.
class _CapturingReviewScheduler extends ReviewScheduler {
  _CapturingReviewScheduler(super.repo);

  final List<({String topicId, String nodeId, String quality})> calls = [];

  @override
  Future<void> onAnswered(
    String topicId,
    String nodeId,
    String quality, {
    Map<String, double>? evidence,
    bool recordCareless = true,
  }) async {
    calls.add((topicId: topicId, nodeId: nodeId, quality: quality));
  }
}

void main() {
  testWidgets(
      'learning: верный ответ уходит в SRS как correct, неверный — incorrect',
      (tester) async {
    final db = MindtreeDb(NativeDatabase.memory());
    final repo = MindtreeRepository(db);
    addTearDown(db.close);

    final engine = _FakeAssessmentEngine(repo);
    final srs = _CapturingReviewScheduler(repo);

    final container = ProviderContainer(overrides: [
      graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
      assessmentEngineProvider.overrideWith((ref) => engine),
      reviewSchedulerProvider.overrideWith((ref) => srs),
    ]);
    addTearDown(container.dispose);

    container.read(graphStoreProvider.notifier).state = const GraphState(
      topicId: _topicId,
      topicName: 'Матан',
      nodes: [
        // contentLoaded: true — иначе `_startQuiz` не соберёт вопросы.
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: QuizScreen(topicId: _topicId)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Режим по умолчанию — «Обучение».
    expect(
      find.text('Сразу видите объяснение после каждого ответа.'),
      findsOneWidget,
    );
    // Фиксируем режим явно, чтобы тест не зависел от дефолта.
    await tester.tap(find.text('Обучение'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Начать тест'));
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

    await tester.tap(find.text('Завершить тест'));
    await tester.pumpAndSettle();
    expect(find.text('Тест завершён!'), findsOneWidget);

    // Ключевое утверждение: до SRS дошёл ФАКТИЧЕСКИЙ результат каждого
    // вопроса, а не «incorrect по умолчанию» из пустой карты.
    expect(srs.calls, [
      (topicId: _topicId, nodeId: _n1, quality: 'correct'),
      (topicId: _topicId, nodeId: _n2, quality: 'incorrect'),
    ]);
  });
}
