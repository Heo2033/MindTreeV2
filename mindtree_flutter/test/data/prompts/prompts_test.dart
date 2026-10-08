import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/prompts/prompts.dart';

/// Regression test: prompt placeholders were written with Dart interpolation
/// (`'${"{token}"}'`) which renders single braces `{token}` in the literal
/// text, while `_replaceOnce/_replaceAll` search for double braces `{{token}}`.
/// Result: every ${NO_META_RULE} placeholder silently leaked into the built
/// prompt and no value was ever substituted (e.g. L2 stayed "Про диффузионные
/// модели" instead of the user query, making every new topic drift to GAN).
void main() {
  final leftoverPlaceholder = RegExp(r'\{\{[A-Za-z_][A-Za-z0-9_]*\}\}');

  void expectNoPlaceholders(String prompt, String name) {
    expect(prompt, isNot(contains(r'${')));
    expect(leftoverPlaceholder.hasMatch(prompt), isFalse,
        reason: '$name left raw placeholder: '
            '${leftoverPlaceholder.allMatches(prompt).map((m) => m.group(0)).toList()}');
  }

  group('graph structure prompts', () {
    test('buildL1Prompt substitutes all tokens', () {
      final p = buildL1Prompt('Диффузионные модели',
          goal: 'overview', level: 'solid_understanding');
      expect(p, contains('Диффузионные модели'));
      expectNoPlaceholders(p, 'L1');
    });

    test('buildL2Prompt substitutes query, root and hints', () {
      final p = buildL2Prompt(
        userQuery: 'Диффузионные модели',
        rootId: 'n1_root',
        rootTitle: 'Диффузионные модели',
        rootCanonicalDefinition: 'Класс генеративных моделей, порождающих данные из шума',
        goal: 'overview',
        level: 'solid_understanding',
      );
      expect(p, contains('Диффузионные модели'));
      expect(p, contains('n1_root'));
      expectNoPlaceholders(p, 'L2');
    });

    test('buildL3Prompt substitutes parent and siblings', () {
      final p = buildL3Prompt(
        userQuery: 'Диффузионные модели',
        rootTitle: 'Диффузионные модели',
        parentId: 'n2_sampling',
        parentTitle: 'Методы сэмплинга',
        parentCanonicalDefinition: 'Способы получения обратного перехода',
        siblings: [
          {'id': 'n2_arch', 'title': 'Архитектуры', 'canonical_definition': 'Слои и блоки'},
          {'id': 'n2_loss', 'title': 'Функции потерь', 'canonical_definition': 'Целевые функции'},
        ],
        goal: 'overview',
        level: 'solid_understanding',
      );
      expect(p, contains('Методы сэмплинга'));
      expect(p, contains('n2_sampling'));
      expect(p, contains('n2_arch'));
      expectNoPlaceholders(p, 'L3');
    });

    test('buildExpandPrompt substitutes nodes to expand', () {
      final p = buildExpandPrompt(
        rootTopic: 'Диффузионные модели',
        contextPaths: ['Корень → Методы сэмплирования'],
        nodesToExpand: [
          {'id': 'n3_ddim', 'title': 'DDIM', 'path': 'Корень → Методы сэмплирования → DDIM'},
        ],
        goal: 'overview',
        level: 'solid_understanding',
      );
      expect(p, contains('DDIM'));
      expect(p, contains('n3_ddim'));
      expectNoPlaceholders(p, 'expand');
    });

    test('buildContentPrompt substitutes node and context', () {
      final p = buildContentPrompt(
        rootTopic: 'Диффузионные модели',
        nodePath: ['Корень', 'Методы сэмплирования', 'DDIM'],
        nodeId: 'n3_ddim',
        nodeLabel: 'DDIM',
        siblings: ['DDPM', 'DPM-Solver'],
        knowledgeLevel: 'intermediate',
        goal: 'deep',
        isRoot: false,
        isCriticalDomain: false,
        ontologyContext: {
          'canonical_definition': 'Детерминированный метод сэмплирования',
          'semantic_axis': 'sampling',
        },
      );
      expect(p, contains('DDIM'));
      expect(p, contains('Детерминированный метод сэмплирования'));
      expectNoPlaceholders(p, 'content');
    });

    test('buildContentPrompt не генерирует relations (id неизвестны модели)', () {
      // Контентная стадия не знает id других узлов: связи задаёт структурная.
      // Промпт обязан требовать пустой массив, иначе модель выдумывает id.
      final p = buildContentPrompt(
        rootTopic: 'Диффузионные модели',
        nodePath: ['Корень', 'DDIM'],
        nodeId: 'n3_ddim',
        nodeLabel: 'DDIM',
        siblings: const [],
        knowledgeLevel: 'intermediate',
        goal: 'deep',
      );
      expect(p, contains('"relations": []'));
      expect(p, isNot(contains('id_другого_узла')));
      expect(p, isNot(contains('id_этого_узла')));
    });

    test('buildContentPrompt добавляет дисциплину фактов и сложности', () {
      final beginner = buildContentPrompt(
        rootTopic: 'Диффузионные модели',
        nodePath: const ['Корень'],
        nodeId: 'n1_root',
        nodeLabel: 'Диффузионные модели',
        siblings: const [],
        knowledgeLevel: 'beginner',
        goal: 'deep',
      );
      expect(beginner, contains('# Фактическая дисциплина'));
      expect(beginner, contains('# Сложность'));
      expect(beginner, contains('расшифруй'));

      // У эксперта блок сложности не нужен, фактическая дисциплина — нужна.
      final expert = buildContentPrompt(
        rootTopic: 'Диффузионные модели',
        nodePath: const ['Корень'],
        nodeId: 'n1_root',
        nodeLabel: 'Диффузионные модели',
        siblings: const [],
        knowledgeLevel: 'expert',
        goal: 'deep',
      );
      expect(expert, isNot(contains('# Сложность')));
      expect(expert, contains('# Фактическая дисциплина'));
    });

    test('buildContentPrompt требует JSON-экранирование слэша в LaTeX', () {
      // jsonDecode считает одиночные `\r`, `\t`, `\n`, `\b`, `\f` валидным
      // escape и молча портит значение, поэтому промпт обязан требовать
      // удвоенный слэш в макросах. Проверяем ИТОГОВУЮ строку, не литерал.
      final p = buildContentPrompt(
        rootTopic: 'Диффузионные модели',
        nodePath: const ['Корень', 'DDIM'],
        nodeId: 'n3_ddim',
        nodeLabel: 'DDIM',
        siblings: const [],
        knowledgeLevel: 'intermediate',
        goal: 'deep',
      );
      expect(p, contains(r'КАЖДЫЙ обратный слэш удваивай'));
      expect(p, contains(r'пиши \\frac, \\text, \\rightarrow'));
      // Ошибочный (неудвоенный) вариант показан только как антипример.
      expect(p, contains(r'а не \frac'));
      expect(p, isNot(contains(r'пиши \frac')));
    });

    test('buildValidatePrompt embeds the real tree JSON', () {
      final p = buildValidatePrompt([
        {
          'id': 'n1_root',
          'label': 'Диффузионные модели',
          'oneliner': 'Класс генеративных моделей',
          'details': 'Описание',
        },
      ]);
      expect(p, contains('n1_root'));
      expectNoPlaceholders(p, 'validate');
    });
  });

  group('non-graph prompts', () {
    test('buildQuizPrompt has no leftover tokens', () {
      final p = buildQuizPrompt('Диффузионные модели', [
        {
          'id': 'n1_root',
          'label': 'Диффузионные модели',
          'one_liner': 'Класс генеративных моделей',
          'details': 'Описание',
        },
      ], 5);
      expectNoPlaceholders(p, 'quiz');
    });

    test('buildExplainPrompt substitutes node and selection', () {
      final p = buildExplainPrompt(
        'Что такое обратный процесс?',
        nodeLabel: 'Обратный процесс',
        nodeDetails: 'Переход от шума к данным',
        selectedText: 'обратный процесс',
      );
      expect(p, contains('Что такое обратный процесс?'));
      expect(p, contains('Обратный процесс'));
      expectNoPlaceholders(p, 'explain');
    });
  });

  group('assessment open-ended contract', () {
    test('buildAssessmentPrompt разделяет referenceAnswer и explanation', () {
      final p = buildAssessmentPrompt(
        topic: 'Диффузионные модели',
        goal: 'понимание',
        sessionItems: const [
          {
            'nodeId': 'n1_root~1a2b3c4d',
            'label': 'Диффузионные модели',
            'oneLiner': 'Класс генеративных моделей',
            'details': 'Описание',
          },
        ],
        questionCount: 6,
      );
      expectNoPlaceholders(p, 'assessment');
      // Поле эталонного ответа описано в инструкции, в примере JSON и в чек-листе.
      expect(p, contains('referenceAnswer'));
      expect(p, contains('ПОЛНЫЙ образец ответа'));
      expect(p, contains('НЕ повторяет и не раскрывает весь referenceAnswer'));
      expect(p, contains('referenceAnswer — только у открытых вопросов'));
      // Рубрика остаётся рубрикой — без неё открытый вопрос непроверяем.
      expect(p, contains('rubric (explanation) содержит конкретные критерии'));
    });

    test('parseAssessmentResult заполняет referenceAnswer, иначе пустая строка', () {
      final qs = parseAssessmentResult({
        'questions': [
          {
            'id': 'a1',
            'type': 'explanation',
            'nodeId': 'n1',
            'question': 'Объясните, как работает X',
            'options': <String>[],
            'correctAnswer': '',
            'explanation': 'Ключевые элементы ответа: 1) шаги, 2) причина',
            'referenceAnswer': 'X работает так: сначала …, затем …',
          },
          // Модель не вернула поле вне схемы — эталон пуст, контракт цел.
          {
            'id': 'a2',
            'type': 'recall',
            'nodeId': 'n1',
            'question': 'Что верно?',
            'options': ['A', 'B', 'C', 'D'],
            'correctAnswer': '0',
            'explanation': 'Потому что …',
          },
        ],
      });
      expect(qs, hasLength(2));
      expect(qs[0]['referenceAnswer'], 'X работает так: сначала …, затем …');
      expect(qs[0]['explanation'], contains('Ключевые элементы'));
      expect(qs[1]['referenceAnswer'], '');
      expect(qs[1]['correctAnswer'], '0');
    });
  });
}