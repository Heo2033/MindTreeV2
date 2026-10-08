// Регресс «сессия не закрывается»: до фикса итоговый тест оценивал ответы,
// но ни одно событие не переводило `LearningSession.status` в `completed` —
// строка оставалась active вечно: карточка «Продолжить» предлагала закрытую
// сессию, а витрины не считали её завершённой (analytics читает именно
// `SessionStatus.completed`).
//
// Контракт фикса (`AssessmentEngine.finalize`):
//   • type == final_  → сессия закрывается: `completed` + `completedAt`;
//   • quiz            → сессию НЕ закрывает (quiz — не финал);
//   • повторный finalize идемпотентен: `completedAt` не двигается;
//   • после закрытия `nextStep` работает (строка сессии существует) и
//     рекомендует итоговый тест;
//   • закрытая сессия больше не предлагается к продолжению.
//
// LLM — детерминированный `FakeLlm`, БД — `NativeDatabase.memory()`.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/assessment_engine.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';
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

const _assessmentItems = [
  AssessmentItem(
    nodeId: _rootId,
    label: 'Теорема остановки',
    oneLiner: 'Обзорная тема раздела.',
  ),
  AssessmentItem(
    nodeId: 'n2_topic_1~$_scope',
    label: 'Понятие 1',
    oneLiner: 'Суть понятия 1 в одном предложении.',
  ),
];

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

  CreateSessionInput input() => const CreateSessionInput(
        topicId: _topicId,
        goal: 'понимание',
        timeBudgetMinutes: 60,
      );

  /// Сессия + все пункты плана закрыты как пройденные.
  Future<LearningSession> sessionWithAllItemsCompleted() async {
    final s = await engines.session.create(input());
    for (final item in s.curriculum.items) {
      await engines.session.markItemCompleted(s.id, item.id,
          nodeId: item.nodeId, quality: 'correct');
    }
    return await engines.session.getSession(s.id) ?? s;
  }

  group('Итоговый тест закрывает сессию', () {
    test('finalize(type final_) → completed + completedAt', () async {
      final s = await engines.session.create(input());
      final asmt = await engines.assessment.generate(
        s.id,
        _topicId,
        _assessmentItems,
        type: AssessmentType.final_,
      );

      await engines.assessment.finalize(asmt.id, 0.75);

      final after = await repo.getSession(s.id);
      expect(after, isNotNull);
      expect(after!.status, SessionStatus.completed);
      expect(after.completedAt, isNotNull);
      expect(DateTime.tryParse(after.completedAt!), isNotNull,
          reason: 'completedAt обязан быть валидной ISO-меткой');
    });

    test('quiz-оценка сессию не закрывает', () async {
      final s = await engines.session.create(input());
      final asmt = await engines.assessment.generate(
        s.id,
        _topicId,
        _assessmentItems,
        type: AssessmentType.quiz,
      );

      await engines.assessment.finalize(asmt.id, 1.0);

      final after = await repo.getSession(s.id);
      expect(after!.status, SessionStatus.active);
      expect(after.completedAt, isNull);
    });

    test('повторный finalize не двигает completedAt', () async {
      final s = await engines.session.create(input());
      final asmt = await engines.assessment.generate(
        s.id,
        _topicId,
        _assessmentItems,
        type: AssessmentType.final_,
      );
      await engines.assessment.finalize(asmt.id, 1.0);
      final closed = await repo.getSession(s.id);
      expect(closed!.status, SessionStatus.completed);

      // Отматываем метку назад: если бы finalize перезаписывал её, тест упал.
      await repo
          .updateSession(closed.copyWith(completedAt: '2024-01-01T00:00:00.000'));
      await engines.assessment.finalize(asmt.id, 1.0);

      final again = await repo.getSession(s.id);
      expect(again!.completedAt, '2024-01-01T00:00:00.000',
          reason: 'идемпотентность: готовое закрытие не перезаписывается');
      expect(again.status, SessionStatus.completed);
    });

    test('finalize с несуществующей сессией не падает', () async {
      final asmt = await engines.assessment.generate(
        'session_missing',
        _topicId,
        _assessmentItems,
        type: AssessmentType.final_,
      );

      await expectLater(engines.assessment.finalize(asmt.id, 0.5),
          completes);
    });
  });

  group('Поведение после закрытия', () {
    test('nextStep не падает (строка сессии существует) и ведёт к финалу',
        () async {
      final s = await sessionWithAllItemsCompleted();
      final asmt = await engines.assessment.generate(
        s.id,
        _topicId,
        _assessmentItems,
        type: AssessmentType.final_,
      );
      await engines.assessment.finalize(asmt.id, 1.0);

      final decision = await engines.adaptive.nextStep(s.id);

      expect(decision.recommendedAction, RecommendedAction.finalAssessment);
      expect(decision.eta, isNotNull);
    });

    test('закрытая сессия больше не предлагается к продолжению', () async {
      final s = await engines.session.create(input());
      expect(await engines.session.latestUnfinishedSessionForTopic(_topicId),
          isNotNull, reason: 'до закрытия сессия незавершённая');

      final asmt = await engines.assessment.generate(
        s.id,
        _topicId,
        _assessmentItems,
        type: AssessmentType.final_,
      );
      await engines.assessment.finalize(asmt.id, 1.0);

      expect(await engines.session.latestUnfinishedSessionForTopic(_topicId),
          isNull, reason: 'после закрытия «Продолжить» нечего предлагать');
    });
  });
}
