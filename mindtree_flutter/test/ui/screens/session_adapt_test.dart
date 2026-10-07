// Виджет-тесты пяти действий Adapt (§80 спеки) на экране сессии.
//
// Что здесь проверяется:
//   • контролы видны рядом с текущим понятием и не появляются без сессии;
//   • каждое нажатие доходит до движка (записывающий фейк) и результат
//     рендерится — включая честную пометку «сохранённый вариант», когда LLM
//     недоступна;
//   • панель и результат привязаны к фазе чтения объяснения (AdaptPhase):
//     полный набор и инлайн-результат — только на шаге «Объяснение»; до
//     активности (контент генерируется по «Изучать», §61) и на «Примере» —
//     только skip/replan; на шаге с вопросом панель скрыта целиком и
//     текстовый результат не показывается;
//   • текстовые результаты (упрощение/глубина/база) рендерятся В карточке
//     понятия — на месте текста, который меняют, а не в панели под кнопками;
//     сброс («Вернуть обычное объяснение»/«Вернуть исходный текст» и чип
//     «Обычно» как чип-возврат) возвращает исходный текст;
//   • результат переживает ровно одну фазу: «Изучать» и переход шага
//     активности его закрывают;
//   • статусные skip/replan остаются в панели, план и точка обновляются;
//   • no-op («уже отмечено») и ошибка движка не роняют экран.
//
// LLM-действия (simplify/changeDepth) возвращают готовые ответы фейка — в
// виджет-тесте модель не участвует. Детерминированные действия
// (prerequisites/skip/replan) идут в реальный движок поверх памятной SQLite:
// так видно, что перерисовка плана — это действительно состояние движка,
// а не локальная подмена. Никаких сетевых вызовов и ключей здесь нет.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/domain/engines/adaptive_learning_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/models/models.dart';
import 'package:mindtree_flutter/providers/app_providers.dart';
import 'package:mindtree_flutter/providers/ui_stores.dart';
import 'package:mindtree_flutter/ui/screens/session_screen.dart';
import 'package:mindtree_flutter/ui/widgets/adapt_panel.dart';
import 'package:mindtree_flutter/ui/widgets/button.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _rootId = 'n1_r~$_scope';
const _aId = 'n2_a~$_scope';
const _bId = 'n3_b~$_scope';

KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзор всей темы.',
      details: 'Подробный обзор темы.',
    );

KnowledgeNode _nodeA() => KnowledgeNode(
      id: _aId,
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие A',
      oneLiner: 'Суть понятия A.',
      details: 'Подробности понятия A.',
    );

/// Понятие B собирается из A (явная связь) и пути по дереву к корню.
KnowledgeNode _nodeB() => KnowledgeNode(
      id: _bId,
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие B',
      oneLiner: 'Суть понятия B.',
      details: 'Подробности понятия B.',
      relations: const [
        Relation(from: _bId, to: _aId, type: RelationType.dependsOn),
      ],
    );

class _FakeGraphNotifier extends GraphNotifier {
  _FakeGraphNotifier(super.ref);

  @override
  Future<void> loadTopic(String id) async {}

  @override
  Future<void> expandNode(String nodeId) async {}

  @override
  Future<void> generateContent(String nodeId) async {}
}

/// Записывающий фейк Adapt-движка: пишет каждый вызов, для LLM-действий
/// отдаёт готовый ответ, остальное (без LLM) прогоняет через настоящий
/// движок — он детерминирован и работает только с хранилищем.
class _RecordingAdaptiveEngine extends AdaptiveLearningEngine {
  _RecordingAdaptiveEngine(AdaptiveLearningEngine base)
      : super(
          repo: base.repo,
          learnerModel: base.learnerModel,
          reviewScheduler: base.reviewScheduler,
          sessionEngine: base.sessionEngine,
          scheduler: base.scheduler,
        );

  /// Каждый вызов в формате `action:sessionId:аргумент`.
  final calls = <String>[];

  /// Действие, которое обязано упасть (проверка: ошибка не роняет экран).
  AdaptAction? failOn;

  /// Готовые ответы LLM-действий.
  AdaptSimplifyResult? simplifyResult;
  AdaptDepthResult? depthResult;

  void _hit(AdaptAction action, String sessionId, [Object? arg]) {
    calls.add('${action.raw}:$sessionId:${arg ?? ''}');
    if (failOn == action) throw Exception('adapt failed');
  }

  @override
  Future<AdaptSimplifyResult> simplify(String sessionId, String nodeId) async {
    _hit(AdaptAction.simplify, sessionId, nodeId);
    return simplifyResult ??
        AdaptSimplifyResult(
          sessionId: sessionId,
          nodeId: nodeId,
          title: 'Понятие',
          text: 'Самое простое объяснение без терминов.',
          source: AdaptSource.llm,
        );
  }

  @override
  Future<AdaptDepthResult> changeDepth(
    String sessionId,
    String nodeId,
    ContentDepth depth,
  ) async {
    _hit(AdaptAction.changeDepth, sessionId, nodeId);
    return depthResult ??
        AdaptDepthResult(
          sessionId: sessionId,
          nodeId: nodeId,
          title: 'Понятие',
          text: 'Объяснение выбранной глубины.',
          source: AdaptSource.llm,
          depth: depth,
        );
  }

  @override
  Future<AdaptPrerequisiteResult> prerequisites(
    String sessionId,
    String nodeId,
  ) async {
    _hit(AdaptAction.prerequisite, sessionId, nodeId);
    return super.prerequisites(sessionId, nodeId);
  }

  @override
  Future<AdaptSkipResult> skip(String sessionId, String itemId) async {
    _hit(AdaptAction.skip, sessionId, itemId);
    return super.skip(sessionId, itemId);
  }

  @override
  Future<AdaptReplanResult> replanRemaining(
    String sessionId, {
    int? remainingMinutes,
  }) async {
    _hit(AdaptAction.replan, sessionId, remainingMinutes);
    return super.replanRemaining(
      sessionId,
      remainingMinutes: remainingMinutes,
    );
  }
}

CurriculumItem _item(
  String id,
  String nodeId,
  String label, {
  int minutes = 10,
  CurriculumItemStatus status = CurriculumItemStatus.pending,
}) =>
    CurriculumItem(
      id: id,
      nodeId: nodeId,
      label: label,
      order: int.parse(id.replaceAll(RegExp(r'\D'), '')),
      type: CurriculumItemType.explain,
      estimatedMinutes: minutes,
      status: status,
    );

/// Read-шаг с исходным объяснением — текст, который подменяет результат.
const ActivityStep _explainStep = ActivityStep(
  type: 'explain',
  title: 'Изучаем понятие',
  body: 'Исходное объяснение понятия B.',
);

/// Шаг с вопросом: тело шага — это сам вопрос, его нельзя вытеснять.
const ActivityStep _recallStep = ActivityStep(
  type: 'recall',
  title: 'Проверка',
  body: 'Вопрос: что важнее при остановке?',
  instruction: 'Выбери один вариант',
  options: ['Первое', 'Второе'],
  correctIndex: 0,
);

const ActivityStep _applyStep = ActivityStep(
  type: 'apply',
  title: 'Применение',
  body: 'Задача: примени правило к своему примеру.',
  instruction: 'Напиши коротко',
  placeholder: 'Твой ответ',
);

/// Шаг «Пример»: read-шаг, но панель на нём даёт только skip/replan —
/// текст примера адаптировать нечего.
const ActivityStep _exampleStep = ActivityStep(
  type: 'example',
  title: 'Разбираем пример',
  body: 'Пример: программа останавливается на первом входе.',
);

/// Готовый текстовый результат для инъекции в состояние — проверка того,
/// что результат, созданный в другой фазе, на этой фазе не показывается.
const AdaptSimplifyResult _simplifyResult = AdaptSimplifyResult(
  sessionId: 's1',
  nodeId: _bId,
  title: 'Понятие B',
  text: 'Самое простое объяснение без терминов.',
  source: AdaptSource.llm,
);

/// Активность текущего понятия: первый незакрытый шаг и есть текущий.
LearningActivity _activity(List<ActivityStep> steps) => LearningActivity(
      sessionId: 's1',
      itemId: 'i1',
      nodeId: _bId,
      nodeLabel: 'Понятие B',
      goal: 'overview',
      steps: steps,
      currentStep: steps.indexWhere((s) => !s.isAnswered),
    );

/// Текстовый результат живёт в карточке понятия, а не в панели действий.
void _expectResultInConceptCard(WidgetTester tester) {
  expect(find.byType(AdaptResultBody), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(AdaptPanel),
      matching: find.byType(AdaptResultBody),
    ),
    findsNothing,
    reason: 'результат рендерится на месте понятия, а не под кнопками панели',
  );
}

/// Результат стоит между [upper] и [lower] по вертикали — то есть внутри
/// того же блока, где заголовок понятия и действие карточки.
void _expectResultBetween(WidgetTester tester, Finder upper, Finder lower) {
  final result = find.byType(AdaptResultBody);
  expect(
    tester.getTopLeft(result).dy,
    greaterThan(tester.getBottomRight(upper).dy),
    reason: 'результат ниже заголовка блока',
  );
  expect(
    tester.getBottomRight(result).dy,
    lessThan(tester.getTopLeft(lower).dy),
    reason: 'результат выше нижнего действия карточки',
  );
}

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;
  late _RecordingAdaptiveEngine fake;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    engines = buildEngines(
      repo: repo,
      configProvider: () => const llm_client.LLMConfig(isMock: true),
    );
    fake = _RecordingAdaptiveEngine(engines.adaptive);
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.createJourney('j1', _topicId);
    await repo.insertNodes([_root(), _nodeA(), _nodeB()]);
  });

  tearDown(() async {
    await db.close();
  });

  /// Кладёт сессию в хранилище — источник истины для плана и ETA.
  Future<LearningSession> seedSession({
    List<CurriculumItem>? items,
    int currentIndex = 0,
    int budget = 30,
  }) async {
    final plan = items ??
        [
          _item('i1', _bId, 'Раздел 1'),
          _item('i2', _aId, 'Раздел 2'),
        ];
    final session = LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: _topicId,
      goal: 'overview',
      timeBudgetMinutes: budget,
      curriculum: Curriculum(
        sessionId: 's1',
        items: plan,
        totalEstimatedMinutes:
            plan.fold<int>(0, (sum, i) => sum + i.estimatedMinutes),
      ),
      currentIndex: currentIndex,
    );
    await repo.createSession(session);
    return session;
  }

  Future<ProviderContainer> pumpSession(
    WidgetTester tester, {
    LearningSession? session,
    LearningActivity? activity,
    AdaptUiState adapt = const AdaptUiState(),
  }) async {
    final container = ProviderContainer(overrides: [
      graphStoreProvider.overrideWith((ref) => _FakeGraphNotifier(ref)),
      sessionStoreProvider.overrideWith((ref) => SessionNotifier(ref)),
      learningSessionEngineProvider.overrideWithValue(engines.session),
      // Активность читается и пишется в ту же памятную БД, что и сессия:
      // без переопределения сервис уходит в провайдер приложения (файловая
      // БД, в тесте не готова).
      learningActivityServiceProvider.overrideWithValue(engines.activity),
      adaptiveLearningEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    // Экран высокий, чтобы панель действий была в первом кадре.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container.read(graphStoreProvider.notifier).state = const GraphState(
      topicId: _topicId,
      topicName: 'Теорема остановки',
    );
    if (session != null) {
      container.read(sessionStoreProvider.notifier).state = SessionState(
        session: session,
        currentItem: session.curriculum.items[session.currentIndex],
        currentIndex: session.currentIndex,
        activity: activity,
        adapt: adapt,
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SessionScreen(topicId: _topicId)),
        ),
      ),
    );
    // Кадр + отработка microtask'ов auto-resume (initState).
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    return container;
  }

  group('контролы Adapt на экране сессии', () {
    testWidgets('до активности: панель есть, но только skip/replan',
        (tester) async {
      final session = await seedSession();
      await pumpSession(tester, session: session);

      expect(find.text('Что ещё можно сделать'), findsOneWidget);
      expect(find.text('Текущее понятие: Раздел 1'), findsOneWidget);
      expect(find.text('Знаю, пропустить'), findsOneWidget);
      expect(find.text('Успеваю только…'), findsOneWidget);
      // Текстовых действий нет: контент генерируется по «Изучать» (§61),
      // до активности упрощать нечего.
      expect(find.text('Объясни проще'), findsNothing);
      expect(find.text('Из чего складывается'), findsNothing);
      expect(find.text('Насколько подробно:'), findsNothing);
      expect(find.text('Обычно'), findsNothing);
      expect(find.text('Глубже'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('до активности: текстовый результат не показывается',
        (tester) async {
      final session = await seedSession();
      // Застрявший результат прошлой фазы (создать его здесь уже нельзя)
      // не должен вставляться в карточку до изучения.
      await pumpSession(
        tester,
        session: session,
        adapt: const AdaptUiState(result: _simplifyResult),
      );

      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        find.textContaining('Самое простое объяснение', findRichText: true),
        findsNothing,
        reason: 'инлайн-вставки до «Изучать» не происходит',
      );
      expect(find.text('Знаю, пропустить'), findsOneWidget,
          reason: 'статусные действия при этом доступны');
      expect(tester.takeException(), isNull);
    });

    testWidgets('без сессии панель не показывается', (tester) async {
      await pumpSession(tester);

      expect(find.text('Что ещё можно сделать'), findsNothing);
      expect(find.text('Начать сессию'), findsOneWidget);
    });
  });

  group('«Объясни проще»', () {
    testWidgets('LLM-ответ рендерится, вызов доходит до движка', (tester) async {
      final session = await seedSession();
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('simplify:s1:$_bId'));
      expect(find.text('Объяснение проще'), findsOneWidget);
      expect(
        find.textContaining('Самое простое объяснение', findRichText: true),
        findsOneWidget,
        reason: 'текст объяснения — контент модели, рендерится как rich text',
      );
      expect(find.text('Сохранённый вариант'), findsNothing);
      // Результат — на месте текста шага, а не под кнопками панели.
      _expectResultInConceptCard(tester);
      _expectResultBetween(
        tester,
        find.text('Изучаем понятие'),
        find.widgetWithText(AppButton, 'Продолжить'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LLM недоступна → сохранённый вариант помечен честно',
        (tester) async {
      final session = await seedSession();
      fake.simplifyResult = const AdaptSimplifyResult(
        sessionId: 's1',
        nodeId: _bId,
        title: 'Понятие B',
        text: 'Сохранённый текст понятия.',
        source: AdaptSource.stored,
      );
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();

      expect(find.text('Сохранённый вариант'), findsOneWidget);
      expect(
        find.text('ИИ сейчас недоступен — показываем текст, который уже есть.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Сохранённый текст понятия', findRichText: true),
        findsOneWidget,
      );
      _expectResultInConceptCard(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Из чего складывается»', () {
    testWidgets('список базы: изучено / ещё не разбирали + понимание',
        (tester) async {
      // A изучен (пункт плана закрыт), корень — нет; по A есть измерение.
      final session = await seedSession(items: [
        _item('i1', _bId, 'Раздел 1'),
        _item('i2', _aId, 'Раздел 2', status: CurriculumItemStatus.completed),
      ]);
      await engines.learnerModel
          .recordEvidence(_topicId, _aId, {dimUnderstanding: 1.0});
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Из чего складывается'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('prerequisite:s1:$_bId'));
      expect(find.text('Из чего складывается'), findsWidgets);
      expect(find.text('Понятие A'), findsOneWidget);
      expect(find.text('Теорема остановки'), findsOneWidget);
      expect(find.text('Изучено'), findsOneWidget);
      expect(find.text('Ещё не разбирали'), findsOneWidget);
      expect(find.textContaining('Понимание'), findsOneWidget);
      expect(
        find.text('Сначала стоит понять: Теорема остановки.'),
        findsOneWidget,
      );
      _expectResultInConceptCard(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('база не требуется → понятный ответ без списка', (tester) async {
      // Текущее понятие — корень темы: у него нет ни связей, ни предков.
      final session = await seedSession(items: [
        _item('i1', _rootId, 'Раздел 1'),
        _item('i2', _aId, 'Раздел 2'),
      ]);
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Из чего складывается'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('prerequisite:s1:$_rootId'));
      expect(
        find.text('Обязательной базы нет — понятие можно изучать само по себе.'),
        findsOneWidget,
      );
      _expectResultInConceptCard(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Знаю, пропустить»', () {
    testWidgets('план и точка сессии обновляются, результат показан',
        (tester) async {
      final session = await seedSession();
      await pumpSession(tester, session: session);
      expect(find.text('0/2 концептов'), findsOneWidget);

      await tester.tap(find.text('Знаю, пропустить'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('skip:s1:i1'));
      expect(find.text('1/2 концептов'), findsOneWidget,
          reason: 'прогресс пересчитан после закрытия пункта');
      expect(find.text('Отмечено'), findsOneWidget);
      expect(find.text('Текущее понятие: Раздел 2'), findsOneWidget,
          reason: 'точка сессии ушла на следующее понятие');
      expect(find.byIcon(Icons.check_circle), findsWidgets,
          reason: 'план перерисован: пройденный пункт помечен');
      // Статусный результат остаётся в панели, а не в карточке понятия.
      expect(
        find.descendant(
          of: find.byType(AdaptPanel),
          matching: find.byType(AdaptResultBody),
        ),
        findsOneWidget,
        reason: 'skip/replan — про план и статус, они показываются в панели',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('повторный пропуск — no-op с деликатным сообщением',
        (tester) async {
      // Текущий пункт уже закрыт: повторный пропуск ничего не меняет.
      final session = await seedSession(items: [
        _item('i1', _bId, 'Раздел 1', status: CurriculumItemStatus.completed),
        _item('i2', _aId, 'Раздел 2'),
      ]);
      await pumpSession(tester, session: session);

      await tester.tap(find.text('Знаю, пропустить'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('skip:s1:i1'));
      expect(find.text('Уже отмечено'), findsOneWidget);
      expect(find.text('Это понятие уже отмечено — ничего не изменилось.'),
          findsOneWidget);
      expect(find.text('Отмечено'), findsNothing);
      // Экран жив: план и призыв к изучению на месте.
      expect(find.text('План сессии'), findsOneWidget);
      expect(find.text('Изучать'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('глубина подачи', () {
    testWidgets('«Глубже» → результат рендерится, вызов с новой глубиной',
        (tester) async {
      final session = await seedSession();
      fake.depthResult = const AdaptDepthResult(
        sessionId: 's1',
        nodeId: _bId,
        title: 'Понятие B',
        text: 'Подробное объяснение с механизмом.',
        source: AdaptSource.llm,
        depth: ContentDepth.deep,
      );
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Глубже'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('change_depth:s1:$_bId'));
      expect(find.text('Подробное объяснение'), findsOneWidget);
      expect(
        find.textContaining('Подробное объяснение с механизмом',
            findRichText: true),
        findsOneWidget,
      );
      // Глубже ≠ проще: аудитория не меняется, бейджа сохранённого нет.
      expect(find.text('Сохранённый вариант'), findsNothing);
      _expectResultInConceptCard(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Успеваю только…»', () {
    testWidgets('пересборка плана под остаток: осталось и отложено',
        (tester) async {
      final session = await seedSession(items: [
        _item('i1', _bId, 'Раздел 1'),
        _item('i2', _aId, 'Раздел 2'),
        _item('i3', _rootId, 'Раздел 3'),
        _item('i4', _bId, 'Раздел 4'),
      ], budget: 30);
      await pumpSession(tester, session: session);
      expect(find.text('0/4 концептов'), findsOneWidget);

      await tester.tap(find.text('Успеваю только…'));
      await tester.pumpAndSettle();
      expect(find.text('Сколько времени осталось?'), findsOneWidget);

      await tester.tap(find.text('15 мин'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('replan:s1:15'));
      expect(find.text('План на оставшееся время'), findsOneWidget);
      expect(find.text('⏱ 15 мин'), findsWidgets);
      expect(find.text('Не влезло в остаток времени (3):'), findsOneWidget);
      expect(find.text('0/1 концептов'), findsOneWidget,
          reason: 'план перерисован под остаток времени');
      expect(find.text('Раздел 4'), findsWidgets, reason: 'отложенный пункт виден в результате');
      // Результат пересборки плана — статусный, остаётся в панели.
      expect(
        find.descendant(
          of: find.byType(AdaptPanel),
          matching: find.byType(AdaptResultBody),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('результат на месте понятия (шаг активности)', () {
    testWidgets(
        'read-шаг: результат заменяет текст шага, сброс возвращает исходный',
        (tester) async {
      final session = await seedSession();
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsOneWidget,
        reason: 'до действия показан исходный текст шага',
      );

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('simplify:s1:$_bId'));
      _expectResultInConceptCard(tester);
      _expectResultBetween(
        tester,
        find.text('Изучаем понятие'),
        find.widgetWithText(AppButton, 'Продолжить'),
      );
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsNothing,
        reason: 'текст шага подменён результатом',
      );

      await tester.tap(find.text('Вернуть обычное объяснение'));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptResultBody), findsNothing);
      expect(find.text('Вернуть обычное объяснение'), findsNothing);
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsOneWidget,
        reason: 'после сброса снова исходный текст',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'глубина: результат сверху, «Вернуть исходный текст» возвращает исходный',
        (tester) async {
      final session = await seedSession();
      fake.depthResult = const AdaptDepthResult(
        sessionId: 's1',
        nodeId: _bId,
        title: 'Понятие B',
        text: 'Подробное объяснение с механизмом.',
        source: AdaptSource.llm,
        depth: ContentDepth.deep,
      );
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Глубже'));
      await tester.pumpAndSettle();

      _expectResultInConceptCard(tester);
      // Чип глубины соответствует показанному тексту.
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Глубже'))
            .selected,
        isTrue,
      );
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsNothing,
      );

      // Подпись сброса не дублирует чип «Обычно» — сказано по делу.
      await tester.tap(
          find.widgetWithText(AppButton, 'Вернуть исходный текст'));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptResultBody), findsNothing);
      expect(find.text('Вернуть исходный текст'), findsNothing);
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'чип «Обычно» при активном результате — возврат без нового запроса',
        (tester) async {
      final session = await seedSession();
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('simplify:s1:$_bId'));
      expect(find.byType(AdaptResultBody), findsOneWidget);
      // Глубина текущая (результата глубины нет) — чип «Обычно» выбран.
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Обычно'))
            .selected,
        isTrue,
      );

      // Нажатие глубины, равной текущей, — это возврат, а не новый результат.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Обычно'));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        find.textContaining('Исходное объяснение понятия B', findRichText: true),
        findsOneWidget,
        reason: 'после чип-возврата снова исходный текст шага',
      );
      expect(
        fake.calls.where((c) => c.startsWith('change_depth')),
        isEmpty,
        reason: 'возврат не ходит в движок — нового результата нет',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('фазы панели и результата', () {
    testWidgets('шаг «Объяснение»: полный набор действий и глубины',
        (tester) async {
      final session = await seedSession();
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      expect(find.text('Что ещё можно сделать'), findsOneWidget);
      expect(find.text('Объясни проще'), findsOneWidget);
      expect(find.text('Из чего складывается'), findsOneWidget);
      expect(find.text('Знаю, пропустить'), findsOneWidget);
      expect(find.text('Успеваю только…'), findsOneWidget);
      expect(find.text('Насколько подробно:'), findsOneWidget);
      expect(find.text('Обычно'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'шаг «Пример»: только skip/replan, текстовый результат не показывается',
        (tester) async {
      final session = await seedSession();
      await pumpSession(
        tester,
        session: session,
        activity: _activity(const [_exampleStep]),
        adapt: const AdaptUiState(result: _simplifyResult),
      );

      // Заголовок остаётся, текстовых действий нет — менять нечего.
      expect(find.text('Что ещё можно сделать'), findsOneWidget);
      expect(find.text('Текущее понятие: Раздел 1'), findsOneWidget);
      expect(find.text('Знаю, пропустить'), findsOneWidget);
      expect(find.text('Успеваю только…'), findsOneWidget);
      expect(find.text('Объясни проще'), findsNothing);
      expect(find.text('Из чего складывается'), findsNothing);
      expect(find.text('Насколько подробно:'), findsNothing);
      expect(find.text('Обычно'), findsNothing);
      // Результат другой фазы на этом шаге не показывается, тело шага на месте.
      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        find.textContaining('Пример: программа останавливается',
            findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'шаг с вопросом: панель скрыта целиком, текстовый результат не показан',
        (tester) async {
      final session = await seedSession();
      await pumpSession(
        tester,
        session: session,
        activity: _activity(const [_recallStep]),
        adapt: const AdaptUiState(result: _simplifyResult),
      );

      // Ни карточки панели, ни её кнопок: в тесте нечего подмешивать.
      expect(find.text('Что ещё можно сделать'), findsNothing);
      expect(find.text('Объясни проще'), findsNothing);
      expect(find.text('Знаю, пропустить'), findsNothing);
      expect(find.text('Насколько подробно:'), findsNothing);
      expect(find.byType(AdaptResultBody), findsNothing);
      // Сам тест цел: вопрос и варианты на месте.
      expect(
        find.textContaining('Вопрос: что важнее при остановке?',
            findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Первое'), findsOneWidget);
      expect(find.text('Второе'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'шаг «Применение»: панель скрыта, поле ввода и кнопка на месте',
        (tester) async {
      final session = await seedSession();
      await pumpSession(
        tester,
        session: session,
        activity: _activity(const [_applyStep]),
        adapt: const AdaptUiState(result: _simplifyResult),
      );

      expect(find.text('Что ещё можно сделать'), findsNothing);
      expect(find.text('Объясни проще'), findsNothing);
      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        find.textContaining('Задача: примени правило', findRichText: true),
        findsOneWidget,
        reason: 'условие задачи остаётся',
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Проверить'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('сброс результата по смене фазы', () {
    testWidgets('«Изучать» закрывает результат — до шага он не доходит',
        (tester) async {
      final session = await seedSession();
      // В этой фазе текстовый результат создать уже нельзя (кнопок нет),
      // но застрявший результат прошлой фазы обязан исчезнуть при старте.
      final container = await pumpSession(
        tester,
        session: session,
        adapt: const AdaptUiState(result: _simplifyResult),
      );
      expect(find.byType(AdaptResultBody), findsNothing,
          reason: 'до активности текстовый результат не показывается');

      await tester.tap(find.widgetWithText(AppButton, 'Изучать'));
      // Сброс синхронный: ещё до подготовки шагов результата уже нет.
      await tester.pump();
      expect(
        container.read(sessionStoreProvider).adapt.result,
        isNull,
        reason: 'результат не должен дожить до активности',
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        container.read(sessionStoreProvider).activity,
        isNotNull,
        reason: 'само изучение дошло до шагов — экран показывает активность',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('переход к следующему шагу сбрасывает результат', (tester) async {
      final session = await seedSession();
      // Реальный сервис читает активность из сессии в БД: без неё шаг
      // не сменится и перехода не будет.
      const steps = [
        ActivityStep(
          type: 'explain',
          title: 'Изучаем понятие',
          body: 'Исходное объяснение понятия B.',
          status: 'current',
        ),
        _recallStep,
      ];
      await repo.updateSession(session.copyWith(
        activityJson: () =>
            jsonEncode({'itemId': 'i1', 'steps': steps}),
      ));
      final container = await pumpSession(tester,
          session: session, activity: _activity(steps));

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();
      expect(find.byType(AdaptResultBody), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Продолжить'));
      await tester.pumpAndSettle();

      expect(
        container.read(sessionStoreProvider).adapt.result,
        isNull,
        reason: 'результат относился к закрытому шагу чтения',
      );
      expect(find.byType(AdaptResultBody), findsNothing);
      expect(
        container.read(sessionStoreProvider).error,
        isNull,
        reason: 'переход шага дошёл до хранилища без ошибки',
      );
      expect(find.text('Что ещё можно сделать'), findsNothing,
          reason: 'следующий шаг — вопрос: панель скрыта');
      expect(
        find.textContaining('Вопрос: что важнее при остановке?',
            findRichText: true),
        findsOneWidget,
        reason: 'открылся следующий шаг — вопрос на месте',
      );
      expect(find.text('Первое'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ошибки Adapt', () {
    testWidgets('сбой движка — баннер, экран и панель живы', (tester) async {
      final session = await seedSession();
      fake.failOn = AdaptAction.simplify;
      await pumpSession(tester,
          session: session, activity: _activity(const [_explainStep]));

      await tester.tap(find.text('Объясни проще'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('simplify:s1:$_bId'));
      expect(find.text('Exception: adapt failed'), findsOneWidget);
      // Панель и сессия не упали: действия доступны для повтора.
      expect(find.text('Что ещё можно сделать'), findsOneWidget);
      expect(find.text('Объясни проще'), findsOneWidget);
      expect(find.text('План сессии'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
