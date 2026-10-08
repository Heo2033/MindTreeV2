// Шаг 8 аудита (Plan): после диагностики пользователь должен увидеть план —
// цель, целевой уровень, оценку времени и причины выбранных понятий — не
// теряя при этом кнопку «К графу».
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
// В models.dart есть одноимённые DTO диагностики — скрываем их, экран
// работает именно с классами движка.
import 'package:mindtree_flutter/domain/models/models.dart'
    hide DiagnosticQuestion, DiagnosticResult;
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/diagnostic_screen.dart';

const _topicId = 't1';
const _n1 = 'n1~aaaa1111';
const _n2 = 'n2~bbbb2222';

/// Диагностика без LLM: вопросы и результат задаются тестом.
class FakeDiagnosticEngine extends DiagnosticEngine {
  FakeDiagnosticEngine({
    required super.repo,
    required super.scheduler,
    required this.questions,
    required this.result,
  });

  final List<DiagnosticQuestion> questions;
  final DiagnosticResult result;

  @override
  Future<List<DiagnosticQuestion>> generate(String topicId) async => questions;

  @override
  Future<DiagnosticResult> evaluate(
    String topicId,
    List<DiagnosticAnswer> answers,
  ) async =>
      result;
}

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

/// Сессия-заглушка с планом, у которого есть reasons.
class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier(super.ref);

  void setSession(LearningSession session) =>
      state = SessionState(session: session);
}

KnowledgeNode _node(String id, String? parentId, int level,
        {required String label, int estimatedMinutes = 5}) =>
    KnowledgeNode(
      id: id,
      topicId: _topicId,
      parentId: parentId,
      level: level,
      label: label,
      oneLiner: '',
      details: '',
      estimatedTimeMinutes: estimatedMinutes,
      state: NodeState.structureGenerated,
    );

const _questions = [
  DiagnosticQuestion(
    id: 'q1',
    nodeId: _n1,
    question: 'Что такое рекурсия?',
    options: ['Вызов функции самой себя', 'Цикл'],
    correctIndex: 0,
  ),
  DiagnosticQuestion(
    id: 'q2',
    nodeId: _n2,
    question: 'Как заканчивается рекурсия?',
    options: ['Никогда', 'Когда сработал базовый случай'],
    correctIndex: 1,
  ),
];

const _result = DiagnosticResult(
  currentLevel: 'basic_understanding',
  knownConcepts: [_n1],
  unknownConcepts: [_n2],
  score: 0.5,
);

Future<(ProviderContainer, FakeSessionNotifier, GoRouter)> _pumpScreen(
  WidgetTester tester, {
  bool withSession = false,
}) async {
  // Высокая поверхность: карточка плана и кнопки должны помещаться без
  // прокрутки, иначе tap по «К графу» не попадает в видимую часть.
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = MindtreeDb(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = MindtreeRepository(db);
  final scheduler = TreeScheduler(
    configProvider: () => const llm_client.LLMConfig(isMock: true),
  );

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWith((ref) async => repo),
    schedulerProvider.overrideWithValue(scheduler),
    diagnosticEngineProvider.overrideWithValue(FakeDiagnosticEngine(
      repo: repo,
      scheduler: scheduler,
      questions: _questions,
      result: _result,
    )),
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => FakeSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);

  container.read(graphStoreProvider.notifier).state = GraphState(
    topicId: _topicId,
    topicName: 'Тема',
    topic: const Topic(
      id: _topicId,
      name: 'Тема',
      goal: LearningGoal.overview,
      targetLevel: MasteryLevel.solidUnderstanding,
      timeBudgetMinutes: 45,
    ),
    nodes: [
      _node(_n1, null, 1, label: 'Корень'),
      _node(_n2, _n1, 2, label: 'Рекурсия', estimatedMinutes: 7),
    ],
  );

  if (withSession) {
    (container.read(sessionStoreProvider.notifier) as FakeSessionNotifier)
        .setSession(LearningSession(
          id: 's1',
          journeyId: 'j1',
          topicId: _topicId,
          status: SessionStatus.active,
          curriculum: const Curriculum(
            sessionId: 's1',
            totalEstimatedMinutes: 40,
            items: [
              CurriculumItem(
                id: 'i1',
                nodeId: _n2,
                label: 'Рекурсия',
                order: 0,
                estimatedMinutes: 5,
                reason: 'Понадобится в следующем разделе',
              ),
              CurriculumItem(
                id: 'i2',
                nodeId: _n1,
                label: 'Корень',
                order: 1,
                estimatedMinutes: 5,
              ),
            ],
          ),
        ));
  }

  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const DiagnosticScreen(topicId: _topicId),
    ),
    GoRoute(
      path: '/topic/learn/graph',
      builder: (_, _) => const Scaffold(body: Center(child: Text('Граф'))),
    ),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return (
    container,
    container.read(sessionStoreProvider.notifier) as FakeSessionNotifier,
    router,
  );
}

/// Прогоняет оба вопроса до экрана результата.
Future<void> _runDiagnostic(WidgetTester tester) async {
  await tester.tap(find.text('Начать диагностику'));
  await tester.pumpAndSettle();

  for (var i = 0; i < _questions.length; i++) {
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    await tester.tap(find.text(i == _questions.length - 1 ? 'Завершить' : 'Далее'));
    await tester.pumpAndSettle();
  }
  expect(find.text('Диагностика завершена'), findsOneWidget);
}

void main() {
  testWidgets(
      'после диагностики виден план: цель, уровень и оценка времени '
      'по понятиям, которые предстоит разобрать', (tester) async {
    final (_, _, _) = await _pumpScreen(tester);
    await _runDiagnostic(tester);

    expect(find.text('Твой план'), findsOneWidget);
    expect(find.text('Цель: Обзор'), findsOneWidget);
    expect(find.text('Целевой уровень: Уверенное понимание'), findsOneWidget);
    // Сессии нет → время считаем по понятию, которое не получилось (7 мин).
    expect(find.text('⏱ ≈ 7 мин'), findsOneWidget);
    expect(
      find.text(
        'Освоено 1 из 2 проверенных понятий — стартуем с текущего уровня.',
      ),
      findsOneWidget,
    );
    // Концепты показываются подписями, а не сырыми id из движка.
    expect(find.text('Корень'), findsWidgets);
    expect(find.text('Рекурсия'), findsWidgets);
  });

  testWidgets('причины выбора понятий — из вопросов диагностики', (tester) async {
    final (_, _, _) = await _pumpScreen(tester);
    await _runDiagnostic(tester);

    expect(find.text('Почему выбраны эти понятия'), findsOneWidget);
    expect(
      find.text(
        'Не получилось ответить на диагностике: «Как заканчивается рекурсия?»',
      ),
      findsOneWidget,
    );
  });

  testWidgets('у активной сессии время и причины берутся из её плана',
      (tester) async {
    final (_, _, _) = await _pumpScreen(tester, withSession: true);
    await _runDiagnostic(tester);

    // totalEstimatedMinutes плана важнее локальных оценок понятий.
    expect(find.text('⏱ ≈ 40 мин'), findsOneWidget);
    expect(find.text('Понадобится в следующем разделе'), findsOneWidget);
    // Причины из плана заменяют диагностические.
    expect(find.textContaining('Не получилось ответить'), findsNothing);
  });

  testWidgets('«К графу» остаётся последним шагом и ведёт в граф',
      (tester) async {
    final (_, _, router) = await _pumpScreen(tester);
    await _runDiagnostic(tester);

    expect(find.text('К графу'), findsOneWidget);
    expect(find.text('Пройти заново'), findsOneWidget);

    await tester.tap(find.text('К графу'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/topic/learn/graph');
  });
}
