import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/lib/srs.dart';

SrsState _state({int interval = 0, double ease = 2.5, int reps = 0}) =>
    SrsState(interval: interval, ease: ease, reps: reps, dueAt: '');

void main() {
  group('scheduleReview — correct', () {
    test('первое повторение: interval 1, ease +0.1, reps+1', () {
      final next = scheduleReview(null, 'correct');
      expect(next.interval, 1);
      expect(next.ease, closeTo(2.6, 1e-9));
      expect(next.reps, 1);
    });

    test('второе повторение: interval 3', () {
      final next =
          scheduleReview(_state(interval: 1, ease: 2.6, reps: 1), 'correct');
      expect(next.interval, 3);
      expect(next.reps, 2);
      expect(next.ease, closeTo(2.7, 1e-9));
    });

    test('далее interval = round(interval * ease)', () {
      final next =
          scheduleReview(_state(interval: 5, ease: 2.0, reps: 3), 'correct');
      expect(next.interval, 10);
      expect(next.reps, 4);
      expect(next.ease, closeTo(2.1, 1e-9));
    });

    test('ease не превышает 2.8', () {
      final next =
          scheduleReview(_state(interval: 3, ease: 2.8, reps: 2), 'correct');
      expect(next.ease, closeTo(2.8, 1e-9));
    });

    test('dueAt примерно через interval дней', () {
      // reps == 1 -> второе повторение, interval ровно 3 дня.
      final next =
          scheduleReview(_state(interval: 1, ease: 2.0, reps: 1), 'correct');
      final due = DateTime.parse(next.dueAt);
      final now = DateTime.now();
      expect(due.isAfter(now.add(const Duration(hours: 23))), isTrue);
      expect(due.isBefore(now.add(const Duration(days: 4))), isTrue);
    });
  });

  group('scheduleReview — incorrect/again', () {
    test('incorrect сбрасывает interval/reps и снижает ease на 0.2', () {
      final next = scheduleReview(
          _state(interval: 10, ease: 2.5, reps: 5), 'incorrect');
      expect(next.interval, 0);
      expect(next.reps, 0);
      expect(next.ease, closeTo(2.3, 1e-9));
    });

    test('ease не опускается ниже 1.3', () {
      final next = scheduleReview(_state(interval: 1, ease: 1.4, reps: 1), 'again');
      expect(next.ease, closeTo(1.3, 1e-9));
    });
  });

  group('isDue', () {
    test('null всегда к повторению', () {
      expect(isDue(null), isTrue);
    });

    test('просроченный dueAt -> due', () {
      final past = SrsState(
        interval: 1,
        ease: 2.5,
        reps: 1,
        dueAt:
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      );
      expect(isDue(past), isTrue);
    });

    test('будущий dueAt -> not due', () {
      final future = SrsState(
        interval: 5,
        ease: 2.5,
        reps: 2,
        dueAt: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      );
      expect(isDue(future), isFalse);
    });

    test('неразбираемый dueAt трактуется как due', () {
      expect(isDue(_state(interval: 3, reps: 1)), isTrue);
    });
  });

  group('estimateMastery', () {
    test('null или reps == 0 -> 0', () {
      expect(estimateMastery(null), 0);
      expect(estimateMastery(_state()), 0);
    });

    test('interval / 21 с ограничением сверху', () {
      expect(estimateMastery(_state(interval: 10, reps: 1)), closeTo(10 / 21, 1e-9));
      expect(estimateMastery(_state(interval: 21, reps: 1)), 1.0);
      expect(estimateMastery(_state(interval: 100, reps: 1)), 1.0);
    });
  });
}