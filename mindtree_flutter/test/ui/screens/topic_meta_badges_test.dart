// Шаг 9 аудита (§81): фокус и граф не отвечали на вопросы «сколько времени
// займёт» и «какая цель». Бейджи под заголовком: цель темы, целевой уровень,
// а при активной сессии — остаток времени (ETA либо бюджет плана).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/focus_screen.dart';
import 'package:mindtree_flutter/ui/screens/graph_screen.dart';

const _topicId = 't1';

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}
}

class FakeLearnerNotifier extends LearnerNotifier {
  FakeLearnerNotifier(super.ref);

  @override
  Future<void> load(String topicId) async {}
}

class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier(super.ref);

  void setSession(LearningSession session, {AdaptiveDecision? adaptive}) =>
      state = SessionState(session: session, adaptive: adaptive);
}

KnowledgeNode _node(String id, String? parentId, int level, String label) =>
    KnowledgeNode(
      id: id,
      topicId: _topicId,
      parentId: parentId,
      level: level,
      label: label,
      oneLiner: '',
      details: '',
      state: NodeState.structureGenerated,
    );

List<KnowledgeNode> _nodes() => [
      _node('n1', null, 1, 'Корень'),
      _node('n2', 'n1', 2, 'Раздел А'),
    ];

/// Активная сессия темы: бюджет 60 мин, один пункт на 5 мин уже пройден →
/// на плане остаётся 55 минут.
LearningSession _session() => const LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      status: SessionStatus.active,
      curriculum: Curriculum(
        sessionId: 's1',
        totalEstimatedMinutes: 60,
        items: [
          CurriculumItem(
            id: 'i1',
            nodeId: 'n1',
            order: 0,
            status: CurriculumItemStatus.completed,
            estimatedMinutes: 5,
          ),
          CurriculumItem(
            id: 'i2',
            nodeId: 'n2',
            order: 1,
            estimatedMinutes: 55,
          ),
        ],
      ),
    );

Future<ProviderContainer> _container({
  bool withSession = false,
  SessionEta? eta,
}) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    learnerStoreProvider.overrideWith((ref) => FakeLearnerNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => FakeSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);

  container.read(graphStoreProvider.notifier).state = GraphState(
    topicId: _topicId,
    topicName: 'Тема',
    topic: const Topic(
      id: _topicId,
      name: 'Тема',
      goal: LearningGoal.deep,
      targetLevel: MasteryLevel.solidUnderstanding,
      timeBudgetMinutes: 60,
    ),
    nodes: _nodes(),
  );

  if (withSession) {
    (container.read(sessionStoreProvider.notifier) as FakeSessionNotifier)
        .setSession(
          _session(),
          adaptive: eta == null
              ? null
              : AdaptiveDecision(
                  recommendedAction: RecommendedAction.studyNext,
                  eta: eta,
                ),
        );
  }
  return container;
}

Future<void> _pumpFocus(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FocusScreen(topicId: _topicId)),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _pumpGraph(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: GraphScreen(topicId: _topicId)),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('фокус: цель, уровень и остаток времени активной сессии',
      (tester) async {
    final container = await _container(withSession: true);
    await _pumpFocus(tester, container);

    expect(find.text('Цель: Глубокое изучение'), findsOneWidget);
    expect(find.text('Уровень: Уверенное понимание'), findsOneWidget);
    expect(find.text('⏱ Осталось ≈ 55 мин'), findsOneWidget);
  });

  testWidgets('фокус: без сессии остаются цель и уровень', (tester) async {
    final container = await _container();
    await _pumpFocus(tester, container);

    expect(find.text('Цель: Глубокое изучение'), findsOneWidget);
    expect(find.text('Уровень: Уверенное понимание'), findsOneWidget);
    expect(find.textContaining('⏱'), findsNothing);
  });

  testWidgets('фокус: при посчитанном ETA показывается диапазон остатка',
      (tester) async {
    final container = await _container(
      withSession: true,
      eta: const SessionEta(
        remainingMinutesMin: 12,
        remainingMinutesMax: 20,
        totalEstimatedMinutes: 60,
      ),
    );
    await _pumpFocus(tester, container);

    expect(find.text('⏱ 12\u201320 мин'), findsOneWidget);
    expect(find.text('⏱ Осталось ≈ 55 мин'), findsNothing);
  });

  testWidgets('граф: те же бейджи в шапке', (tester) async {
    final container = await _container(withSession: true);
    await _pumpGraph(tester, container);

    expect(find.text('Цель: Глубокое изучение'), findsOneWidget);
    expect(find.text('Уровень: Уверенное понимание'), findsOneWidget);
    expect(find.text('⏱ Осталось ≈ 55 мин'), findsOneWidget);
  });
}
