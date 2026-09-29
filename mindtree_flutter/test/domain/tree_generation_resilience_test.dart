// Устойчивость и детерминизм пайплайна генерации дерева знаний.
//
// Закрывает дефекты, найденные на живом провайдере (тема «Диффузионные модели»,
// 30 мин): 52.7 мин на 16 вызовов, 3 жёстких сбоя, из-за одного сбоя
// `structure-l2` потерян целиком уровень 2 (дерево = 7 узлов вместо ~17).
//
// Что здесь проверяется:
//  1. Сбой `structure-l2` НЕ «съедает» уровень 2: движок переключается на
//     `expand` от корня, а если и он падает — на детерминированный скелет.
//     В обоих случаях инварианты дерева (один корень, `parentId` существуют,
//     циклов нет, уровни консистентны) сохраняются.
//  2. Параллельный L3 даёт тот же порядок узлов, что и последовательный:
//     результат не зависит от того, в каком порядке ответили ветви.
//  3. Ремонт не каскадирует: бюджет ограничивает число вызовов `repair`
//     на всё дерево, при исчерпании пайплайн не падает.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';

import '../../tool/probe/fake_llm.dart';

const String _query = 'диффузионные модели';

/// L2-узлы детерминированного fake-LLM для темы выше — в порядке генерации.
const List<String> _expectedL2Ids = [
  'n2_root_1',
  'n2_root_2',
  'n2_root_3',
  'n2_root_4',
];

/// Порядок id в полном дереве: корень → L2 по ветвям → L3 по ветвям.
/// Именно такой порядок даёт и последовательный, и параллельный прогон.
List<String> _expectedNodeIds() => <String>[
      'n1_root',
      for (final id in _expectedL2Ids) id,
      for (final id in _expectedL2Ids)
        for (var i = 1; i <= 3; i++) 'n3_${id.substring(3)}_$i',
    ];

/// `parentId` раздела из L3-промпта (см. `fake_llm.dart::_parentId`).
String _parentIdOfL3Prompt(String prompt) {
  final m = RegExp(r'"parentId"\s*:\s*"([^"]+)"').firstMatch(prompt);
  return m == null ? '' : m.group(1)!;
}

// ─── Подставные транспорты ───────────────────────────────────────────────────

/// Ломает выбранные виды промптов (детерминированный сбой на уровне ответа).
class _BrokenFakes extends FakeLlm {
  _BrokenFakes({required this.broken});

  final Set<PromptKind> broken;

  @override
  String respondTo(PromptKind kind, String prompt) {
    if (broken.contains(kind)) {
      throw StateError('подставной сбой транспорта на ${kind.schedulerOperation}');
    }
    return super.respondTo(kind, prompt);
  }
}

/// L3-ответы приходят в обратном порядке ветвей + счётчик одновременных вызовов.
///
/// Обратный порядок завершения — то, что ломало бы наивную параллелизацию.
class _ReverseL3Llm extends FakeLlm {
  int inFlight = 0;
  int maxInFlight = 0;
  final List<String> completionOrder = [];

  @override
  Future<LLMResult> invoke(
    LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) async {
    final kind = classifyPrompt(prompt);
    if (kind == PromptKind.l3) {
      final parentId = _parentIdOfL3Prompt(prompt);
      final rank = _expectedL2Ids.indexOf(parentId);
      // Слот держим всю «латентность» подставного ответа: иначе счётчик не
      // увидит перекрытия (всё завершается в микротаске).
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      try {
        if (rank >= 0) {
          // Чем ниже ветвь, тем быстрее отвечает: порядок завершения обратный.
          await Future<void>.delayed(Duration(milliseconds: 60 - rank * 15));
          completionOrder.add(parentId);
        }
        return await super.invoke(cfg, prompt,
            model: model, temperature: temperature, seed: seed);
      } finally {
        inFlight--;
      }
    }
    return super.invoke(cfg, prompt,
        model: model, temperature: temperature, seed: seed);
  }
}

/// Валидация всегда находит проблемы → ремонт запрашивается на каждой ветке.
class _AlwaysInvalidLlm extends FakeLlm {
  @override
  String respondTo(PromptKind kind, String prompt) {
    if (kind == PromptKind.validate) {
      return jsonEncode({
        'valid': false,
        'issues': <Map<String, dynamic>>[
          {'type': 'OVERLAP', 'node_id': 'n1_root', 'reason': 'наложение понятий'},
        ],
        'missing_concepts': <Map<String, dynamic>>[],
        'should_expand': false,
      });
    }
    return super.respondTo(kind, prompt);
  }
}

// ─── Обвязка ──────────────────────────────────────────────────────────────────

MindtreeEngines _engines(MindtreeDb db, FakeLlm fake,
    {int maxConcurrency = 1}) {
  return buildEngines(
    repo: MindtreeRepository(db),
    configProvider: () =>
        const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
    schedulerConfig: SchedulerConfig(
      maxRPM: 100000,
      maxRPD: 100000,
      maxConcurrency: maxConcurrency,
      maxRetries: 0,
    ),
    llmCall: (cfg, prompt, {model, temperature, seed}) async =>
        fake.invoke(cfg, prompt, model: model, temperature: temperature),
  );
}

/// Прогоняет `generate` на подставном транспорте и возвращает результат.
Future<TreeBuildResult> _generate(FakeLlm fake,
    {String level = 'intermediate', int maxConcurrency = 1}) async {
  final db = MindtreeDb(NativeDatabase.memory());
  final engines = _engines(db, fake, maxConcurrency: maxConcurrency);
  try {
    return await engines.graph.generate(
      _query,
      goal: 'overview',
      level: level,
      timeBudgetMinutes: 30,
    );
  } finally {
    await db.close();
  }
}

/// Инварианты дерева (AGENTS.md): один корень, `parentId` существуют, циклов
/// нет, уровень равен глубине. Падает с понятным сообщением при нарушении.
void _expectTreeInvariants(List<NodeDraft> nodes) {
  expect(nodes, isNotEmpty);
  final byId = {for (final n in nodes) n.id: n};
  expect(byId.length, nodes.length, reason: 'id узлов должны быть уникальны');

  final roots = nodes.where((n) => n.parentId == null).toList();
  expect(roots.length, 1, reason: 'в дереве должен быть ровно один корень');

  for (final n in nodes) {
    final parentId = n.parentId;
    if (parentId == null) continue;
    expect(
      byId.containsKey(parentId),
      isTrue,
      reason: 'parentId «$parentId» узла «${n.title}» не существует',
    );
  }

  // Циклов нет: подъём к корню обязан завершиться, а `level` равен глубине.
  for (final n in nodes) {
    var depth = 0;
    String? cursor = n.parentId;
    final seen = <String>{n.id};
    while (cursor != null) {
      expect(
        seen.add(cursor),
        isTrue,
        reason: 'цикл в дереве: узел «${n.title}» (${n.id})',
      );
      depth++;
      expect(depth, lessThanOrEqualTo(nodes.length),
          reason: 'слишком длинная цепочка родителей — вероятен цикл');
      cursor = byId[cursor]?.parentId;
    }
    expect(
      n.level,
      depth + 1,
      reason: 'уровень узла «${n.title}» не совпадает с глубиной',
    );
  }
}

void main() {
  group('fail-soft уровня 2', () {
    test('сбой structure-l2 → уровень восстановлен через expand', () async {
      final fake = _BrokenFakes(broken: {PromptKind.l2});
      final result = await _generate(fake);

      // Уровень 2 не потерян.
      final l2 = result.nodes.where((n) => n.level == 2).toList();
      expect(l2, isNotEmpty,
          reason: 'после сбоя structure-l2 тема не должна остаться без разделов');
      expect(l2.length, 3, reason: 'expand от корня даёт трёх детей уровня 2');

      // Дальше конвейер продолжает работу: L3 тоже сгенерирован.
      expect(result.nodes.where((n) => n.level == 3), isNotEmpty);

      // Корень ровно один, все дети — его.
      final root = result.nodes.firstWhere((n) => n.parentId == null);
      for (final n in l2) {
        expect(n.parentId, root.id);
      }

      // Деградация помечена: узлы в degradedNodeIds + warning в отчёт probe.
      expect(result.degradedNodeIds, isNotEmpty);
      expect(
        result.warnings.where((w) => w.contains('восстановлен')).length,
        1,
        reason: 'нужен ровно один warning о восстановлении: ${result.warnings}',
      );
      expect(
        result.warnings.any((w) => w.contains('Генерация разделов не завершена')),
        isTrue,
      );

      _expectTreeInvariants(result.nodes);
    });

    test('сбой structure-l2 и expand → детерминированный скелет', () async {
      final fake = _BrokenFakes(broken: {PromptKind.l2, PromptKind.expand});
      final result = await _generate(fake);

      final l2 = result.nodes.where((n) => n.level == 2).toList();
      expect(l2, isNotEmpty, reason: 'уровень 2 должен быть восстановлен скелетом');
      expect(
        l2.map((n) => n.title).toList(),
        ['Основы', 'Ключевые направления', 'Применение'],
        reason: 'запасной уровень 2 детерминирован (fallbackStructure)',
      );

      // Скелет привязан к НАСТОЯЩЕМУ корню, а не к id из demo-дерева.
      final root = result.nodes.firstWhere((n) => n.parentId == null);
      expect(root.id, 'n1_root');
      for (final n in l2) {
        expect(n.parentId, root.id,
            reason: 'parentId демо-раздела должен указывать на реальный корень');
      }

      expect(result.degradedNodeIds.length, l2.length);
      expect(
        result.warnings.any((w) => w.contains('демо-структурой')),
        isTrue,
        reason: 'пользователь должен видеть, что структура ненастоящая: '
            '${result.warnings}',
      );

      _expectTreeInvariants(result.nodes);
    });

    test('сбой structure-l2 не ломает инкрементальный onBatch', () async {
      final db = MindtreeDb(NativeDatabase.memory());
      final fake = _BrokenFakes(broken: {PromptKind.l2});
      final engines = _engines(db, fake);
      // `onBatch` получает «сырые» id (скоупит вызывающий), поэтому порядок
      // «родитель раньше детей» проверяем по ним: ребёнок не должен попасть в
      // БД раньше родителя, иначе репозиторий отбросит сироту.
      final seen = <String>{};
      final batches = <int>[];
      try {
        final result = await engines.graph.generate(
          _query,
          goal: 'overview',
          level: 'intermediate',
          timeBudgetMinutes: 30,
          onBatch: (batch) async {
            batches.add(batch.length);
            for (final n in batch) {
              final parent = n.parentId;
              expect(
                parent == null || seen.contains(parent),
                isTrue,
                reason: 'ребёнок «${n.title}» ($n) сохранён раньше родителя $parent',
              );
            }
            seen.addAll(batch.map((n) => n.id));
          },
        );
        _expectTreeInvariants(result.nodes);
        expect(seen, hasLength(result.nodes.length),
            reason: 'onBatch обязан передать все узлы ровно по одному разу');
        // Уровни персистятся инкрементально, а не одним батчем в конце.
        expect(batches.length, greaterThan(1));
        expect(batches.first, 1, reason: 'корень виден пользователю сразу');
      } finally {
        await db.close();
      }
    });
  });

  group('параллельный L3', () {
    test('порядок узлов не зависит от порядка ответов ветвей', () async {
      final fake = _ReverseL3Llm();
      final result = await _generate(fake, maxConcurrency: 4);

      // Ответы действительно пришли в обратном порядке — иначе тест ничего
      // не проверяет.
      expect(fake.completionOrder.length, 4);
      expect(
        fake.completionOrder,
        _expectedL2Ids.reversed.toList(),
        reason: 'подставной транспорт должен отвечать в обратном порядке',
      );

      // Порядок узлов — как при последовательном прогоне.
      expect(
        result.nodes.map((n) => n.id).toList(),
        _expectedNodeIds(),
      );
      _expectTreeInvariants(result.nodes);
    });

    test('два прогона с обратным порядком ответов дают один и тот же список',
        () async {
      final first = await _generate(_ReverseL3Llm(), maxConcurrency: 4);
      final second = await _generate(_ReverseL3Llm(), maxConcurrency: 4);
      expect(
        first.nodes.map((n) => '${n.id}|${n.title}').toList(),
        second.nodes.map((n) => '${n.id}|${n.title}').toList(),
      );
    });

    test('ветви действительно идут конкурентно, но не шире лимита движка',
        () async {
      final fake = _ReverseL3Llm();
      await _generate(fake, maxConcurrency: 4);
      expect(fake.maxInFlight, greaterThan(1),
          reason: 'без параллелизма L3 выигрыша во времени не будет');
      expect(fake.maxInFlight, lessThanOrEqualTo(4),
          reason: 'движок держит не больше 4 ветвей в полёте');
    });
  });

  group('бюджет ремонта', () {
    test('валидация на каждой ветке не превращается в каскад repair', () async {
      final fake = _AlwaysInvalidLlm();
      final result = await _generate(fake);

      // Валидаций было 5 (L1+L2 + по одной на каждую из 4 ветвей), а ремонт
      // ограничен бюджетом на всё дерево.
      expect(fake.callsByKind['validate'], 5);
      expect(fake.callsByKind['repair'], 2,
          reason: 'бюджет ремонта на дерево = 2 вызова');

      // Исчерпание бюджета — не ошибка: ровно один warning, пайплайн жив.
      expect(
        result.warnings.where((w) => w.contains('Ремонт исчерпан')).length,
        1,
        reason: 'warning об исчерпании не должен дублироваться по ветвям: '
            '${result.warnings}',
      );
      expect(result.warnings.any((w) => w.contains('Ремонт исчерпан: 2')),
          isTrue,
          reason: '${result.warnings}');
      expect(result.nodes, isNotEmpty);
      _expectTreeInvariants(result.nodes);
    });
  });
}
