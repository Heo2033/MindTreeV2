// Единый резолв `correctAnswer` с вариантами ответа.
//
// ─── Зачем он общий ──────────────────────────────────────────────────────────
// `questions_json` в боевой базе всегда приведён к контракту оценки
// (`AssessmentEngine._parseAssessmentResult`):
// * ЗАКРЫТЫЙ вопрос (`options` непустой): `correctAnswer` — строковый ИНДЕКС
//   правильного варианта («"0".."3"»). Ученик отвечает тем же индексом, и
//   экраны считают ответ верным как `selected.toString() == q.correctAnswer`
//   (`quiz_screen.dart`, `final_assessment_screen.dart`);
// * ОТКРЫТЫЙ вопрос (`options` пустой): `correctAnswer` пуст ПО ПОСТРОЕНИЮ —
//   эталона не требуется и не существует, оценивает `gradeOpenEnded` по рубрике
//   из `explanation` (`lib/domain/lib/grading.dart`).
//
// Значит резолвить «правильный вариант» текстовым сравнением нельзя: на боевых
// данных `correctAnswer` = «"0"», текстом не совпадёт ни с одним вариантом, и
// любой потребитель, который ищет только текст, получает ложный вывод
// «правильный ответ неизвестен». Движок и ревью обязаны считать одинаково,
// поэтому реализация одна, а порядок шагов зафиксирован ниже.
//
// Детерминизм: без «сейчас», без случайности, без locale-зависимых регулярных
// выражений (список разрядов задан числами).

/// Нормализация текста варианта для сравнения: trim + нижний регистр, пробелы и
/// пунктуация превращаются в один пробел, повторы схлопываются.
///
/// Так «Верно: останавливается» и «верно останавливается» сравниваются как одно
/// и то же. Непустой результат — пригодный ключ сравнения.
String normalizeOptionText(String input) {
  final buffer = StringBuffer();
  final chars = input.trim().toLowerCase().runes.toList();
  var lastWasSpace = false;
  for (final c in chars) {
    // whitespace
    if (c == 0x20 ||
        c == 0x09 ||
        c == 0x0A ||
        c == 0x0D ||
        c == 0x0B ||
        c == 0x0C) {
      if (!lastWasSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        lastWasSpace = true;
      }
      continue;
    }
    // punctuation
    if (c == 0x2C ||
        c == 0x2E ||
        c == 0x3B ||
        c == 0x3A ||
        c == 0x21 ||
        c == 0x3F ||
        c == 0x2D ||
        c == 0x5F ||
        c == 0x28 ||
        c == 0x29 ||
        c == 0x5B ||
        c == 0x5D ||
        c == 0x7B ||
        c == 0x7D ||
        c == 0x22 ||
        c == 0x27 ||
        c == 0x60) {
      if (!lastWasSpace && buffer.isNotEmpty) {
        buffer.write(' ');
        lastWasSpace = true;
      }
      continue;
    }
    buffer.writeCharCode(c);
    lastWasSpace = false;
  }
  return buffer.toString().trim();
}

/// Индекс правильного варианта в [options] либо `null`, если сопоставить нечем.
///
/// Порядок резолва зафиксирован контрактом и менять его нельзя:
/// 1) целочисленный индекс в диапазоне `[0, options.length)` — основная форма
///    (`correctAnswer` = «"0".."3"»); индекс вне диапазона НЕ является ответом и
///    проверяется дальше как текст;
/// 2) нормализованное текстовое совпадение — терпимость к LLM-ответам и
///    историческим данным, где прислали текст варианта вместо индекса.
///
/// `null` — вариантов нет (открытый вопрос), `correctAnswer` пуст либо ни один
/// вариант не сопоставим. Вызывающий обязан трактовать это как «правильный
/// ответ неизвестен», а не подставлять свой вариант.
int? resolveCorrectOptionIndex(List<String> options, String? correctAnswer) {
  if (options.isEmpty) return null;
  final raw = (correctAnswer ?? '').trim();
  if (raw.isEmpty) return null;

  final asIndex = int.tryParse(raw);
  if (asIndex != null && asIndex >= 0 && asIndex < options.length) {
    return asIndex;
  }

  final target = normalizeOptionText(raw);
  if (target.isEmpty) return null;
  for (var i = 0; i < options.length; i++) {
    final option = normalizeOptionText(options[i]);
    if (option.isNotEmpty && option == target) return i;
  }
  return null;
}

/// [resolveCorrectOptionIndex], приведённый к форме, в которой `correctAnswer`
/// лежит в `questions_json`: строковый индекс. `''` — сопоставить не удалось
/// (такой вопрос движок при генерации отбрасывает).
String resolveCorrectAnswerIndex(List<String> options, String? correctAnswer) =>
    resolveCorrectOptionIndex(options, correctAnswer)?.toString() ?? '';
