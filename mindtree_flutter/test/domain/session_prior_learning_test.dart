// Регресс «новая сессия начинается с нуля»: до фикса `create` вообще не читал
// накопленный прогресс — каждый план строился так, будто ученик видит тему
// впервые: пройденные концепты предлагались снова, due-повторения и слабые
// понятия выпадали из порядка до тех пор, пока их не поднял nextStep.
//
// Контракт фикса:
//   • первая сессия (пустая модель) — план байт-в-байт, что и раньше;
//   • повторная — due → слабые → новые, прочно изученное не включается;
//   • узкий бюджет: due-понятие возвращается в план и стоит первым;
//   • всё изучено → отказ ДО создания строки сессии (ее ловит UI);
//   • `includeLearned: true` — явный запрос «учить заново» = старое поведение.
//
// Пороги: `kMasteredMasteryScore` (0.7) для «прочно», `getWeakConcepts` (<0.6)
// для слабых. LLM — детерминированный `FakeLlm` (без сети и ключей).
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

import '../../tool/probe/fake_llm.dart';

const _topicId = 't1';
const _scope = '1a2b3c4d';
const _rootId = 'n1_topic~$_scope';

KnowledgeNode _root() => KnowledgeNode(
      id: _rootId,
      topicId: _topicId,
      parentId: null,
      level: 1,
      label: 'Теорема остановки',
      oneLiner: 'Обзорная тема раздела.',
      details: 'Подробности корня.',
    );

KnowledgeNode _child(int i) => KnowledgeNode(
      id: 'n2_topic_$i~$_scope',
      topicId: _topicId,
      parentId: _rootId,
      level: 2,
      label: 'Понятие $i',
      oneLiner: 'Суть понятия $i в одном предложении.',
      details: 'Подробности понятия $i.',
      estimatedTimeMinutes: 5,
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late MindtreeEngines engines;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    final fake = FakeLlm();
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
      llmCall: (cfg, prompt, {model, temperature, seed}) async =>
          fake.invoke(cfg, prompt, model: model, temperature: temperature),
    );
    await repo.createTopic(const Topic(id: _topicId, name: 'Теорема остановки'));
    await repo.insertNodes([_root(), _child(1), _child(2), _child(3)]);
  });

  tearDown(() async {
    await db.close();
  });

  CreateSessionInput input({int budget = 60, bool includeLearned = false}) =>
      CreateSessionInput(
        topicId: _topicId,
        goal: 'понимание',
        timeBudgetMinutes: budget,
        includeLearned: includeLearned,
      );

  List<String> nodeIds(LearningSession s) =>
      [for (final i in s.curriculum.items) i.nodeId];

  int totalOf(LearningSession s) =>
      s.curriculum.items.fold<int>(0, (sum, i) => sum + i.estimatedMinutes);

  /// Два свидетельства по всем измерениям: 0 → 0.5 → 0.75 (≥ 0.7 — прочно).
  Future<void> strongEvidence(String nodeId) async {
    for (var i = 0; i < 2; i++) {
      await engines.learnerModel.recordEvidence(_topicId, nodeId, const {
        dimUnderstanding: 1.0,
        dimRecall: 1.0,
        dimApplication: 1.0,
        dimTransfer: 1.0,
      });
    }
  }

  /// Прочно освоенный концепт: пройденный пункт плана + мастерство 0.75.
  Future<void> completeSolid(String sessionId, CurriculumItem item) async {
    await engines.session
        .markItemCompleted(sessionId, item.id, nodeId: item.nodeId);
    await strongEvidence(item.nodeId);
  }

  /// Слабый концепт: одно свидетельство → 0.5 (< 0.6), без SRS (не due).
  Future<void> makeWeak(String nodeId) =>
      engines.learnerModel.recordEvidence(_topicId, nodeId, const {
        dimUnderstanding: 1.0,
        dimRecall: 1.0,
        dimApplication: 1.0,
        dimTransfer: 1.0,
      });

  /// Due-повторение: интервал истёк. Мастерство поднимаем до 0.75, чтобы
  /// концепт НЕ был слабым — проверяется именно приоритет due.
  Future<void> makeDue(String nodeId) async {
    await engines.learnerModel.updateSrs(
        _topicId, nodeId, (interval: 1, ease: 2.5, dueAt: '2020-01-01T00:00:00.000'));
    await strongEvidence(nodeId);
  }

  group('Первая сессия: пустая модель — план как раньше', () {
    test('собирает все узлы дерева, все pending, порядок непрерывен', () async {
      final s = await engines.session.create(input());

      expect(nodeIds(s).toSet(),
          {_rootId, _child(1).id, _child(2).id, _child(3).id});
      expect(s.curriculum.items.first.nodeId, _rootId, reason: 'корень первым');
      expect(
          [for (final i in s.curriculum.items) i.status],
          List.filled(4, CurriculumItemStatus.pending));
      expect([for (final i in s.curriculum.items) i.order], [1, 2, 3, 4]);
      expect(s.curriculum.totalEstimatedMinutes, totalOf(s));
    });

    test('повторное создание без обучения даёт идентичный план', () async {
      final first = await engines.session.create(input());
      final second = await engines.session.create(input());

      expect(nodeIds(second), nodeIds(first));
      expect(
          [for (final i in second.curriculum.items) i.estimatedMinutes],
          [for (final i in first.curriculum.items) i.estimatedMinutes]);
      expect(second.curriculum.totalEstimatedMinutes,
          first.curriculum.totalEstimatedMinutes);
    });
  });

  group('Повторная сессия продолжает прогресс', () {
    test('due → слабые → новые, прочно изученное пропущено', () async {
      final first = await engines.session.create(input());
      await completeSolid(
          first.id,
          first.curriculum.items
              .firstWhere((i) => i.nodeId == _child(1).id));
      await makeWeak(_child(2).id);
      await makeDue(_child(3).id);

      final second = await engines.session.create(input());

      expect(
        nodeIds(second),
        [_child(3).id, _child(2).id, _rootId],
        reason: 'due первым, слабое вторым, новое последним',
      );
      expect(nodeIds(second), isNot(contains(_child(1).id)),
          reason: 'прочно изученный концепт в план не возвращается');
      expect([for (final i in second.curriculum.items) i.order], [1, 2, 3]);
      expect(second.curriculum.totalEstimatedMinutes, totalOf(second));
    });

    test('несколько сессий подряд: изученное не дублируется', () async {
      final first = await engines.session.create(input());
      await completeSolid(
          first.id,
          first.curriculum.items
              .firstWhere((i) => i.nodeId == _child(1).id));

      final second = await engines.session.create(input());
      final third = await engines.session.create(input());

      expect(nodeIds(second), isNot(contains(_child(1).id)));
      expect(nodeIds(third), isNot(contains(_child(1).id)));
      expect(nodeIds(third).toSet(),
          {_rootId, _child(2).id, _child(3).id});
    });

    test('прочно изученное, но просроченное повторение остаётся в плане',
        () async {
      final first = await engines.session.create(input());
      await completeSolid(
          first.id,
          first.curriculum.items
              .firstWhere((i) => i.nodeId == _child(1).id));
      // Мастерство высокое, но SRS требует проверки — концепт НЕ solid.
      await engines.learnerModel.updateSrs(
          _topicId,
          _child(1).id,
          (interval: 1, ease: 2.5, dueAt: '2020-01-01T00:00:00.000'));

      final second = await engines.session.create(input());

      expect(second.curriculum.items.first.nodeId, _child(1).id,
          reason: 'due-повернение важнее мастерства');
    });

    test('узкий бюджет: due-понятие возвращается в план и идёт первым',
        () async {
      final plain = await engines.session.create(input(budget: 20));
      expect(nodeIds(plain), isNot(contains(_child(3).id)),
          reason: 'без повторения бюджет отрезает понятие 3');

      await makeDue(_child(3).id);
      final withDue = await engines.session.create(input(budget: 20));

      expect(withDue.curriculum.items.first.nodeId, _child(3).id);
      expect(withDue.curriculum.items.length, lessThan(4));
      expect(totalOf(withDue), lessThanOrEqualTo(20));
      expect(withDue.curriculum.totalEstimatedMinutes, totalOf(withDue));
    });
  });

  group('Отказ и явный запрос «учить заново»', () {
    test('всё изучено → отказ, сессия не создаётся', () async {
      final first = await engines.session.create(input());
      for (final item in first.curriculum.items) {
        await completeSolid(first.id, item);
      }

      await expectLater(
        engines.session.create(input()),
        throwsA(predicate(
            (e) => '$e'.contains('Все концепции по теме уже изучены'))),
      );

      final sessions = await repo.listSessionsForTopic(_topicId);
      expect(sessions, hasLength(1),
          reason: 'строка сессии не должна появиться после отказа');
      expect(await _journeyRows(db), 1, reason: 'journey не плодится');
    });

    test('includeLearned: true — явный запрос игнорирует прогресс', () async {
      final first = await engines.session.create(input());
      for (final item in first.curriculum.items) {
        await completeSolid(first.id, item);
      }

      final s = await engines.session.create(input(includeLearned: true));

      expect(nodeIds(s), nodeIds(first), reason: 'старое поведение: весь план');
      expect([for (final i in s.curriculum.items) i.order],
          [for (final i in first.curriculum.items) i.order]);
    });
  });
}

/// Число строк `learning_journeys` на тему — отказ не должен их плодить.
Future<int> _journeyRows(MindtreeDb db, [String topicId = _topicId]) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM learning_journeys WHERE topic_id = ?',
        variables: [Variable<String>(topicId)],
      )
      .getSingle();
  return row.read<int>('c');
}
