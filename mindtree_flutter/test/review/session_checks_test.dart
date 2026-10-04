// Детерминированные проверки ПРОЖИТОЙ учебной сессии.
//
// Файл закрывает `tool/review/session_checks.dart` — набор из 15 проверок,
// которые ревьюер применяет к плоскому `SessionView`. БД, drift и сеть не
// нужны: на вход DTO, на выход — список `Finding`.
//
// ЗАЧЕМ ЭТИ ТЕСТЫ. Коды проверок и тексты сообщений — часть контракта отчёта
// (`review-*.json`), а отчёты сравнивают между прогонами. Поэтому фиксируем:
//   * какой КОД и с какой СЕРЬЁЗНОСТЬЮ срабатывает на минимальном дефекте;
//   * что здоровая сессия не даёт НИ ОДНОЙ находки (защита от ложных
//     срабатываний — иначе ревью превратится в шум);
//   * что порядок и тексты находок детерминированы между вызовами.
//
// ФИКСТУРА «ЗДОРОВАЯ» ДОЛЖНА БЫТЬ ПОЛНОЙ. `learner_models` хранит только
// текущее состояние мастерства, поэтому снимка «до» в боевых данных нет и
// `checkMasteryDelta` на таком входе честно выдаёт info. Чтобы защитный тест
// «ни одной находки» оставался строгим, `cleanView` задаёт НЕПУСТОЙ
// `masteryBefore`; кейс «снимка ДО нет» проверяется отдельно и явно —
// фильтровать info в helper'ах значило бы прятать дефект проверки.
//
// Пороги проверок не «подстраиваются» под тест: константы импортируются из
// самого `session_checks.dart`, поэтому правка порога в продакшене уронит
// тест — и это правильно.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/review/finding.dart';
import '../../tool/review/session_checks.dart';

// ─── Эталонные шаги и активность ─────────────────────────────────────────────

/// Recall-шаг без дефектов: 2 варианта, `correctIndex` в диапазоне.
const SessionStepView goodRecall = SessionStepView(
  type: kStepRecall,
  title: 'Что такое остановка?',
  options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
  correctIndex: 0,
  userAnswer: 'Верно: останавливается',
  correct: true,
  feedback: 'верно: это и есть определение остановки',
);

/// Apply-шаг без дефектов: есть инструкция и этал, ответ отличается от этала.
const SessionStepView goodApply = SessionStepView(
  type: kStepApply,
  title: 'Своими словами',
  instruction: 'Объясни своими словами, что такое остановка.',
  bestAnswer: 'Программа не завершится за конечное время.',
  userAnswer: 'Любая программа рано или поздно зависнет.',
  correct: true,
  feedback: 'верно, формулировка близка к эталону',
);

/// Активность без дефектов: есть и recall, и apply, помечена завершённой.
const SessionActivityView goodActivity = SessionActivityView(
  nodeId: 'n1',
  nodeLabel: 'Остановка',
  isComplete: true,
  steps: <SessionStepView>[goodRecall, goodApply],
);

/// Вопрос без дефектов: закрытый, с эталоном, вердиктом и пояснением.
const SessionQuestionView goodQuestion = SessionQuestionView(
  nodeId: 'n1',
  type: kStepRecall,
  question: 'Что такое остановка?',
  options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
  correctAnswer: 'Верно: останавливается',
  correctIndex: 0,
  userAnswer: 'Верно: останавливается',
  correct: true,
  feedback: 'верно: это и есть определение остановки',
  timeSpentMs: 30000,
);

/// Сессия без дефектов: план, активности, вопросы и mastery согласованы.
SessionView cleanView({
  String status = kStatusCompleted,
  int timeBudgetMinutes = 45,
  List<String> plannedNodeIds = const <String>['n1'],

  /// Состояние плана: эталонная сессия его прошла целиком. Пока плана в
  /// `SessionView` нет (0 пунктов), `checkSessionCompletion` молчит — иначе любая
  /// сессия без curriculum в отчёте получала бы находку.
  int plannedItemsCompleted = 1,
  int plannedItemsTotal = 1,
  List<SessionActivityView> activities = const <SessionActivityView>[goodActivity],
  List<SessionQuestionView> questions = const <SessionQuestionView>[goodQuestion],
  // Снимок mastery «до» обязателен: без него `checkMasteryDelta` выдаёт info,
  // и «здоровая» фикстура перестаёт быть эталоном чистого отчёта.
  Map<String, double> masteryBefore = const <String, double>{'n1': 0.25},
  Map<String, double> masteryAfter = const <String, double>{'n1': 0.625},
  List<String> misconceptions = const <String>[],
  Map<String, String> misconceptionsByNode = const <String, String>{},
  List<AssessmentScoreView> assessments = const <AssessmentScoreView>[],
}) =>
    SessionView(
      topicName: 'Теорема остановки',
      goal: 'overview',
      targetLevel: 'basic_understanding',
      timeBudgetMinutes: timeBudgetMinutes,
      startedAt: '2024-05-01T10:00:00.000',
      completedAt: '2024-05-01T10:30:00.000',
      status: status,
      plannedNodeIds: plannedNodeIds,
      plannedItemsCompleted: plannedItemsCompleted,
      plannedItemsTotal: plannedItemsTotal,
      activities: activities,
      questions: questions,
      masteryBefore: masteryBefore,
      masteryAfter: masteryAfter,
      misconceptions: misconceptions,
      misconceptionsByNode: misconceptionsByNode,
      assessments: assessments,
    );

// ─── Хелперы для утверждений ─────────────────────────────────────────────────

/// Только находки с указанным кодом — проверяем конкретный дефект.
List<Finding> withCode(List<Finding> findings, String code) =>
    <Finding>[for (final f in findings) if (f.code == code) f];

/// Коды находок в порядке выдачи — компактно для `expect`.
List<String> codesOf(List<Finding> findings) =>
    <String>[for (final f in findings) f.code];

/// «код/серьёзность» в порядке выдачи.
List<String> tagsOf(List<Finding> findings) =>
    <String>[for (final f in findings) '${f.code}/${f.severity.name}'];

/// Все проверки по отдельности — эталон для проверки точки входа.
List<Finding> everyCheck(SessionView view) => <Finding>[
      ...checkActivityNodesKnown(view),
      ...checkActivityStepMix(view),
      ...checkRecallOptions(view),
      ...checkApplyContract(view),
      ...checkFeedbackMissing(view),
      ...checkAnswersScored(view),
      ...checkApplyDegenerate(view),
      ...checkStepDuration(view),
      ...checkSessionCompletion(view),
      ...checkMasteryDelta(view),
      ...checkMisconceptionRemediation(view),
      ...checkQuestionDepth(view),
      ...checkSessionProgression(view),
      ...checkAssessmentScores(view),
      ...checkVerdictConsistency(view),
    ];

/// Сессия со всеми возможными дефектами сразу — для проверки детерминизма
/// и того, что точка входа ничего не теряет и не дублирует.
SessionView dirtyView() => SessionView(
      topicName: 'Теорема остановки',
      goal: 'overview',
      timeBudgetMinutes: 5,
      startedAt: '2024-05-01T10:00:00.000',
      status: 'active',
      plannedNodeIds: const <String>['n-plan'],
      activities: const <SessionActivityView>[
        SessionActivityView(
          nodeId: 'n-alien',
          nodeLabel: 'Чужой узел',
          steps: <SessionStepView>[
            SessionStepView(
              type: kStepExplain,
              title: 'Лекция',
              // Отвечен, но замера нет: ровно тот случай, который ловит проверка.
              userAnswer: 'понял',
              body: 'Очень длинный текст лекции, который никто не замерял '
                  'и потому время шага осталось нулевым, а это уже больше '
                  'четырёхсот символов в одной строке, чтобы проверка времени '
                  'сработала и напомнила про метрику Learning Gain / Time, '
                  'которая без замеров бессмысленна, и добавляем ещё текста '
                  'для гарантии по порогу в четыреста символов подряд.',
            ),
            SessionStepView(type: kStepRecall, title: 'Без вариантов'),
          ],
        ),
        SessionActivityView(
          nodeId: 'n-plan',
          nodeLabel: 'Плановый узел',
          steps: <SessionStepView>[
            SessionStepView(type: kStepExplain, title: 'Лекция 1'),
            SessionStepView(type: kStepExplain, title: 'Лекция 2'),
            SessionStepView(type: kStepExplain, title: 'Лекция 3'),
            SessionStepView(
              type: kStepApply,
              title: 'apply без контракта',
              userAnswer: 'какой-то ответ',
            ),
          ],
        ),
      ],
      questions: const <SessionQuestionView>[
        SessionQuestionView(
          nodeId: 'n-alien',
          type: 'application',
          question: 'Приведи пример программы, которая не останавливается.',
          userAnswer: 'busy wait без yield',
        ),
      ],
      masteryAfter: const <String, double>{'n-прочь': 0.9},
      misconceptions: const <String>['Путает остановку с бесконечным циклом'],
    );

void main() {
  group('здоровая сессия', () {
    test('не даёт ни одной находки (защита от ложных срабатываний)', () {
      final view = cleanView();
      expect(view.masteryBefore, isNotEmpty,
          reason: 'здоровая фикстура обязана быть полной: без снимка «до» '
              'checkMasteryDelta честно выдаёт info, и строгая проверка '
              'перестала бы что-то защищать');
      final findings = runSessionChecks(view);

      expect(findings, isEmpty,
          reason: 'согласованная сессия не должна попадать в отчёт:\n'
              '${findings.map((f) => f.toString()).join('\n')}');
      expect(summarizeFindings(findings).hasProblems, isFalse);
    });

    test('пустая сессия даёт ровно одну info-находку про mastery', () {
      // `SessionView()` без данных — это «сессия, из которой ничего не
      // прочиталось». Ожидаемый контракт: не падать и честно сказать, что
      // дельту mastery проверить нечем.
      final findings = runSessionChecks(const SessionView(topicName: ''));

      expect(tagsOf(findings), <String>['session_mastery_delta/info']);
      expect(findings.single.message, contains('дельту проверить нечем'));
    });
  });

  group('session_activity_node_unknown', () {
    test('активность на узле вне плана → fail', () {
      final findings = runSessionChecks(cleanView(
        plannedNodeIds: const <String>['n1'],
        activities: const <SessionActivityView>[
          SessionActivityView(nodeId: 'n-пришелец', nodeLabel: 'Пришелец'),
        ],
        questions: const <SessionQuestionView>[],
      ));

      final hit = withCode(findings, SessionCheckCode.activityNodeUnknown);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.nodeId, 'n-пришелец');
      expect(hit.single.data?['knownCount'], 1);
    });

    test('без плана, mastery и вопросов — info, а не fail', () {
      final findings = runSessionChecks(cleanView(
        plannedNodeIds: const <String>[],
        activities: const <SessionActivityView>[
          SessionActivityView(nodeId: 'n1'),
        ],
        questions: const <SessionQuestionView>[],
        // Про узел не знает никто: ни план, ни mastery до/после — это и есть
        // условие ветки «проверить нечем».
        masteryBefore: const <String, double>{},
        masteryAfter: const <String, double>{},
      ));

      final hit = withCode(findings, SessionCheckCode.activityNodeUnknown);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.info);
      expect(hit.single.message, contains('проверить, откуда взялись активности'));
    });

    test('без активностей проверка молчит', () {
      final findings = runSessionChecks(cleanView(activities: const []));
      expect(withCode(findings, SessionCheckCode.activityNodeUnknown), isEmpty);
    });
  });

  group('session_step_mix', () {
    test('только лекция → warn со списком типов', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            nodeLabel: 'Остановка',
            steps: <SessionStepView>[
              SessionStepView(type: kStepExplain, title: 'Лекция'),
              SessionStepView(type: kStepExample, title: 'Пример'),
            ],
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.stepMix);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.data?['stepTypes'], <String>[kStepExplain, kStepExample]);
      expect(hit.single.message, contains('только читает'));
    });

    test('один recall среди explain спасает активность', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(type: kStepExplain, title: 'Лекция'),
              SessionStepView(
                type: kStepRecall,
                title: 'Проверка',
                options: <String>['да', 'нет'],
                correctIndex: 0,
              ),
            ],
          ),
        ],
      ));

      expect(withCode(findings, SessionCheckCode.stepMix), isEmpty);
    });

    test('активность вовсе без шагов → warn с пустым списком типов', () {
      // Загрузчик такую активность выбрасывает (судить о прохождении не по
      // чему), но проверка обязана корректно описывать и такой DTO. Кейс
      // «пустой steps в activity_json» проверяется на загрузчике, здесь
      // фиксируется поведение самой проверки.
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(nodeId: 'n1', nodeLabel: 'Остановка'),
        ],
        questions: const <SessionQuestionView>[],
      ));

      expect(const SessionActivityView(nodeId: 'n1').stepsOfType(kStepRecall), isEmpty);
      expect(tagsOf(findings), <String>['${SessionCheckCode.stepMix}/warn']);
      final hit = withCode(findings, SessionCheckCode.stepMix).single;
      expect(hit.data?['stepTypes'], isEmpty, reason: 'типов шагов нет вообще');
      expect(hit.message, contains('типы: )'),
          reason: 'косметический дефект текста: пустые скобки в сообщении');
    });
  });

  group('session_recall_options', () {
    SessionView viewWithRecall(SessionStepView step) => cleanView(
          activities: <SessionActivityView>[
            SessionActivityView(
                nodeId: 'n1', nodeLabel: 'Остановка', steps: <SessionStepView>[step]),
          ],
          questions: const <SessionQuestionView>[],
        );

    test('вариантов нет → fail', () {
      final findings = runSessionChecks(viewWithRecall(
          const SessionStepView(type: kStepRecall, title: 'Без вариантов')));

      final hit = withCode(findings, SessionCheckCode.recallOptions);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.message, contains('вариантов нет'));
    });

    test('один вариант и пять вариантов → fail (границы 2..4)', () {
      final one = withCode(
        runSessionChecks(viewWithRecall(const SessionStepView(
            type: kStepRecall, title: 'Один', options: <String>['да'], correctIndex: 0))),
        SessionCheckCode.recallOptions,
      );
      final five = withCode(
        runSessionChecks(viewWithRecall(const SessionStepView(
            type: kStepRecall,
            title: 'Пять',
            options: <String>['a', 'b', 'c', 'd', 'e'],
            correctIndex: 0))),
        SessionCheckCode.recallOptions,
      );

      expect(one.single.data?['options'], 1);
      expect(five.single.data?['options'], 5);
      expect(one.single.message, contains('вариантов 1'));
      expect(five.single.message, contains('вариантов 5'));
    });

    test('correctIndex не задан → fail', () {
      final findings = runSessionChecks(viewWithRecall(const SessionStepView(
        type: kStepRecall,
        title: 'Без этала',
        options: <String>['да', 'нет'],
      )));

      expect(withCode(findings, SessionCheckCode.recallOptions).single.message,
          contains('не задан correctIndex'));
    });

    test('correctIndex вне диапазона → fail с числами в data', () {
      final findings = runSessionChecks(viewWithRecall(const SessionStepView(
        type: kStepRecall,
        title: 'Мимо',
        options: <String>['да', 'нет'],
        correctIndex: 3,
      )));

      final hit = withCode(findings, SessionCheckCode.recallOptions);
      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.data?['correctIndex'], 3);
      expect(hit.single.data?['options'], 2);
      expect(hit.single.message, contains('вне диапазона 0..1'));
    });

    test('границы диапазона (2 и 4 варианта) — чисто', () {
      for (final options in <List<String>>[
        <String>['да', 'нет'],
        <String>['a', 'b', 'c', 'd'],
      ]) {
        final findings = runSessionChecks(viewWithRecall(SessionStepView(
          type: kStepRecall,
          title: 'В границах',
          options: options,
          correctIndex: 0,
        )));
        expect(withCode(findings, SessionCheckCode.recallOptions), isEmpty,
            reason: 'вариантов ${options.length} — это норма');
      }
      // Сами пороги обязаны совпадать с объявленными в продакшене.
      expect(kMinRecallOptions, 2);
      expect(kMaxRecallOptions, 4);
    });
  });

  group('session_apply_contract', () {
    SessionView viewWithApply(SessionStepView step) => cleanView(
          activities: <SessionActivityView>[
            SessionActivityView(
                nodeId: 'n1', nodeLabel: 'Остановка', steps: <SessionStepView>[step]),
          ],
          questions: const <SessionQuestionView>[],
        );

    test('нет инструкции и этала → две fail-находки', () {
      final findings = runSessionChecks(
          viewWithApply(const SessionStepView(type: kStepApply, title: 'Голый apply')));

      final hit = withCode(findings, SessionCheckCode.applyContract);
      expect(hit, hasLength(2));
      expect(hit.map((f) => f.severity), everyElement(FindingSeverity.fail));
      expect(hit.first.message, contains('пустая инструкция'));
      expect(hit.last.message, contains('нет эталонного ответа'));
    });

    test('инструкция из пробелов считается пустой', () {
      final findings = runSessionChecks(viewWithApply(const SessionStepView(
        type: kStepApply,
        title: 'Пробелы',
        instruction: '   ',
        bestAnswer: 'эталон есть',
      )));

      expect(withCode(findings, SessionCheckCode.applyContract), hasLength(1));
    });

    test('есть и инструкция, и этал → чисто', () {
      expect(withCode(runSessionChecks(viewWithApply(goodApply)), SessionCheckCode.applyContract),
          isEmpty);
    });
  });

  group('session_apply_degenerate', () {
    test('этал дословно повторяет инструкцию → warn', () {
      const text = 'Объясни своими словами что такое остановка';
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(
                type: kStepApply,
                title: 'Этал = инструкция',
                instruction: text,
                bestAnswer: text,
              ),
            ],
          ),
        ],
        questions: const <SessionQuestionView>[],
      ));

      final hit = withCode(findings, SessionCheckCode.applyDegenerate);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.message, contains('дословно совпадает с инструкцией'));
    });

    test('серия apply с ответом = этал → warn с maxRun', () {
      final findings = runSessionChecks(cleanView(
        activities: <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              for (var i = 0; i < kApplyEchoRun; i++)
                SessionStepView(
                  type: kStepApply,
                  title: 'Задача $i',
                  instruction: 'Сформулируй определение остановки',
                  bestAnswer: 'Программа не завершится за конечное время',
                  userAnswer: 'Программа не завершится за конечное время',
                  correct: true,
                  feedback: 'верно',
                ),
            ],
          ),
        ],
        questions: const <SessionQuestionView>[],
      ));

      final hit = withCode(findings, SessionCheckCode.applyDegenerate);
      expect(hit, hasLength(1));
      expect(hit.single.data?['maxRun'], kApplyEchoRun);
      expect(hit.single.message, contains('копипаст'));
      expect(kApplyEchoRun, 3);
    });

    test('серия короче порога — молчим', () {
      final findings = runSessionChecks(cleanView(
        activities: <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              for (var i = 0; i < kApplyEchoRun - 1; i++)
                SessionStepView(
                  type: kStepApply,
                  title: 'Задача $i',
                  instruction: 'Сформулируй определение остановки',
                  bestAnswer: 'Программа не завершится за конечное время',
                  userAnswer: 'Программа не завершится за конечное время',
                  correct: true,
                  feedback: 'верно',
                ),
            ],
          ),
        ],
        questions: const <SessionQuestionView>[],
      ));

      expect(withCode(findings, SessionCheckCode.applyDegenerate), isEmpty);
    });
  });

  group('session_feedback_missing и session_answer_not_scored', () {
    test('отвеченный шаг без фидбека → warn; незаполненный — молчит', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(
                  type: kStepRecall, title: 'Отвечен', userAnswer: 'да', correct: true),
              SessionStepView(type: kStepRecall, title: 'Не отвечен'),
            ],
          ),
        ],
        questions: const <SessionQuestionView>[],
      ));

      final hit = withCode(findings, SessionCheckCode.feedbackMissing);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.message, contains('Отвечен'));
    });

    test('ответ есть, вердикта нет → warn отдельно по шагам и вопросам', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(
                type: kStepApply,
                title: 'Без вердикта',
                instruction: 'Опиши остановку',
                bestAnswer: 'не завершится',
                userAnswer: 'зависнет',
                feedback: 'близко',
              ),
            ],
          ),
        ],
        questions: const <SessionQuestionView>[
          SessionQuestionView(
            nodeId: 'n1',
            question: 'Что такое остановка?',
            options: <String>['да', 'нет'],
            correctIndex: 0,
            userAnswer: 'да',
            feedback: 'верно',
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.answerNotScored);
      expect(hit, hasLength(2));
      expect(hit.every((f) => f.severity == FindingSeverity.warn), isTrue);
      expect(hit.first.message, contains('correct == null'));
      expect(hit.last.message, contains('correct == null'));
    });
  });

  group('session_step_duration', () {
    test('сумма времени в 2.5 бюджета → warn', () {
      final findings = runSessionChecks(cleanView(
        timeBudgetMinutes: 1,
        questions: const <SessionQuestionView>[
          SessionQuestionView(
            nodeId: 'n1',
            question: 'Что такое остановка?',
            correctAnswer: 'остановка',
            userAnswer: 'остановка',
            correct: true,
            timeSpentMs: 150000,
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.stepDuration);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.data?['ratio'], 2.5);
      expect(hit.single.message, contains('2.5x;'));
      expect(kSessionDurationWarnRatio, 2.0);
    });

    test('сумма времени в 6x бюджета → fail', () {
      final findings = runSessionChecks(cleanView(
        timeBudgetMinutes: 1,
        questions: const <SessionQuestionView>[
          SessionQuestionView(
            nodeId: 'n1',
            question: 'Что такое остановка?',
            correctAnswer: 'остановка',
            userAnswer: 'остановка',
            correct: true,
            timeSpentMs: 400000,
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.stepDuration);
      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.message, contains('fail от 5.0x'));
      expect(kSessionDurationFailRatio, 5.0);
    });

    test('абсолютное время вместо длительности → fail и оно исключено из суммы', () {
      // Боевой дефект: UI стартует отсчёт не при показе экрана, поэтому в
      // `time_spent_ms` уезжает DateTime.now().millisecondsSinceEpoch. Такое
      // значение — не «медленно отвечал», и в сумму против бюджета оно не идёт.
      final findings = runSessionChecks(cleanView(
        timeBudgetMinutes: 1,
        questions: const <SessionQuestionView>[
          SessionQuestionView(
            nodeId: 'n1',
            question: 'Что такое остановка?',
            correctAnswer: 'остановка',
            userAnswer: 'остановка',
            correct: true,
            timeSpentMs: 1753128000000,
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.stepDuration);
      expect(hit, hasLength(1), reason: 'битый замер не должен ещё и превышать '
          'бюджет второй находкой');
      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.message, contains('неработающий таймер'));
      expect(hit.single.data?['implausibleQuestions'], 1);
      expect(hit.single.data?['maxPlausibleMs'], kImplausibleAnswerMs);
      expect(kImplausibleAnswerMs, 2 * 60 * 60 * 1000);
    });

    test('отвеченный длинный шаг без замера → warn со списком шагов', () {
      final findings = runSessionChecks(cleanView(
        activities: <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            nodeLabel: 'Остановка',
            steps: <SessionStepView>[
              SessionStepView(
                type: kStepExplain,
                title: 'Длинная лекция',
                body: 'я' * (kLongStepTextChars + 10),
                userAnswer: 'понял',
              ),
              goodRecall,
            ],
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.stepDuration);
      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.data?['silentSteps'], 1);
      expect(hit.single.message, contains('n1#1'));
      expect(hit.single.message, contains('$kLongStepTextChars символов'));
    });

    test('незавершённый длинный шаг — не находка: его не начали, замера нет по сути', () {
      // Раньше шаг с нулём ловился независимо от статуса, поэтому любая живая
      // сессия с непрочитанной лекцией выглядела битой.
      final findings = runSessionChecks(cleanView(
        activities: <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            nodeLabel: 'Остановка',
            isComplete: false,
            steps: <SessionStepView>[
              SessionStepView(
                type: kStepExplain,
                title: 'Длинная лекция',
                body: 'я' * (kLongStepTextChars + 10),
              ),
              goodRecall,
            ],
          ),
        ],
      ));

      expect(withCode(findings, SessionCheckCode.stepDuration), isEmpty);
    });

    test('короткий шаг без замера — не находка', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(type: kStepExplain, title: 'Короткая подсказка', body: 'мало'),
              goodRecall,
            ],
          ),
        ],
      ));

      expect(withCode(findings, SessionCheckCode.stepDuration), isEmpty);
    });
  });

  group('session_completion', () {
    test('план пройден, а сессия осталась активной → info, не warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          status: 'active',
          plannedItemsCompleted: 3,
          plannedItemsTotal: 3,
        )),
        SessionCheckCode.completion,
      );

      expect(hit, hasLength(1));
      // info, а не warn: незакрытая строка сессии в приложении норма, и warn
      // здесь срабатывал бы на каждой здоровой пройденной сессии.
      expect(hit.single.severity, FindingSeverity.info);
      expect(hit.single.message, contains('Все 3'));
      expect(hit.single.message, contains('осталась незакрытой'));
      expect(hit.single.data?['plannedItemsCompleted'], 3);
      expect(hit.single.data?['plannedItemsTotal'], 3);
    });

    test('план в процессе — молчим: незакрытая сессия это норма', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            status: 'active',
            plannedItemsCompleted: 2,
            plannedItemsTotal: 3,
          )),
          SessionCheckCode.completion,
        ),
        isEmpty,
        reason: 'приложение статус сессии не переключает, поэтому незакрытая '
            'сессия — не дефект, а нормальный промежуточный статус',
      );
    });

    test('плана в данных нет — молчим, а не гадаем', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            status: 'active',
            plannedItemsCompleted: 0,
            plannedItemsTotal: 0,
          )),
          SessionCheckCode.completion,
        ),
        isEmpty,
        reason: 'без curriculum_json судить о завершении не по чему',
      );
    });

    test('completed при незакрытом плане — молчим: ранний finalize законен', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            status: kStatusCompleted,
            plannedItemsCompleted: 1,
            plannedItemsTotal: 4,
          )),
          SessionCheckCode.completion,
        ),
        isEmpty,
      );
    });

    test('completed и план пройден — чисто', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            status: kStatusCompleted,
            plannedItemsCompleted: 1,
            plannedItemsTotal: 1,
          )),
          SessionCheckCode.completion,
        ),
        isEmpty,
      );
    });
  });

  group('session_mastery_delta', () {
    // Контракт: рост утверждается ТОЛЬКО когда известно состояние «до». Раньше
    // `before` не читался вовсе, и каждый новый для сессии узел давал warn —
    // на боевых данных это были десятки ложных срабатываний.
    test('нет данных ПОСЛЕ → info', () {
      final hit = withCode(
        runSessionChecks(cleanView(masteryAfter: const <String, double>{})),
        SessionCheckCode.masteryDelta,
      );

      expect(hit.single.severity, FindingSeverity.info);
      expect(hit.single.message, contains('дельту проверить нечем'));
    });

    test('снимка ДО нет, а ПОСЛЕ есть → ровно одна info, без per-node находок', () {
      final findings = runSessionChecks(cleanView(
        masteryBefore: const <String, double>{},
        masteryAfter: const <String, double>{'n1': 0.625, 'n-прочь': 0.9},
      ));

      expect(tagsOf(findings), <String>['${SessionCheckCode.masteryDelta}/info']);
      final hit = withCode(findings, SessionCheckCode.masteryDelta).single;
      expect(hit.nodeId, isNull, reason: 'находка про данные, а не про узел');
      expect(hit.data, isNull);
      expect(hit.message, contains('Нет снимка мастерства ДО'));
    });

    test('рост на узле вне сессии при известном «до» → warn с before/after', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          masteryBefore: const <String, double>{'n-прочь': 0.2},
          masteryAfter: const <String, double>{'n-прочь': 0.9},
        )),
        SessionCheckCode.masteryDelta,
      );

      expect(hit, hasLength(1));
      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.nodeId, 'n-прочь');
      expect(hit.single.data?['before'], 0.2);
      expect(hit.single.data?['after'], 0.9);
      expect(hit.single.message, contains('0.200 → 0.900'));
      expect(hit.single.message, contains('не было ни в плане'));
    });

    test('узел новый (before == null), но он был в сессии → молчим', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            masteryBefore: const <String, double>{'n-другой': 0.4},
            masteryAfter: const <String, double>{'n1': 0.9},
          )),
          SessionCheckCode.masteryDelta,
        ),
        isEmpty,
        reason: 'без состояния «до» рост не доказан, а узел был в плане',
      );
    });

    test('mastery не выросла (после <= до) → молчим', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            masteryBefore: const <String, double>{'n1': 0.9},
            masteryAfter: const <String, double>{'n1': 0.5},
          )),
          SessionCheckCode.masteryDelta,
        ),
        isEmpty,
      );
    });
  });

  group('session_misconception_without_remediation', () {
    test('мисконцепция без nodeId → warn (данных не хватает)', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          misconceptions: const <String>['Путает остановку с зацикливанием'],
        )),
        SessionCheckCode.misconceptionWithoutRemediation,
      );

      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.data?['count'], 1);
      expect(hit.single.message, contains('без nodeId'));
    });

    test('мисконцепция на узле без активностей → warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          misconceptions: const <String>['Путает остановку с зацикливанием'],
          misconceptionsByNode: const <String, String>{'n-прочь': 'Путает остановку'},
          plannedNodeIds: const <String>[],
          activities: const <SessionActivityView>[],
          questions: const <SessionQuestionView>[],
        )),
        SessionCheckCode.misconceptionWithoutRemediation,
      );

      expect(hit.single.message, contains('активностей по узлу не было вовсе'));
    });

    test('активности без apply → warn: отработки не было', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          misconceptions: const <String>['Путает остановку с зацикливанием'],
          misconceptionsByNode: const <String, String>{'n1': 'Путает остановку'},
          activities: const <SessionActivityView>[
            SessionActivityView(nodeId: 'n1', steps: <SessionStepView>[goodRecall]),
          ],
        )),
        SessionCheckCode.misconceptionWithoutRemediation,
      );

      expect(hit.single.data?['activities'], 1);
      expect(hit.single.message, contains('без apply-шага'));
    });

    test('активность с apply на узле мисконцепции → чисто', () {
      expect(
        withCode(
          runSessionChecks(cleanView(
            misconceptions: const <String>['Путает остановку с зацикливанием'],
            misconceptionsByNode: const <String, String>{'n1': 'Путает остановку'},
          )),
          SessionCheckCode.misconceptionWithoutRemediation,
        ),
        isEmpty,
      );
    });
  });

  group('session_question_shallow', () {
    test('закрытый вопрос без фидбека → warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'recall',
              question: 'Что такое остановка?',
              options: <String>['да', 'нет'],
              correctIndex: 0,
              userAnswer: 'да',
              correct: true,
            ),
          ],
        )),
        SessionCheckCode.questionShallow,
      );

      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.message, contains('нет фидбека'));
    });

    test('фидбек без цитаты варианта и без оценочной связки → warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'recall',
              question: 'Что такое остановка?',
              options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
              correctIndex: 0,
              userAnswer: 'Верно: останавливается',
              correct: true,
              feedback: 'Ну вот как-то так',
            ),
          ],
        )),
        SessionCheckCode.questionShallow,
      );

      expect(hit.single.message, contains('фидбек не объясняет правильный вариант'));
    });

    test('открытый вопрос без эталона → warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'application',
              question: 'Приведи пример вечной программы.',
              userAnswer: 'busy wait',
              correct: true,
              feedback: 'хороший пример',
            ),
          ],
        )),
        SessionCheckCode.questionShallow,
      );

      expect(hit.single.message, contains('без эталонного ответа'));
    });

    test('оценочная связка из продакшена засчитывается как пояснение', () {
      // Связка должна совпасть ПОЛНОСТЬЮ: «потому что» — да, «потому» — нет.
      expect(
        withCode(
          runSessionChecks(cleanView(
            questions: const <SessionQuestionView>[
              SessionQuestionView(
                nodeId: 'n1',
                type: 'recall',
                question: 'Что такое остановка?',
                options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
                correctIndex: 0,
                userAnswer: 'Верно: останавливается',
                correct: true,
                feedback: 'Ответ принят, потому что это определение остановки',
              ),
            ],
          )),
          SessionCheckCode.questionShallow,
        ),
        isEmpty,
      );
    });

    test('усечённая связка «потому» пояснением не считается', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'recall',
              question: 'Что такое остановка?',
              options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
              correctIndex: 0,
              userAnswer: 'Верно: останавливается',
              correct: true,
              feedback: 'Ответ принят, потому остановка и есть остановка',
            ),
          ],
        )),
        SessionCheckCode.questionShallow,
      );

      expect(hit, hasLength(1));
    });
  });

  group('session_question_shallow: зафиксированный дефект', () {
    test('этал не из вариантов + оценочная связка → проверка молчит', () {
      // Комментарий в коде проверки обещает, что связка («верно», «потому что»)
      // засчитывается как пояснение «только если вариант известен». На деле
      // условие `option != null` не проверяется: вопрос, у которого
      // `correctAnswer` не совпал ни с одним вариантом (loader вернул
      // `correctIndex == null`), проходит с любым фидбеком вида «верно».
      // Зафиксировано как есть — правка нужна в `checkQuestionDepth`.
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'recall',
              question: 'Что такое остановка?',
              options: <String>['да', 'нет'],
              correctAnswer: 'возможно',
              correctIndex: null,
              userAnswer: 'да',
              correct: true,
              feedback: 'верно',
            ),
          ],
        )),
        SessionCheckCode.questionShallow,
      );

      expect(hit, isEmpty);
    });
  });

  group('session_progression', () {
    test('4 шага одного типа → info с порядком типов', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(type: kStepExplain, title: 'Лекция 1'),
              SessionStepView(type: kStepExplain, title: 'Лекция 2'),
              SessionStepView(type: kStepExplain, title: 'Лекция 3'),
              SessionStepView(type: kStepExplain, title: 'Лекция 4'),
            ],
          ),
        ],
      ));

      final hit = withCode(findings, SessionCheckCode.progression);
      expect(hit.single.severity, FindingSeverity.info);
      expect(hit.single.data?['repeats'], 3);
      expect(hit.single.data?['transitions'], 3);
      expect(hit.single.message, contains('100%'));
      expect(kMinStepsForProgression, 4);
      expect(kMaxSameTypeRunRatio, 0.6);
    });

    test('трёх шагов мало для вывода о повторах', () {
      final findings = runSessionChecks(cleanView(
        activities: const <SessionActivityView>[
          SessionActivityView(
            nodeId: 'n1',
            steps: <SessionStepView>[
              SessionStepView(type: kStepExplain, title: 'Лекция 1'),
              SessionStepView(type: kStepExplain, title: 'Лекция 2'),
              SessionStepView(type: kStepExplain, title: 'Лекция 3'),
            ],
          ),
        ],
      ));

      expect(withCode(findings, SessionCheckCode.progression), isEmpty);
    });
  });

  group('session_score_mismatch', () {
    test('балл расходится с долей верных попыток → warn', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          assessments: const <AssessmentScoreView>[
            AssessmentScoreView(
              type: 'quiz',
              recordedScore: 0.9,
              attempts: 3,
              correctAttempts: 2,
            ),
          ],
        )),
        SessionCheckCode.scoreMismatch,
      );

      expect(hit.single.severity, FindingSeverity.warn);
      expect(hit.single.message, contains('0.90'));
    });

    test('балл в пределах допуска → без находки', () {
      expect(
        runSessionChecks(cleanView(
          assessments: const <AssessmentScoreView>[
            AssessmentScoreView(
              type: 'quiz',
              recordedScore: 0.7,
              attempts: 3,
              correctAttempts: 2,
            ),
          ],
        )),
        isEmpty,
      );
    });

    test('попыток нет, а балл записан → warn: сверить нечего', () {
      final hit = withCode(
        runSessionChecks(cleanView(
          assessments: const <AssessmentScoreView>[
            AssessmentScoreView(type: 'quiz', recordedScore: 0.8),
          ],
        )),
        SessionCheckCode.scoreMismatch,
      );

      expect(hit.single.message, contains('попыток'));
    });
  });

  group('session_verdict_contradicts_answer', () {
    test('ответ равен эталону, а попытка «неверно» → fail', () {
      // Кейс из архива сессии: правильный ответ помечен как ошибка, из-за чего
      // mastery и мисконцепции считают ученика неуспешным на ровном месте.
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: kStepRecall,
              question: 'Что такое остановка?',
              options: <String>['Верно: останавливается', 'Неверно: работает вечно'],
              correctAnswer: 'Верно: останавливается',
              correctIndex: 0,
              userAnswer: 'Верно: останавливается',
              correct: false,
              feedback: 'Ну вот как-то так',
            ),
          ],
        )),
        SessionCheckCode.verdictContradictsAnswer,
      );

      expect(hit.single.severity, FindingSeverity.fail);
      expect(hit.single.message, contains('правильным вариантом'));
      expect(hit.single.nodeId, 'n1');
    });

    test('ответ совпал с текстом правильного варианта → тоже fail', () {
      // `correctAnswer` в базе может быть пустым, а совпадение идёт по тексту
      // варианта с correctIndex.
      final hit = withCode(
        checkVerdictConsistency(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: kStepRecall,
              question: 'Что такое остановка?',
              options: <String>['останавливается', 'работает вечно'],
              correctIndex: 0,
              userAnswer: 'останавливается',
              correct: false,
            ),
          ],
        )),
        SessionCheckCode.verdictContradictsAnswer,
      );

      expect(hit, isNotEmpty);
    });

    test('открытый вопрос без этала не считается противоречием', () {
      // Вердикт по открытому ответу может быть rubric-оценкой — сравнивать
      // тексты здесь нельзя, иначе будут ложные срабатывания.
      final hit = withCode(
        runSessionChecks(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: 'application',
              question: 'Постройте пример остановки.',
              correctAnswer: 'любой корректный пример',
              userAnswer: 'любой корректный пример',
              correct: false,
              feedback: 'Ответ верный по смыслу, но не развёрнут.',
            ),
          ],
        )),
        SessionCheckCode.verdictContradictsAnswer,
      );

      expect(hit, isEmpty);
    });

    test('correctIndex за границами вариантов → без падения и без находки', () {
      // Битые данные не должны ронять ревью - ровно то, что мы чинили в
      // загрузчике, нельзя reintroduce в проверках.
      final hit = withCode(
        checkVerdictConsistency(cleanView(
          questions: const <SessionQuestionView>[
            SessionQuestionView(
              nodeId: 'n1',
              type: kStepRecall,
              question: 'Что такое остановка?',
              options: <String>['останавливается', 'работает вечно'],
              correctIndex: 7,
              userAnswer: 'останавливается',
              correct: false,
            ),
          ],
        )),
        SessionCheckCode.verdictContradictsAnswer,
      );

      expect(hit, isEmpty);
    });

    test('здоровый вердикт не даёт находок', () {
      expect(checkVerdictConsistency(cleanView()), isEmpty);
    });
  });

  group('детерминизм', () {
    test('два вызова на одном входе дают идентичный список находок', () {
      final view = dirtyView();
      final first = runSessionChecks(view);
      final second = runSessionChecks(view);

      expect(
        <Map<String, dynamic>>[for (final f in second) f.toJson()],
        <Map<String, dynamic>>[for (final f in first) f.toJson()],
      );
      expect(jsonEncode(<Object>[for (final f in second) f.toJson()]),
          jsonEncode(<Object>[for (final f in first) f.toJson()]));
    });

    test('находки отсортированы по коду, затем по узлу', () {
      final findings = runSessionChecks(dirtyView());
      final codes = codesOf(findings);

      expect(codes, <String>[...codes]..sort());
      expect(findings.length, greaterThan(3),
          reason: 'грязная сессия обязана дать несколько находок разных проверок');
    });

    test('точка входа = все проверки + стабильная сортировка', () {
      // Ни одна проверка не теряется и не дублируется на пути к отчёту.
      final view = dirtyView();
      final throughEntryPoint = runSessionChecks(view);
      final direct = sortedFindings(everyCheck(view));

      expect(
        <Map<String, dynamic>>[for (final f in throughEntryPoint) f.toJson()],
        <Map<String, dynamic>>[for (final f in direct) f.toJson()],
      );
    });

    test('грязная сессия даёт и fail, и warn', () {
      final summary = summarizeFindings(runSessionChecks(dirtyView()));

      expect(summary.fail, greaterThan(0));
      expect(summary.warn, greaterThan(0));
      expect(summary.hasProblems, isTrue);
      expect(summary.hasFailures, isTrue);
      expect(summary.rankMax, FindingSeverity.fail.rank);
    });

    test('info появляется ровно там, где данных не хватает', () {
      // Нет mastery «после» — единственная находка должна быть info, и никаких
      // warn/fail: неполные данные не должны выглядеть как плохое обучение.
      final summary = summarizeFindings(
          runSessionChecks(cleanView(masteryAfter: const <String, double>{})));

      expect(summary.info, 1);
      expect(summary.warn, 0);
      expect(summary.fail, 0);
      expect(summary.hasProblems, isFalse);
    });
  });
}