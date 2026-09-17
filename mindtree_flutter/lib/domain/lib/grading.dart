/// Эвристическая оценка открытых ответов (explanation/diagnosis/application/
/// transfer) по ключевым словам рубрики. Без LLM, детерминированно.
///
/// Правила (результат переноса из `_gradeOpenEnded` экрана финальной проверки):
/// - пустой ответ → false;
/// - пустой rubric → true (нет критерия — засчитываем);
/// - из рубрики извлекаются ключевые термины (слова > 3 символов, кириллица/
///   латиница, без пунктуации);
/// - терминов нет → принимаем ответы длиннее 10 символов;
/// - иначе «верно», если в ответе встречается ≥ 30% ключевых терминов.
bool gradeOpenEnded(String answer, {required String rubric}) {
  final trimmed = answer.trim();
  if (trimmed.isEmpty) return false;
  if (rubric.isEmpty) return true;

  final rubricWords = rubric
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 3)
      .toSet();

  if (rubricWords.isEmpty) return answer.length > 10;

  final answerLower = trimmed.toLowerCase();
  final matched = rubricWords.where((w) => answerLower.contains(w)).length;
  final threshold = rubricWords.length * 0.3;

  return matched >= threshold;
}