import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Scheduler, который всегда падает — проверяем детерминированный fallback
/// DiagnosticEngine.generate (последний движок, где LLM-вызов не был защищён).
class _FailingScheduler extends TreeScheduler {
  int calls = 0;
  _FailingScheduler()
    : super(configProvider: () => const llm_client.LLMConfig(isMock: true));

  @override
  Future<ExecuteResult<T>> execute<T>(
    String operation,
    String Function() promptFn,
    T Function(String raw) parseFn, {
    String? cacheKey,
    List<String>? nodeIds,
    String? promptVersion,
    String? model,
  }) async {
    calls++;
    throw Exception('LLM down (test)');
  }
}

KnowledgeNode _node(String id, String label, {String oneLiner = ''}) =>
    KnowledgeNode(
      id: id,
      topicId: 't1',
      parentId: null,
      level: 1,
      label: label,
      oneLiner: oneLiner.isEmpty ? 'Это $label в одном предложении.' : oneLiner,
      details: 'Подробности',
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late _FailingScheduler scheduler;
  late DiagnosticEngine engine;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    scheduler = _FailingScheduler();
    engine = DiagnosticEngine(repo: repo, scheduler: scheduler);
    await repo.createTopic(
      const Topic(id: 't1', name: 'Математический анализ'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedNodes(int count) async {
    const labels = ['Производная', 'Интеграл', 'Предел', 'Локальный экстремум'];
    await repo.insertNodes([
      for (var i = 0; i < count; i++) _node('n${i + 1}~abcdef0$i', labels[i]),
    ]);
  }

  group('DiagnosticEngine.generate — fallback без LLM', () {
    test('падение LLM не пробрасывает исключение, а даёт вопросы', () async {
      await seedNodes(4);

      final questions = await engine.generate('t1');

      expect(scheduler.calls, 1);
      expect(questions, isNotEmpty);
    });

    test('вопросов не больше шести', () async {
      await seedNodes(4);
      final questions = await engine.generate('t1');
      expect(questions.length, lessThanOrEqualTo(6));
    });

    test('correctIndex указывает на подпись своего узла', () async {
      await seedNodes(4);

      final questions = await engine.generate('t1');

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.options.length, greaterThanOrEqualTo(2));
        expect(q.correctIndex, inInclusiveRange(0, q.options.length - 1));
        // Подпись правильного варианта — ровно label его узла.
        final node = (await repo.getNode(q.nodeId))!;
        expect(q.options[q.correctIndex], node.label);
      }
    });

    test(
      'детерминирован: два прогона дают одинаковые варианты и позиции',
      () async {
        await seedNodes(4);

        final first = await engine.generate('t1');
        final second = await engine.generate('t1');

        expect(first.length, second.length);
        for (var i = 0; i < first.length; i++) {
          expect(first[i].options, second[i].options);
          expect(first[i].correctIndex, second[i].correctIndex);
          expect(first[i].nodeId, second[i].nodeId);
          expect(first[i].question, second[i].question);
        }
      },
    );

    test('правильный вариант не всегда первый — позиция плавает', () async {
      await seedNodes(4);

      final questions = await engine.generate('t1');
      final positions = questions.map((q) => q.correctIndex).toSet();

      // Сдвиг задаётся индексом узла, поэтому первый вариант выбирается не всегда.
      expect(positions.length, greaterThan(1));
    });

    test('дерево из одного узла не даёт бессмысленный вопрос', () async {
      await seedNodes(1);

      final questions = await engine.generate('t1');

      expect(questions, isEmpty);
    });

    test('пустое дерево даёт пустой список, а не исключение', () async {
      final questions = await engine.generate('t1');
      expect(questions, isEmpty);
    });

    test('в вопросе нет жаргона: используется one_liner узла', () async {
      await seedNodes(2);

      final questions = await engine.generate('t1');

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.question, startsWith('Что означает понятие'));
        expect(q.explanation, isNotEmpty);
        expect(q.explanation.length, lessThanOrEqualTo(300));
      }
    });

    test('в вариантах нет повторов, а правильный — label узла', () async {
      await seedNodes(4);

      final questions = await engine.generate('t1');

      for (final q in questions) {
        expect(q.options.toSet().length, q.options.length);
        final node = (await repo.getNode(q.nodeId))!;
        expect(q.options[q.correctIndex], node.label);
      }
    });

    test(
      'одинаковые подписи не дают вопрос с единственным вариантом',
      () async {
        // Отличить варианты нечем → узлы пропускаются, вместо вопроса с одним
        // вариантом ответа.
        await repo.insertNodes([
          _node('n1~aaaa0001', 'Понятие', oneLiner: 'Раз определение X.'),
          _node(
            'n2~aaaa0002',
            'Понятие',
            oneLiner: 'Раз другое определение X.',
          ),
        ]);

        final questions = await engine.generate('t1');

        expect(questions, isEmpty);
      },
    );
  });
}
