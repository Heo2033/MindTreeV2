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
}
