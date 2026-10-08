/// Эвристическая оценка открытых ответов (explanation/diagnosis/application/
/// transfer) по ключевым словам рубрики. Без LLM, детерминированно.
///
/// Правила:
/// - пустой ответ → false;
/// - пустая рубрика → true (нет критерия — засчитываем);
/// - из рубрики извлекаются ключевые термины: слова > 3 символов, без
///   пунктуации; **служебные слова** ([_stopWords]: является/можно/который…)
///   отбрасываются — их наличие не доказывает знания, а в знаменателе порога
///   они раздували required-маччи;
/// - терминов нет → принимаем ответы длиннее 10 символов;
/// - иначе «верно», если найдено ≥ 30% ключевых терминов;
/// - термин считается найденным, если он встречается в ответе как подстрока
///   **либо делит с каким-нибудь словом ответа основу ≥ 4 символов**
///   (морфология: «приращения» ↔ «приращений», «клетки» ↔ «клетка»). Ровно
///   это и ослабило прежний вариант: содержательный пересказ другими
///   словоформами не проходил, а болтовня с совпадением основ всё равно не
///   набирает порог.
///
/// Порог 30% сохранён намеренно: упоминание одного-двух терминов из длинной
/// рубрики — это name-dropping, а не знание.
bool gradeOpenEnded(String answer, {required String rubric}) {
  final trimmed = answer.trim();
  if (trimmed.isEmpty) return false;
  if (rubric.isEmpty) return true;

  final answerLower = trimmed.toLowerCase();
  // Слова ответа длиннее 3 символов — по ним ищем основу термина рубрики.
  final answerWords = answerLower
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 3)
      .toList();

  final rubricWords = <String>{
    for (final w in _tokenize(rubric))
      if (!_stopWords.contains(w)) w,
  };

  if (rubricWords.isEmpty) return answer.length > 10;

  var matched = 0;
  for (final term in rubricWords) {
    if (_matchesTerm(term, answerLower, answerWords)) matched++;
  }
  final threshold = rubricWords.length * 0.3;

  return matched >= threshold;
}

/// Слова рубрики без пунктуации и короче 4 символов не считаются ключевыми.
Set<String> _tokenize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.length > 3)
    .toSet();

/// Служебные слова: есть почти в любой рубрике и почти в любом ответе, но
/// знания не доказывают. Их удаление из знаменателя — единственное место,
/// где порог «30%» пересчитывается, сами 30% не трогаем.
const Set<String> _stopWords = {
  'является', 'являются', 'являться', 'являлся', 'становится',
  'означает', 'значит', 'можно', 'нельзя', 'нужно', 'нужен', 'нужна',
  'нужны', 'очень', 'весь', 'всех', 'такой', 'такая', 'такие', 'таком',
  'того', 'этот', 'этой', 'этих', 'этому', 'этого',
  'который', 'которая', 'которые', 'которое', 'которых', 'которой',
  'будет', 'будут', 'было', 'были', 'была', 'быть',
  'уже', 'тоже', 'также', 'именно', 'поэтому', 'потому', 'однако',
  'причем', 'примерно', 'например', 'просто', 'вообще', 'даже',
  'себя', 'себе', 'свою', 'свой', 'своя', 'своих', 'своей',
  'этом', 'через', 'между', 'около', 'когда', 'чтобы', 'похоже',
};

/// Термин найден в ответе: подстрока (точная словоформа) либо общая основа
/// ≥ 4 символов с каким-нибудь словом ответа (морфология).
bool _matchesTerm(String term, String answerLower, List<String> answerWords) {
  if (answerLower.contains(term)) return true;
  for (final w in answerWords) {
    if (_commonPrefixLen(term, w) >= 4) return true;
  }
  return false;
}

int _commonPrefixLen(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}
