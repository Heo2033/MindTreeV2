// Регресс-тесты рендера формул в FormattedText.
//
// Симптом бага (пользователь видел):
//   «На каждом шаге Parse error: unexpected character:` , где … — шум»
// Вместо формулы отрисовался внутренний текст парсера TeX.
//
// Причина: отказ парсинга обрабатывался через `try/catch` вокруг `Math.tex`,
// который не срабатывал НИКОГДА — пакет сам ловит ошибку и рисует
// `defaultOnErrorFallback` (то есть диагностику парсера пользователю).
// Теперь отказ обрабатывает `onErrorFallback`, плюс добавлена санитация
// markdown-обвязки (модель оборачивала формулу в инлайн-код, и TeX-парсер
// падал на символе «`»).
//
// ВАЖНО про фикстуры этого файла: raw-строки Dart (`r'...'`) НЕ поддерживают
// интерполяцию — `$` в них обычный символ. Поэтому все фикстуры, где нужен
// `$dollar`, записаны обычными строками с удвоенным обратным слэшем.
// Ровно на этом же эффекте сломан fallback в formatted_text.dart (см. последний
// тест группы A).
//
// Примечание по среде: `flutter_math_fork` — чистая Dart-реализация KaTeX
// (никакого JS-рантайма), поэтому `Math.tex` полностью работает в
// `flutter test`: и успешный рендер, и отказ через `onErrorFallback`
// проверяются по-настоящему. Шрифты KaTeX для этих проверок не нужны —
// тесты смотрят на дерево виджетов и текст, а не на картинку.

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';

/// Знак доллара отдельной константой: подставлять его через `$dollar`
/// удобнее, чем экранировать каждый раз, и фикстуры остаются читаемыми.
const dollar = r'$';

/// Маркеры внутренней диагностики парсера/рендерера TeX. Ни один из них
/// не должен попасть в то, что видит пользователь.
const _leakMarkers = <String>[
  'Parse error',
  'Parser Error',
  'ParseException',
  'Unexpected character',
  'unexpected character',
  'Undefined control sequence',
  'Expected ',
  'Unsanitized',
  'Build Exception',
  '\u0332', // подчёркивание проблемного места в сообщении парсера
];

/// Управляющий символ внутри формулы: TeX-лексер его не понимает и раньше
/// рапортовал «Unexpected character». Именно эту формулировку пользователь
/// видел в испорченном выводе.
const _badChar = '\u0007';

/// Плейсхолдер, который InlineSpan.toPlainText() подставляет вместо
/// содержимого WidgetSpan, то есть вместо нарисованной inline-формулы.
const _mathSpot = '\uFFFC';

/// Монтирует FormattedText и прокачивает кадр.
Future<void> _pump(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: FormattedText(text))),
    ),
  );
  await tester.pump();
}

/// Весь текст, реально отданный пользователю: обычные абзацы, исходник
/// формулы из fallback и глифы, которые нарисовал KaTeX.
///
/// Порядок обхода дерева не гарантирует визуальный порядок (инлайн-формула
/// живёт в отдельном поддереве), поэтому строки проверяем через `contains`.
String _visibleText(WidgetTester tester) {
  final buf = StringBuffer();
  void visit(Element e) {
    final w = e.widget;
    if (w is RichText) buf.write(w.text.toPlainText());
    e.visitChildren(visit);
  }

  visit(tester.element(find.byType(FormattedText)));
  return buf.toString();
}

/// Тексты span'ов виджетов Text/Text.rich — то, что осталось от исходного
/// текста. Содержимое inline-формул сюда не попадает: это WidgetSpan.
/// Используется для точных проверок границ абзацев.
List<String> _plainSpans(WidgetTester tester) {
  final out = <String>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is Text) {
      final t = w.data ?? w.textSpan?.toPlainText() ?? '';
      if (t.isNotEmpty) out.add(t);
    }
    e.visitChildren(visit);
  }

  visit(tester.element(find.byType(FormattedText)));
  return out;
}

/// Все виджеты Math, дошедшие до рендера.
List<Math> _maths(WidgetTester tester) =>
    tester.widgetList<Math>(find.byType(Math)).toList();

/// Падал ли парсер на какой-либо из формул.
bool _hasParseError(WidgetTester tester) =>
    _maths(tester).any((m) => m.parseError != null);

/// Ни один маркер диагностики парсера не должен попасть в вывод.
void expectNoParserDiagnostics(String visible) {
  for (final marker in _leakMarkers) {
    expect(
      visible,
      isNot(contains(marker)),
      reason: 'диагностика парсера попала в вывод',
    );
  }
}

void main() {
  group('A. Диагностика парсера не попадает в вывод', () {
    testWidgets(
      'инлайн-формула с обратной кавычкой: парсер не ругается, формула '
      'отрисована',
      (tester) async {
        // Ровно тот случай из репорта: модель обернула формулу в инлайн-код,
        // обратная кавычка попала внутрь TeX.
        await _pump(
          tester,
          'На каждом шаге $dollar`X_{t+1} = \\beta X_t$dollar, '
          'где X — состояние',
        );

        expect(tester.takeException(), isNull);
        expectNoParserDiagnostics(_visibleText(tester));
        // Ошибки парсинга нет, формула действительно нарисована.
        expect(_hasParseError(tester), isFalse);
        expect(_maths(tester), hasLength(1));
        // И пользователю не показан исходник вместо формулы.
        expect(find.text('$dollar\\beta$dollar'), findsNothing);
      },
    );

    testWidgets('блочная формула с обратной кавычкой: та же гарантия',
        (tester) async {
      await _pump(
        tester,
        '$dollar$dollar`X_{t+1} = \\beta X_t$dollar$dollar',
      );

      expect(tester.takeException(), isNull);
      expectNoParserDiagnostics(_visibleText(tester));
      final maths = _maths(tester);
      expect(maths, hasLength(1));
      expect(maths.single.parseError, isNull);
      // Блочная формула остаётся блочной (MathStyle.display).
      expect(maths.single.mathStyle, MathStyle.display);
    });

    testWidgets(
      'управляющий символ в формуле (unexpected character) не утекает',
      (tester) async {
        // Символ не убирается санитацией, поэтому доходит до TeX-лексера
        // и роняет парсер — проверяем именно обработку отказа.
        await _pump(
          tester,
          'Коэффициент $dollar${_badChar}X_{t+1}$dollar — шум',
        );

        expect(tester.takeException(), isNull);
        // Парсер действительно отказал — иначе тест ничего бы не проверял.
        expect(_hasParseError(tester), isTrue);
        expectNoParserDiagnostics(_visibleText(tester));
      },
    );

    testWidgets('неизвестный макрос: диагностика не утекает', (tester) async {
      await _pump(tester, 'Формула: $dollar\\undefinedmacro$dollar');

      expect(tester.takeException(), isNull);
      expect(_hasParseError(tester), isTrue);
      expectNoParserDiagnostics(_visibleText(tester));
    });

    testWidgets(
      'несбалансированная группа в блочной формуле: диагностика не утекает',
      (tester) async {
        await _pump(
          tester,
          '$dollar$dollar\\frac{a}$dollar$dollar',
        );

        expect(tester.takeException(), isNull);
        expect(_hasParseError(tester), isTrue);
        expectNoParserDiagnostics(_visibleText(tester));
      },
    );

    // ЗАПРОС ТРЕБОВАНИЯ A: «пользователь хотя бы видит формулу текстом».
    // Заблокировано дефектом прода (правка запрещена). В _mathOrFallback строка
    // fallback — raw-строка, а Dart в raw-строках НЕ интерполирует: вместо
    // исходника пользователю печатается литерал шаблона с seg.content.
    // Фикс: убрать префикс r у двух строк и экранировать знаки доллара,
    // например display ? '\$\$${seg.content}\$\$' : '\$${seg.content}\$'.
    // (У testWidgets параметр skip булев, поэтому причина вынесена сюда.)
    testWidgets(
      'битый TeX: пользователь видит исходник формулы, а не шаблон',
      (tester) async {
        await _pump(tester, 'Формула: $dollar\\undefinedmacro$dollar');

        expect(_visibleText(tester), contains(r'\undefinedmacro'));
      },
      );
  });

  group('B. Санитация markdown-обвязки', () {
    testWidgets('инлайн-код вокруг формулы: символ «`» исчезает полностью',
        (tester) async {
      await _pump(
        tester,
        'На каждом шаге $dollar`X_{t+1}$dollar`, где `X` — состояние',
      );

      expect(tester.takeException(), isNull);
      expect(_visibleText(tester), isNot(contains('`')));
      // Формула при этом осталась формулой, а не текстом.
      final maths = _maths(tester);
      expect(maths, hasLength(1));
      expect(maths.single.parseError, isNull);
      // Окружающий текст не пострадал.
      expect(
        _plainSpans(tester).join(),
        allOf(contains('На каждом шаге '), contains(', где X — состояние')),
      );
    });

    testWidgets(
      'ограждения с формулой: ограждения уходят, формула рисуется',
      (tester) async {
        await _pump(
          tester,
          'Смотри:\n```latex\n${dollar}X_{t+1} = '
          '\\beta X_t$dollar\n```\nВот так',
        );

        expect(tester.takeException(), isNull);
        final text = _visibleText(tester);
        expect(text, isNot(contains('`')));
        expect(text, isNot(contains('latex')));
        final maths = _maths(tester);
        expect(maths, hasLength(1));
        expect(maths.single.parseError, isNull);
        // Содержимое ограждений не выкинуто, переносы на месте.
        expect(
          _plainSpans(tester).join(),
          allOf(contains('Смотри:\n'), contains('\nВот так')),
        );
      },
    );

    testWidgets('ограждения без формулы: содержимое сохраняется',
        (tester) async {
      await _pump(tester, 'Шаг 1\n```\nX_{t+1}\n```\nШаг 2');

      expect(tester.takeException(), isNull);
      expect(_visibleText(tester), isNot(contains('`')));
      expect(_maths(tester), isEmpty);
      expect(_plainSpans(tester), ['Шаг 1\n\nX_{t+1}\n\nШаг 2']);
    });

    testWidgets(
      'текст без единой обратной кавычки не меняется (регресс санитации)',
      (tester) async {
        // Реальный текст LLM: «5 и 10 долларов» — это цены, а не формула.
        await _pump(
          tester,
          'Цена ${dollar}5 и ${dollar}10 в день.\nВторой абзац.',
        );

        expect(tester.takeException(), isNull);
        final spans = _plainSpans(tester).join();
        // Ничего не потеряно и не склеено, переносы строк на месте.
        expect(spans, contains('Цена '));
        expect(spans, contains('10 в день.\nВторой абзац.'));
        final text = _visibleText(tester);
        expect(text, contains('Цена '));
        expect(text, contains('5'));
        expect(text, contains('10'));
        expect(text, contains('Второй абзац.'));
      },
    );
  });

  group('C. Валидные формулы не сломались', () {
    testWidgets('валидные инлайн-формулы рендерятся и не подменяются исходником',
        (tester) async {
      await _pump(
        tester,
        'Коэффициент $dollar\\beta$dollar, формула '
        '${dollar}E = mc^2$dollar, интеграл '
        '$dollar\\int_0^1 x^2 dx$dollar.',
      );

      expect(tester.takeException(), isNull);
      final maths = _maths(tester);
      expect(maths, hasLength(3));
      for (final m in maths) {
        expect(m.parseError, isNull);
        expect(m.mathStyle, MathStyle.text);
      }
      final text = _visibleText(tester);
      expectNoParserDiagnostics(text);
      // Fallback-виджет (исходник) не показан: нарисована формула.
      expect(find.text('$dollar\\beta$dollar'), findsNothing);
      expect(text, isNot(contains(r'\beta')));
      expect(text, isNot(contains(r'\int_0^1')));
    });

    testWidgets(
      'смешанный текст: абзацы + инлайн + блочная формула, границы сохранены',
      (tester) async {
        await _pump(
          tester,
          'Первый абзац.\n\nВторой: ${dollar}E = mc^2$dollar и текст.\n\n'
          'Третий.\n\n$dollar$dollar\n\\int_0^1 x^2 dx\n'
          '$dollar$dollar\nИтог.',
        );

        expect(tester.takeException(), isNull);
        final maths = _maths(tester);
        expect(maths, hasLength(2));
        expect(maths[0].mathStyle, MathStyle.text);
        expect(maths[1].mathStyle, MathStyle.display);
        for (final m in maths) {
          expect(m.parseError, isNull);
        }
        // Переносы строк между абзацами не съедены.
        final spans = _plainSpans(tester);
        expect(spans.first, startsWith('Первый абзац.\n\nВторой: '));
        expect(spans.first, contains(' и текст.\n\nТретий.\n\n'));
        expect(spans.last, '\nИтог.');
      },
    );

    testWidgets('только блочная формула: рендерится отдельным виджетом',
        (tester) async {
      await _pump(
        tester,
        'До.\n\n$dollar${dollar}a + b$dollar$dollar\n\nПосле.',
      );

      expect(tester.takeException(), isNull);
      final maths = _maths(tester);
      expect(maths, hasLength(1));
      expect(maths.single.parseError, isNull);
      expect(maths.single.mathStyle, MathStyle.display);
      expect(_plainSpans(tester), ['До.\n\n', '\n\nПосле.']);
    });
  });

  group('D. Регресс разбиения на сегменты', () {
    testWidgets('инлайнная и блочная формулы становятся отдельными виджетами',
        (tester) async {
      await _pump(
        tester,
        'A ${dollar}x$dollar B $dollar${dollar}y$dollar$dollar C',
      );

      expect(tester.takeException(), isNull);
      final maths = _maths(tester);
      expect(maths, hasLength(2));
      expect(maths[0].mathStyle, MathStyle.text);
      expect(maths[1].mathStyle, MathStyle.display);
      for (final m in maths) {
        expect(m.parseError, isNull);
      }
      // Текстовые куски остались текстом, формулы из них вырезаны.
      expect(_plainSpans(tester), ['A $_mathSpot B ', ' C']);
    });

    testWidgets('непарный одиночный знак доллара остаётся обычным текстом',
        (tester) async {
      await _pump(
        tester,
        'Стоимость 5 долларов и 10 долларов, ${dollar}5',
      );

      expect(tester.takeException(), isNull);
      expect(_maths(tester), isEmpty);
      expect(
        _plainSpans(tester),
        ['Стоимость 5 долларов и 10 долларов, ${dollar}5'],
      );
    });

    testWidgets('незакрытая блочная формула остаётся обычным текстом',
        (tester) async {
      await _pump(tester, 'Формула $dollar${dollar}a + b');

      expect(tester.takeException(), isNull);
      expect(_maths(tester), isEmpty);
      expect(_plainSpans(tester), ['Формула $dollar${dollar}a + b']);
    });

    testWidgets('пустой текст и текст без формул рендерятся без ошибок',
        (tester) async {
      await _pump(tester, '');
      expect(tester.takeException(), isNull);
      expect(_maths(tester), isEmpty);
      expect(_plainSpans(tester), isEmpty);

      await _pump(tester, 'Просто текст без формул.');
      expect(tester.takeException(), isNull);
      expect(_maths(tester), isEmpty);
      expect(_plainSpans(tester), ['Просто текст без формул.']);
    });
  });
}