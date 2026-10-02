// Рендер отчёта ревью: JSON и Markdown.
//
// Закрывает `tool/review/report.dart` — последний слой перед файлами отчёта.
// LLM-судью не зовём: блок `judgeFindings` заполняем руками, сети и ключей нет.
//
// ЧТО ФИКСИРУЕМ
//   * контракт полей `toJson` (в том числе `judgeSummary == null`, когда судья
//     не работал);
//   * ДЕТЕРМИНИЗМ: в отчёте нет ни времени прогона, ни id провайдера — два
//     одинаковых отчёта дают побайтово одинаковые строки;
//   * подписи метрик и разметку Markdown (включая экранирование `|`);
//   * раскладку файлов `writeReports`: имя выводится из вида артефакта и их
//     количества, без времени.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/review/finding.dart';
import '../../tool/review/judge.dart';
import '../../tool/review/report.dart';

/// Метрики сессии ровно те, что собирает CLI в `_reviewSession`.
const Map<String, dynamic> kSessionMetrics = <String, dynamic>{
  'activityCount': 1,
  'stepCount': 2,
  'answeredSteps': 2,
  'questionCount': 1,
  'questionsAnswered': 1,
  'questionsCorrect': 1,
  'eventCount': 3,
  'masteryNodes': 2,
  'milestoneCount': 1,
  'nodeCount': 5,
  'timeBudgetMinutes': 45,
  'status': 'completed',
};

/// Находки вразнобой: по коду `session_activity_node_unknown` идёт после
/// `session_step_mix`, поэтому сортировка в отчёте обязана переставить их.
const List<Finding> kUnsortedFindings = <Finding>[
  Finding(
    code: 'session_step_mix',
    severity: FindingSeverity.warn,
    nodeId: 'n2',
    message: 'В активности «Рекурсия» нет ни recall, ни apply шага',
  ),
  Finding(
    code: 'session_activity_node_unknown',
    severity: FindingSeverity.fail,
    nodeId: 'n-alien',
    message: 'Активность ссылается на узел, которого нет в плане',
  ),
];

/// Отчёт сессии для тестов рендера.
ReviewReport sessionReport({
  List<Finding> findings = kUnsortedFindings,
  List<JudgeFinding> judgeFindings = const <JudgeFinding>[],
  List<String> warnings = const <String>[],
  String subject = 's1',
}) =>
    ReviewReport(
      kind: ReviewSubjectKind.session,
      subject: subject,
      topicName: 'Теорема остановки',
      subjectSummary: 'цель overview, уровень basic_understanding, '
          'бюджет 45 мин, статус completed',
      metrics: kSessionMetrics,
      findings: findings,
      judgeFindings: judgeFindings,
      warnings: warnings,
    );

void main() {
  group('контракт toJson', () {
    test('набор ключей фиксирован (времени прогона в нём нет)', () {
      final json = sessionReport().toJson();

      expect(
        json.keys.toList(),
        <String>[
          'kind',
          'subject',
          'topicName',
          'subjectSummary',
          'metrics',
          'summary',
          'judgeSummary',
          'findings',
          'judgeFindings',
          'warnings',
        ],
      );
      expect(json['kind'], 'session');
      expect(json['subject'], 's1');
      expect(json['topicName'], 'Теорема остановки');
      expect(json['judgeFindings'], isEmpty);
    });

    test('без судьи judgeSummary == null (секция не рендеруется)', () {
      expect(sessionReport().toJson()['judgeSummary'], isNull);
      expect(sessionReport().judgeSummary.total, 0);
    });

    test('судья отработал → judgeSummary заполнен, находки с префиксом judge_', () {
      final report = sessionReport(judgeFindings: const <JudgeFinding>[
        JudgeFinding(
          dimension: 'factual',
          severity: FindingSeverity.fail,
          nodeId: 'n1',
          message: 'Формула неверна',
          suggestion: 'Заменить на теорему остановки',
        ),
      ]);

      final json = report.toJson();
      expect(json['judgeSummary'],
          <String, dynamic>{'info': 0, 'warn': 0, 'fail': 1, 'total': 1});
      expect((json['judgeFindings'] as List<dynamic>).single,
          <String, dynamic>{
            'dimension': 'factual',
            'severity': 'fail',
            'nodeId': 'n1',
            'message': 'Формула неверна',
            'suggestion': 'Заменить на теорему остановки',
          });
      expect(report.judgeSummary.fail, 1);
    });

    test('сводка честно считает серьёзности находок', () {
      final report = sessionReport();

      expect(report.summary.fail, 1);
      expect(report.summary.warn, 1);
      expect(report.summary.info, 0);
      expect(report.summary.total, 2);
      expect(report.summary.hasProblems, isTrue);
      expect(report.summary.hasFailures, isTrue);
      expect(report.summary.rankMax, FindingSeverity.fail.rank);
    });

    test('одни warn → hasFailures == false (порог --fail-on не срабатывает)', () {
      final report = sessionReport(findings: const <Finding>[
        Finding(
          code: 'session_step_mix',
          severity: FindingSeverity.warn,
          message: 'только лекция',
        ),
      ]);

      expect(report.hasFailures, isFalse);
      expect(report.summary.rankMax, FindingSeverity.warn.rank);
    });

    test('fail только у судьи → hasFailures == true', () {
      final report = sessionReport(
        findings: const <Finding>[],
        judgeFindings: const <JudgeFinding>[
          JudgeFinding(
            dimension: 'pedagogy',
            severity: FindingSeverity.fail,
            message: 'задание не проверяет понимание',
          ),
        ],
      );

      expect(report.hasFailures, isTrue);
    });

    test('находки в JSON отсортированы независимо от порядка на входе', () {
      final codes = <String>[
        for (final f in (sessionReport().toJson()['findings'] as List<dynamic>)
            .cast<Map<String, dynamic>>())
          f['code'] as String,
      ];

      expect(codes, <String>['session_activity_node_unknown', 'session_step_mix']);
    });

    test('toJsonString — валидный JSON с отступами', () {
      final text = sessionReport().toJsonString();

      expect(() => jsonDecode(text), returnsNormally);
      expect(text, startsWith('{\n  "kind": "session"'));
    });
  });

  group('детерминизм', () {
    test('два одинаковых отчёта дают побайтово одинаковый JSON', () {
      expect(sessionReport(subject: 's1').toJsonString(),
          sessionReport(subject: 's1').toJsonString());
    });

    test('порядок находок на входе не влияет на вывод', () {
      final shuffled = sessionReport(
        findings: const <Finding>[
          Finding(
            code: 'session_step_mix',
            severity: FindingSeverity.warn,
            nodeId: 'n2',
            message: 'В активности «Рекурсия» нет ни recall, ни apply шага',
          ),
          Finding(
            code: 'session_activity_node_unknown',
            severity: FindingSeverity.fail,
            nodeId: 'n-alien',
            message: 'Активность ссылается на узел, которого нет в плане',
          ),
        ],
      );

      expect(shuffled.toJsonString(), sessionReport().toJsonString());
    });

    test('в отчёте нет случайных полей времени прогона', () {
      final json = sessionReport().toJson();

      for (final forbidden in <String>['timestamp', 'generatedAt', 'date', 'now']) {
        expect(json.keys, isNot(contains(forbidden)),
            reason: 'время прогона в отчёт не попадает: два прогона должны '
                'быть сравнимы побайтово');
      }
    });
  });

  group('Markdown', () {
    test('шапка: вид артефакта, имя темы, артефакт и контекст', () {
      final md = _markdown(sessionReport());

      expect(md, startsWith('# Ревью MindTree\n'));
      expect(md, contains('## Учебная сессия: Теорема остановки'));
      expect(md, contains('- Артефакт: `s1`'));
      expect(md, contains('- Контекст: цель overview, уровень basic_understanding, '
          'бюджет 45 мин, статус completed'));
    });

    test('метрики подписаны по-русски, неизвестные ключи остаются как есть', () {
      final md = _markdown(sessionReport());

      expect(md, contains('- активностей: 1'));
      expect(md, contains('- шагов: 2'));
      expect(md, contains('- отвеченных шагов: 2'));
      expect(md, contains('- вопросов оценки: 1'));
      expect(md, contains('- событий: 3'));
      expect(md, contains('- узлов с mastery: 2'));
      expect(md, contains('- узлов: 5'));
      expect(md, contains('- бюджет, мин: 45'));
      // Ключей без подписи в `_metricLabel` нет намеренно: они видны как есть,
      // чтобы не потерять метрику.
      expect(md, contains('- questionsAnswered: 1'));
      expect(md, contains('- status: completed'));
    });

    test('итог со сводкой и список находок с узлами', () {
      final md = _markdown(sessionReport());

      expect(md, contains('**Итог**: детерминированные проверки — '
          'fail: 1, warn: 1, info: 0.'));
      expect(md, contains('### Детерминированные проверки'));
      expect(
        md,
        contains('- **fail** `session_activity_node_unknown` — `n-alien`: '
            'Активность ссылается на узел, которого нет в плане'),
      );
      expect(
        md,
        contains('- **warn** `session_step_mix` — `n2`: '
            'В активности «Рекурсия» нет ни recall, ни apply шага'),
      );
    });

    test('без находок печатается «Находок нет.» и нет пустых секций', () {
      final md = _markdown(sessionReport(findings: const <Finding>[]));

      expect(md, contains('Находок нет.'));
      expect(md, isNot(contains('### Детерминированные проверки')));
      expect(md, isNot(contains('### LLM-судья')));
      expect(md, isNot(contains('### Предупреждения инструмента')));
    });

    test('блок судьи печатается с правкой, труба в тексте экранируется', () {
      final md = _markdown(sessionReport(
        findings: const <Finding>[
          Finding(
            code: 'session_question_shallow',
            severity: FindingSeverity.warn,
            nodeId: 'n1',
            message: 'таблица a|b\nи вторая строка',
          ),
        ],
        judgeFindings: const <JudgeFinding>[
          JudgeFinding(
            dimension: 'factual',
            severity: FindingSeverity.fail,
            nodeId: 'n1',
            message: 'Формула неверна',
            suggestion: 'Заменить на теорему остановки',
          ),
        ],
        warnings: const <String>['битый JSON в questions_json'],
      ));

      expect(md, contains('### LLM-судья'));
      expect(md, contains('- **fail** factual — `n1`: Формула неверна'));
      expect(md, contains('  - правка: Заменить на теорему остановки'));
      // `|` экранируется, перевод строки внутри сообщения схлопывается.
      expect(md, contains(r'таблица a\|b и вторая строка'));
      expect(md, isNot(contains('таблица a|b')));
      expect(md, contains('### Предупреждения инструмента'));
      expect(md, contains('- битый JSON в questions_json'));
    });
  });

  group('writeReports', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mindtree_review_report_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    String out(String sub) => '${dir.path}${Platform.pathSeparator}$sub';

    test('файлы называются review-<вид>-<количество>, каталог создаётся', () {
      final target = out('nested/deep/review');
      writeReports(<ReviewReport>[sessionReport()], target);

      expect(File('$target${Platform.pathSeparator}review-session-1.json').existsSync(),
          isTrue);
      expect(File('$target${Platform.pathSeparator}review-session-1.md').existsSync(),
          isTrue);
    });

    test('два прогона дают одинаковые байты (имя без времени)', () {
      final target = out('повтор');
      final first = <ReviewReport>[sessionReport(), sessionReport(subject: 's2')];
      writeReports(first, target);

      final jsonBytes = File('$target${Platform.pathSeparator}review-session-2.json')
          .readAsBytesSync();
      final mdBytes = File('$target${Platform.pathSeparator}review-session-2.md')
          .readAsBytesSync();

      writeReports(first, target);

      expect(File('$target${Platform.pathSeparator}review-session-2.json')
          .readAsBytesSync(), jsonBytes);
      expect(File('$target${Platform.pathSeparator}review-session-2.md')
          .readAsBytesSync(), mdBytes);

      // Вид отчёта и количество — единственное, что попадает в имя.
      expect(
        Directory(target)
            .listSync()
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort(),
        <String>['review-session-2.json', 'review-session-2.md'],
      );
    });

    test('дерево и сессия в одном пакете → review-mixed-2, порядок не важен', () {
      // Раньше имя бралось от первого отчёта: тот же набор артефактов давал
      // `review-tree-2` или `review-session-2` в зависимости от порядка
      // аргументов CLI.
      final byKind = out('смешанный-порядок-1');
      final bySession = out('смешанный-порядок-2');
      writeReports(<ReviewReport>[
        ReviewReport(kind: ReviewSubjectKind.tree, subject: 'mindtree-topic.json'),
        sessionReport(),
      ], byKind);
      writeReports(<ReviewReport>[
        sessionReport(),
        ReviewReport(kind: ReviewSubjectKind.tree, subject: 'mindtree-topic.json'),
      ], bySession);

      final sep = Platform.pathSeparator;
      expect(File('$byKind${sep}review-mixed-2.json').existsSync(), isTrue,
          reason: 'смешанный набор не должен называться по виду одного отчёта');
      expect(File('$byKind${sep}review-tree-2.json').existsSync(), isFalse);
      expect(
        File('$byKind${sep}review-mixed-2.json').readAsStringSync(),
        File('$bySession${sep}review-mixed-2.json').readAsStringSync(),
      );
    });

    test('пустой пакет → review-empty-0, рендер не падает', () {
      final target = out('пусто');
      writeReports(const <ReviewReport>[], target);

      final json = File('$target${Platform.pathSeparator}review-empty-0.json')
          .readAsStringSync();
      expect(jsonDecode(json), <String, dynamic>{
        'reports': <dynamic>[],
      });
      expect(
        File('$target${Platform.pathSeparator}review-empty-0.md').readAsStringSync(),
        startsWith('# Ревью MindTree'),
      );
    });
  });
}

/// Markdown одного отчёта — приватный рендер проверяем через публичный путь
/// `writeReports`, чтобы тест шёл по тому же коду, что и CLI.
String _markdown(ReviewReport report) {
  final dir = Directory.systemTemp.createTempSync('mindtree_review_md_');
  try {
    writeReports(<ReviewReport>[report], dir.path);
    return File('${dir.path}${Platform.pathSeparator}review-session-1.md')
        .readAsStringSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}