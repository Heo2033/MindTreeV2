/// Отсчёт времени ответа на вопрос теста (quiz / итоговый).
///
/// Таймер завязан на ПОКАЗ, а не на генерацию теста: он заводится при создании
/// (экран уже показан) и перезапускается в каждом месте, где ученик видит новый
/// вопрос. Поэтому старт не может быть `0`.
///
/// Регрессия, которую закрывает класс: экраны держали поле `int _startedAt = 0`
/// и заводили его только в успешной ветке `generate`. Подхват незавершённого
/// теста (`_tryLoadExisting` в `final_assessment_screen`) `_startedAt` не трогал,
/// и в `assessment_attempts.time_spent_ms` уезжало
/// `DateTime.now().millisecondsSinceEpoch` (~1.8e12 мс ≈ 20 суток). Тул ревью
/// помечал это fail'ом «Неправдоподобный замер времени» и исключал запись из
/// суммы Learning Gain / Time.
class QuestionTimer {
  /// Момент показа текущего вопроса (epoch-мс). Заводится в конструкторе —
  /// State создаётся в момент показа экрана.
  int _startedAt = DateTime.now().millisecondsSinceEpoch;

  /// Начать отсчёт заново: новый вопрос стал видим ученику.
  void restart() => _startedAt = DateTime.now().millisecondsSinceEpoch;

  /// Сколько миллисекунд идёт ответ на текущий вопрос.
  int elapsedMs() =>
      elapsedBetween(_startedAt, DateTime.now().millisecondsSinceEpoch);

  /// Длительность от [startedAtMs] до [nowMs], защищённая от битого старта.
  ///
  /// Не заведённый старт (`0`, отрицательный), ушедшие назад часы или
  /// «старт из будущего» дают `0`, а не epoch-значение: правдоподобный ноль
  /// лучше неправдоподобных суток в сумме времени.
  static int elapsedBetween(int startedAtMs, int nowMs) {
    if (startedAtMs <= 0 || startedAtMs > nowMs) return 0;
    return nowMs - startedAtMs;
  }
}
