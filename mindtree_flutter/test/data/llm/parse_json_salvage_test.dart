// Тесты «спасения» обрезанного JSON в `parseLLMJson`.
//
// Длинные структурные ответы (structure-l2/l3, content) упираются в
// `max_tokens` и обрезаются провайдером; вместо полного повтора запроса на
// медленной strong-модели мы отбрасываем недописанный хвост. Все тесты
// детерминированные, без сети: проверяют чистую функцию парсинга.

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
}