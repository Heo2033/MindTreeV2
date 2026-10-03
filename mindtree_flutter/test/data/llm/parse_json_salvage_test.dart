// Тесты разбора JSON-ответа модели в `parseLLMJson`.
//
// 1) «Спасение» обрезанного JSON: длинные структурные ответы (structure-l2/l3,
// content) упираются в `max_tokens` и обрезаются провайдером; вместо полного
// повтора запроса на медленной strong-модели мы отбрасываем недописанный хвост.
// 2) Нормализация LaTeX: модель пишет `\rightarrow` одним слэшем, а `jsonDecode`
// считает `\r` валидным escape и тихо портит значение (CR + `ightarrow`).
//
// Все тесты детерминированные, без сети: проверяют чистую функцию парсинга.

import 'package:flutter_test/flutter_test.dart';
import 'package:mindtree_flutter/data/llm/client.dart';

void main() {
  group('parseLLMJson: спасение обрезанного JSON', () {
    test('полный валидный JSON не трогается', () {
      const raw = '{"nodes": [{"id": "a", "title": "A"}]}';
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      expect(out['nodes'], isA<List<dynamic>>());
    });

    test('массив с недописанным последним элементом — элемент отбрасывается', () {
      const raw = '{"nodes": [{"id": "a", "title": "A"}, '
          '{"id": "b", "title": "B"}';
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      final nodes = (out['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes.length, 2);
      expect(nodes.map((n) => n['id']), ['a', 'b']);
    });

    test('недописанная строка с незакрытой скобкой массива чинится', () {
      const raw = '["один", "два", "тр';
      final out = parseLLMJson<List<dynamic>>(raw);
      expect(out, ['один', 'два']);
    });

    test('объект с незакрытой строкой значения — значение отбрасывается', () {
      const raw = '{"a": 1, "b": "недо';
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      expect(out['a'], 1);
      expect(out.containsKey('b'), isFalse);
    });

    test('объект: незакрытый последний ключ без значения отбрасывается', () {
      const raw = '{"a": 1, "b": "ваlue", "c": 42, "d"';
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      expect(out['a'], 1);
      expect(out['c'], 42);
      expect(out.containsKey('d'), isFalse);
    });

    test('вложенная структура с недописанным внутренним объектом чинится', () {
      const raw = '[{"id": "x", "meta": {"k": 1}}';
      final out = parseLLMJson<List<dynamic>>(raw);
      expect(out, hasLength(1));
      expect((out.first as Map<String, dynamic>)['id'], 'x');
    });

    test('полностью нерепарируемый мусор бросает ошибку', () {
      const raw = 'просто текст без единой скобки';
      expect(() => parseLLMJson<Map<String, dynamic>>(raw),
          throwsA(anything));
    });

    test('NaN/Infinity-подобный мусор бросает ошибку, а не молчит', () {
      const raw = '"{"nodes": }начение';
      expect(() => parseLLMJson<List<dynamic>>(raw), throwsA(anything));
    });

    test('недописанная строка закрывается: целостность JSON сохраняется', () {
      const raw = '{"nodes": [{"id": "a", "date": "2026-09-';
      // Строка закрывается как есть («2026-09-»), массив и объекты — до
      // валидного JSON: мы не выдумываем значения, только доводим скобки.
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      final nodes = (out['nodes'] as List).cast<Map<String, dynamic>>();
      expect(nodes.single['id'], 'a');
      expect(nodes.single['date'], '2026-09-');
    });
  });

  group('parseLLMJson: LaTeX в строковых значениях', () {
    // Позитив: макросы, начинающиеся с буквы control-escape, выживают.
    test(r'\rightarrow не превращается в CR + "ightarrow"', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"Формула: $6CO_2 + 18ATP  \rightarrow C_6H_{12}O_6$"}',
      );
      expect(out['details'],
          r'Формула: $6CO_2 + 18ATP  \rightarrow C_6H_{12}O_6$');
    });

    test(r'\text и \frac выживают в одном значении', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$\text{плотность} = \frac{m}{V}$"}',
      );
      expect(out['details'], r'$\text{плотность} = \frac{m}{V}$');
    });

    test(r'\beta, \theta и \times выживают', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$\beta_{ij} = \theta \times \omega$"}',
      );
      expect(out['details'], r'$\beta_{ij} = \theta \times \omega$');
    });

    test(r'\to с пробелом (не escape) выживает', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$A \to B$"}',
      );
      expect(out['details'], r'$A \to B$');
    });

    test(r'\neq и \notin выживают', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$a \neq b$, $x \notin S$"}',
      );
      expect(out['details'], r'$a \neq b$, $x \notin S$');
    });

    test(r'\begin{...} ... \end{...} выживает', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$\begin{aligned} a &= b \\ c &= d \end{aligned}$"}',
      );
      expect(out['details'],
          r'$\begin{aligned} a &= b \ c &= d \end{aligned}$');
    });

    test('макросы во всех элементах массива и во вложенном объекте', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"items":[{"one_liner":"$\rho$ вода"},'
        r'{"one_liner":"$\lfloor x \rfloor$"}]}',
      );
      final items = (out['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((i) => i['one_liner']), [r'$\rho$ вода', r'$\lfloor x \rfloor$']);
    });

    test('LaTeX и реальный перевод строки в одном значении', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"строка\nздесь ' r'\to конец"}',
      );
      expect(out['details'], 'строка\nздесь ' r'\to конец');
    });

    // Негатив: настоящие escape не должны пострадать.
    test(r'"a\nb" остаётся переводом строки', () {
      final out = parseLLMJson<Map<String, dynamic>>(r'{"details":"a\nb"}');
      expect(out['details'], 'a\nb');
    });

    test(r'"a\tb" остаётся табом', () {
      final out = parseLLMJson<Map<String, dynamic>>(r'{"details":"a\tb"}');
      expect(out['details'], 'a\tb');
    });

    test(r'"a\rb" и "a\bb" остаются control-символами', () {
      expect(parseLLMJson<Map<String, dynamic>>(r'{"details":"a\rb"}')['details'],
          'a\rb');
      expect(parseLLMJson<Map<String, dynamic>>(r'{"details":"a\bb"}')['details'],
          'a\bb');
      expect(parseLLMJson<Map<String, dynamic>>(r'{"details":"a\fb"}')['details'],
          'a\fb');
    });

    test(r'"\\" остаётся одиночным обратным слэшем', () {
      final out = parseLLMJson<Map<String, dynamic>>(r'{"details":"a\\b"}');
      expect(out['details'], r'a\b');
    });

    test(r'\" внутри строки не ломает разбор', () {
      final out =
          parseLLMJson<Map<String, dynamic>>(r'{"details":"кавычка \" внутри"}');
      expect(out['details'], 'кавычка " внутри');
    });

    test(r'JSON-escape \uXXXX остаются символами', () {
      // Собираем «сырой» ответ руками: escape-последовательности должны дойти
      // до парсера буквами (`jsonEncode` выдаёт символы как есть).
      final bs = r'\';
      final raw = '{"details":"caf${bs}u00e9 ${bs}u0416"}';
      final out = parseLLMJson<Map<String, dynamic>>(raw);
      expect(out['details'], 'café Ж');
    });

    test(r'оборванный \u без 4 hex не роняет парсер', () {
      // Не escape → слэш удваивается, обрезка чинится: в значении остаётся
      // literal `\u00`, а не исключение.
      final out = parseLLMJson<Map<String, dynamic>>(r'{"details":"\u00');
      expect(out['details'], r'\u00');
    });

    // Негатив: уже экранированный LaTeX не удваивается повторно.
    test(r'уже экранированный \\to остаётся \\to, а не \\\to', () {
      final out =
          parseLLMJson<Map<String, dynamic>>(r'{"details":"$A \\to B$"}');
      expect(out['details'], r'$A \to B$');
      expect(out['details'] as String, isNot(contains(r'\\')));
    });

    test(r'LaTeX-перенос строки \\ не удваивается лишний раз', () {
      final out =
          parseLLMJson<Map<String, dynamic>>(r'{"details":"разрыв \\ раздел"}');
      expect(out['details'], r'разрыв \ раздел');
    });

    // Негатив: прочий валидный JSON не меняется.
    test('валидный JSON без LaTeX разбирается как раньше', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        '{"a": 1, "b": [1, 2.5, -3e2], "c": null, "d": true, '
        r'"e": "просто текст", "f": "слеш\/и кавычка\"", "g": "\u0416"}',
      );
      expect(out['a'], 1);
      expect(out['b'], [1, 2.5, -300.0]);
      expect(out['c'], isNull);
      expect(out['d'], isTrue);
      expect(out['e'], 'просто текст');
      expect(out['f'], r'слеш/и кавычка"');
      expect(out['g'], 'Ж');
    });

    // Нормализация применяется ко всем путям декодирования внутри
    // parseLLMJson, а не только к прямому parse.
    test('code fence: LaTeX выживает', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        '```json\n' r'{"details":"$\frac{1}{2}$", "x": 1}' '\n```',
      );
      expect(out['details'], r'$\frac{1}{2}$');
      expect(out['x'], 1);
    });

    test('bracket matching: LaTeX выживает при тексте вокруг JSON', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        'Смотри формулу \\alpha\n' r'{"details":"$\to$ и $\beta$"}' '\nВсё.',
      );
      expect(out['details'], r'$\to$ и $\beta$');
    });

    test('repair control chars: LaTeX выживает вместе с чисткой переводов', () {
      // Здесь перевод строки — настоящий control-символ внутри строки, из-за
      // него прямой parse падает и включается `_repairControlChars`.
      final out = parseLLMJson<Map<String, dynamic>>(
        '{"details":"строка\nздесь ' r'\rightarrow конец"}',
      );
      expect(out['details'], 'строка\nздесь ' r'\rightarrow конец');
    });

    test('salvage обрезанного ответа сохраняет LaTeX', () {
      final out = parseLLMJson<Map<String, dynamic>>(
        r'{"details":"$\to начало$", "analogy":"$\beta',
      );
      expect(out['details'], r'$\to начало$');
      expect(out.containsKey('analogy'), isFalse);
    });
  });
}
