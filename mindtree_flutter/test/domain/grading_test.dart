import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/lib/grading.dart';

void main() {
  group('gradeOpenEnded', () {
    test('пустой ответ всегда неверен, даже при пустой рубрике', () {
      expect(gradeOpenEnded('', rubric: 'Объясни, что такое производная'), isFalse);
      expect(gradeOpenEnded('   ', rubric: ''), isFalse);
      expect(gradeOpenEnded('', rubric: ''), isFalse);
    });

    test('пустая рубрика — fallback: засчитываем любой непустой ответ', () {
      expect(gradeOpenEnded('Да', rubric: ''), isTrue);
      expect(gradeOpenEnded('Короткий ответ', rubric: ''), isTrue);
    });

    test('ответ с ключевыми терминами рубрики — верно (30% порог)', () {
      const rubric = 'Производная функции — предел отношения приращения функции '
          'к приращению аргумента.';
      expect(
        gradeOpenEnded('Производная функции это предел отношения приращений', rubric: rubric),
        isTrue,
      );
    });

    test('ответ без ключевых терминов — неверно', () {
      const rubric = 'Производная функции — предел отношения приращения функции '
          'к приращению аргумента.';
      expect(gradeOpenEnded('Ответ не по теме', rubric: rubric), isFalse);
    });

    test('слова короче 4 символов не считаются ключевыми', () {
      const rubric = 'Это проверка знаний.';
      // ключевые слова: "проверка", "знаний" (2 шт), порог 0.6 → нужно ≥1
      expect(gradeOpenEnded('это', rubric: rubric), isFalse); // "это" — не ключевое
      expect(gradeOpenEnded('проверка', rubric: rubric), isTrue);
    });

    test('пунктуация и регистр не мешают совпадению', () {
      const rubric = 'Митоз: деление клетки!';
      // ключевые слова: "митоз", "деление", "клетки" (3 шт), порог 0.9 → нужно ≥1
      expect(gradeOpenEnded('Митоз и деление клетки', rubric: rubric), isTrue);
    });

    test('рубрика без терминов (>3 символов) — fallback по длине ответа', () {
      const rubric = 'да нет!';
      // ключевых слов нет (все ≤3) → принимаем ответ длиннее 10 символов
      expect(gradeOpenEnded('короткий', rubric: rubric), isFalse);
      expect(gradeOpenEnded('достаточно длинный ответ на вопрос', rubric: rubric), isTrue);
    });
  });
}