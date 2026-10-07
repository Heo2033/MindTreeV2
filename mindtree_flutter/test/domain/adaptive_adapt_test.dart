// Детерминированные тесты действий Adapt (§80 спеки): упрощённое объяснение,
// prerequisite, пропуск уже известного, смена глубины (L1/L2/L3) и пересборка
// плана под оставшееся время.
//
// Ключевые свойства, которые здесь фиксируются:
//   • детерминизм: одинаковый вход → одинаковый результат, случайности нет;
//   • разделение «проще» и «глубже»: simplify меняет аудиторию на новичка,
//     changeDepth меняет только ЦЕЛЬ, аудитория берётся из уровня ученика;
//   • fallback: сбой LLM отдаёт сохранённый текст узла (`source: stored`),
//     а не роняет сценарий;
//   • skip пишет свидетельство самооценки и SRS-контроль (SM-2), но не
//     раздувает уровень ученика;
//   • replan использует тот же `fitPlanToBudget`, что и генерация плана.
//
// БД — `NativeDatabase.memory()`, LLM — детерминированный `FakeLlm` из
// `tool/probe/fake_llm.dart`: ни сети, ни ключей, ни Random() в пути.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/adaptive_learning_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _rootId = 'n1_topic~$_scope';
const _aId = 'n2_a~$_scope';
const _bId = 'n2_b~$_scope';

/// Корень темы.
KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзорная тема раздела.',
      details: 'Подробности корня.',
    );

/// Узел без связей: prerequisite у него — только предок по дереву.
KnowledgeNode _nodeA() => KnowledgeNode(
      id: _aId,
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие A',
      oneLiner: 'Суть понятия A в одном предложении.',
      details: 'Подробности понятия A.',
    );

/// Узел, который зависит от A: `prerequisitesOf` читает связи самого узла
/// (`rel.to` для depends_on/requires), затем идут предки по `parentId`.
KnowledgeNode _nodeB() => KnowledgeNode(
      id: _bId,
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие B',
      oneLiner: 'Суть понятия B в одном предложении.',
      details: 'Подробности понятия B.',
      relations: [
        const Relation(from: _bId, to: _aId, type: RelationType.dependsOn),
      ],
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;
  late FakeLlm fake;
  late List<String> prompts;

  /// Промпты контента (билдер `buildContentPrompt`) — по роли из prompts.dart.
  List<String> contentPrompts() =>
      [for (final p in prompts) if (p.contains('Ты — эксперт-энциклопедист')) p];

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    fake = FakeLlm();
    prompts = <String>[];
    engines = buildEngines(
      repo: repo,
      configProvider: () =>
          const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
      schedulerConfig: const SchedulerConfig(
        maxRPM: 100000,
        maxRPD: 100000,
        maxConcurrency: 1,
        maxRetries: 0,
      ),
      llmCall: (cfg, prompt, {model, temperature, seed}) async {
        prompts.add(prompt);
        return fake.invoke(cfg, prompt, model: model, temperature: temperature);
      },
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([_root(), _nodeA(), _nodeB()]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<LearningSession> createSession({String goal = 'exam', int budget = 30}) =>
      engines.session.create(CreateSessionInput(
        topicId: _topicId,
        goal: goal,
        timeBudgetMinutes: budget,
      ));

  /// Сессия с заданным планом (пункты задаются явно, без LLM-куррикулума).
  Future<LearningSession> sessionWithPlan(
    List<CurriculumItem> items, {
    int currentIndex = 0,
    String? blob,
    int step = 0,
    int budget = 30,
  }) async {
    final s = await createSession(budget: budget);
    final updated = s.copyWith(
      curriculum: Curriculum(
        sessionId: s.id,
        items: items,
        totalEstimatedMinutes:
            items.fold<int>(0, (sum, i) => sum + i.estimatedMinutes),
      ),
      currentIndex: currentIndex,
      activityJson: () => blob,
      currentActivityStep: step,
    );
    await repo.updateSession(updated);
    return updated;
  }

  CurriculumItem makeItem(
    int i, {
    CurriculumItemStatus status = CurriculumItemStatus.pending,
    int minutes = 10,
    String? nodeId,
    String? label,
  }) =>
      CurriculumItem(
        id: 'ci_$i',
        nodeId: nodeId ?? 'n2_p$i~$_scope',
        label: label ?? 'Пункт $i',
        order: i,
        estimatedMinutes: minutes,
        status: status,
      );

  Matcher throwsWith(String text) => throwsA(isA<Exception>()
      .having((e) => e.toString(), 'message', contains(text)));

  group('simplify: упрощённое объяснение', () {
    test('LLM: аудитория — новичок, цель берётся из сессии', () async {
      final s = await createSession(goal: 'exam');

      final r = await engines.adaptive.simplify(s.id, _aId);

      expect(r.action, AdaptAction.simplify);
      expect(r.source, AdaptSource.llm);
      expect(r.nodeId, _aId);
      expect(r.sessionId, s.id);
      expect(r.title, 'Понятие A');
      expect(r.oneLiner, isNotEmpty);
      expect(r.details, isNotEmpty);
      expect(r.text, isNotEmpty);
      expect(r.reasons, isNotEmpty);

      final prompt = contentPrompts().last;
      expect(prompt, contains('Опиши узел «Понятие A»'),
          reason: 'тот же билдер контента, что у обычного чтения узла');
      expect(prompt, contains('# Аудитория\nПиши максимально доступно для новичка'),
          reason: 'simplify всегда опускает аудиторию до новичка');
      expect(prompt, contains('# Цель\nЦель — подготовка к экзамену'),
          reason: 'цель подачи не переопределяется — остаётся цель сессии');
    });

    test('LLM недоступен → сохранённый текст узла, source: stored', () async {
      final s = await createSession();
      final offline = buildEngines(
        repo: repo,
        configProvider: () =>
            const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
        schedulerConfig: const SchedulerConfig(
          maxRPM: 100000,
          maxRPD: 100000,
          maxConcurrency: 1,
          maxRetries: 0,
        ),
        llmCall: (cfg, prompt, {model, temperature, seed}) async =>
            throw Exception('offline'),
      );

      final r = await offline.adaptive.simplify(s.id, _aId);

      expect(r.source, AdaptSource.stored);
      expect(r.text, 'Подробности понятия A.',
          reason: 'fallback — детерминированный текст узла');
      expect(r.oneLiner, 'Суть понятия A в одном предложении.');
      expect(r.reasons.first, contains('сохранённый текст'));
    });

    test('неизвестная сессия / чужой узел → исключения', () async {
      final s = await createSession();

      await expectLater(
          engines.adaptive.simplify('s_нет~$_scope', _aId), throwsWith('Session not found'));

      await repo.createTopic(const Topic(id: 't2', name: 'Другая тема'));
      await repo.insertNodes([
        const KnowledgeNode(
          id: 'n1_other~$_scope',
          topicId: 't2',
          parentId: null,
          level: 1,
          label: 'Другой корень',
          oneLiner: 'Другая тема.',
          details: 'Другие подробности.',
        ),
      ]);

      await expectLater(
          engines.adaptive.simplify(s.id, 'n1_other~$_scope'), throwsWith('Node not found'));
      await expectLater(
          engines.adaptive.simplify(s.id, 'n2_нет~$_scope'), throwsWith('Node not found'));
    });
  });

  group('changeDepth: глубина подачи', () {
    test('deep: цель глубокого изучения, аудитория — уровень ученика', () async {
      // Уровень поднят до «твёрдого понимания» → intermediate-тон. Глубже
      // не значит проще: новичковый тон в промпт deep-подачи попадать не должен.
      await engines.learnerModel
          .raiseOverallLevel(_topicId, MasteryLevel.solidUnderstanding);
      final s = await createSession(goal: 'exam');

      final r = await engines.adaptive.changeDepth(s.id, _aId, ContentDepth.deep);

      expect(r.action, AdaptAction.changeDepth);
      expect(r.depth, ContentDepth.deep);
      expect(r.source, AdaptSource.llm);
      expect(r.title, 'Понятие A');
      expect(r.text, isNotEmpty);

      final prompt = contentPrompts().last;
      expect(prompt, contains('# Цель\nЦель — глубокое изучение'));
      expect(
        prompt,
        contains('# Аудитория\nПиши для знакомого с основами читателя'),
        reason: 'аудитория берётся из уровня ученика, а не из глубины',
      );
      expect(prompt, isNot(contains('Пиши максимально доступно для новичка')));
    });

    test('overview / standard: меняется только цель подачи', () async {
      final s = await createSession(goal: 'exam');

      await engines.adaptive.changeDepth(s.id, _aId, ContentDepth.overview);
      final overviewPrompt = contentPrompts().last;
      expect(overviewPrompt, contains('# Цель\nЦель — общий обзор'));

      await engines.adaptive.changeDepth(s.id, _aId, ContentDepth.standard);
      final standardPrompt = contentPrompts().last;
      expect(standardPrompt, contains('# Цель\nЦель — подготовка к экзамену'),
          reason: 'стандартная глубина — это цель самой сессии');
    });

    test('одинаковый вход → идентичный результат', () async {
      final s = await createSession();

      final a = await engines.adaptive.changeDepth(s.id, _aId, ContentDepth.standard);
      final b = await engines.adaptive.changeDepth(s.id, _aId, ContentDepth.standard);

      expect(a.toJson(), b.toJson());
    });
  });

  group('prerequisites: чего не хватает', () {
    test('связь depends_on + предок по дереву, без LLM', () async {
      final s = await createSession();
      final before = prompts.length;

      final r = await engines.adaptive.prerequisites(s.id, _bId);

      expect(r.action, AdaptAction.prerequisite);
      expect(prompts.length, before,
          reason: 'оба источника детерминированы — LLM не вызывается');
      expect(r.prerequisites.map((p) => p.nodeId).toList(), [_aId, _rootId]);
      expect(
        r.prerequisites.map((p) => p.kind).toList(),
        [PrerequisiteKind.dependsOn, PrerequisiteKind.parent],
      );
      expect(r.missingNodeIds, [_aId, _rootId]);
      expect(r.prerequisites.every((p) => !p.studied), isTrue);
      expect(r.prerequisites.every((p) => p.mastery == null), isTrue,
          reason: 'измерений по концептам ещё не было');
      expect(r.text, contains('Не хватает'));
      expect(r.reasons.last, contains('Не изучено'));
    });

    test('изученный prerequisite помечается studied', () async {
      final s = await sessionWithPlan([
        makeItem(1, nodeId: _rootId, label: 'Теорема остановки',
            status: CurriculumItemStatus.completed),
        makeItem(2, nodeId: _aId, label: 'Понятие A'),
      ]);

      final r = await engines.adaptive.prerequisites(s.id, _bId);

      final rootRef = r.prerequisites.firstWhere((p) => p.nodeId == _rootId);
      expect(rootRef.studied, isTrue);
      expect(r.missingNodeIds, [_aId]);
      expect(r.text, isNot(contains('Все prerequisite')));
    });

    test('у корня нет ни связей, ни предков → пустой список, детерминизм', () async {
      final s = await createSession();

      final a = await engines.adaptive.prerequisites(s.id, _rootId);
      final b = await engines.adaptive.prerequisites(s.id, _rootId);

      expect(a.prerequisites, isEmpty);
      expect(a.missingNodeIds, isEmpty);
      expect(a.text, contains('нет обязательных prerequisite'));
      expect(a.toJson(), b.toJson());
    });
  });

  group('skip: пропуск уже известного', () {
    test('закрывает пункт, пишет SRS и свидетельство самооценки', () async {
      final s = await createSession();
      final item = s.curriculum.items.first;
      final total = s.curriculum.items.length;

      final r = await engines.adaptive.skip(s.id, item.id);

      expect(r.action, AdaptAction.skip);
      expect(r.changed, isTrue);
      expect(r.itemId, item.id);
      expect(r.evidence, kSkipEvidence);
      expect(r.progress, closeTo(1 / total, 1e-9));
      // поймано свидетельство (0→0.5 по двум измерениям), четыре измерения → 0.25.
      expect(r.masteryScore, closeTo(0.25, 1e-9));
      expect(r.text, contains('Понятие'));

      final after = await repo.getSession(s.id);
      expect(after!.curriculum.items.first.status, CurriculumItemStatus.completed);
      expect(after.currentIndex, 1, reason: 'индекс сдвинут как при обычном закрытии');

      final profile = await engines.learnerModel
          .getConceptProfile(item.nodeId, _topicId);
      expect(profile, isNotNull);
      expect(profile!.understanding, closeTo(0.5, 1e-9),
          reason: 'самооценка «знаю» блендится формулой new = prev*(1-w)+score*w');
      expect(profile.recall, closeTo(0.5, 1e-9));
      expect(profile.application, 0, reason: 'самооценка не evidencит применение');
      expect(profile.transfer, 0);
      expect(profile.srsInterval, 1, reason: 'первый контроль SM-2 — через 1 день');
      expect(profile.srsEase, closeTo(2.6, 1e-9), reason: 'ease 2.5 + 0.1 за correct');
    });

    test('повторный пропуск — no-op: changed=false, измерения не растут', () async {
      final s = await createSession();
      final item = s.curriculum.items.first;

      final first = await engines.adaptive.skip(s.id, item.id);
      final second = await engines.adaptive.skip(s.id, item.id);

      expect(first.changed, isTrue);
      expect(second.changed, isFalse);
      expect(second.evidence, isEmpty);
      expect(second.progress, first.progress);
      expect(second.masteryScore, first.masteryScore,
          reason: 'без повторного свидетельства мастерство не двигается');

      final profile = await engines.learnerModel
          .getConceptProfile(item.nodeId, _topicId);
      expect(profile!.understanding, closeTo(0.5, 1e-9));
      expect(profile.srsInterval, 1, reason: 'повторный skip не планирует второй контроль');
    });

    test('пункт без nodeId: SRS и мастерство не трогаются', () async {
      final s = await sessionWithPlan([
        const CurriculumItem(id: 'ci_x', nodeId: '', label: 'Без узла', order: 1),
        makeItem(2),
      ]);

      final r = await engines.adaptive.skip(s.id, 'ci_x');

      expect(r.changed, isTrue);
      expect(r.nodeId, isNull);
      expect(r.evidence, isEmpty);
      expect(r.masteryScore, isNull);
      expect(r.progress, closeTo(0.5, 1e-9));
    });

    test('неизвестная сессия / пункт → исключения', () async {
      final s = await createSession();

      await expectLater(
          engines.adaptive.skip('s_нет~$_scope', 'ci_1'), throwsWith('Session not found'));
      await expectLater(
          engines.adaptive.skip(s.id, 'ci_нет~$_scope'), throwsWith('Item not found'));
    });
  });

  group('replanRemaining: план под оставшееся время', () {
    test('остаток 15 мин: лишние пункты откладываются, blob стирается', () async {
      final s = await sessionWithPlan([
        makeItem(1, status: CurriculumItemStatus.completed),
        makeItem(2),
        makeItem(3),
        makeItem(4),
        makeItem(5),
      ], currentIndex: 2, blob: '{"itemId":"ci_3","steps":[]}', step: 3);

      final r = await engines.adaptive.replanRemaining(s.id, remainingMinutes: 15);

      expect(r.action, AdaptAction.replan);
      expect(r.remainingMinutes, 15);
      expect(r.elapsedMinutes, 0);
      expect(r.kept.map((i) => i.id).toList(), ['ci_1', 'ci_2'],
          reason: 'завершённое остаётся + влезшее по бюджету (10 из 40 мин)');
      expect(r.kept.map((i) => i.order).toList(), [1, 2],
          reason: 'нумерация пересобирается под новый состав');
      expect(
        r.kept.map((i) => i.status).toList(),
        [CurriculumItemStatus.completed, CurriculumItemStatus.pending],
      );
      expect(r.deferred.map((i) => i.id).toList(), ['ci_3', 'ci_4', 'ci_5']);
      expect(r.kept.fold<int>(0, (sum, i) => sum + i.estimatedMinutes), 20);

      final after = await repo.getSession(s.id);
      expect(after!.curriculum.items.map((i) => i.id).toList(), ['ci_1', 'ci_2']);
      expect(after.curriculum.totalEstimatedMinutes, 20);
      expect(after.currentIndex, 1,
          reason: 'старый текущий пункт отложен — встаём на первый незавершённый');
      expect(after.activityJson, '[]',
          reason: 'blob нарисован под отложенный пункт — он убирается');
      expect(after.currentActivityStep, 0);

      expect(r.eta.pace, PaceClass.faster, reason: '0 мин на 1 завершённый — быстрее плана');
      expect(r.eta.completedItems, 1);
      expect(r.eta.totalItems, 2);
      expect(r.text, contains('отложено 3'));
      expect(r.reasons.first, contains('Прошло 0 мин из 30 мин'));
    });

    test('повторный пересбор с тем же остатком идемпотентен', () async {
      final s = await sessionWithPlan([
        makeItem(1, status: CurriculumItemStatus.completed),
        makeItem(2),
        makeItem(3),
        makeItem(4),
      ], currentIndex: 2);

      final first = await engines.adaptive.replanRemaining(s.id, remainingMinutes: 15);
      final second = await engines.adaptive.replanRemaining(s.id, remainingMinutes: 15);

      expect(second.kept.map((i) => i.id).toList(), first.kept.map((i) => i.id).toList());
      expect(second.kept.map((i) => i.order).toList(), [1, 2]);
      expect(second.deferred, isEmpty, reason: 'отложить больше нечего');
      expect(second.remainingMinutes, 15);
    });

    test('остаток 0 мин: остаётся хотя бы один пункт', () async {
      final s =
          await sessionWithPlan([makeItem(1), makeItem(2), makeItem(3), makeItem(4)]);

      final r = await engines.adaptive.replanRemaining(s.id, remainingMinutes: 0);

      expect(r.remainingMinutes, 0);
      expect(r.kept.map((i) => i.id).toList(), ['ci_1'],
          reason: 'первый пункт сохраняется всегда, иначе план пуст');
      expect(r.deferred.map((i) => i.id).toList(), ['ci_2', 'ci_3', 'ci_4']);

      final negative =
          await engines.adaptive.replanRemaining(s.id, remainingMinutes: -10);
      expect(negative.remainingMinutes, 0, reason: 'отрицательный остаток обрезается');
    });

    test('без явного остатка берётся остаток бюджета сессии', () async {
      final s = await sessionWithPlan(
        [makeItem(1), makeItem(2), makeItem(3), makeItem(4)],
        budget: 30,
      );
      await repo.insertEvent(LearningEvent(
        id: 'ev_elapsed',
        sessionId: s.id,
        type: LearningEventType.itemCompleted,
        durationMs: 25 * 60 * 1000,
      ));

      final r = await engines.adaptive.replanRemaining(s.id);

      expect(r.elapsedMinutes, 25);
      expect(r.remainingMinutes, 5, reason: '30 мин бюджета − 25 мин прошло');
      expect(r.kept.map((i) => i.id).toList(), ['ci_1'],
          reason: 'под 5 мин влезает только первый 10-минутный пункт');
      expect(r.eta.elapsedMinutes, 25);
    });

    test('текущий пункт выжил → активность не трогаем', () async {
      const blob = '{"itemId":"ci_2","steps":[]}';
      final s = await sessionWithPlan([
        makeItem(1, status: CurriculumItemStatus.completed),
        makeItem(2),
        makeItem(3),
      ], currentIndex: 1, blob: blob, step: 3);

      await engines.adaptive.replanRemaining(s.id, remainingMinutes: 15);

      final after = await repo.getSession(s.id);
      expect(after!.currentIndex, 1);
      expect(after.activityJson, blob);
      expect(after.currentActivityStep, 3);
    });

    test('неизвестная сессия → исключение', () async {
      await expectLater(engines.adaptive.replanRemaining('s_нет~$_scope'),
          throwsWith('Session not found'));
    });
  });
}
