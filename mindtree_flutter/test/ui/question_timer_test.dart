import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/lib/time_plausibility.dart';
import 'package:mindtree_flutter/ui/question_timer.dart';

/// Регрессия дефекта таймера оценки: `now - _startedAt` при незаведённом
/// старте (`_startedAt == 0`) давал `DateTime.now().millisecondsSinceEpoch`
/// ≈ 1.8e12 мс — тул ревью помечал запись fail'ом «Неправдоподобный замер
/// времени» и исключал её из суммы Learning Gain / Time.
void main() {
  const now = 1753128000000; // опорный момент в epoch-мс

  group('QuestionTimer.elapsedBetween', () {
    test('незаведённый старт (0) не даёт epoch-значение', () {
      expect(QuestionTimer.elapsedBetween(0, now), 0);
      expect(QuestionTimer.elapsedBetween(-5, now), 0);
    });

    test('нормальная длительность считается как now - start', () {
      expect(QuestionTimer.elapsedBetween(now - 1500, now), 1500);
      expect(QuestionTimer.elapsedBetween(now, now), 0);
    });

    test('ушедшие назад часы и старт из будущего дают 0', () {
      expect(QuestionTimer.elapsedBetween(now + 5000, now), 0);
    });

    test('неправдоподобно долгий старт — техническая находка, не эталон', () {
      // Сутки простоя в фоне: значение больше порога ревью — такое запись
      // в сумме времени не участвует, но и не превращается в epoch-мс.
      final dayMs = 24 * 60 * 60 * 1000;
      final elapsed = QuestionTimer.elapsedBetween(now - dayMs, now);
      expect(elapsed, dayMs);
      expect(elapsed, greaterThan(kImplausibleDurationMs));
    });
  });

  group('QuestionTimer', () {
    test('новый таймер заведён в момент создания — старт не 0', () {
      final timer = QuestionTimer();
      final first = timer.elapsedMs();
      expect(first, greaterThanOrEqualTo(0));
      expect(first, lessThan(5000));
    });

    test('restart заново заводит отсчёт от текущего момента', () {
      final timer = QuestionTimer();
      timer.restart();
      final elapsed = timer.elapsedMs();
      expect(elapsed, greaterThanOrEqualTo(0));
      expect(elapsed, lessThan(5000));
      // Никакого абсолютного времени: сутки отсчёта таймер дать не может.
      expect(elapsed, lessThan(kImplausibleDurationMs));
    });
  });

  test('порог совпадает с порогом тул ревью (2 часа)', () {
    expect(kImplausibleDurationMs, 2 * 60 * 60 * 1000);
  });
}
