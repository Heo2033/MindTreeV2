import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/curriculum_engine.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/engines/learning_session_engine.dart';
import 'package:mindtree_flutter/domain/engines/review_scheduler.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Scheduler, который всегда падает — чтобы проверить детерминированный fallback.
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
    double? temperature,
  }) async {
    calls++;
    throw Exception('LLM down (test)');
  }
}

const _nodeId = 'n1~abcdef01';

KnowledgeNode _node({String details = ''}) => KnowledgeNode(
      id: _nodeId,
      topicId: 't1',
      parentId: null,
      level: 1,
      label: 'Производная',
      oneLiner: 'Предел отношения приращения функции к приращению аргумента.',
      details: details,
      relations: const [
        Relation(from: _nodeId, to: 'n2~abcdef02', type: RelationType.related, label: 'Смежный концепт'),
      ],
    );

void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late _FailingScheduler scheduler;
  late LearningSessionEngine engine;
  late LearningActivityService service;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    scheduler = _FailingScheduler();
    engine = LearningSessionEngine(
      repo: repo,
      scheduler: scheduler,
      learnerModel: LearnerModelService(repo),
      reviewScheduler: ReviewScheduler(repo),
      eventBus: EventBus(repo),
      curriculumEngine: CurriculumEngine(repo: repo, scheduler: scheduler),
      assessmentEngine: AssessmentEngine(repo: repo, scheduler: scheduler),
    );
    service = LearningActivityService(
      engine: engine,
      repo: repo,
      scheduler: scheduler,
    );
    await repo.createTopic(const Topic(id: 't1', name: 'Математический анализ'));
    await repo.createJourney('j1', 't1');
    await repo.insertNodes([_node()]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSession(String sessionId, String nodeId, {int order = 0}) async {
    final session = LearningSession(
      id: sessionId,
      journeyId: 'j1',
      topicId: 't1',
      curriculum: Curriculum(
        sessionId: sessionId,
        items: [
          CurriculumItem(
            id: 'i1',
            nodeId: nodeId,
            label: 'Производная',
            order: order,
            estimatedMinutes: 5,
          ),
        ],
      ),
    );
    await repo.createSession(session);
  }

  group('ensureActivity — fallback без LLM', () {
    test('при падении LLM строит 4 шага explain/example/recall/apply', () async {
      await seedSession('s1', _nodeId);
      final activity = await service.ensureActivity('s1');

      expect(activity.steps.map((s) => s.type), ['explain', 'example', 'recall', 'apply']);
      expect(activity.isComplete, isFalse);
      expect(scheduler.calls, 1); // одна попытка LLM, упала, дальше fallback
    });

    test('explain при пустом details не равен голому one_liner и содержит связи', () async {
      await seedSession('s1', _nodeId);
      final activity = await service.ensureActivity('s1');
      final explain = activity.steps.first;

      expect(explain.body, isNotNull);
      expect(explain.body, isNot(equals(_node().oneLiner)));
      expect(explain.body, contains('Связано с'));
    });

    test('recall-дистракторы осмысленные: не пустые и не равны правильному', () async {
      await seedSession('s1', _nodeId);
      final activity = await service.ensureActivity('s1');
      final recall = activity.steps[2];

      expect(recall.options, hasLength(4));
      expect(recall.correctIndex, inInclusiveRange(0, 3));
      final correct = recall.options![recall.correctIndex!];
      final distractors = [
        for (var i = 0; i < recall.options!.length; i++)
          if (i != recall.correctIndex) recall.options![i],
      ];
      expect(correct.toLowerCase(), contains('предел')); // правильный — из one_liner
      for (final d in distractors) {
        expect(d, isNotEmpty);
        expect(d, isNot(equals(correct))); // не дублирует правильный
      }
    });

    test('повторный ensureActivity берёт сессию из activityJson, LLM не дёргается', () async {
      await seedSession('s1', _nodeId);
      await service.ensureActivity('s1');
      final before = scheduler.calls;

      final again = await service.ensureActivity('s1');
      expect(scheduler.calls, before);
      expect(again.steps, hasLength(4));
    });
  });

  group('activity cache (prefetch)', () {
    test('prefetchActivity сохраняет шаги в кэш, ensureActivity подхватывает без LLM', () async {
      await seedSession('s1', _nodeId);
      await service.prefetchActivity('s1', _nodeId, 0);
      final cached = await repo.getCachedActivitySteps(_nodeId, 'overview');
      expect(cached, isNotNull);
      expect(cached, hasLength(4));
      expect(scheduler.calls, 1);

      // ensureActivity на свежей сессии: кэш спасает от повторного LLM-вызова.
      await seedSession('s2', _nodeId);
      final activity = await service.ensureActivity('s2');
      expect(activity.steps, hasLength(4));
      expect(scheduler.calls, 1); // не вырос: взяли из кэша
    });

    test('кэш различается по goal (overview vs deep)', () async {
      final node = _node();
      await repo.insertOrReplaceNodes([node]);
      final sessionGoal = 'overview';
      final deepSessionGoal = 'deep';

      // prefetch читает goal из сессии, поэтому готовим две сессии с разными целями.
      await seedSession('s1', _nodeId);
      await service.prefetchActivity('s1', _nodeId, 0);
      await repo.createSession(LearningSession(
        id: 's2',
        journeyId: 'j1',
        topicId: 't1',
        goal: deepSessionGoal,
        curriculum: const Curriculum(sessionId: 's2'),
      ));
      await service.prefetchActivity('s2', _nodeId, 0);

      final ov = await repo.getCachedActivitySteps(_nodeId, sessionGoal);
      final deep = await repo.getCachedActivitySteps(_nodeId, deepSessionGoal);
      expect(ov, isNotNull);
      expect(deep, isNotNull);
      expect(scheduler.calls, 2); // каждая цель — своя генерация
    });
  });
}