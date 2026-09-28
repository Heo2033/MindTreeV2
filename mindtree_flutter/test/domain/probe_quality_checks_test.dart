// Тесты quality-проверок probe.
//
// Проверки детерминированы, поэтому тесты не зависят от LLM и проверяют
// одновременно контракт (чистый прогон = пусто) и реакцию на каждое
// нарушение по отдельности.
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/domain/engines/diagnostic_engine.dart';
import 'package:mindtree_flutter/domain/models/activity.dart';
import 'package:mindtree_flutter/domain/models/assessment.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';
import 'package:mindtree_flutter/domain/models/primitives.dart';

import '../../tool/probe/jargon.dart';
import '../../tool/probe/quality_checks.dart';

KnowledgeNode _node({
  required String id,
  String? parentId,
  int level = 2,
  String label = 'Узел',
  String oneLiner = 'Короткая формулировка без жаргона',
  String details = 'Подробное объяснение для не-эксперта',
  bool contentLoaded = true,
  String? analogy,
}) {
  return KnowledgeNode(
    id: id,
    topicId: 't1',
    parentId: parentId,
    level: level,
    label: label,
    oneLiner: oneLiner,
    details: details,
    analogy: analogy,
    state: NodeState.contentGenerated,
    contentLoaded: contentLoaded,
  );
}

/// Минимальное корректное дерево: корень + два ребёнка + один внук.
List<KnowledgeNode> _goodTree() => [
      _node(
        id: 'n1',
        parentId: null,
        level: 1,
        label: 'Теорема остановки',
        oneLiner: 'Любая программа, вечно использующая память, однажды остановится',
      ),
      _node(id: 'n2', parentId: 'n1', label: 'Основные понятия'),
      _node(id: 'n3', parentId: 'n1', label: 'Практические следствия'),
      _node(id: 'n4', parentId: 'n2', level: 3, label: 'Диагонализация'),
    ];

QualityInput _input({
  List<KnowledgeNode>? nodes,
  int targetLevel = 1,
  String goal = 'понять теорему остановки',
  List<ActivityStep>? recall,
  List<ActivityStep>? apply,
  List<LearningActivity>? activities,
  List<DiagnosticQuestion>? diagnostic,
  List<AssessmentQuestion>? assessment,
  List<String> curriculum = const ['n2'],
}) =>
    QualityInput(
      nodes: nodes ?? _goodTree(),
      targetLevel: targetLevel,
      goal: goal,
      recallSteps: recall ?? const [],
      applySteps: apply ?? const [],
      activities: activities ?? const [],
      diagnosticQuestions: diagnostic ?? const [],
      assessmentQuestions: assessment ?? const [],
      curriculumNodeIds: curriculum,
    );

/// Коды нарушений среди всех результатов.
Set<String> _codes(List<CheckResult> results) =>
    {for (final r in results) r.code};

void main() {
  group('jargon', () {
    test('находит русские словоформы по основе', () {
      expect(findJargon('Здесь используется инвариант системы', 1),
          contains('инвариант'));
      // Падежные формы склеиваются по префиксу.
      expect(findJargon('Нарушение инварианта идёт дальше', 1),
          contains('инварианта'));
    });

    test('латинские термины срабатывают только целиком', () {
      expect(findJargon('Вызов API сервера', 1), contains('API'));
      // `id` не должен ловить «идея» и любые слова с этими буквами.
      expect(findJargon('Обычная идея и простое цифровое слово', 1), isEmpty);
    });

    test('не-expert уровень строже экспертного', () {
      const text = 'Здесь обсуждается архитектура решения';
      expect(findJargon(text, 1), isNotEmpty, reason: 'уровень 1 — строго');
      expect(findJargon(text, 5), isEmpty, reason: 'уровень 5 — мягко');
    });

    test('пустой текст не даёт совпадений', () {
      expect(findJargon('', 1), isEmpty);
      expect(findJargon('   ', 1), isEmpty);
    });
  });

  group('one_liner_max_len', () {
    test('короткий one_liner проходит', () {
      expect(checkOneLinerLength(_goodTree()), isEmpty);
    });

    test('слишком длинный one_liner ловится с точным id', () {
      final nodes = [
        _node(
          id: 'n1',
          parentId: null,
          level: 1,
          oneLiner: 'я' * (kOneLinerMaxLength + 1),
        ),
      ];
      final r = checkOneLinerLength(nodes);
      expect(r, hasLength(1));
      expect(r.single.code, CheckCode.oneLinerMaxLen);
      expect(r.single.severity, Severity.fail);
      expect(r.single.nodeId, 'n1');
      expect(r.single.message, contains('${kOneLinerMaxLength + 1}'));
    });
  });

  group('single_root', () {
    test('один корень проходит', () {
      expect(checkSingleRoot(_goodTree()), isEmpty);
    });

    test('два корня — fail', () {
      final r = checkSingleRoot([
        _node(id: 'n1', parentId: null, level: 1),
        _node(id: 'n2', parentId: null, level: 1),
      ]);
      expect(r.single.code, CheckCode.singleRoot);
      expect(r.single.severity, Severity.fail);
      expect(r.single.message, contains('2 корня'));
    });

    test('нет корня — отдельное сообщение', () {
      final r = checkSingleRoot([_node(id: 'n2', parentId: 'n1')]);
      expect(r.single.severity, Severity.fail);
      expect(r.single.message, contains('нет корня'));
    });
  });

  group('parent_exists', () {
    test('все родители на месте', () {
      expect(checkParentsExist(_goodTree()), isEmpty);
    });

    test('битый parentId указывает на узел', () {
      final r = checkParentsExist([
        _node(id: 'n1', parentId: null, level: 1),
        _node(id: 'n2', parentId: 'нет-такого'),
      ]);
      expect(r.single.code, CheckCode.parentExists);
      expect(r.single.nodeId, 'n2');
      expect(r.single.message, contains('нет-такого'));
    });
  });

  group('no_cycles', () {
    test('acyclic проходит', () {
      expect(checkNoCycles(_goodTree()), isEmpty);
    });

    test('цикл ловится на всех участниках', () {
      final r = checkNoCycles([
        _node(id: 'a', parentId: 'c', level: 2),
        _node(id: 'b', parentId: 'a', level: 3),
        _node(id: 'c', parentId: 'b', level: 2),
      ]);
      expect(_codes(r), {CheckCode.noCycles});
      expect(r.map((e) => e.nodeId).toSet(), {'a', 'b', 'c'});
      // Порядок стабильный — узлы отсортированы.
      expect(r.map((e) => e.nodeId), ['a', 'b', 'c']);
    });

    test('цикл в одном поддереве не задевает остальное', () {
      final r = checkNoCycles([
        _node(id: 'a', parentId: 'b', level: 2),
        _node(id: 'b', parentId: 'a', level: 2),
        _node(id: 'ok', parentId: null, level: 1),
      ]);
      expect(r.map((e) => e.nodeId).toSet(), {'a', 'b'});
    });
  });

  group('level_consistent', () {
    test('корректные уровни проходят', () {
      expect(checkLevelConsistency(_goodTree()), isEmpty);
    });

    test('корень не на первом уровне', () {
      final r = checkLevelConsistency([_node(id: 'n1', parentId: null, level: 2)]);
      expect(r.single.code, CheckCode.levelConsistent);
      expect(r.single.message, contains('Корень'));
    });

    test('разрыв между уровнями', () {
      final r = checkLevelConsistency([
        _node(id: 'n1', parentId: null, level: 1),
        _node(id: 'n2', parentId: 'n1', level: 4),
      ]);
      expect(r.single.code, CheckCode.levelConsistent);
      expect(r.single.message, contains('ожидался 2'));
    });
  });

  group('no_empty_content', () {
    test('заполненный контент проходит', () {
      expect(checkNoEmptyContent(_goodTree()), isEmpty);
    });

    test('пустой one_liner при contentLoaded ловится', () {
      final r = checkNoEmptyContent([_node(id: 'n1', oneLiner: '   ')]);
      expect(r.single.code, CheckCode.noEmptyContent);
      expect(r.single.message, contains('one_liner'));
    });

    test('пустой label ловится', () {
      final r = checkNoEmptyContent([_node(id: 'n1', label: '')]);
      expect(r.single.code, CheckCode.noEmptyContent);
      expect(r.single.message, contains('label'));
    });

    test('contentLoaded == false не проверяется', () {
      // Пропущенный контент — не нарушение, это ожидаемое состояние.
      expect(
        checkNoEmptyContent([_node(id: 'n1', oneLiner: '', contentLoaded: false)]),
        isEmpty,
      );
    });
  });

  group('no_duplicate_labels', () {
    test('уникальные подписи проходят', () {
      expect(checkNoDuplicateLabels(_goodTree()), isEmpty);
    });

    test('одинаковые подписи у одного родителя — warn', () {
      final r = checkNoDuplicateLabels([
        _node(id: 'n1', parentId: null, level: 1, label: 'Корень'),
        _node(id: 'n2', parentId: 'n1', label: 'Основные понятия'),
        _node(id: 'n3', parentId: 'n1', label: 'основные  понятия'),
      ]);
      expect(r.single.code, CheckCode.noDuplicateLabels);
      expect(r.single.severity, Severity.warn);
      // Нормализация: регистр и пробелы не делают подписи разными.
      expect(r.single.message, contains('Основные понятия'));
      expect(r.single.message, contains('n2'));
    });

    test('одинаковые подписи у РАЗНЫХ родителей — не нарушение', () {
      expect(
        checkNoDuplicateLabels([
          _node(id: 'n1', parentId: null, level: 1, label: 'Корень'),
          _node(id: 'n2', parentId: 'n1', label: 'Понятие'),
          _node(id: 'n3', parentId: 'n1', label: 'Другое'),
          _node(id: 'n4', parentId: 'n2', level: 3, label: 'Понятие'),
        ]),
        isEmpty,
      );
    });
  });

  group('jargon_free', () {
    test('чистый контент проходит', () {
      expect(checkJargonFree(_goodTree(), 1), isEmpty);
    });

    test('необъяснённый термин — warn со списком', () {
      final r = checkJargonFree([
        _node(id: 'n1', parentId: null, level: 1, details: 'Здесь вводится инвариант.'),
      ], 1);
      expect(r.single.code, CheckCode.jargonFree);
      expect(r.single.severity, Severity.warn);
      expect(r.single.message, contains('инвариант'));
    });

    test('термин в one_liner тоже ловится', () {
      final r = checkJargonFree([
        _node(id: 'n1', parentId: null, level: 1, oneLiner: 'Ключевой инвариант тут'),
      ], 1);
      expect(r, hasLength(1));
    });

    test('термины дедуплицируются и сортируются', () {
      final r = checkJargonFree([
        _node(
          id: 'n1',
          parentId: null,
          level: 1,
          details: 'Рефакторинг и рефакторинг, плюс API и API.',
        ),
      ], 1);
      expect(r.single.message, contains('API'));
      expect(r.single.message, contains('Рефакторинг'));
      // Каждый термин один раз.
      expect('API'.allMatches(r.single.message).length, 1);
    });

    test('без контента проверка молчит', () {
      expect(
        checkJargonFree(
            [_node(id: 'n1', parentId: null, level: 1, contentLoaded: false)], 1),
        isEmpty,
      );
    });
  });

  group('recall_wellformed', () {
    const good = ActivityStep(
      type: 'recall',
      title: 'Что такое инвариант?',
      options: ['A', 'B', 'C', 'D'],
      correctIndex: 0,
    );

    test('корректный recall проходит', () {
      expect(checkRecallWellformed([good]), isEmpty);
    });

    test('неверный type', () {
      final r = checkRecallWellformed([
        const ActivityStep(type: 'apply', title: 'X', bestAnswer: 'Y'),
      ]);
      expect(r.single.code, CheckCode.recallWellformed);
      expect(r.single.message, contains('ожидался recall'));
    });

    test('мало вариантов', () {
      final r = checkRecallWellformed([
        const ActivityStep(type: 'recall', title: 'X', options: ['A'], correctIndex: 0),
      ]);
      expect(r.single.message, contains('2..4'));
    });

    test('нет correctIndex', () {
      final r = checkRecallWellformed([
        const ActivityStep(type: 'recall', title: 'X', options: ['A', 'B']),
      ]);
      expect(r.single.message, contains('correctIndex'));
    });

    test('correctIndex вне диапазона', () {
      final r = checkRecallWellformed([
        const ActivityStep(
            type: 'recall', title: 'X', options: ['A', 'B'], correctIndex: 5),
      ]);
      expect(r.single.message, contains('вне диапазона'));
    });
  });

  group('apply_wellformed', () {
    const good = ActivityStep(
      type: 'apply',
      title: 'Примените',
      instruction: 'Приведите пример',
      bestAnswer: 'Пример: ...',
    );

    test('корректный apply проходит', () {
      expect(checkApplyWellformed([good]), isEmpty);
    });

    test('пустая инструкция', () {
      final r = checkApplyWellformed([
        const ActivityStep(type: 'apply', title: 'X', bestAnswer: 'Y'),
      ]);
      expect(r.single.code, CheckCode.applyWellformed);
      expect(r.single.message, contains('инструкция'));
    });

    test('нет эталона', () {
      final r = checkApplyWellformed([
        const ActivityStep(type: 'apply', title: 'X', instruction: 'Y'),
      ]);
      expect(r.single.message, contains('bestAnswer'));
    });

    test('варианты у открытого вопроса', () {
      final r = checkApplyWellformed([
        const ActivityStep(
            type: 'apply',
            title: 'X',
            instruction: 'Y',
            bestAnswer: 'Z',
            options: ['A']),
      ]);
      expect(r.single.message, contains('варианты'));
    });
  });

  group('no_duplicate_activity', () {
    LearningActivity mkActivity(String nodeId, String itemId) => LearningActivity(
          sessionId: 's1',
          itemId: itemId,
          nodeId: nodeId,
          nodeLabel: 'Узел',
          goal: 'g',
        );

    test('по одной активности на узел — ок', () {
      expect(
        checkNoDuplicateActivity([mkActivity('n1', 'i1'), mkActivity('n2', 'i2')]),
        isEmpty,
      );
    });

    test('две активности на один узел — warn', () {
      final r = checkNoDuplicateActivity([mkActivity('n2', 'i1'), mkActivity('n2', 'i2')]);
      expect(r.single.code, CheckCode.noDuplicateActivity);
      expect(r.single.severity, Severity.warn);
      expect(r.single.nodeId, 'n2');
      expect(r.single.message, contains('2 активностей'));
    });
  });

  group('question_wellformed / question_node_known', () {
    DiagnosticQuestion mkDiag({
      String id = 'd1',
      String nodeId = 'n1',
      String question = 'Что это?',
      List<String> options = const ['A', 'B', 'C', 'D'],
      int correctIndex = 0,
    }) =>
        DiagnosticQuestion(
          id: id,
          nodeId: nodeId,
          question: question,
          options: options,
          correctIndex: correctIndex,
          explanation: 'пояснение',
        );

    AssessmentQuestion mkAssess({
      String id = 'q1',
      String nodeId = 'n1',
      QuestionType type = QuestionType.recognition,
      String question = 'Что это?',
      List<String>? options = const ['A', 'B', 'C', 'D'],
    }) =>
        AssessmentQuestion(
          id: id,
          nodeId: nodeId,
          type: type,
          question: question,
          options: options,
        );

    test('корректные вопросы проходят', () {
      expect(
        checkQuestionsWellformed(
          diagnostic: [mkDiag()],
          assessment: [mkAssess()],
        ),
        isEmpty,
      );
      expect(
        checkQuestionNodesKnown(
          _goodTree(),
          diagnostic: [mkDiag()],
          assessment: [mkAssess()],
        ),
        isEmpty,
      );
    });

    test('диагностика: correctIndex вне диапазона', () {
      final r = checkQuestionsWellformed(
        diagnostic: [mkDiag(options: ['A', 'B'], correctIndex: 7)],
        assessment: const [],
      );
      expect(r.single.code, CheckCode.questionWellformed);
      expect(r.single.message, contains('вне диапазона'));
    });

    test('диагностика: мало вариантов', () {
      final r = checkQuestionsWellformed(
        diagnostic: [mkDiag(options: ['A'])],
        assessment: const [],
      );
      expect(r.single.message, contains('2..4'));
    });

    test('оценка: закрытый тип без вариантов', () {
      final r = checkQuestionsWellformed(
        diagnostic: const [],
        assessment: [mkAssess(type: QuestionType.recall, options: null)],
      );
      expect(r.single.code, CheckCode.questionWellformed);
      expect(r.single.message, contains('без вариантов'));
    });

    test('оценка: открытый тип с вариантами — warn', () {
      final r = checkQuestionsWellformed(
        diagnostic: const [],
        assessment: [mkAssess(type: QuestionType.application)],
      );
      expect(r.single.severity, Severity.warn);
      expect(r.single.message, contains('открытый тип'));
    });

    test('вопрос про неизвестный узел', () {
      final r = checkQuestionNodesKnown(
        _goodTree(),
        diagnostic: [mkDiag(nodeId: 'нет-такого')],
        assessment: [mkAssess(id: 'q2', nodeId: 'ещё-нет')],
      );
      expect(_codes(r), {CheckCode.questionNodeKnown});
      expect(r, hasLength(2));
    });
  });

  group('goal_coverage', () {
    test('план ссылается на узлы дерева — ок', () {
      expect(checkGoalCoverage(_input()), isEmpty);
    });

    test('пустой план — fail', () {
      final r = checkGoalCoverage(_input(curriculum: const []));
      expect(r.single.code, CheckCode.goalCoverage);
      expect(r.single.severity, Severity.fail);
      expect(r.single.message, contains('пуст'));
    });

    test('план с чужими узлами — fail со списком', () {
      final r = checkGoalCoverage(_input(curriculum: const ['n2', 'призрак-1', 'призрак-2']));
      expect(r.single.message, contains('призрак-1'));
      expect(r.single.message, contains('призрак-2'));
      expect(r.single.message, contains('2 узла'));
    });
  });

  group('content_coverage', () {
    test('полное покрытие — info', () {
      final r = checkContentCoverage(_goodTree());
      expect(r.single.code, CheckCode.contentCoverage);
      expect(r.single.severity, Severity.info);
      expect(r.single.message, contains('4 из 4'));
    });

    test('частичное покрытие — warn с процентом', () {
      final nodes = [
        _node(id: 'n1', parentId: null, level: 1, contentLoaded: true),
        _node(id: 'n2', parentId: 'n1', contentLoaded: false),
      ];
      final r = checkContentCoverage(nodes);
      expect(r.single.severity, Severity.warn);
      expect(r.single.message, contains('1 из 2'));
      expect(r.single.message, contains('50%'));
    });

    test('пустое дерево — fail', () {
      expect(checkContentCoverage(const []).single.severity, Severity.fail);
    });
  });

  group('runChecks', () {
    test('чистый вход даёт только info, без warn/fail', () {
      final results = runChecks(_input());
      expect(
        results.where((r) => r.severity != Severity.info),
        isEmpty,
        reason: 'ожидался чистый прогон, получено: $results',
      );
      final s = summarize(results);
      expect(s.hasFailures, isFalse);
      expect(s.hasProblems, isFalse);
    });

    test('результаты отсортированы по коду', () {
      final results = runChecks(_input(curriculum: const []));
      final codes = results.map((r) => r.code).toList();
      final sorted = codes.toList()..sort();
      expect(codes, sorted, reason: 'порядок кодов должен быть стабильным');
    });

    test('повторный прогон на том же входе идентичен', () {
      final input = _input(
        recall: const [
          ActivityStep(type: 'recall', title: 'X', options: ['A'], correctIndex: 0)
        ],
      );
      expect(runChecks(input).map((r) => r.toString()).toList(),
          runChecks(input).map((r) => r.toString()).toList());
    });

    test('сводка считает серьёзности', () {
      final results = runChecks(_input(curriculum: const [], targetLevel: 1));
      final s = summarize(results);
      expect(s.fail, greaterThan(0), reason: 'пустой план — это fail');
      expect(s.total, results.length);
    });
  });

  group('CheckResult.toJson', () {
    test('nodeId попадает в JSON только когда задан', () {
      const withNode = CheckResult(
        code: 'c1',
        severity: Severity.warn,
        nodeId: 'n1',
        message: 'm',
      );
      const withoutNode = CheckResult(
        code: 'c1',
        severity: Severity.info,
        message: 'm',
      );
      expect(withNode.toJson(), {
        'code': 'c1',
        'severity': 'warn',
        'nodeId': 'n1',
        'message': 'm',
      });
      expect(withoutNode.toJson(), {
        'code': 'c1',
        'severity': 'info',
        'message': 'm',
      });
    });
  });

  group('ConceptType smoke', () {
    test('импорт моделей используется', () {
      // Гарантирует, что quality_checks видит те же enums, что и движки.
      expect(ConceptType.fromString('concept'), ConceptType.concept);
    });
  });
}
