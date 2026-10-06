// Регресс бага «Завершить концепт всегда засчитывает верный ответ».
//
// Симптом: кнопка «Завершить концепт» → `markItemCompleted` звал
// `reviewScheduler.onAnswered(topic, node, 'correct')` при ЛЮБЫХ ответах
// ученика, потому что параметр жёстко дефолтился в 'correct', а UI его не
// передавал. Итог: каждый завершённый концепт давал +0.15 recall /
// +0.1 understanding и продлевал интервал SRS.
//
// Что здесь проверяется — чистая функция вывода качества
// (`deriveCompletionQuality` / `qualityFromSteps`): без БД, без LLM, без
// случайности. Правило: свидетельство — только шаги с непустым `correct`;
// хотя бы один `correct == false` → 'again' (интервал сбрасывается, ложная
// мисконцепция `careless` не пишется); всё остальное → 'correct'.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/domain/lib/activity_blob.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

const _itemId = 'ci_1~abcdef01';

ActivityStep _step(String type, {bool? correct, String status = 'answered'}) =>
    ActivityStep(
      type: type,
      title: 'Шаг $type',
      status: status,
      correct: correct,
    );

/// Blob ровно такой формы, какую пишет `LearningActivityService._persistSteps`.
String _blob(List<ActivityStep> steps, {String itemId = _itemId}) =>
    jsonEncode({
      'itemId': itemId,
      'steps': [for (final s in steps) s.toJson()],
    });

void main() {
  group('qualityFromSteps: свидетельство = только шаги с оценкой', () {
    test('все шаги верные → correct', () {
      expect(
        qualityFromSteps([
          _step('explain', correct: null),
          _step('example', correct: null),
          _step('recall', correct: true),
          _step('apply', correct: true),
        ]),
        'correct',
      );
    });

    test('хотя бы один неверный → again', () {
      expect(
        qualityFromSteps([
          _step('recall', correct: true),
          _step('apply', correct: false),
        ]),
        'again',
      );
    });

    test('только чтение/объяснение (correct == null) → correct', () {
      // «Не отвечал» — не «ответил неверно»: read-шаги свидетельством не являются.
      expect(
        qualityFromSteps([
          _step('explain'),
          _step('example'),
          _step('explain', correct: null),
        ]),
        'correct',
      );
    });

    test('смесь: верный recall + неверный apply → again', () {
      expect(
        qualityFromSteps([
          _step('explain', correct: null),
          _step('recall', correct: true),
          _step('apply', correct: false),
        ]),
        'again',
      );
    });

    test('неверный recall при верном apply → again (порог любой один)', () {
      expect(
        qualityFromSteps([
          _step('recall', correct: false),
          _step('apply', correct: true),
        ]),
        'again',
      );
    });

    test('пустой список шагов → correct', () {
      expect(qualityFromSteps(const []), 'correct');
    });
  });

  group('deriveCompletionQuality: blob сессии', () {
    test('все шаги верные → correct', () {
      final blob = _blob([
        _step('explain', correct: null),
        _step('recall', correct: true),
        _step('apply', correct: true),
      ]);

      expect(deriveCompletionQuality(blob, _itemId), 'correct');
    });

    test('есть ошибочный шаг → again', () {
      final blob = _blob([
        _step('explain', correct: null),
        _step('recall', correct: false),
        _step('apply', correct: true),
      ]);

      expect(deriveCompletionQuality(blob, _itemId), 'again');
    });

    test('blob без itemId (голый список шагов) — шаги всё равно читаются', () {
      final blob = jsonEncode([
        _step('recall', correct: false).toJson(),
      ]);

      expect(deriveCompletionQuality(blob, _itemId), 'again');
    });
  });

  group('deriveCompletionQuality: мягкая деградация (без исключений)', () {
    test('null → correct', () {
      expect(deriveCompletionQuality(null, _itemId), 'correct');
    });

    test('пустая строка → correct', () {
      expect(deriveCompletionQuality('', _itemId), 'correct');
    });

    test('невалидный JSON → correct и НЕ бросает', () {
      expect(() => deriveCompletionQuality('{не json', _itemId), returnsNormally);
      expect(deriveCompletionQuality('{не json', _itemId), 'correct');
    });

    test('JSON без steps → correct', () {
      expect(deriveCompletionQuality(jsonEncode({'itemId': _itemId}), _itemId),
          'correct');
    });

    test('дефолт БД [] → correct', () {
      expect(deriveCompletionQuality('[]', _itemId), 'correct');
    });

    test('blob ЧУЖОГО itemId → correct (ошибка не выдумывается)', () {
      // Активность от другого пункта плана не должна портить SRS этого узла.
      final blob = _blob(
        [_step('recall', correct: false)],
        itemId: 'ci_чужая~abcdef01',
      );

      expect(deriveCompletionQuality(blob, _itemId), 'correct');
    });

    test('шаги с битым полем не роняют вывод', () {
      // `type`/`title` обязательны в `ActivityStep.fromJson`: мусорный шаг
      // обязан деградировать, а не уронить UI-кнопку.
      final blob = jsonEncode({
        'itemId': _itemId,
        'steps': [
          {'привет': 'мир'},
        ],
      });

      expect(() => deriveCompletionQuality(blob, _itemId), returnsNormally);
      expect(deriveCompletionQuality(blob, _itemId), 'correct');
    });
  });
}
