import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/domain/engines/event_bus.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

void main() {
  group('LearningEventType — контракт wire-строк', () {
    test('fromString(t.wire) == t для всех значений', () {
      for (final t in LearningEventType.values) {
        expect(
          LearningEventType.fromString(t.wire),
          t,
          reason: 'wire-строка «${t.wire}» не разбирается обратно в $t',
        );
      }
    });

    test('kinds покрывает все значения и уникален', () {
      expect(
        LearningEventType.kinds.toSet(),
        hasLength(LearningEventType.values.length),
      );
      expect(
        LearningEventType.kinds,
        containsAll(LearningEventType.values.map((e) => e.wire)),
      );
    });

    test('события жизненного цикла не схлопываются в explain', () {
      // Регрессия: раньше эти пять видов молча становились `explain`, и
      // `recent(topic, ['explain'])` возвращал смесь разных событий.
      const lifecycle = [
        'session_started',
        'item_completed',
        'activity_started',
        'activity_answer',
        'activity_step_done',
      ];
      for (final kind in lifecycle) {
        expect(
          LearningEventType.fromString(kind),
          isNot(LearningEventType.explain),
          reason: '«$kind» не должен превращаться в explain',
        );
      }
      expect(LearningEventType.kinds, containsAll(lifecycle));
    });

    test('неизвестная строка — безопасный fallback на explain', () {
      expect(
        LearningEventType.fromString('выдумка'),
        LearningEventType.explain,
      );
      expect(LearningEventType.fromString(null), LearningEventType.explain);
    });

    test('LearningEvent.toJson → fromJson не теряет тип', () {
      for (final t in LearningEventType.values) {
        final event = LearningEvent(id: 'e1', sessionId: 's1', type: t);
        expect(LearningEvent.fromJson(event.toJson()).type, t);
      }
    });
  });

  group('EventBus — вид события в БД соответствует kind', () {
    late MindtreeDb db;
    late EventBus bus;
    const sessionId = 'sess_1';

    setUp(() async {
      db = MindtreeDb(NativeDatabase.memory());
      final repo = MindtreeRepository(db);
      // Сессия нужна как внешний ключ для learning_events.
      await repo.insertTopicWithNodes(
        const Topic(id: 'topic_1', name: 'Тема'),
        const [],
      );
      await repo.createSession(
        const LearningSession(
          id: sessionId,
          journeyId: 'j1',
          topicId: 'topic_1',
          timeBudgetMinutes: 60,
          startedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      bus = EventBus(repo);
    });

    tearDown(() async => db.close());

    test('все эмиты движков пишутся в type без потерь', () async {
      // Ровно те kind, которые реально эмитят движки.
      const emitted = [
        'session_started',
        'explain',
        'item_completed',
        'assessment',
        'activity_started',
        'activity_answer',
        'activity_step_done',
      ];
      for (final kind in emitted) {
        await bus.emit(sessionId: sessionId, topicId: 'topic_1', kind: kind);
      }

      final stored = await bus.repo.listEvents(sessionId);
      expect(stored.map((e) => e.type.wire).toSet(), emitted.toSet());
    });

    test('несколько событий подряд получают разные id', () async {
      // Регрессия: id строился из `microsecondsSinceEpoch`, и события,
      // эмитнутые в одном тике, падали с UNIQUE constraint failed.
      final ids = <String>{};
      for (var i = 0; i < 50; i++) {
        ids.add(
          await bus.emit(
            sessionId: sessionId,
            topicId: 'topic_1',
            kind: 'activity_answer',
          ),
        );
      }
      expect(ids, hasLength(50));
      expect((await bus.repo.listEvents(sessionId)), hasLength(50));
    });

    test('recent фильтрует по виду события и не смешивает', () async {
      for (final kind in ['explain', 'session_started', 'activity_answer']) {
        await bus.emit(sessionId: sessionId, topicId: 'topic_1', kind: kind);
      }

      final explained = await bus.recent('topic_1', ['explain']);
      expect(explained.map((e) => e['type']).toList(), ['explain']);

      final started = await bus.recent('topic_1', ['session_started']);
      expect(started.map((e) => e['type']).toList(), ['session_started']);

      // Раньше второй запрос вернул бы пусто, а первый — все три события.
      final answered = await bus.recent('topic_1', ['activity_answer']);
      expect(answered.map((e) => e['type']).toList(), ['activity_answer']);
    });
  });
}
