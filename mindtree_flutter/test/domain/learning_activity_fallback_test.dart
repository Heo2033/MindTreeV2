import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/engines/learning_activity_service.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

KnowledgeNode _node({
  String oneLiner = 'Определение понятия X',
  String? analogy,
  String details = 'Подробное объяснение',
}) => KnowledgeNode(
  id: 'n1',
  topicId: 't1',
  parentId: null,
  level: 1,
  label: 'Понятие X',
  oneLiner: oneLiner,
  details: details,
  analogy: analogy,
);

void main() {
  group('fallbackExample', () {
    test('не повторяет определение (one_liner) в тексте примера', () {
      final text = fallbackExample(_node());

      expect(text, isNot(contains('Определение понятия X')));
      // Пример всё же привязан к понятию и содержит простую инструкцию.
      expect(text, contains('Понятие X'));
      expect(text, contains('пример'));
    });

    test('использует аналогию, если она есть', () {
      final text = fallbackExample(_node(analogy: 'Это как рецепт блюда'));

      expect(text, contains('Аналогия: Это как рецепт блюда'));
    });
  });

  group('explainBody (fallback без details)', () {
    test('НЕ содержит аналогию — её забирает шаг «пример»', () {
      final text =
          explainBody(_node(details: '', analogy: 'Это как рецепт блюда'));

      expect(text, contains('Определение понятия X'));
      expect(text, isNot(contains('Аналогия')));
    });
  });

  group('ensureDistinctExample', () {
    test('пример, дублирующий объяснение, подменяется на fallback-пример', () {
      final node = _node(analogy: 'Это как рецепт блюда');
      final explain = 'Объяснение с определениями';

      final distinct = ensureDistinctExample(node, explain, explain);

      expect(distinct, contains('Аналогия: Это как рецепт блюда'));
    });

    test('различный пример не трогается', () {
      final distinct =
          ensureDistinctExample(_node(), 'Объяснение', 'Пример про жизнь');

      expect(distinct, 'Пример про жизнь');
    });
  });

  group('sanitizeExample: шаг «пример» не отдаёт ученику задание', () {
    test('императив из LLM заменяется на fallback-пример', () {
      final node = _node(analogy: 'Это как рецепт блюда');

      // Раньше такой текст уезжал в UI как есть: вместо примера — задача.
      final body =
          sanitizeExample(node, 'Объяснение', 'Приведите один простой пример.');

      expect(body, contains('Аналогия: Это как рецепт блюда'));
      expect(body, isNot(contains('Приведите')));
    });

    test('вопрос вместо примера заменяется на fallback', () {
      final body = sanitizeExample(_node(), 'Объяснение', 'А как это работает?');

      expect(body, isNot(endsWith('?')));
    });

    test('нормальный пример от LLM сохраняется', () {
      const example = 'В фотографии кадры собирают постепенно, шум уходит.';

      expect(sanitizeExample(_node(), 'Объяснение', example), example);
    });

    test('fallback-пример никогда не выглядит как задание ученику', () {
      for (final text in [
        fallbackExample(_node()),
        fallbackExample(_node(analogy: 'Это как рецепт блюда')),
      ]) {
        expect(looksLikeLearnerTask(text), isFalse,
            reason: 'шаг «Разбираем пример» не должен содержать задание: $text');
      }
    });
  });

  group('apply.reference_answer отвечает на задание про применение', () {
    test('пересказ определения не принимается за образец ответа', () {
      final node = _node();

      // Раньше такое значение показывалось как «Образец ответа» к заданию
      // «где применяется» — ученик получал ложное «Есть ошибки».
      expect(isUsableReferenceAnswer('Определение понятия X', node), isFalse);
      expect(
        isUsableReferenceAnswer(
          'В задаче о прогнозе погоды это понятие применяют так: сначала '
          'собирают частные признаки, потом усредняют их в один вывод.',
          node,
        ),
        isTrue,
      );
    });

    test('короткий или пустой образец отбрасывается', () {
      final node = _node();

      expect(isUsableReferenceAnswer('', node), isFalse);
      expect(isUsableReferenceAnswer('Применяется в жизни', node), isFalse);
    });

    test('образец, дословно повторяющий определение, отбрасывается', () {
      final node = _node(details: 'Подробное объяснение понятия. Идёт деталь.');

      // Ответ про применение без дословного пересказа определения — нормально.
      expect(
        isUsableReferenceAnswer(
          'Это нужно там, где решают задачи прогноза: сначала собирают '
          'признаки по отдельности, потом сводят их в один вывод.',
          node,
        ),
        isTrue,
      );
      // Дословный пересказ details — нет.
      expect(
        isUsableReferenceAnswer('Подробное объяснение понятия. Идёт деталь.', node),
        isFalse,
      );
      // Дословный пересказ one_liner — тоже нет.
      expect(
        isUsableReferenceAnswer(
          'Определение понятия X, и всё.',
          node,
        ),
        isFalse,
      );
    });
  });
}
