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
      expect(p, contains('n3_ddim'));
      expect(p, contains('Детерминированный метод сэмплирования'));
      expectNoPlaceholders(p, 'content');
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
}