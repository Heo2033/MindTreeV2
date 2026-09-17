import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/engines/mastery_engine.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

void main() {
  group('levelFromScore', () {
    test('низкий score -> awareness', () {
      expect(levelFromScore(0), MasteryLevel.awareness);
      expect(levelFromScore(0.05), MasteryLevel.awareness);
      expect(levelFromScore(0.11), MasteryLevel.awareness);
    });

    test('середины полос дают ожидаемый уровень', () {
      // Границы в коде — i/5 - 0.08, поэтому берём значения чуть выше
      // float-границы (0.12/0.32/0.52/0.72/0.92).
      expect(levelFromScore(0.121), MasteryLevel.basicUnderstanding);
      expect(levelFromScore(0.321), MasteryLevel.solidUnderstanding);
      expect(levelFromScore(0.521), MasteryLevel.practicalApplication);
      expect(levelFromScore(0.721), MasteryLevel.advanced);
      expect(levelFromScore(0.921), MasteryLevel.expert);
    });

    test('score >= 1 -> expert, отрицательный -> awareness', () {
      expect(levelFromScore(1.0), MasteryLevel.expert);
      expect(levelFromScore(2.0), MasteryLevel.expert);
      expect(levelFromScore(-0.5), MasteryLevel.awareness);
    });

    test('не убывает по score', () {
      var prev = -1;
      for (var i = 0; i <= 20; i++) {
        final idx = MasteryLevel.order.indexOf(levelFromScore(i / 20));
        expect(idx, greaterThanOrEqualTo(prev));
        prev = idx;
      }
    });
  });
}