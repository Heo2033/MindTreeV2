// Регрессии безопасной обрезки `one_liner` (инвариант AGENTS.md: <= 120).
//
// Исходный дефект: обрезка по границе слова оставляла висящие служебные слова —
// «описание прямого и обратного процессов как», «сигнала x̂_0, предсказание».
// Слово целое, синтаксис разрушен; пользователь видел это в экспорте темы
// (`lib/data/io/topic_file.dart`).
//
// Этими же тестами были зафиксированы и два последующих дефекта (теперь
// исправлены в проде):
//  1. обрезка по границе предложения теряла завершающий знак — теперь `.`/`!`/`?`
//     входит в результат;
//  2. результат мог оказаться пустым (вход из одной пунктуации) — теперь
//     гарантированно непустой; НЕ покрыт случай, когда тело куска состоит
//     только из пробелов (см. тест с пробелами ниже).
//  3. жёсткий срез (внутри лимита нет ни одной границы) больше не снимает
//     пунктуацию с хвоста.
//
// Тесты детерминированные: LLM не участвует, вход → ожидаемый выход. Логика
// обрезки в тесте НЕ дублируется — проверяется экспорт движка.
// Зеркало: `server/src/domain/KnowledgeGraphEngine.ts`, тесты —
// `server/src/domain/__tests__/knowledgeGraph.test.ts`. Таблица [_golden]
// продублирована там 1:1: расхождение строк означает разъезд стеков.

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart'
    show enforceOneLinerLimit, oneLinerMaxChars, truncateOneLiner;

/// Порог пригодности границы: 60% лимита. Границы раньше порога игнорируются,
/// обрезка идёт дальше по тексту (иначе фраза стала бы нечитаемой).
final int _boundaryFloor = (oneLinerMaxChars * 0.6).floor();

// --- Фикстуры --------------------------------------------------------------

/// Описание, из которого на живом прогоне остался хвост «…процессов как».
const String _danglingHead = 'Ключевая идея состоит в описании прямого и обратного процессов преобразования сигнала во времени';

/// Длинный «токен» после хвоста: внутри лимита нет ни границ, ни пробелов.
const String _longToken = 'псевдослучайнойпоследовательности';

/// Регресс из бага целиком. Сразу после `как` идёт длинное слово, поэтому
/// граница слова съедает ровно `… как`, и без снятия хвоста пользователь получил
/// бы «…преобразования сигнала во времени как».
const String _danglingTailBug =
    '$_danglingHead как $_longToken и применение в теории сигналов';

/// Регресс «сигнала x̂_0, предсказание»: запятая перед последним словом.
/// `x\u0302_0` — это x с комбинирующим знаком чётности (U+0302): именно такой
/// вид строки приходил с живого прогона.
const String _signalBug = 'Практика показывает что средняя ошибка оценки '
    'сигнала x̂_0 зависит от длины выборки, предсказание достигается '
    'обучением на длинных последовательностях';

/// Граница клаузы (запятая на позиции 95) важнее границы слова (пробел на 119).
const String _clauseBug = 'Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу, добавляя шум на каждом шаге обучения';

/// Тот же текст без запятой: остаётся только граница слова.
const String _wordOnly = 'Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу добавляя шум на каждом шаге обучения';

/// Полное предложение с точкой; после него — ещё текст без точек.
const String _sentenceFirst = 'Теорема остановки говорит, что любая детерминированная программа рано или поздно остановится.';
const String _sentenceTail = ' Применяется к автоматам, стековым машинам и всей теории вычислимости';
const String _sentenceBug = '$_sentenceFirst$_sentenceTail';

/// То же предложение без завершающего знака — тело для знаков `.`/`!`/`?`.
final String _sentenceBody =
    _sentenceFirst.substring(0, _sentenceFirst.length - 1);

/// Хвост из служебного союза и приклеенного тире: «…остановится— и применяется».
const String _dashTail = 'Теорема остановки это утверждение о том что любая детерминированная программа рано или поздно остановится— и применяется к автоматам';

/// Ранняя точка (позиция 6 — ниже порога) игнорируется: режем по последнему
/// пробелу, а висящий предлог «на» с хвоста снимается.
const String _earlySentence = 'Кратко. Диффузионная модель постепенно учится восстанавливать исходную картинку по зашумлённому сигналу и обучается на шуме';

/// Основа для каскада: заканчивается точкой «… слово и как.».
const String _cascadeHead = 'Базовое определение термина фиксирует минимальный набор требований к описанию предмета';
const String _cascadeTail = ' Далее идут уточнения и примеры применения в задачах';

/// Каскад со знаком конца: снимаются оба служебных слова, знак сохраняется.
const String _cascadeDot = '$_cascadeHead слово и как.$_cascadeTail';

/// Каскад с запятой: знак клаузы — висящая пунктуация, он снимается и НЕ
/// восстанавливается (в отличие от знака конца предложения).
const String _cascadeComma = '$_cascadeHead слово и как,$_cascadeTail';

/// Шапка жёсткого среза: последний пробел на позиции 71 — ниже порога
/// пригодности границы, поэтому внутри лимита не остаётся ни одной границы.
const String _hardCutHead =
    'Описание понятия задаёт базовый смысл темы и требует понимания причин и ';

/// Токен без пробелов, дотягивающийся до последнего символа лимита.
const String _hardCutToken =
    'псевдослучайнаяпоследовательностьсгенерированнаяскрытымсостоянием';

const String _hardCutBug = '$_hardCutHead$_hardCutToken хвост';

/// Тот же жёсткий срез, у которого последний символ внутри лимита — [tailMark].
/// Знак стоит ровно на позиции 119: он уже не образует границу (следующего
/// пробела внутри лимита нет), но раньше снимался как хвостовая пунктуация.
String _hardCutWith(String tailMark) {
  const String tokenBase = 'псевдослучайнаяпоследовательность_';
  final String token =
      tokenBase.padRight(oneLinerMaxChars - _hardCutHead.length - 1, 'я');
  return '$_hardCutHead$token$tailMark хвост';
}

/// Знаки конца предложения: в отличие от клаузной пунктуации они входят
/// в результат.
const List<String> _terminalMarks = <String>['.', '!', '?'];

/// Пунктуация, которая не должна оставаться в хвосте никогда.
const List<String> _danglingPunctChars = <String>[
  ',', ';', ':', '—', '–', '-', ' ', '»', ')', ']', "'", '"',
];

/// Служебные слова, которые не должны оказываться перед знаком конца.
const List<String> _serviceTailWords = <String>[
  'как', 'и', 'в', 'во', 'на', 'по', 'за', 'от', 'до', 'об', 'о', 'у', 'к',
  'ко', 'с', 'со', 'для', 'при', 'через', 'а', 'но', 'же', 'бы', 'то', 'ли',
  'что', 'чтобы', 'так', 'тем', 'где', 'не', 'ни', 'да',
];

/// Фикстуры для «свойственных» проверок (инварианты, а не конкретный текст).
const List<String> _fixtures = <String>[
  _danglingTailBug,
  _signalBug,
  _clauseBug,
  _wordOnly,
  _sentenceBug,
  _cascadeDot,
  _cascadeComma,
  _dashTail,
  _earlySentence,
  _hardCutBug,
  'Короткое описание темы.',
];

/// Строка ровно [length] символов из обычных слов: ни границ, ни служебных
/// хвостов — для чистой проверки инварианта длины.
String _ofLength(int length) {
  var s = 'тема';
  var i = 0;
  while (s.length < length) {
    s = '$s часть$i';
    i++;
  }
  if (s.length > length) {
    final head = s.substring(0, length);
    final lastSpace = head.lastIndexOf(' ');
    s = lastSpace > 0 ? head.substring(0, lastSpace) : head;
  }
  while (s.length < length) {
    s = '$sя';
  }
  return s;
}

/// Золотая таблица: [вход, ожидаемый результат]. Продублирована 1:1 в
/// `server/src/domain/__tests__/knowledgeGraph.test.ts` — строки обязаны
/// совпадать, иначе Flutter и server разошлись.
final List<List<String>> _golden = <List<String>>[
  <String>[_danglingTailBug, _danglingHead],
  <String>[
    _signalBug,
    'Практика показывает что средняя ошибка оценки сигнала '
        'x̂_0 зависит от длины выборки',
  ],
  <String>[
    _clauseBug,
    'Диффузионная модель учится постепенно восстанавливать исходную '
        'картинку по зашумлённому сигналу',
  ],
  <String>[
    _wordOnly,
    'Диффузионная модель учится постепенно восстанавливать исходную '
        'картинку по зашумлённому сигналу добавляя шум на каждом',
  ],
  <String>[_sentenceBug, _sentenceFirst],
  <String>[_cascadeDot, '$_cascadeHead слово.'],
  <String>[_cascadeComma, '$_cascadeHead слово'],
  <String>[
    _dashTail,
    'Теорема остановки это утверждение о том что любая '
        'детерминированная программа рано или поздно остановится',
  ],
  <String>[
    _earlySentence,
    'Кратко. Диффузионная модель постепенно учится восстанавливать '
        'исходную картинку по зашумлённому сигналу и обучается',
  ],
  <String>[_hardCutBug, _hardCutBug.substring(0, oneLinerMaxChars)],
  <String>[
    ',' * (oneLinerMaxChars + 1),
    ',' * (oneLinerMaxChars - 1),
  ],
  <String>[_hardCutWith(';'), _hardCutWith(';').substring(0, oneLinerMaxChars)],
  <String>['Короткое описание темы.', 'Короткое описание темы.'],
];

void main() {
  group('truncateOneLiner: инвариант длины', () {
    test('результат всегда <= oneLinerMaxChars на разной длине входа', () {
      for (final length in const <int>[100, 119, 120, 121, 200, 500]) {
        expect(truncateOneLiner(_ofLength(length)).length,
            lessThanOrEqualTo(oneLinerMaxChars),
            reason: 'вход длиной $length символов');
      }
    });

    test('результат <= oneLinerMaxChars на каждой длине от 0 до 520', () {
      for (var length = 0; length <= 520; length++) {
        expect(truncateOneLiner(_ofLength(length)).length,
            lessThanOrEqualTo(oneLinerMaxChars),
            reason: 'вход длиной $length символов');
      }
    });

    test('результат — префикс входа и без хвостовых пробелов', () {
      for (var length = 0; length <= 520; length++) {
        final input = _ofLength(length);
        final out = truncateOneLiner(input);
        expect(input, startsWith(out), reason: 'вход длиной $length');
        expect(out, out.trimRight(), reason: 'вход длиной $length');
      }
    });

    test('лимит соблюдается для любого переданного maxChars', () {
      final input = _ofLength(400);
      for (final maxChars in const <int>[0, 1, 10, 30, 60, 72, 100, 120, 200]) {
        expect(truncateOneLiner(input, maxChars: maxChars).length,
            lessThanOrEqualTo(maxChars),
            reason: 'maxChars=$maxChars');
      }
    });

    test('знак конца не выводит результат за лимит', () {
      // Гарантия `_finalizeTruncation`: знак дописывается только при
      // out.length + 1 <= maxChars. Отрицательная ветка математически
      // недостижима (тело обрезки всегда короче лимита хотя бы на символ,
      // чистка только укорачивает), поэтому проверяем сам инвариант.
      for (final fixture in _fixtures) {
        for (var maxChars = 0; maxChars <= 200; maxChars++) {
          final String out = truncateOneLiner(fixture, maxChars: maxChars);
          expect(out.length, lessThanOrEqualTo(maxChars),
              reason: 'maxChars=$maxChars, результат «$out»');
          if (out.isNotEmpty && _terminalMarks.contains(out[out.length - 1])) {
            expect(out.substring(0, out.length - 1).trim(), isNotEmpty,
                reason: 'знак конца не должен составлять весь результат');
          }
        }
      }
    });

    test('повторный вызов ничего не меняет', () {
      for (final fixture in _fixtures) {
        final once = truncateOneLiner(fixture);
        expect(truncateOneLiner(once), once,
            reason: 'второй вызов изменил результат: «$once»');
      }
    });
  });

  group('короткие входы не обрезаются', () {
    test('предложение короче лимита возвращается без изменений', () {
      const String input =
          'Диффузионная модель восстанавливает картинку из шума шаг за шагом.';
      expect(input.length, lessThan(oneLinerMaxChars));
      expect(truncateOneLiner(input), input);
    });

    test('строка ровно в 120 символов не обрезается', () {
      final input = _ofLength(120);
      expect(input.length, oneLinerMaxChars);
      expect(truncateOneLiner(input), input);
    });

    test('строка в 120 символов с хвостом «как» тоже не трогается', () {
      // Чистка хвоста — часть процесса усечения; без обрезки не вмешиваемся.
      final String input = '${_wordOnly.substring(0, oneLinerMaxChars - 4)} как';
      expect(input.length, oneLinerMaxChars);
      expect(input, endsWith('как'));
      expect(truncateOneLiner(input), input);
    });

    test('пустая строка и строка из пробелов не падают', () {
      expect(truncateOneLiner(''), '');
      expect(truncateOneLiner('   '), '   ');
    });
  });

  group('выбор границы', () {
    test('граница предложения важнее границы слова, знак конца входит в '
        'результат', () {
      final String out = truncateOneLiner(_sentenceBug);
      expect(out, _sentenceFirst);
      expect(out, endsWith('остановится.'));
      expect(out.length, lessThan(oneLinerMaxChars));
    });

    for (final String mark in _terminalMarks) {
      test('обрезка по границе предложения сохраняет знак «$mark»', () {
        final String input = '$_sentenceBody$mark$_sentenceTail';
        final String out = truncateOneLiner(input);
        expect(out, '$_sentenceBody$mark');
        expect(out, endsWith(mark));
        expect(out.length, _sentenceBody.length + 1);
        expect(out.length, lessThanOrEqualTo(oneLinerMaxChars));
      });
    }

    test('граница предложения важнее границы клаузы', () {
      final String out = truncateOneLiner(_sentenceBug);
      final int commaInTail = _sentenceBug.indexOf(',', _sentenceFirst.length);
      expect(commaInTail, greaterThan(_boundaryFloor));
      expect(out.length, lessThan(commaInTail),
          reason: 'режем по точке предложения, а не по запятой в хвосте');
    });

    test('граница клаузы важнее границы слова', () {
      final int commaAt = _clauseBug.indexOf(',');
      expect(commaAt, greaterThan(_boundaryFloor));
      expect(
        _clauseBug.substring(0, oneLinerMaxChars).lastIndexOf(' '),
        119,
        reason: 'фикстура: граница слова была бы на позиции 119',
      );
      final String out = truncateOneLiner(_clauseBug);
      expect(out, _clauseBug.substring(0, commaAt));
      expect(out, endsWith('сигналу'));
      expect(out.length, lessThan(119));
    });

    test('при отсутствии границ обрезка идёт по последнему пробелу', () {
      final int lastSpace =
          _wordOnly.substring(0, oneLinerMaxChars).lastIndexOf(' ');
      expect(lastSpace, greaterThan(_boundaryFloor));
      expect(
        truncateOneLiner(_wordOnly),
        'Диффузионная модель учится постепенно восстанавливать исходную '
        'картинку по зашумлённому сигналу добавляя шум на каждом',
      );
      expect(truncateOneLiner(_wordOnly).length, lastSpace);
    });

    test('ранняя точка (ниже порога) игнорируется', () {
      expect(_earlySentence.indexOf('.'), lessThanOrEqualTo(_boundaryFloor));
      final String out = truncateOneLiner(_earlySentence);
      expect(
        out,
        'Кратко. Диффузионная модель постепенно учится восстанавливать '
        'исходную картинку по зашумлённому сигналу и обучается',
      );
      // Точка внутри строки остаётся: граница предложения здесь не выбрана.
      expect(out, startsWith('Кратко. '));
      // Хвост «…на шуме» срезан по пробелу, висящий предлог «на» снят.
      expect(out, isNot(endsWith(' на')));
    });

    test('жёсткий срез по лимиту, если после порога нет ни границ, ни пробелов',
        () {
      expect(
        _hardCutBug.substring(0, oneLinerMaxChars).lastIndexOf(' '),
        71,
        reason: 'фикстура: последний пробел ниже порога $_boundaryFloor',
      );
      final String out = truncateOneLiner(_hardCutBug);
      expect(out.length, oneLinerMaxChars);
      expect(out, _hardCutBug.substring(0, oneLinerMaxChars));
    });

    for (final String mark in const <String>[';', ':', '»', ')', '—']) {
      test('жёсткий срез сохраняет знак «$mark» на хвосте', () {
        final String input = _hardCutWith(mark);
        expect(
          input.substring(0, oneLinerMaxChars).lastIndexOf(' '),
          71,
          reason: 'фикстура: последний пробел ниже порога $_boundaryFloor',
        );
        final String out = truncateOneLiner(input);
        expect(out, input.substring(0, oneLinerMaxChars));
        expect(out, endsWith(mark));
        expect(out.length, oneLinerMaxChars);
      });
    }
  });

  group('висящие служебные слова и пунктуация', () {
    test('регресс: «…процессов как» — хвост «как» снят', () {
      final String out = truncateOneLiner(_danglingTailBug);
      expect(out, _danglingHead);
      expect(out, isNot(endsWith('как')));
      expect(out, isNot(endsWith(' как')));
      expect(out.length, lessThanOrEqualTo(oneLinerMaxChars));
    });

    test('регресс: «сигнала x̂_0, предсказание» — хвост снят по запятой', () {
      final String out = truncateOneLiner(_signalBug);
      expect(out, _signalBug.substring(0, _signalBug.indexOf(',')));
      expect(out, isNot(endsWith('предсказание')));
      expect(out, endsWith('выборки'));
    });

    for (final String punct in _terminalMarks) {
      test('каскад «… слово и как$punct»: оба слова сняты, знак сохранён', () {
        final String input = '$_cascadeHead слово и как$punct$_cascadeTail';
        final String out = truncateOneLiner(input);
        expect(out, '$_cascadeHead слово$punct');
        expect(out, isNot(endsWith('как')));
        expect(out, isNot(endsWith(' и')));
        expect(out, endsWith(punct));
      });
    }

    test('знак клаузы после каскада не восстанавливается', () {
      final String out = truncateOneLiner(_cascadeComma);
      expect(out, '$_cascadeHead слово');
      expect(out, isNot(endsWith(',')));
    });

    test('регистр хвоста не важен: «КАК» тоже снимается', () {
      final String input = '$_danglingHead КАК $_longToken и применение';
      expect(truncateOneLiner(input), _danglingHead);
    });

    test('тире и союз на хвосте снимаются вместе', () {
      final String out = truncateOneLiner(_dashTail);
      expect(
        out,
        'Теорема остановки это утверждение о том что любая '
        'детерминированная программа рано или поздно остановится',
      );
      expect(out, isNot(endsWith('—')));
      expect(out, isNot(endsWith(' и')));
    });

    test('обычное слово на хвосте не выбрасывается', () {
      // Защита от обратной ошибки: чистка не должна съедать содержание.
      final String out = truncateOneLiner(_wordOnly);
      expect(out, endsWith('каждом'));
      expect(out.length, 118);
      expect(out.length, greaterThan(_boundaryFloor));
    });

    test('хвост не заканчивается клаузной пунктуацией или пробелом', () {
      // `.`/`!`/`?` — законные знаки конца предложения, их проверяет отдельный
      // тест; в клаузной позиции такая пунктуация снимается всегда.
      for (final String fixture in _fixtures) {
        if (fixture.length <= oneLinerMaxChars) continue;
        final String out = truncateOneLiner(fixture);
        for (final String ch in _danglingPunctChars) {
          expect(out.endsWith(ch), isFalse,
              reason: 'хвост «$ch» в результате: «${out.substring(out.length > 30 ? out.length - 30 : 0)}»');
        }
      }
    });

    test('знак конца предложения не прячет висящее служебное слово', () {
      final List<String> marked = _fixtures
          .map(truncateOneLiner)
          .where((String s) => s.isNotEmpty && _terminalMarks.contains(s[s.length - 1]))
          .toList();
      expect(marked, isNotEmpty,
          reason: 'нужен хотя бы один результат со знаком конца');
      for (final String out in marked) {
        final String body = out.substring(0, out.length - 1);
        final int lastSpace = body.lastIndexOf(' ');
        final String lastWord =
            (lastSpace >= 0 ? body.substring(lastSpace + 1) : body).toLowerCase();
        expect(_serviceTailWords.contains(lastWord), isFalse,
            reason: 'перед знаком конца висящее слово «$lastWord» в «$out»');
      }
    });
  });

  group('дегенератные входы и детерминированность', () {
    test('результат непустой для входа из одной пунктуации', () {
      final Map<String, String> cases = <String, String>{
        'запятые': ',' * (oneLinerMaxChars + 1),
        'точки': '.' * (oneLinerMaxChars + 10),
        'точки с запятой': ';' * 200,
        'тире': '—' * 200,
      };
      cases.forEach((String label, String input) {
        final String out = truncateOneLiner(input);
        expect(out, isNotEmpty, reason: '$label: результат не должен быть пустым');
        expect(out.length, lessThanOrEqualTo(oneLinerMaxChars), reason: label);
        expect(input, startsWith(out), reason: label);
      });
      // Запятая — единственный случай, когда кусок короче лимита на символ:
      // граница клаузы съела последнюю запятую, чистка съела всё, и вернулся
      // необработанный кусок.
      expect(truncateOneLiner(',' * (oneLinerMaxChars + 1)),
          ',' * (oneLinerMaxChars - 1));
      // Точки идут по ветке границы предложения: знак конца возвращается.
      expect(truncateOneLiner('.' * (oneLinerMaxChars + 10)),
          '.' * oneLinerMaxChars);
    });

    test('известный пробел: строка из одних пробелов остаётся пустой', () {
      // Гарантия непустоты не покрывает тело, состоящее только из пробелов:
      // `trimRight` даёт пустую строку, и fallback не срабатывает. Не-пустота
      // здесь — не инвариант, тест фиксирует фактическое поведение.
      expect(truncateOneLiner(' ' * 200), isEmpty);
      expect(truncateOneLiner('\t' * 300), isEmpty);
    });

    test('короткий остаток сохраняет смысл, а не выбрасывает текст', () {
      expect(
        truncateOneLiner('описание процессов как тут длинный текст',
            maxChars: 26),
        'описание процессов',
      );
    });

    test('два вызова на одном входе дают идентичный результат', () {
      for (final String fixture in _fixtures) {
        expect(truncateOneLiner(fixture), truncateOneLiner(fixture));
      }
    });

    test('enforceOneLinerLimit совпадает с truncateOneLiner', () {
      for (final String fixture in _fixtures) {
        expect(enforceOneLinerLimit(fixture), truncateOneLiner(fixture));
      }
    });

    test('enforceOneLinerLimit: пустое и пробельное — без обрезки', () {
      expect(enforceOneLinerLimit(null), '');
      expect(enforceOneLinerLimit('   '), '');
      expect(enforceOneLinerLimit(_danglingTailBug).length,
          lessThanOrEqualTo(oneLinerMaxChars));
    });

    test('золотая таблица фикстур совпадает с ожиданиями', () {
      expect(
        _golden.map((List<String> row) => truncateOneLiner(row.first)).toList(),
        _golden.map((List<String> row) => row.last).toList(),
      );
    });
  });
}