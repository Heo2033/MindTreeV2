import 'dart:convert';

import 'package:mindtree_flutter/domain/lib/short_ids.dart';

import '../../data/database/mindtree_repository.dart';
import '../models/models.dart';

/// Event log bus. Emits learning events into persistent storage and reads
/// recent events per topic.
class EventBus {
  final MindtreeRepository repo;

  /// Отметки начала текущей единицы работы (шаг активности либо пункт
  /// curriculum) по sessionId. Нужны, чтобы события, закрывающие единицу,
  /// несли реальную длительность: сумма durationMs по сессии = время изучения,
  /// на котором считаются ETA и аналитика.
  final Map<String, int> _unitStarts = {};

  EventBus(this.repo);

  Future<String> emit({
    required String sessionId,
    required String topicId,
    required String kind,
    String? nodeId,
    Map<String, dynamic>? payload,
    int durationMs = 0,
  }) async {
    // id события — через общий генератор коротких id, а не из timestamp.
    // На timestamp'е два события, эмитнутые в одном тике (например,
    // `activity_answer` дважды подряд или `session_started` сразу за
    // `explain`), получали одинаковый id и падали с
    // `UNIQUE constraint failed: learning_events.id` — событие терялось.
    final id = shortIdWith('ev_');
    await repo.insertEvent(LearningEvent(
      id: id,
      sessionId: sessionId,
      type: LearningEventType.fromString(kind),
      nodeId: nodeId,
      data: payload ?? const {},
      durationMs: durationMs,
    ));
    return id;
  }

  /// Запомнить момент старта единицы работы в сессии.
  void markUnitStart(String sessionId) {
    _unitStarts[sessionId] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Закрыть единицу работы: вернуть прошедшие миллисекунды и снять отметку,
  /// чтобы следующая единица стартовала с текущего момента.
  /// 0 — если отметки нет или системные часы ушли назад. Без исключений.
  int closeUnit(String sessionId) {
    final start = _unitStarts.remove(sessionId);
    if (start == null) return 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - start;
    return elapsed > 0 ? elapsed : 0;
  }

  Future<List<Map<String, dynamic>>> recent(String topicId, List<String> kinds,
      {int limit = 20}) async {
    final sessions = await repo.listSessionsForTopic(topicId);
    final ids = sessions.map((s) => s.id).toSet();
    final results = <Map<String, dynamic>>[];
    for (final id in ids) {
      final events = await repo.listEvents(id);
      for (final e in events) {
        if (!kinds.contains(e.type.wire)) continue;
        final data = _decode(e.data);
        results.add({
          'id': e.id,
          'sessionId': e.sessionId,
          'nodeId': e.nodeId,
          'type': e.type.wire,
          'timestamp': e.timestamp,
          'duration_ms': e.durationMs,
          'data_json': data,
        });
      }
    }
    results.sort((a, b) =>
        (a['timestamp'] as String).compareTo(b['timestamp'] as String));
    return results.reversed.take(limit).toList();
  }

  Map<String, dynamic> _decode(Map<String, dynamic> data) {
    final raw = data['raw'];
    if (raw is String) {
      try {
        final v = jsonDecode(raw);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    return data;
  }
}
