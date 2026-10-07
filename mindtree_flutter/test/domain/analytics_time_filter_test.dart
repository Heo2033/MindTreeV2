import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/analytics_service.dart';
import 'package:mindtree_flutter/domain/engines/learner_model_service.dart';
import 'package:mindtree_flutter/domain/lib/time_plausibility.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Learning Gain / Time обязан считаться только из достоверных замеров.
///
/// Боевой дефект: в `duration_ms` событий и в `assessment_attempts.time_spent_ms`
/// попадало абсолютное время (незаведённый старт таймера → `now - 0` ≈ 1.8e12
/// мс ≈ 20 суток). Одна такая строка раздувала `studyMinutes` до десятков
/// миллионов и обнуляла `learningGainPerMinute` — ключевая метрика продукта
/// становилась бессмысленной. Тул ревью такие записи помечает fail'ом
/// (`kImplausibleAnswerMs`), но метрика не должна полагаться на то, что
/// кто-то прогонит отчёт: фильтрация живёт в самом сервисе.
void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late AnalyticsService service;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    service = AnalyticsService(repo: repo, learnerModel: LearnerModelService(repo));
    await repo.createTopic(const Topic(id: 't1', name: 'Математический анализ'));
    await repo.createSession(const LearningSession(
      id: 's1',
      journeyId: 'j1',
      topicId: 't1',
      goal: 'overview',
      startedAt: '2026-01-01T00:00:00.000',
    ));
  });

  tearDown(() => db.close());

  test('битая длительность не попадает в studyMinutes и Learning Gain / Time',
      () async {
    // Час достоверной работы...
    await repo.insertEvent(const LearningEvent(
      id: 'ev_ok',
      sessionId: 's1',
      type: LearningEventType.itemCompleted,
      durationMs: 60 * 60 * 1000,
    ));
    // ...плюс запись со сломанным таймером: в длительность утекло
    // абсолютное время (epoch-мс).
    await repo.insertEvent(const LearningEvent(
      id: 'ev_broken',
      sessionId: 's1',
      type: LearningEventType.activityAnswer,
      durationMs: 1753128000000,
    ));

    // Прирост на один уровень: стартовый basic_understanding → текущий
    // solid_understanding.
    final learner = LearnerModelService(repo);
    await learner.raiseOverallLevel(
      't1',
      MasteryLevel.basicUnderstanding,
      asInitial: true,
    );
    await learner.raiseOverallLevel('t1', MasteryLevel.solidUnderstanding);

    final metrics = await service.topicMetrics('t1');
    expect(metrics, isNotNull);

    // Только достоверный час: до фильтрации здесь было бы ~29 млн минут.
    expect(metrics!.studyMinutes, 60);
    expect(metrics.learningGain, 1.0);
    // 1 уровень за 60 минут = 1 уровень в час; без фильтрации темп
    // обнулялся бы (деление на «сутки»).
    expect(metrics.learningGainPerMinute, closeTo(1.0, 1e-9));
  });

  test('все замеры неправдоподобны — время ограничено эвристикой сессии, '
      'а не битой суммой', () async {
    await repo.insertEvent(const LearningEvent(
      id: 'ev_broken',
      sessionId: 's1',
      type: LearningEventType.activityAnswer,
      durationMs: kImplausibleDurationMs + 1,
    ));

    final metrics = await service.topicMetrics('t1');
    expect(metrics, isNotNull);
    // Фильтр выбросил единственный замер → включается прежняя эвристика
    // «время жизни сессии», ограниченная часом на сессию. До фильтрации
    // studyMinutes был бы ~2 суток.
    expect(metrics!.studyMinutes, lessThanOrEqualTo(60));
    expect(metrics.studyMinutes, greaterThanOrEqualTo(0));
  });
}
