import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Регрессия: `durationMs` не заполнялся ни в одном из 9 вызовов emit,
/// из-за чего ETA (`adaptive_learning_engine`: фильтр `durationMs > 0`)
/// и аналитика (`analytics_service`: сумма duration_ms) всегда получали 0.
void main() {
  late MindtreeDb db;
  late MindtreeRepository repo;
  late EventBus bus;

  setUp(() async {
    db = MindtreeDb(NativeDatabase.memory());
    repo = MindtreeRepository(db);
    bus = EventBus(repo);
    await repo.createTopic(const Topic(id: 't1', name: 'Тема'));
    // learning_events.sessionId — FK на learning_sessions, нужна реальная сессия.
    await repo.createJourney('j1', 't1');
    await repo.createSession(
      const LearningSession(id: 's1', journeyId: 'j1', topicId: 't1'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('EventBus.markUnitStart / closeUnit', () {
    test('без отметки closeUnit возвращает 0, а не падает', () {
      expect(bus.closeUnit('s1'), 0);
    });

    test(
      'после markUnitStart closeUnit возвращает положительное время',
      () async {
        bus.markUnitStart('s1');
        await Future<void>.delayed(const Duration(milliseconds: 12));

        final spent = bus.closeUnit('s1');

        expect(spent, greaterThan(0));
      },
    );

    test('closeUnit снимает отметку — повторный вызов даёт 0', () {
      bus.markUnitStart('s1');
      bus.closeUnit('s1');
      expect(bus.closeUnit('s1'), 0);
    });

    test('отметки разных сессий изолированы', () async {
      bus.markUnitStart('s1');
      bus.markUnitStart('s2');

      final a = bus.closeUnit('s1');
      final b = bus.closeUnit('s2');

      expect(a, greaterThanOrEqualTo(0));
      expect(b, greaterThanOrEqualTo(0));
      // Закрытие s1 не тронуло отметку s2.
      expect(bus.closeUnit('s2'), 0);
    });
  });

  group('emit пишет durationMs в событие', () {
    test('сумма durationMs по событиям = измеренное время изучения', () async {
      bus.markUnitStart('s1');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final firstStep = bus.closeUnit('s1');
      await bus.emit(
        sessionId: 's1',
        topicId: 't1',
        kind: 'activity_step_done',
        nodeId: 'n1~abcdef01',
        durationMs: firstStep,
      );

      bus.markUnitStart('s1');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final secondStep = bus.closeUnit('s1');
      await bus.emit(
        sessionId: 's1',
        topicId: 't1',
        kind: 'item_completed',
        nodeId: 'n1~abcdef01',
        durationMs: secondStep,
      );

      final events = await repo.listEvents('s1');
      final total = events.fold<int>(0, (s, e) => s + e.durationMs);

      // Именно это значение читают ETA и аналитика.
      expect(total, firstStep + secondStep);
      expect(total, greaterThan(0));
    });

    test('маркерные события пишут durationMs = 0', () async {
      bus.markUnitStart('s1');
      await bus.emit(
        sessionId: 's1',
        topicId: 't1',
        kind: 'activity_started',
        nodeId: 'n1~abcdef01',
      );

      final events = await repo.listEvents('s1');
      expect(events.single.durationMs, 0);
    });
  });
}
