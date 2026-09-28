// Регрессии инварианта `one_liner <= 120` (AGENTS.md).
//
// Закрывает дефект, найденный на живом LLM: контентный вызов возвращал
// one_liner на 121–302 символа, и проверка качества probe падала `fail`.
// Решение (по решению пользователя): НЕ обрезать молча, а ПЕРЕСПРАШИВАТЬ
// модель (fast-тир, операция `oneline-rewrite`), с детерминированной
// триммацией как запасным вариантом (fallback обязателен по AGENTS.md).

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart'
    show oneLinerMaxChars;
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/mastery.dart';
import 'package:mindtree_flutter/domain/models/primitives.dart';
import 'package:mindtree_flutter/domain/models/topic.dart';

import '../../tool/probe/fake_llm.dart';
import '../../tool/probe/tree_mapper.dart';

const String _query = 'диффузионные модели';
const String _fixedCreatedAt = '1970-01-01T00:00:00.000Z';

/// Заведомо длинный one_liner (длиннее 120 символов).
final String _longOneLiner =
    'Диффузионные модели — это класс генеративных моделей машинного обучения, '
    'которые учатся восстанавливать данные из шума, постепенно обращая процесс '
    'зашумления: сначала портят картинку, потом обучаются её восстанавливать, '
    'что позволяет генерировать новые изображения и аудио на основе обучающей выборки.';

/// Короткий вариант, который должен вернуть переспрос.
const String _rewritten = 'Суть: генерация данных из шума шаг за шагом.';

/// Как ведёт себя переспрос (`oneline-rewrite`).
enum RewriteMode {
  /// Отдаёт короткий вариант — нормальный переспрос.
  ok,

  /// Возвращает ещё длиннее — движок должен оттримить детерминированно.
  long,

  /// Падает — движок должен оттримить детерминированно.
  error,
}

class _OnelineLlm extends FakeLlm {
  _OnelineLlm({this.mode = RewriteMode.ok});

  final RewriteMode mode;

  @override
  String respondTo(PromptKind kind, String prompt) {
    if (kind == PromptKind.content) {
      return jsonEncode({
        'one_liner': _longOneLiner,
        'details': 'Подробное описание понятия, не важно для теста.',
        'analogy': 'Аналогия: восстановление порванной картинки.',
        'relations': <Map<String, dynamic>>[],
        'sources': <String>[],
      });
    }
    if (kind == PromptKind.expand) {
      // Раздуваем canonical_definition у каждого ребёнка: структура-шов
      // должен переспросить и сохранить короткий one_liner.
      final Map<String, dynamic> data =
          jsonDecode(super.respondTo(kind, prompt)) as Map<String, dynamic>;
      final base = (data['nodes'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic item in base) {
        if (item is! Map<String, dynamic>) continue;
        final children = item['children'];
        if (children is! List) continue;
        for (final dynamic child in children) {
          if (child is Map<String, dynamic>) {
            child['canonical_definition'] = _longOneLiner;
          }
        }
      }
      return jsonEncode({'nodes': base});
    }
    if (kind == PromptKind.onelineRewrite) {
      switch (mode) {
        case RewriteMode.ok:
          return jsonEncode({'one_liner': _rewritten});
        case RewriteMode.long:
          return jsonEncode({'one_liner': _longOneLiner});
        case RewriteMode.error:
          throw StateError('переспрос временно недоступен');
      }
    }
    return super.respondTo(kind, prompt);
  }
}

/// Строит дерево и заполняет контент всех узлов (content-шов).
Future<List<KnowledgeNode>> _runTreeAndContent(FakeLlm fake) async {
  final db = MindtreeDb(NativeDatabase.memory());
  final engines = buildEngines(
    repo: MindtreeRepository(db),
    configProvider: () =>
        const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
    schedulerConfig: const SchedulerConfig(
      maxRPM: 100000,
      maxRPD: 100000,
      maxConcurrency: 1,
      maxRetries: 0,
    ),
    llmCall: (cfg, prompt, {model, temperature, seed}) async =>
        fake.invoke(cfg, prompt, model: model, temperature: temperature),
  );
  try {
    final topic = await engines.repo.createTopic(Topic(
      id: 't_oneline_test',
      name: _query,
      goal: LearningGoal.fromString('overview'),
      targetLevel: MasteryLevel.fromString('intermediate'),
      timeBudgetMinutes: 30,
      createdAt: _fixedCreatedAt,
    ));
    final build = await engines.graph.generate(
      _query,
      goal: 'overview',
      level: 'intermediate',
      timeBudgetMinutes: 30,
    );
    await engines.repo.insertNodes(
      draftsToNodes(scopeNodeIds(build.nodes, topic.id), topic.id),
    );
    final skeleton = await engines.repo.listNodes(topic.id);
    for (final n in sortNodesForReport(skeleton)) {
      try {
        await engines.graph.generateNodeContentFromDb(topic.id, n.id);
      } catch (_) {
        // Контент в этом тесте не важен; важен one_liner после переспроса.
      }
    }
    return await engines.repo.listNodes(topic.id);
  } finally {
    await db.close();
  }
}

void main() {
  test('короткий контент не запускает переспрос', () async {
    final fake = FakeLlm();
    final loaded = await _runTreeAndContent(fake);
    expect(loaded.map((n) => n.oneLiner).where((o) => o.trim().isNotEmpty),
        isNotEmpty);
    for (final n in loaded) {
      expect(n.oneLiner.trim().length, lessThanOrEqualTo(oneLinerMaxChars));
    }
    expect(fake.callsByKind['oneline-rewrite'], isNull);
  });

  test('content-шов: длинный one_liner → переспрос → короткий', () async {
    final fake = _OnelineLlm(mode: RewriteMode.ok);
    final loaded = await _runTreeAndContent(fake);
    expect(loaded, isNotEmpty);
    for (final n in loaded) {
      expect(
        n.oneLiner,
        _rewritten,
        reason: 'one_liner узла «${n.label}» должен прийти из переспроса',
      );
    }
    expect(fake.callsByKind['oneline-rewrite'], greaterThan(0));
  });

  test('fallback: переспрос вернул длинный текст → детерминированная триммация',
      () async {
    final fake = _OnelineLlm(mode: RewriteMode.long);
    final loaded = await _runTreeAndContent(fake);
    expect(loaded, isNotEmpty);
    for (final n in loaded) {
      expect(n.oneLiner.trim(), isNot(equals(_longOneLiner)));
      expect(n.oneLiner.trim().length, lessThanOrEqualTo(oneLinerMaxChars));
    }
  });

  test('fallback: сбой переспроса не роняет сценарий → триммация', () async {
    final fake = _OnelineLlm(mode: RewriteMode.error);
    final loaded = await _runTreeAndContent(fake);
    expect(loaded, isNotEmpty);
    for (final n in loaded) {
      expect(n.oneLiner.trim(), isNot(equals(_longOneLiner)));
      expect(n.oneLiner.trim().length, lessThanOrEqualTo(oneLinerMaxChars));
    }
  });

  test('expand-шов: длинный canonical_definition → короткий one_liner', () async {
    final db = MindtreeDb(NativeDatabase.memory());
    final fake = _OnelineLlm(mode: RewriteMode.ok);
    final engines = buildEngines(
      repo: MindtreeRepository(db),
      configProvider: () =>
          const LLMConfig(isMock: true, temperature: 0, numCtx: 16384),
      schedulerConfig: const SchedulerConfig(
        maxRPM: 100000,
        maxRPD: 100000,
        maxConcurrency: 1,
        maxRetries: 0,
      ),
      llmCall: (cfg, prompt, {model, temperature, seed}) async =>
          fake.invoke(cfg, prompt, model: model, temperature: temperature),
    );
    try {
      final topic = await engines.repo.createTopic(Topic(
        id: 't_oneline_expand',
        name: _query,
        goal: LearningGoal.fromString('overview'),
        targetLevel: MasteryLevel.fromString('intermediate'),
        timeBudgetMinutes: 30,
        createdAt: _fixedCreatedAt,
      ));
      final build = await engines.graph.generate(
        _query,
        goal: 'overview',
        // Уровень beginner: L3 не генерируется на этапе generate, поэтому
        // expandNodeFromDb реально создаёт детей (и его шов переспроса).
        level: 'beginner',
        timeBudgetMinutes: 30,
      );
      await engines.repo.insertNodes(
        draftsToNodes(scopeNodeIds(build.nodes, topic.id), topic.id),
      );
      final l2 = (await engines.repo.listNodes(topic.id))
          .where((n) => n.level == 2)
          .toList();
      expect(l2, isNotEmpty);
      for (final node in l2) {
        await engines.graph.expandNodeFromDb(topic.id, node.id);
      }
      final withChildren = await engines.repo.listNodes(topic.id);
      final children = withChildren.where((n) => n.level == 3).toList();
      expect(children, isNotEmpty);
      for (final c in children) {
        expect(
          c.oneLiner,
          _rewritten,
          reason: 'one_liner ребёнка «${c.label}» должен прийти из переспроса',
        );
      }
      expect(fake.callsByKind['oneline-rewrite'], greaterThan(0));
    } finally {
      await db.close();
    }
  });
}