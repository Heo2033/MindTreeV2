import 'dart:convert';

import '../../data/database/mindtree_repository.dart';
import '../models/models.dart';

/// Event log bus. Emits learning events into persistent storage and reads
/// recent events per topic.
class EventBus {
  final MindtreeRepository repo;

  EventBus(this.repo);

  Future<String> emit({
    required String sessionId,
    required String topicId,
    required String kind,
    String? nodeId,
    Map<String, dynamic>? payload,
    int durationMs = 0,
  }) async {
    return repo.insertEvent(LearningEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      type: LearningEventType.fromString(kind),
      nodeId: nodeId,
      data: payload ?? const {},
      durationMs: durationMs,
    ));
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
