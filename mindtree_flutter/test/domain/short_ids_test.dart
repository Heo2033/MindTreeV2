import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/lib/short_ids.dart';

void main() {
  group('shortId', () {
    test('уникальность при N вызовах в один тик (баг H1: коллизии ci_/ms_)', () {
      // Ранее локальные _shortId() в один ms-тик давали одинаковые суффиксы:
      // счётчик в хелпере гарантирует попарное различие даже в одном тике.
      final ids = List.generate(2000, (_) => shortId());
      expect(ids.toSet().length, ids.length,
          reason: 'должны быть попарно различны, найдено дублей: '
              '${ids.length - ids.toSet().length}');
    });

    test('формат: ровно 8 символов, алфавит base36 (0-9a-z)', () {
      final re = RegExp(r'^[0-9a-z]{8}$');
      for (var i = 0; i < 300; i++) {
        final id = shortId();
        expect(id.length, 8, reason: 'сгенерирован «$id»');
        expect(id, matches(re), reason: 'сгенерирован «$id»');
      }
    });

    test('shortIdWith сохраняет префиксы движков', () {
      const prefixes = [
        'ci_', // curriculum items (H1: markItemCompleted помечал все пункты)
        'curriculum_', // curriculum sessionId
        'ms_', // milestones (H1: дубликат PK в insertMilestones)
        'journey_', 'session_', 'assess_', // learning_session_engine (H1)
        'asmt_', 'att_', 'a_', // assessment_engine
        'd_', // diagnostic_engine
      ];
      for (final prefix in prefixes) {
        final id = shortIdWith(prefix);
        expect(id, startsWith(prefix), reason: 'префикс $prefix');
        expect(id.length, prefix.length + 8,
            reason: 'суффикс $prefix должен быть ровно 8 символов');
        expect(id.substring(prefix.length), matches(RegExp(r'^[0-9a-z]{8}$')));
      }
    });

    test('prefixed id тоже попарно различны в один проход', () {
      final ids = List.generate(500, (_) => shortIdWith('ci_'));
      expect(ids.toSet().length, ids.length);
    });
  });
}