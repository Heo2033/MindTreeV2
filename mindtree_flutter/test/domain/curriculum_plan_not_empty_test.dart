// Регрессия: CurriculumEngine.generate возвращал ПУСТОЙ curriculum.
//
// Симптом у пользователя: «нажал генерацию — ничего не создалось» (сессия с
// 0 элементов, вечное «генерация…»).
//
// Причина (исправлено в `lib/domain/engines/curriculum_engine.dart`):
//   List<CurriculumItemResult> llmItems = baseline;
//   try { llmItems = await llmSelect(req); } catch (_) { /* baseline */ }
// `llmItems` заменял детерминированный baseline ЛЮБЫМ результатом LLM, а
// `parseCurriculumResult` не бросает исключение на `{"items": []}` (и на ответе
// вовсе без поля `items`) — возвращает пустой список. Значит `catch` не
// срабатывал, и пустой список заменял baseline. Вторая половина бага: модель
// часто возвращает «сырые» id без `~`-скоупа (n2_root_1 вместо n2_root_1~hash),
// и такой план тоже не соответствовал дереву.
//
// Фикс: LLM-результат фильтруется по `knownIds`; если после фильтра пусто —
// остаётся baseline; плюс последний рубеж `fitted.isEmpty && baseline.isNotEmpty`.
//
// Тесты детерминированы: настоящий CurriculumEngine и настоящий TreeScheduler,
// в который подставлен `llmCall`, отдающий заранее заданный «сырой» JSON.
// Ни сети, ни ключей, ни Random() в пути.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// `~`-суффикс scoped-идов (`lib/domain/engines/scoped_ids.dart`).
const _scope = '1a2b3c4d';
const _rootId = 'n1_topic~$_scope';

/// Подмена LLM: отдаёт заранее заданный сырой ответ либо падает.
/// `raw == null` → вызов бросает исключение (сбой провайдера).
/// `LLMMockException` scheduler не ретраит (`shouldRetry`), поэтому тест не ждёт.
class _FakeLlm {
  _FakeLlm(this.raw);

  final String? raw;
  int calls = 0;

  Future<llm_client.LLMResult> invoke(
    llm_client.LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) async {
    calls++;
    if (raw == null) {
      throw llm_client.LLMMockException('провайдер недоступен (тест)');
    }
    return llm_client.LLMResult(
      text: raw!,
      usage: const llm_client.LLMUsage(inputTokens: 10, outputTokens: 10),
    );
  }
}

TreeScheduler _scheduler(_FakeLlm fake) => TreeScheduler(
      configProvider: () => const llm_client.LLMConfig(isMock: true),
      config: const SchedulerConfig(maxRetries: 0),
      llmCall: fake.invoke,
    );

/// Ответ LLM в контракте `parseCurriculumResult`.
String _rawItems(List<Map<String, Object>> items, {int? totalMinutes}) =>
    jsonEncode({
      'items': items,
      'total_estimated_minutes': totalMinutes ??
          items.fold<int>(0, (s, i) => s + (i['estimated_minutes'] as int)),
    });

Map<String, Object> _llmItem(String nodeId, int order, int minutes) => {
      'node_id': nodeId,
      'order': order,
      'estimated_minutes': minutes,
      'why': 'потому что $nodeId',
    };

KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: 't1',
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзорная тема раздела.',
      details: 'Подробности корня.',
    );

/// Узел уровня 2 — именно они попадают в учебный план (корень не учится).
/// Важность и время намеренно различаются, чтобы baseline был неоднородным.
KnowledgeNode _child(int i) => KnowledgeNode(
      id: 'n2_root_$i~$_scope',
      topicId: 't1',
      parentId: _rootId,
      level: 2,
      label: 'Понятие $i',
      oneLiner: 'Суть понятия $i в одном предложении.',
      details: 'Подробности понятия $i.',
      importance: 0.35 + 0.05 * (i % 6),
      estimatedTimeMinutes: 4 + (i % 5) * 3, // 4, 7, 10, 13, 16 минут
    );

/// Дерево из [learnable] учебных узлов (уровень ≥ 2) плюс корень.
/// «Размер дерева» в тестах = число учимых понятий: корень в план не идёт.
List<KnowledgeNode> _tree(int learnable) => [
      _root(),
      for (var i = 1; i <= learnable; i++) _child(i),
    ];

CurriculumRequest _req(
  List<KnowledgeNode> nodes, {
  int budget = 60,
  String goal = 'понимание',
  Set<String>? known,
}) =>
    CurriculumRequest(
      topicId: 't1',
      topicName: 'Теорема остановки',
      goal: goal,
      targetLevel: 'solid_understanding',
      currentLevel: 'basic_understanding',
      timeBudgetMinutes: budget,
      nodes: nodes,
      knownNodeIds: known,
    );

int _sumMinutes(List<CurriculumItem> items) =>
    items.fold<int>(0, (s, i) => s + i.estimatedMinutes);

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    await repo.createTopic(const Topic(id: 't1', name: 'Теорема остановки'));
  });

  tearDown(() async {
    await db.close();
  });

  // Настоящий движок с подменённым LLM.
  ({CurriculumEngine engine, _FakeLlm llm}) engineWith(String? raw) {
    final llm = _FakeLlm(raw);
    return (engine: CurriculumEngine(repo: repo, scheduler: _scheduler(llm)), llm: llm);
  }

  group('parseCurriculumResult: почему одного catch не хватало', () {
    test('пустой items не бросает исключение, а отдаёт пустой список', () {
      // Именно этот дефект ломал fallback: catch не срабатывал.
      final CurriculumLlmResult parsed = parseCurriculumResult({
        'items': <Object>[],
        'total_estimated_minutes': 0,
      });
      expect(parsed.items, isEmpty);
    });

    test('ответ без поля items тоже не бросает исключение', () {
      final CurriculumLlmResult parsed =
          parseCurriculumResult({'total_estimated_minutes': 0});
      expect(parsed.items, isEmpty);
    });

    test('битый JSON-тип (items не список) не бросает исключение', () {
      final CurriculumLlmResult parsed =
          parseCurriculumResult({'items': 'вместо списка'});
      expect(parsed.items, isEmpty);
    });
  });

  group('CurriculumEngine.generate: план непустой при любом ответе LLM', () {
    test('LLM вернул {"items": []} → план из детерминированного baseline', () async {
      final nodes = _tree(3);
      final req = _req(nodes);
      final (engine: engine, llm: llm) = engineWith(_rawItems(const []));

      final result = await engine.generate(req);

      expect(llm.calls, 1, reason: 'LLM был вызван — тест не подменяет generate');
      expect(result.curriculum.items, isNotEmpty,
          reason: 'пустой ответ LLM не должен обнулять план');
      final baseline = engine.deterministicSelect(req);
      expect([for (final i in result.curriculum.items) i.nodeId],
          [for (final b in baseline) b.nodeId]);
      expect([for (final i in result.curriculum.items) i.estimatedMinutes],
          [for (final b in baseline) b.estimatedMinutes]);
    });

    test('LLM вернул ответ без поля items → тот же непустой план', () async {
      final nodes = _tree(3);
      final req = _req(nodes);
      final (engine: engine, llm: llm) = engineWith(
        jsonEncode({'total_estimated_minutes': 0, 'note': 'не знаю что выбрать'}),
      );

      final result = await engine.generate(req);

      expect(llm.calls, 1);
      expect(result.curriculum.items, isNotEmpty);
      final baseline = engine.deterministicSelect(req);
      expect([for (final i in result.curriculum.items) i.nodeId],
          [for (final b in baseline) b.nodeId]);
    });

    test('LLM вернул битый JSON → парсер/движок не роняют сценарий', () async {
      final nodes = _tree(3);
      final req = _req(nodes);
      final (engine: engine, llm: llm) = engineWith('просто текст без JSON');

      final result = await engine.generate(req);

      expect(llm.calls, greaterThanOrEqualTo(1));
      expect(result.curriculum.items, isNotEmpty);
    });

    test('LLM вернул только сырые id без скоупа → всё отброшено, взят baseline',
        () async {
      final nodes = _tree(3);
      final req = _req(nodes);
      // Модель «забыла» `~`-суффикс: n2_root_1 вместо n2_root_1~1a2b3c4d.
      final (engine: engine, llm: llm) = engineWith(
        _rawItems([
          _llmItem('n2_root_1', 1, 7),
          _llmItem('n2_root_2', 2, 9),
          _llmItem('n2_root_3', 3, 11),
        ]),
      );

      final result = await engine.generate(req);

      expect(llm.calls, 1);
      expect(result.curriculum.items, isNotEmpty);
      final treeIds = {for (final n in nodes) n.id};
      for (final item in result.curriculum.items) {
        expect(treeIds, contains(item.nodeId),
            reason: 'сырой id без скоупа попал в план');
      }
      final baseline = engine.deterministicSelect(req);
      expect([for (final i in result.curriculum.items) i.nodeId],
          [for (final b in baseline) b.nodeId]);
    });

    test('LLM вернул смешанный список → остались только валидные', () async {
      final nodes = _tree(4);
      final req = _req(nodes);
      final validA = 'n2_root_2~$_scope';
      final validB = 'n2_root_3~$_scope';
      final (engine: engine, llm: llm) = engineWith(
        _rawItems([
          _llmItem(validA, 1, 7),
          _llmItem('n2_root_99', 2, 99), // мусор: нет такого узла
          _llmItem(validB, 3, 3),
          _llmItem('', 4, 5), // пустой id
        ]),
      );

      final result = await engine.generate(req);

      expect(llm.calls, 1);
      expect([for (final i in result.curriculum.items) i.nodeId],
          [validA, validB],
          reason: 'порядок и состав — только из валидных пунктов LLM');
      expect([for (final i in result.curriculum.items) i.estimatedMinutes],
          [7, 3],
          reason: 'минуты берутся из валидных пунктов, мусорные 99 не попадают');
      // Порядок возрастает (после отбрасывания мусора в order остаются пропуски —
      // fitPlanToBudget только сортирует, но не перенумеровывает).
      final orders = [for (final i in result.curriculum.items) i.order];
      expect(orders, orderedEquals([...orders]..sort()));
    });

    test('LLM упал исключением → детерминированный baseline (не сломали)',
        () async {
      final nodes = _tree(3);
      final req = _req(nodes);
      final (engine: engine, llm: llm) = engineWith(null);

      final result = await engine.generate(req);

      expect(llm.calls, 1, reason: 'LLMMockException не ретраится');
      expect(result.curriculum.items, isNotEmpty);
      final baseline = engine.deterministicSelect(req);
      expect([for (final i in result.curriculum.items) i.nodeId],
          [for (final b in baseline) b.nodeId]);
    });

    test('валидный план LLM не вытесняется baseline-ом', () async {
      // Обратная сторона фикса: если LLM ответил осмысленно, его выбор сохраняется.
      final nodes = _tree(4);
      final req = _req(nodes);
      final (engine: engine, llm: llm) = engineWith(
        _rawItems([
          _llmItem('n2_root_4~$_scope', 1, 12),
          _llmItem('n2_root_1~$_scope', 2, 6),
        ]),
      );

      final result = await engine.generate(req);

      expect(llm.calls, 1);
      expect([for (final i in result.curriculum.items) i.nodeId],
          ['n2_root_4~$_scope', 'n2_root_1~$_scope']);
    });
  });

  group('Инвариант: непустой план при непустом бюджете', () {
    const budgets = [1, 5, 30, 60];
    const sizes = [1, 3, 20];
    const goals = [
      'понимание',
      'практическое применение',
      'подготовка к экзамену',
    ];

    test('план непустой во всех комбинациях бюджет × размер × цель', () async {
      final failures = <String>[];
      for (final budget in budgets) {
        for (final size in sizes) {
          for (final goal in goals) {
            final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
            // Подставляем LLM-ответ, который раньше обнулял план.
            final result =
                await engine.generate(_req(_tree(size), budget: budget, goal: goal));
            final ids = [for (final i in result.curriculum.items) i.nodeId];
            if (ids.isEmpty) {
              failures.add('budget=$budget size=$size goal="$goal"');
            }
            // Пункты плана всегда указывают на узлы дерева.
            final treeIds = {for (final n in _tree(size)) n.id};
            for (final id in ids) {
              if (!treeIds.contains(id)) failures.add('visiting id $id');
            }
          }
        }
      }
      expect(failures, isEmpty, reason: 'пустой план: ${failures.join(", ")}');
    });

    test('план непустой при LLM-ответе из одних сырых id', () async {
      final failures = <String>[];
      for (final budget in budgets) {
        for (final size in sizes) {
          final (engine: engine, llm: llm) = engineWith(
            _rawItems([_llmItem('n2_root_1', 1, 5), _llmItem('n2_root_2', 2, 5)]),
          );
          final result = await engine.generate(_req(_tree(size), budget: budget));
          if (result.curriculum.items.isEmpty) {
            failures.add('budget=$budget size=$size');
          }
        }
      }
      expect(failures, isEmpty, reason: 'пустой план: ${failures.join(", ")}');
    });

    test('бюджет соблюдён: сумма минут ≤ бюджета (кроме одного длинного пункта)',
        () async {
      final violations = <String>[];
      for (final budget in budgets) {
        for (final size in sizes) {
          final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
          final result = await engine.generate(_req(_tree(size), budget: budget));
          final items = result.curriculum.items;
          if (items.isEmpty) {
            violations.add('budget=$budget size=$size: пустой план');
            continue;
          }
          final total = _sumMinutes(items);
          // Допустимое исключение fitPlanToBudget: единственный пункт, который
          // сам по себе длиннее бюджета (иначе план был бы пустым).
          final singleTooLong =
              items.length == 1 && items.single.estimatedMinutes > budget;
          if (total > budget && !singleTooLong) {
            violations.add(
              'budget=$budget size=$size: $total мин в ${items.length} пунктах',
            );
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('; '));
    });

    test('totalEstimatedMinutes совпадает с суммой пунктов', () async {
      for (final budget in budgets) {
        for (final size in sizes) {
          final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
          final result = await engine.generate(_req(_tree(size), budget: budget));
          expect(result.curriculum.totalEstimatedMinutes,
              _sumMinutes(result.curriculum.items),
              reason: 'budget=$budget size=$size');
        }
      }
    });

    test('детерминирован: два одинаковых входа дают одинаковый план', () async {
      for (final budget in budgets) {
        for (final size in sizes) {
          final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
          final req = _req(_tree(size), budget: budget);
          final first = await engine.generate(req);
          final second = await engine.generate(req);
          expect([for (final i in second.curriculum.items) i.nodeId],
              [for (final i in first.curriculum.items) i.nodeId],
              reason: 'порядок и node id: budget=$budget size=$size');
          expect([for (final i in second.curriculum.items) i.estimatedMinutes],
              [for (final i in first.curriculum.items) i.estimatedMinutes]);
        }
      }
    });
  });

group('Границы: когда пустой план — это законно', () {
    test('дерево только с корнем (level 1) → в план попадает корень', () async {
      // Раньше deterministicSelect брал только level >= 2, и на дереве из
      // одного корня план выходил пустым — то самое «генерация не создалась».
      // Теперь корневая страховка: сессия всегда предлагает хоть что-то.
      final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
      final result = await engine.generate(_req([_root()]));
      expect(result.curriculum.items, hasLength(1));
      expect(result.curriculum.items.single.nodeId, _root().id);
    });

    test('пустое дерево → пустой план без исключения', () async {
      final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
      final result = await engine.generate(_req(const []));
      expect(result.curriculum.items, isEmpty);
      expect(result.curriculum.totalEstimatedMinutes, 0);
    });

    test('все узлы уже освоены → план пуст, но alreadyKnown заполнен', () async {
      final nodes = _tree(3);
      final known = {for (final n in nodes) n.id};
      final (engine: engine, llm: llm) = engineWith(_rawItems(const []));
      final result = await engine.generate(_req(nodes, known: known));
      expect(result.curriculum.items, isEmpty);
      expect(result.alreadyKnown, isNotEmpty);
    });
  });
}
