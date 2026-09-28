// Проверка детерминированного fake-LLM: маршрутизация по реальным промптам.
//
// Тест строит промпты настоящими билдерами из `prompts.dart`, поэтому ломается
// сразу, если в шаблоне поменяется строка роли или формат контекста.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/llm/client.dart';
import 'package:mindtree_flutter/data/prompts/prompts.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';

import '../../../tool/probe/fake_llm.dart';

void main() {
  group('classifyPrompt', () {
    test('L1 определяется по теме пользователя', () {
      expect(
        classifyPrompt(buildL1Prompt('доказательство теоремы остановки')),
        PromptKind.l1,
      );
    });

    test('L1Edit не путается с L1 (другая строка роли)', () {
      final prompt = buildL1EditPrompt('теорема остановки', {
        'id': 'n1_root',
        'label': 'Теорема остановки',
        'one_liner': 'Один из вариантов определения',
        'level': 1,
      });
      expect(classifyPrompt(prompt), PromptKind.l1Edit);
    });

    test('L2 определяется по названию корня', () {
      final prompt = buildL2Prompt(
        userQuery: 'доказательство теоремы остановки',
        rootId: 'n1_root',
        rootTitle: 'Теорема остановки',
      );
      expect(classifyPrompt(prompt), PromptKind.l2);
    });

    test('L3 определяется по одному конкретному разделу', () {
      final prompt = buildL3Prompt(
        userQuery: 'доказательство теоремы остановки',
        rootTitle: 'Теорема остановки',
        parentId: 'n2_root_1',
        parentTitle: 'Основные понятия',
        siblings: const [],
      );
      expect(classifyPrompt(prompt), PromptKind.l3);
    });

    test('expand определяется по секции узлов для расширения', () {
      final prompt = buildExpandPrompt(
        rootTopic: 'доказательство теоремы остановки',
        contextPaths: const ['Теорема остановки → Основные понятия'],
        nodesToExpand: const [
          {'id': 'n3_root_1_1', 'title': 'Ключевые свойства', 'path': 'A → B'},
        ],
        existingTree: const [
          {'id': 'n1_root', 'title': 'Теорема остановки', 'level': 1},
        ],
      );
      expect(classifyPrompt(prompt), PromptKind.expand);
    });

    test('validate и repair различаются, хотя роль начинается одинаково', () {
      const nodes = [
        {'id': 'n1_root', 'parentId': null, 'level': 1, 'label': 'Корень'},
      ];
      final validate = buildValidatePrompt(nodes);
      final repair = buildRepairPrompt(
        problemNodes: nodes,
        issues: const [
          {'type': 'DUPLICATE', 'node_id': 'n1_root', 'reason': 'дубль'},
        ],
      );
      expect(classifyPrompt(validate), PromptKind.validate);
      expect(classifyPrompt(repair), PromptKind.repair);
    });

    test('content определяется по строке роли и содержит scoped id', () {
      final prompt = buildContentPrompt(
        rootTopic: 'доказательство теоремы остановки',
        nodePath: const ['Теорема остановки', 'Основные понятия'],
        nodeId: 'n2_root_1~1a2b3c4d',
        nodeLabel: 'Основные понятия',
        siblings: const ['Устройство и процессы'],
        nodeLevel: 2,
      );
      expect(classifyPrompt(prompt), PromptKind.content);
      expect(prompt, contains('n2_root_1~1a2b3c4d'));
    });

    test('explain, activity и activityFeedback различаются', () {
      final explain = buildExplainPrompt(
        'теорема остановки',
        nodeLabel: 'Основные понятия',
        nodeDetails: 'текст узла',
        selectedText: 'непонятный фрагмент',
      );
      final activity = buildActivityPrompt(
        topic: 'теорема остановки',
        goal: 'понимание',
        targetLevel: 'basic_understanding',
        label: 'Основные понятия',
        oneLiner: 'суть',
        details: 'подробно',
        conceptType: 'concept',
        difficulty: 0.5,
      );
      final feedback = buildActivityFeedbackPrompt(
        nodeLabel: 'Основные понятия',
        nodeOneLiner: 'суть',
        instruction: 'задание',
        referenceAnswer: 'эталон',
        userAnswer: 'мой ответ',
      );
      expect(classifyPrompt(explain), PromptKind.explain);
      expect(classifyPrompt(activity), PromptKind.activity);
      expect(classifyPrompt(feedback), PromptKind.activityFeedback);
    });

    test('оценочные и навигационные промпты различаются', () {
      const nodes = [
        {'id': 'n2_root_1~1a2b3c4d', 'label': 'Основные понятия', 'one_liner': 'суть'},
      ];
      expect(
        classifyPrompt(buildAssessmentPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          sessionItems: const [
            {
              'nodeId': 'n2_root_1~1a2b3c4d',
              'label': 'Основные понятия',
              'oneLiner': 'суть',
              'details': 'подробно',
            }
          ],
          questionCount: 6,
        )),
        PromptKind.assessment,
      );
      expect(
        classifyPrompt(buildCurriculumPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          currentLevel: 'awareness',
          targetLevel: 'basic_understanding',
          timeBudgetMinutes: 30,
          nodes: nodes,
        )),
        PromptKind.curriculum,
      );
      expect(
        classifyPrompt(buildDiagnosticPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          targetLevel: 'basic_understanding',
          nodes: nodes,
        )),
        PromptKind.diagnostic,
      );
      expect(
        classifyPrompt(buildMasteryPrompt(
          topic: 'теорема остановки',
          targetLevel: 'basic_understanding',
          items: const [
            {
              'nodeId': 'n2_root_1~1a2b3c4d',
              'label': 'Основные понятия',
              'type': 'explanation',
              'userAnswer': 'мой ответ',
              'correct': true,
              'rubric': 'рубрика',
            }
          ],
        )),
        PromptKind.mastery,
      );
      expect(
        classifyPrompt(buildMilestonePrompt(
          topic: 'теорема остановки',
          currentLevel: 'awareness',
          goal: 'понимание',
        )),
        PromptKind.milestone,
      );
      expect(
        classifyPrompt(buildQuizPrompt('теорема остановки', nodes, 6)),
        PromptKind.quiz,
      );
    });

    test('tutor определяется по контекстному репетитору', () {
      final prompt = buildTutorPrompt(
        topic: 'теорема остановки',
        goal: 'понимание',
        targetLevel: 'basic_understanding',
        currentLevel: 'awareness',
        currentNode: 'Основные понятия',
        nodePath: const ['Теорема остановки', 'Основные понятия'],
        message: 'не понял, зачем это',
      );
      expect(classifyPrompt(prompt), PromptKind.tutor);
    });

    test('неизвестный промпт бросает UnknownPromptKind', () {
      expect(
        () => classifyPrompt('Ты — неизвестный помощник. Ответь чем угодно.'),
        throwsA(isA<UnknownPromptKind>()),
      );
    });

    test('неоднозначность маршрутизации — тоже ошибка', () {
      const l1Role =
          'Ты — педагог-структуролог. Твоя задача — определить корень (тему) онтологии дерева знаний.';
      const contentRole =
          'Ты — эксперт-энциклопедист. Дай точное, краткое описание понятия.';
      expect(
        () => classifyPrompt('$l1Role\n$contentRole'),
        throwsA(isA<UnknownPromptKind>()),
      );
    });
  });

  group('детерминированность', () {
    test('один и тот же промпт даёт побайтово одинаковый ответ', () {
      final prompt = buildContentPrompt(
        rootTopic: 'доказательство теоремы остановки',
        nodePath: const ['Теорема остановки', 'Основные понятия'],
        nodeId: 'n2_root_1~1a2b3c4d',
        nodeLabel: 'Основные понятия',
        siblings: const ['Устройство и процессы'],
        nodeLevel: 2,
      );
      expect(
        FakeLlm().respondTo(PromptKind.content, prompt),
        FakeLlm().respondTo(PromptKind.content, prompt),
      );
    });

    test('L1 на одном запросе стабилен между прогонами', () {
      final prompt = buildL1Prompt('доказательство теоремы остановки');
      expect(
        FakeLlm().respondTo(PromptKind.l1, prompt),
        FakeLlm().respondTo(PromptKind.l1, prompt),
      );
    });
  });

  group('контракты ответов', () {
    Map<String, dynamic> decode(PromptKind kind, String prompt) =>
        jsonDecode(FakeLlm().respondTo(kind, prompt)) as Map<String, dynamic>;

    test('L1: один корень, parentId == null, level == 1', () {
      final data = decode(PromptKind.l1, buildL1Prompt('доказательство теоремы остановки'));
      final nodes = (data['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes, hasLength(1));
      expect(nodes.single['parentId'], isNull);
      expect(nodes.single['level'], 1);
      expect(nodes.single['title'], 'доказательство теоремы остановки');
    });

    test('L2: все дети — уровень 2 с parentId корня, подписи различны', () {
      final data = decode(
        PromptKind.l2,
        buildL2Prompt(
          userQuery: 'доказательство теоремы остановки',
          rootId: 'n1_root',
          rootTitle: 'Теорема остановки',
        ),
      );
      final nodes = (data['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes.length, greaterThanOrEqualTo(3));
      for (final n in nodes) {
        expect(n['parentId'], 'n1_root');
        expect(n['level'], 2);
      }
      final labels = nodes.map((n) => n['title']).toList();
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('L3: дети уровня 3 с parentId родителя, подписи различны', () {
      const parentId = 'n2_root_2';
      final data = decode(
        PromptKind.l3,
        buildL3Prompt(
          userQuery: 'доказательство теоремы остановки',
          rootTitle: 'Теорема остановки',
          parentId: parentId,
          parentTitle: 'Устройство и процессы',
          siblings: const [
            {'id': 'n2_root_1', 'title': 'Основные понятия'}
          ],
        ),
      );
      final nodes = (data['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes, isNotEmpty);
      for (final n in nodes) {
        // Engine отбирает только `parentId == parent.id && level == 3`.
        expect(n['parentId'], parentId);
        expect(n['level'], 3);
        expect((n['id'] as String), startsWith('n3_'));
      }
      final labels = nodes.map((n) => n['title']).toList();
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('L3 под разными родителями даёт непересекающиеся подписи', () {
      String labelsOf(String parentId, String parentTitle) {
        final data = decode(
          PromptKind.l3,
          buildL3Prompt(
            userQuery: 'теорема остановки',
            rootTitle: 'Теорема остановки',
            parentId: parentId,
            parentTitle: parentTitle,
            siblings: const [],
          ),
        );
        return (data['nodes'] as List)
            .cast<Map<String, dynamic>>()
            .map((n) => n['title'] as String)
            .toSet()
            .join('|');
      }

      expect(
        labelsOf('n2_root_1', 'Основные понятия'),
        isNot(labelsOf('n2_root_2', 'Устройство и процессы')),
      );
    });

    test('expand: дети на уровень+1 только для целевых узлов', () {
      final data = decode(
        PromptKind.expand,
        buildExpandPrompt(
          rootTopic: 'теорема остановки',
          contextPaths: const ['Теорема остановки → Основные понятия'],
          nodesToExpand: const [
            {
              'id': 'n3_root_1_1',
              'title': 'Теорема остановки: ключевые свойства',
              'path': 'A → B → C',
            }
          ],
          // Узлы существующего дерева не должны попасть в «Узлы для расширения».
          existingTree: const [
            {'id': 'n1_root', 'title': 'Теорема остановки', 'level': 1},
            {'id': 'n2_root_1', 'title': 'Основные понятия', 'level': 2},
            {
              'id': 'n3_root_1_1',
              'title': 'Теорема остановки: ключевые свойства',
              'level': 3
            },
          ],
        ),
      );
      final nodes = (data['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes, hasLength(1));
      expect(nodes.single['id'], 'n3_root_1_1');
      final children = (nodes.single['children'] as List).cast<Map<String, dynamic>>();
      expect(children, isNotEmpty);
      for (final c in children) {
        expect(c['parentId'], 'n3_root_1_1');
        expect(c['level'], 4);
      }
    });

    test('validate: valid=true, should_expand=false — repair не вызывается', () {
      final data = decode(
        PromptKind.validate,
        buildValidatePrompt(const [
          {'id': 'n1_root', 'parentId': null, 'level': 1, 'label': 'Корень'},
        ]),
      );
      expect(data['valid'], isTrue);
      expect(data['should_expand'], isFalse);
      expect((data['issues'] as List), isEmpty);
    });

    test('repair: пустой массив узлов', () {
      final raw = FakeLlm().respondTo(
        PromptKind.repair,
        buildRepairPrompt(
          problemNodes: const [
            {'id': 'n1_root', 'parentId': null, 'level': 1, 'label': 'Корень'}
          ],
          issues: const [
            {'type': 'DUPLICATE', 'node_id': 'n1_root', 'reason': 'дубль'}
          ],
        ),
      );
      expect(jsonDecode(raw), isEmpty);
    });

    test('content: one_liner ≤ 120, details ≤ 500, нет висячих связей', () {
      const nodeId = 'n2_root_1~1a2b3c4d';
      final data = decode(
        PromptKind.content,
        buildContentPrompt(
          rootTopic: 'теорема остановки',
          nodePath: const ['Теорема остановки', 'Основные понятия'],
          nodeId: nodeId,
          nodeLabel: 'Основные понятия',
          siblings: const ['Устройство и процессы'],
          nodeLevel: 2,
        ),
      );
      final oneLiner = data['one_liner'] as String;
      final details = data['details'] as String;
      expect(oneLiner, isNotEmpty);
      expect(details, isNotEmpty);
      expect(oneLiner.length, lessThanOrEqualTo(120));
      expect(details.length, lessThanOrEqualTo(500));
      expect((data['analogy'] as String).length, lessThanOrEqualTo(120));

      // Промпт подставляет соседей как ПОДПИСИ, а не id, — единственный
      // известный id это текущий узел. Поэтому корректный ответ — пустой
      // relations: любая связь была бы висячей и потерялась бы при записи.
      final relations = (data['relations'] as List).cast<Map<String, dynamic>>();
      expect(relations, isEmpty);
    });

    test('content для корня даёт one_liner уровня 1', () {
      final data = decode(
        PromptKind.content,
        buildContentPrompt(
          rootTopic: 'теорема остановки',
          nodePath: const ['Теорема остановки'],
          nodeId: 'n1_root~1a2b3c4d',
          nodeLabel: 'Теорема остановки',
          siblings: const [],
          nodeLevel: 1,
          isRoot: true,
        ),
      );
      expect(data['one_liner'], contains('обзорная тема'));
    });

    test('activity: recall из 4 вариантов + apply с эталоном', () {
      final data = decode(
        PromptKind.activity,
        buildActivityPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          targetLevel: 'basic_understanding',
          label: 'Основные понятия',
          oneLiner: 'суть',
          details: 'подробно',
          conceptType: 'concept',
          difficulty: 0.5,
        ),
      );
      expect(data['example'], isNotEmpty);
      final recall = data['recall'] as Map<String, dynamic>;
      expect((recall['options'] as List), hasLength(4));
      expect(recall['correct_index'], isA<int>());
      final apply = data['apply'] as Map<String, dynamic>;
      expect(apply['instruction'], contains('Основные понятия'));
      expect(apply['reference_answer'], isNotEmpty);
    });

    test('activityFeedback: partial + misconception (для отчёта о мисконцепциях)', () {
      final data = decode(
        PromptKind.activityFeedback,
        buildActivityFeedbackPrompt(
          nodeLabel: 'Основные понятия',
          nodeOneLiner: 'суть',
          instruction: 'задание',
          referenceAnswer: 'эталон',
          userAnswer: 'мой ответ',
        ),
      );
      expect(data['assessment'], 'partial');
      expect(data['feedback'], isNotEmpty);
      expect(data['misconception'], isNotEmpty);
    });

    test('assessment: ровно question_count вопросов, типы из 6 допустимых', () {
      final data = decode(
        PromptKind.assessment,
        buildAssessmentPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          sessionItems: const [
            {
              'nodeId': 'n2_root_1~1a2b3c4d',
              'label': 'Основные понятия',
              'oneLiner': 'суть',
              'details': 'подробно',
            }
          ],
          questionCount: 6,
        ),
      );
      final qs = (data['questions'] as List).cast<Map<String, dynamic>>();
      expect(qs, hasLength(6));
      const allowed = {
        'recognition',
        'recall',
        'explanation',
        'diagnosis',
        'application',
        'transfer',
      };
      for (final q in qs) {
        expect(allowed, contains(q['type']));
        final isClosed = q['type'] == 'recognition' || q['type'] == 'recall';
        final options = (q['options'] as List).cast<String>();
        if (isClosed) {
          expect(options, hasLength(4));
          expect(int.parse(q['correctAnswer'] as String), inInclusiveRange(0, 3));
        } else {
          expect(options, isEmpty);
          expect(q['correctAnswer'] as String, isEmpty);
          // Для открытых типов explanation — это рубрика.
          expect(q['explanation'] as String, contains('Рубрика'));
        }
        expect(q['nodeId'], isNotEmpty);
      }
    });

    test('curriculum: node_id из дерева, сумма минут сходится', () {
      final nodes = [
        for (var i = 1; i <= 8; i++)
          {'id': 'n2_root_$i~1a2b3c4d', 'label': 'Раздел $i', 'one_liner': 'суть $i'},
      ];
      final data = decode(
        PromptKind.curriculum,
        buildCurriculumPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          currentLevel: 'awareness',
          targetLevel: 'basic_understanding',
          timeBudgetMinutes: 60,
          nodes: nodes,
        ),
      );
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(6));
      expect(
        data['total_estimated_minutes'],
        items.fold<int>(0, (s, i) => s + (i['estimated_minutes'] as int)),
      );
      final known = nodes.map((n) => n['id']).toSet();
      for (final i in items) {
        expect(known, contains(i['node_id']));
        expect(i['why'] as String, isNotEmpty);
      }
    });

    test('diagnostic: 3–4 вопроса, correctIndex в 0..3', () {
      final nodes = [
        for (var i = 1; i <= 3; i++)
          {'id': 'n2_root_$i~1a2b3c4d', 'label': 'Раздел $i', 'one_liner': 'суть $i'},
      ];
      final data = decode(
        PromptKind.diagnostic,
        buildDiagnosticPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          targetLevel: 'basic_understanding',
          nodes: nodes,
        ),
      );
      final qs = (data['questions'] as List).cast<Map<String, dynamic>>();
      expect(qs.length, inInclusiveRange(3, 4));
      for (final q in qs) {
        expect((q['options'] as List), hasLength(4));
        expect(q['correctIndex'], inInclusiveRange(0, 3));
        expect(q['nodeId'], isNotEmpty);
      }
    });

    test('mastery: 4 измерения в 0..1, misconception ровно у одного', () {
      final data = decode(
        PromptKind.mastery,
        buildMasteryPrompt(
          topic: 'теорема остановки',
          targetLevel: 'basic_understanding',
          items: [
            for (var i = 1; i <= 3; i++)
              {
                'nodeId': 'n2_root_$i~1a2b3c4d',
                'label': 'Раздел $i',
                'type': 'explanation',
                'userAnswer': 'ответ',
                'correct': i == 1,
                'rubric': 'рубрика',
              }
          ],
        ),
      );
      final concepts = (data['concepts'] as List).cast<Map<String, dynamic>>();
      expect(concepts, hasLength(3));
      var withMisconception = 0;
      for (final c in concepts) {
        for (final dim in ['understanding', 'recall', 'application', 'transfer']) {
          expect(c[dim] as num, inInclusiveRange(0, 1));
        }
        if (c['misconception'] != null) withMisconception++;
      }
      expect(withMisconception, 1);
      expect(data['enough'], isFalse);
      expect((data['gaps'] as List), isNotEmpty);
    });

    test('milestone: уровни по возрастанию, alternative_paths только вперёд', () {
      final data = decode(
        PromptKind.milestone,
        buildMilestonePrompt(
          topic: 'теорема остановки',
          currentLevel: 'awareness',
          goal: 'понимание',
        ),
      );
      final ms = (data['milestones'] as List).cast<Map<String, dynamic>>();
      const order = [
        'awareness',
        'basic_understanding',
        'solid_understanding',
        'practical_application',
        'advanced',
        'expert',
      ];
      expect(ms.map((m) => m['level'] as String).toList(), order);
      for (final m in ms) {
        expect(m['capabilities'] as List, isNotEmpty);
        expect(m['estimated_hours'], isA<int>());
      }
      expect((ms.last['alternative_paths'] as List), isEmpty);
    });

    test('quiz: 6 вопросов, ≥2 misconception, correctIndex в 0..3', () {
      final nodes = [
        for (var i = 1; i <= 4; i++)
          {'id': 'n2_root_$i~1a2b3c4d', 'label': 'Раздел $i', 'one_liner': 'суть $i'},
      ];
      final data = decode(
        PromptKind.quiz,
        buildQuizPrompt('теорема остановки', nodes, 6),
      );
      final qs = (data['questions'] as List).cast<Map<String, dynamic>>();
      expect(qs, hasLength(6));
      expect(qs.where((q) => q['misconception'] == true).length, greaterThanOrEqualTo(2));
      for (final q in qs) {
        expect((q['options'] as List), hasLength(4));
        expect(q['correctIndex'], inInclusiveRange(0, 3));
        final explanation = q['explanation'] as String;
        expect(explanation, isNotEmpty);
        // Запрет шаблона «Вариант A — правильный ответ».
        expect(explanation, isNot(contains('Вариант A')));
      }
    });

    test('explain и tutor — обычный текст без JSON', () {
      final explainText = FakeLlm().respondTo(
        PromptKind.explain,
        buildExplainPrompt(
          'теорема остановки',
          nodeLabel: 'Основные понятия',
          nodeDetails: 'текст узла',
          selectedText: 'непонятный фрагмент',
        ),
      );
      expect(explainText, contains('непонятный фрагмент'));
      expect(() => jsonDecode(explainText), throwsFormatException);

      final tutorText = FakeLlm().respondTo(
        PromptKind.tutor,
        buildTutorPrompt(
          topic: 'теорема остановки',
          goal: 'понимание',
          targetLevel: 'basic_understanding',
          currentLevel: 'awareness',
          currentNode: 'Основные понятия',
          message: 'не понял, зачем это',
        ),
      );
      expect(tutorText, contains('Основные понятия'));
      expect(() => jsonDecode(tutorText), throwsFormatException);
    });
  });

  group('FakeLlm.invoke', () {
    const cfg = LLMConfig();

    test('логирует вызовы и считает токены по длине текста', () async {
      final fake = FakeLlm();
      final prompt = buildL1Prompt('теорема остановки');
      final result = await fake.invoke(cfg, prompt);

      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.kind, PromptKind.l1);
      expect(fake.callsByKind['L1'], 1);
      expect(result.usage.inputTokens, prompt.length ~/ 4);
      expect(result.usage.outputTokens, result.text.length ~/ 4);
      expect(result.text, isNotEmpty);
    });

    test('неизвестный промпт пробрасывается наружу, а не глотается', () {
      final fake = FakeLlm();
      expect(
        () => fake.invoke(cfg, 'совершенно другой текст'),
        throwsA(isA<UnknownPromptKind>()),
      );
      expect(fake.calls, isEmpty);
    });
  });

  group('совместимость со scopeNodeIds', () {
    test('raw-ids из L2 проходят scopeNodeIds без дублей и стабильно', () {
      final data = jsonDecode(
        FakeLlm().respondTo(
          PromptKind.l2,
          buildL2Prompt(
            userQuery: 'теорема остановки',
            rootId: 'n1_root',
            rootTitle: 'Теорема остановки',
          ),
        ),
      ) as Map<String, dynamic>;

      final drafts = (data['nodes'] as List).cast<Map<String, dynamic>>().map((n) => NodeDraft(
            id: n['id'] as String,
            title: n['title'] as String,
            parentId: n['parentId'] as String,
            level: n['level'] as int,
          )).toList();

      const topicId = 'probe_0_1a2b3c4d';
      final scoped = scopeNodeIds(drafts, topicId);
      expect(scoped, hasLength(drafts.length));
      // Суффикс — `~` + hash8(topicId), а не сам topicId.
      final suffix = scopedSuffix(topicId);
      expect(suffix, matches(RegExp(r'^~[0-9a-f]{8}$')));
      for (final d in scoped) {
        expect(d.id, endsWith(suffix));
      }
      expect(scoped.map((s) => s.id).toSet(), hasLength(scoped.length));
      // Один и тот же topicId → один и тот же результат.
      expect(
        scopeNodeIds(drafts, topicId).map((d) => d.id),
        scoped.map((d) => d.id),
      );
    });
  });
}
