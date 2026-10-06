import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';

class FakeGraphNotifier extends GraphNotifier {
  FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

/// Сессия-нотифаер без БД и LLM: методы только завершаются, состояние не меняют.
class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier(super.ref);

  @override
  Future<void> resume() async {}

  @override
  Future<void> createSession(
    String topicId, {
    String goal = 'overview',
    String? milestoneId,
    int timeBudget = 30,
  }) async {}

  @override
  Future<void> startStudy(String nodeId) async {}

  @override
  Future<void> ensureActivity() async {}

  @override
  Future<void> answerStep(int stepIndex, String answer) async {}

  @override
  Future<void> completeConcept(
    String itemId, {
    String? nodeId,
    String? quality,
  }) async {}

  @override
  Future<String?> finalize() async => null;
}

CurriculumItem _item({
  String id = 'i1',
  String nodeId = 'n2',
  String label = 'Раздел А',
  int order = 0,
  CurriculumItemStatus status = CurriculumItemStatus.pending,
}) =>
    CurriculumItem(
      id: id,
      nodeId: nodeId,
      label: label,
      order: order,
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
      status: status,
    );

LearningSession _session(List<CurriculumItem> items) => LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: 't1',
      goal: 'overview',
      curriculum: Curriculum(sessionId: 's1', items: items),
    );

Future<void> _pumpSession(
  WidgetTester tester, {
  SessionState sessionState = const SessionState(),
}) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => FakeSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  container.read(graphStoreProvider.notifier).state = const GraphState(
    topicId: 't1',
    topicName: 'Тема',
  );
  container.read(sessionStoreProvider.notifier).state = sessionState;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SessionScreen(topicId: 't1')),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('нет сессии — рендерится стартовая карточка с целью', (tester) async {
    await _pumpSession(tester);

    expect(find.text('Сессия \u00b7 Тема'), findsOneWidget);
    expect(find.text('Начать сессию'), findsOneWidget);
    expect(find.text('30 мин'), findsOneWidget);
  });

  testWidgets('активная сессия рендерит план и призыв к изучению',
      (tester) async {
    final item = _item();
    final session = _session([item]);

    await _pumpSession(
      tester,
      sessionState: SessionState(session: session, currentItem: item),
    );

    expect(find.text('План сессии'), findsOneWidget);
    expect(find.text('Изучать'), findsOneWidget);
    expect(find.text('0/1 концептов'), findsOneWidget);
  });

  testWidgets('шаг активности рендерит breadcrumb из четырёх фаз',
      (tester) async {
    final item = _item();
    final session = _session([item]);
    final activity = LearningActivity(
      sessionId: 's1',
      itemId: 'i1',
      nodeId: 'n2',
      nodeLabel: 'Раздел А',
      goal: 'overview',
      steps: const [
        ActivityStep(type: 'explain', title: 'Объяснение шага'),
        ActivityStep(type: 'example', title: 'Пример шага'),
        ActivityStep(type: 'recall', title: 'Проверка шага'),
        ActivityStep(type: 'apply', title: 'Применение шага'),
      ],
    );

    await _pumpSession(
      tester,
      sessionState: SessionState(
        session: session,
        currentItem: item,
        activity: activity,
      ),
    );

    expect(find.text('Объяснение'), findsOneWidget);
    expect(find.text('Пример'), findsOneWidget);
    expect(find.text('Проверка'), findsOneWidget);
    expect(find.text('Применение'), findsOneWidget);
  });

  testWidgets('все концепты изучены — рендерится финальный призыв',
      (tester) async {
    final items = [_item(status: CurriculumItemStatus.completed)];
    final session = _session(items);

    await _pumpSession(tester, sessionState: SessionState(session: session));

    expect(find.text('Все концепты изучены!'), findsOneWidget);
    expect(find.text('Перейти к итоговому тесту'), findsOneWidget);
  });
}