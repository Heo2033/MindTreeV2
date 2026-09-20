import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';

class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

/// Носитель сессии, который реально мутирует state (без БД и LLM):
/// answerStep помечает шаг, resetAnsweredView сбрасывает view отвеченного шага.
class _StatefulSessionNotifier extends SessionNotifier {
  _StatefulSessionNotifier(super.ref);

  @override
  Future<void> answerStep(int stepIndex, String answer) async {
    final activity = state.activity;
    if (activity == null) return;
    if (stepIndex < 0 || stepIndex >= activity.steps.length) return;
    final step = activity.steps[stepIndex];

    final correct = switch (step.type) {
      'recall' => answer == (step.correctIndex?.toString() ?? '-1'),
      _ => null,
    };
    final updated = ActivityStep(
      type: step.type,
      title: step.title,
      body: step.body,
      instruction: step.instruction,
      options: step.options,
      correctIndex: step.correctIndex,
      bestAnswer: step.bestAnswer,
      placeholder: step.placeholder,
      status: 'answered',
      userAnswer: answer.isEmpty ? null : answer,
      correct: correct,
      feedback: correct == true ? 'Отлично!' : null,
    );
    final steps = List<ActivityStep>.from(activity.steps);
    steps[stepIndex] = updated;
    final next = steps.indexWhere((s) => !s.isAnswered);
    state = state.copyWith(
      activity: activity.copyWith(steps: steps, currentStep: next < 0 ? steps.length : next),
      answeredStepView: () => stepIndex,
    );
  }

  @override
  void resetAnsweredView() {
    state = state.copyWith(answeredStepView: () => null);
  }

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
  Future<void> completeConcept(
    String itemId, {
    String? nodeId,
    String quality = 'correct',
  }) async {
    state = state.copyWith(activity: null, answeredStepView: () => null);
  }

  @override
  Future<String?> finalize() async => null;
}

CurriculumItem _item() => const CurriculumItem(
      id: 'i1',
      nodeId: 'n2',
      label: 'Раздел А',
      order: 0,
      type: CurriculumItemType.explain,
      estimatedMinutes: 5,
    );

LearningSession _session() => LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: 't1',
      goal: 'overview',
      curriculum: Curriculum(
        sessionId: 's1',
        items: [_item()],
      ),
    );

LearningActivity _activity(List<ActivityStep> steps) => LearningActivity(
      sessionId: 's1',
      itemId: 'i1',
      nodeId: 'n2',
      nodeLabel: 'Раздел А',
      goal: 'overview',
      steps: steps,
      currentStep: steps.indexWhere((s) => !s.isAnswered),
    );

Future<void> _pumpSession(
  WidgetTester tester, {
  LearningActivity? activity,
  int? answeredStepView,
  SessionState? customState,
}) async {
  final container = ProviderContainer(overrides: [
    graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
    sessionStoreProvider.overrideWith((ref) => _StatefulSessionNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  container.read(graphStoreProvider.notifier).state = const GraphState(
    topicId: 't1',
    topicName: 'Тема',
  );
  container.read(sessionStoreProvider.notifier).state = customState ??
      SessionState(
        session: _session(),
        currentItem: _item(),
        activity: activity,
        answeredStepView: answeredStepView,
      );
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

final List<ActivityStep> _fourSteps = const [
  ActivityStep(type: 'explain', title: 'Изучаем понятие', status: 'answered'),
  ActivityStep(type: 'example', title: 'Разбираем пример'),
  ActivityStep(type: 'recall', title: 'Проверка'),
  ActivityStep(type: 'apply', title: 'Применение'),
];

ActivityStep _answered(ActivityStep s, {bool? correct}) => ActivityStep(
      type: s.type,
      title: s.title,
      body: s.body,
      instruction: s.instruction,
      options: s.options,
      correctIndex: s.correctIndex,
      bestAnswer: s.bestAnswer,
      placeholder: s.placeholder,
      status: 'answered',
      userAnswer: s.type == 'recall' ? (s.correctIndex?.toString() ?? '0') : 'text',
      correct: correct ?? (s.type == 'recall' ? true : null),
      feedback: correct == true || s.type != 'recall' ? null : 'Ошибка',
    );

void main() {
  group('фидбек шага сессии', () {
    testWidgets('read-шаг (explain) — бейдж «Прочитано», а не «Есть ошибки»',
        (tester) async {
      final activity = _activity(const [
        ActivityStep(type: 'explain', title: 'Изучаем понятие', status: 'answered'),
      ]);
      await _pumpSession(tester, activity: activity, answeredStepView: 0);

      expect(find.text('Прочитано'), findsOneWidget);
      expect(find.text('Есть ошибки'), findsNothing);
      expect(find.text('Верно'), findsNothing);
      expect(find.text('Лучший ответ:'), findsNothing);
      expect(find.text('Далее'), findsOneWidget);
    });

    testWidgets('recall с верным ответом — бейдж «Верно»', (tester) async {
      final activity = _activity(const [
        ActivityStep(
          type: 'recall',
          title: 'Проверка',
          status: 'answered',
          options: ['A', 'B', 'C', 'D'],
          correctIndex: 2,
          userAnswer: '2',
          correct: true,
          feedback: 'Отлично!',
        ),
      ]);
      await _pumpSession(tester, activity: activity, answeredStepView: 0);

      expect(find.text('Верно'), findsOneWidget);
      expect(find.text('Есть ошибки'), findsNothing);
      expect(find.text('Лучший ответ:'), findsNothing);
    });

    testWidgets('recall с ошибкой — «Есть ошибки» и «Лучший ответ»',
        (tester) async {
      final activity = _activity(const [
        ActivityStep(
          type: 'recall',
          title: 'Проверка',
          status: 'answered',
          options: ['A', 'B', 'C', 'D'],
          correctIndex: 2,
          userAnswer: '0',
          correct: false,
          bestAnswer: 'C',
        ),
      ]);
      await _pumpSession(tester, activity: activity, answeredStepView: 0);

      expect(find.text('Есть ошибки'), findsOneWidget);
      expect(find.text('Лучший ответ:'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('apply-шаг с ответом — «Верно» без «Есть ошибки»',
        (tester) async {
      final activity = _activity(const [
        ActivityStep(
          type: 'apply',
          title: 'Применение',
          status: 'answered',
          userAnswer: 'Мой ответ',
          correct: true,
        ),
      ]);
      await _pumpSession(tester, activity: activity, answeredStepView: 0);

      expect(find.text('Верно'), findsOneWidget);
      expect(find.text('Есть ошибки'), findsNothing);
    });
  });

  group('кнопка «Далее»', () {
    testWidgets('«Далее» на read-шаге переводит к следующему не-отвеченному',
        (tester) async {
      final activity = _activity(_fourSteps);
      await _pumpSession(tester, activity: activity, answeredStepView: 0);

      // Сейчас фидбек первого шага с кнопкой «Далее».
      expect(find.text('Прочитано'), findsOneWidget);
      expect(find.text('Далее'), findsOneWidget);

      // Нажимаем: первый не-отвеченный — example (read) → answerStep(1, '').
      await tester.tap(find.text('Далее'));
      await tester.pump();

      expect(find.text('Прочитано'), findsOneWidget);
      expect(find.text('Разбираем пример'), findsOneWidget);
    });

    testWidgets('«Далее» с recall переходит к apply (пропускает answered)',
        (tester) async {
      final steps = [
        _fourSteps[0],
        _answered(_fourSteps[1]),
        _answered(_fourSteps[2], correct: true),
        _fourSteps[3],
      ];
      final activity = _activity(steps);
      await _pumpSession(tester, activity: activity, answeredStepView: 2);

      expect(find.text('Верно'), findsOneWidget);

      await tester.tap(find.text('Далее'));
      await tester.pump();

      // Появляется apply-шаг (последний не-отвеченный).
      // «Применение» встречается дважды: breadcrumb и заголовок шага.
      expect(find.text('Применение'), findsWidgets);
      expect(find.text('Верно'), findsNothing);
    });

    testWidgets('когда все шаги отвечены — «Далее» уводит к завершению концепта',
        (tester) async {
      final steps = [
        _fourSteps[0],
        _answered(_fourSteps[1]),
        _answered(_fourSteps[2], correct: true),
        _answered(_fourSteps[3], correct: true),
      ];
      final activity = _activity(steps);
      await _pumpSession(tester, activity: activity, answeredStepView: 3);

      expect(find.text('Верно'), findsOneWidget);

      await tester.tap(find.text('Далее'));
      await tester.pump();

      expect(find.text('Концепт проработан'), findsOneWidget);
      expect(find.text('Завершить концепт'), findsOneWidget);
    });
  });

  group('баннер ошибки активной сессии', () {
    testWidgets('ошибка показывается, кнопка «Изучать» снова доступна',
        (tester) async {
      await _pumpSession(
        tester,
        customState: SessionState(
          session: _session(),
          currentItem: _item(),
          error: 'LLM недоступен (test)',
        ),
      );

      // Не зависший спиннер, а понятная ошибка + возможность повторить.
      expect(find.text('Генерация объяснения…'), findsNothing);
      expect(find.text('Подготовка учебного материала…'), findsNothing);
      expect(find.text('LLM недоступен (test)'), findsOneWidget);
      expect(find.text('Изучать'), findsOneWidget);
    });

    testWidgets('крестик баннера очищает ошибку (clearError)', (tester) async {
      await _pumpSession(
        tester,
        customState: SessionState(
          session: _session(),
          currentItem: _item(),
          error: 'LLM недоступен (test)',
        ),
      );

      expect(find.text('LLM недоступен (test)'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.text('LLM недоступен (test)'), findsNothing);
      // Сессия при этом не сбрасывается.
      expect(find.text('Изучать'), findsOneWidget);
    });
  });
}