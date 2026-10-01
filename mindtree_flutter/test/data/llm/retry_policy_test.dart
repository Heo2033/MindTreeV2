import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';

/// Регрессия транспорта LLM: политика повторных попыток и читаемость сообщения
/// об ошибке. Пользовательский баг (провайдер aitunnel):
///
/// ```
/// [studyNode] content generation failed for n3_1~e6d461c2
/// LLM: исчерпаны попытки запроса (4); последняя ошибка: Exception: LLM API error
/// (400): {"error":{"message":"Указанная модель (qwen3.5-flash) не найдена, ...
/// ```
///
/// Два дефекта, которые закрывает этот файл:
///
/// 1. Перманентный 400 «модель не найдена» ретраился 4 раза при `maxRetries: 3`
///    — запрос заведомо не мог стать валидным, время тратилось впустую.
/// 2. Сообщение было нечитаемым: обёртка прятала причину за «исчерпаны попытки
///    запроса (4)», а обрезка тела до 300 символов резала его ровно на имени
///    модели — самом полезном куске.
///
/// Зеркало server-теста `server/src/llm/__tests__/retryPolicy.test.ts`.
void main() {
  /// Сырое тело ответа провайдера на несуществующее имя модели (AITUNNEL).
  const modelNotFoundBody = <String, Object?>{
    'error': <String, Object?>{
      'message':
          'Указанная модель (qwen3.5-flash) не найдена, либо сейчас недоступна. '
          'Возможно вы хотели использовать модель "qwen3.8-flash"?',
      'code': 400,
    },
  };

  /// Тот же текст, но уже сплющенный `_compactErrorBody` — ровно то, что видит
  /// пользователь в тексте ошибки (обёртка JSON убрана, хвост не обрезан).
  const modelNotFoundMessage =
      'Указанная модель (qwen3.5-flash) не найдена, либо сейчас недоступна. '
      'Возможно вы хотели использовать модель "qwen3.8-flash"?';

  /// Ошибка того же вида, что бросает транспорт: HTTP-статус в скобках плюс
  /// уже сплющенное тело. Именно такой объект видит `shouldRetry`.
  Exception transportError(int status, String body) =>
      Exception('LLM API error ($status): $body');

  /// Вызывает [body] и возвращает пойманную ошибку (для проверки текста).
  Future<Object> catchError(Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      return e;
    }
    throw StateError('ожидалась ошибка LLM, а вызов завершился успешно');
  }

  /// Локальный сервер: копит тела POST-запросов и отвечает по [respond].
  ///
  /// `provider: 'openai'` в конфиге обязателен — по умолчанию адрес на
  /// 127.0.0.1 распознаётся как Ollama и уходит в другую ветку вызова.
  Future<({String baseUrl, List<Map<String, dynamic>> bodies})> startServer(
    ({int status, String contentType, String body}) Function(
      Map<String, dynamic> body,
    ) respond,
  ) async {
    final bodies = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      final parsed = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      bodies.add(parsed);
      final out = respond(parsed);
      req.response
        ..statusCode = out.status
        // charset задаём явно: иначе dart:io кодирует тело однобайтово и кидает
        // «Contains invalid characters» на кириллице.
        ..headers.contentType = ContentType.parse('${out.contentType}; charset=utf-8')
        ..add(utf8.encode(out.body));
      await req.response.close();
    });
    return (baseUrl: 'http://127.0.0.1:${server.port}/v1', bodies: bodies);
  }

  llm_client.LLMConfig cfgFor(String baseUrl, {String model = 'qwen3.5-flash'}) =>
      llm_client.LLMConfig(
        provider: 'openai',
        baseUrl: baseUrl,
        model: model,
      );

  group('политика ретраев: isPermanentLLMError', () {
    test('перманентные 4xx: 400, 401, 403, 404, 422', () {
      for (final status in [400, 401, 403, 404, 422]) {
        expect(
          llm_client.isPermanentLLMError(transportError(status, 'отказ')),
          isTrue,
          reason: 'статус $status не должен повторяться',
        );
      }
    });

    test('408 и 429 — временные, перманентными не считаются', () {
      expect(
        llm_client.isPermanentLLMError(transportError(408, 'таймаут')),
        isFalse,
      );
      expect(
        llm_client.isPermanentLLMError(transportError(429, 'лимит')),
        isFalse,
      );
    });

    test('5xx и ошибки без распознаваемого статуса — не перманентные', () {
      for (final status in [500, 502, 503, 504]) {
        expect(
          llm_client.isPermanentLLMError(transportError(status, 'сбой')),
          isFalse,
          reason: 'статус $status ретраится',
        );
      }
      // Сетевая неопределённость: статуса нет — повтор оправдан.
      expect(llm_client.isPermanentLLMError(Exception('boom')), isFalse);
    });

    test('LLMRateLimitException отдаёт свой статус, а не текст', () {
      expect(
        llm_client.isPermanentLLMError(
          llm_client.LLMRateLimitException(429, 'превышен лимит запросов (429)'),
        ),
        isFalse,
      );
      expect(
        llm_client.isPermanentLLMError(
          llm_client.LLMRateLimitException(403, 'доступ запрещён'),
        ),
        isTrue,
      );
    });
  });

  group('политика ретраев: shouldRetry', () {
    test('400 не ретраится ни на одной из четырёх попыток (главный фикс)', () {
      final err = transportError(400, modelNotFoundMessage);
      for (var attempt = 0; attempt <= 3; attempt++) {
        expect(
          llm_client.shouldRetry(err, attempt, 3),
          isFalse,
          reason: 'attempt=$attempt: перманентный 400 повтором не лечится',
        );
      }
    });

    test('401, 403, 404, 422 тоже не ретраятся', () {
      for (final status in [401, 403, 404, 422]) {
        for (var attempt = 0; attempt <= 3; attempt++) {
          expect(
            llm_client.shouldRetry(transportError(status, 'отказ'), attempt, 3),
            isFalse,
            reason: 'статус $status, attempt=$attempt',
          );
        }
      }
    });

    test('408 и 429 ретраятся, но упираются в потолок', () {
      for (final status in [408, 429]) {
        final err = transportError(status, 'временно');
        expect(
          llm_client.shouldRetry(err, 0, 3),
          isTrue,
          reason: '$status attempt=0',
        );
        expect(
          llm_client.shouldRetry(err, 1, 3),
          isTrue,
          reason: '$status attempt=1',
        );
        // Старое поведение: на rate-limit статусах дальше attempt >= 2 не идём.
        expect(
          llm_client.shouldRetry(err, 2, 3),
          isFalse,
          reason: '$status attempt=2',
        );
        expect(
          llm_client.shouldRetry(err, 3, 3),
          isFalse,
          reason: '$status attempt=3',
        );
      }
    });

    test('5xx ретраится до потолка maxRetries', () {
      final err = transportError(500, 'Internal Server Error');
      expect(llm_client.shouldRetry(err, 0, 3), isTrue);
      expect(llm_client.shouldRetry(err, 1, 3), isTrue);
      expect(llm_client.shouldRetry(err, 2, 3), isTrue);
      expect(
        llm_client.shouldRetry(err, 3, 3),
        isFalse,
        reason: 'исчерпан maxRetries',
      );
    });

    test('502/503/504 не ретраится начиная с attempt >= 2 (старое поведение)', () {
      for (final status in [502, 503, 504]) {
        final err = transportError(status, 'шлюз недоступен');
        expect(
          llm_client.shouldRetry(err, 0, 3),
          isTrue,
          reason: '$status attempt=0',
        );
        expect(
          llm_client.shouldRetry(err, 1, 3),
          isTrue,
          reason: '$status attempt=1',
        );
        expect(
          llm_client.shouldRetry(err, 2, 3),
          isFalse,
          reason: '$status attempt=2',
        );
      }
    });

    test('LLMMockException не ретраится', () {
      expect(
        llm_client.shouldRetry(llm_client.LLMMockException('офлайн-режим'), 0, 3),
        isFalse,
      );
    });

    test('ошибка без распознаваемого статуса ретраится', () {
      expect(llm_client.shouldRetry(Exception('boom'), 0, 3), isTrue);
      expect(llm_client.shouldRetry(Exception('boom'), 2, 3), isTrue);
      expect(llm_client.shouldRetry(Exception('boom'), 3, 3), isFalse);
    });

    test('отказ 400 из-за reasoning тоже перманентный для scheduler', () {
      // Регресс-риск: если бы 400-про-reasoning стал фатальным на уровне
      // планировщика, «обход» клиента не успевал бы сработать. Граница
      // ответственности: scheduler не повторяет, клиент лечит сам (см. группу
      // «сообщение об ошибке читаемо»).
      final err = transportError(
        400,
        "reasoning.effort 'none' is not supported by this model",
      );
      expect(llm_client.isPermanentLLMError(err), isTrue);
      expect(llm_client.shouldRetry(err, 0, 3), isFalse);
    });
  });

  group('политика ретраев: retryDelayMs', () {
    test('для 5xx пауза фиксирована: 10 с на любой попытке', () {
      // У 5xx нет retry-after, поэтому берётся дефолт 10 с, обрезанный потолком
      // `(attempt + 1) * 10`. На первой попытке потолок равен самому дефолту,
      // дальше он перестаёт влиять — пауза не растёт.
      expect(llm_client.retryDelayMs(transportError(500, 'сбой'), 0), 10000);
      expect(llm_client.retryDelayMs(transportError(500, 'сбой'), 1), 10000);
      expect(llm_client.retryDelayMs(transportError(500, 'сбой'), 3), 10000);
    });

    test('без статуса — линейный рост', () {
      expect(llm_client.retryDelayMs(Exception('boom'), 0), 2000);
      expect(llm_client.retryDelayMs(Exception('boom'), 1), 4000);
    });

    test('429 с retry-after: 0 — паузы нет', () {
      // Этим же приёмом устроен интеграционный сценарий с 5xx ниже: нулевая
      // пауза вместо реальных 10/20/30 секунд.
      expect(
        llm_client.retryDelayMs(
          llm_client.LLMRateLimitException(429, 'лимит', 0),
          0,
        ),
        0,
      );
    });
  });

  group('сообщение об ошибке читаемо (реальный транспорт)', () {
    test('400 «модель не найдена»: оба имени модели видны, JSON-обёртки нет', () async {
      final server = await startServer(
        (_) => (
          status: 400,
          contentType: 'application/json',
          body: jsonEncode(modelNotFoundBody),
        ),
      );

      final err = await catchError(
        () => llm_client.callLLM(cfgFor(server.baseUrl), 'prompt'),
      );
      final text = err.toString();

      // Имя запрошенной модели и подсказка провайдера — именно они терялись
      // при обрезке тела до 300 символов.
      expect(text, contains('qwen3.5-flash'));
      expect(text, contains('qwen3.8-flash'));
      // Сырая обёртка убрана: в сообщении её больше нет.
      expect(text, isNot(contains('{"error"')));
      expect(text, isNot(contains('"message"')));
      // И добавлена подсказка про build-time конфиг (иначе диагностика упирается
      // в «модель не найдена» без пути к исправлению).
      expect(text, contains('provider-config.json'));
    });

    test('400 не про модель: подсказки про пересборку нет', () async {
      final server = await startServer(
        (_) => (
          status: 400,
          contentType: 'application/json',
          body: jsonEncode({
            'error': {'message': 'context length exceeded', 'code': 400},
          }),
        ),
      );

      final err = await catchError(
        () => llm_client.callLLM(cfgFor(server.baseUrl), 'prompt'),
      );
      final text = err.toString();

      expect(text, contains('context length exceeded'));
      expect(text, contains('(400)'));
      expect(text, isNot(contains('provider-config.json')));
      expect(text, isNot(contains('{"error"')));
    });

    test('тело не-JSON не ломается и сохраняется как есть', () async {
      final server = await startServer(
        (_) => (
          status: 400,
          contentType: 'text/plain',
          body: 'Internal Server Error',
        ),
      );

      final err = await catchError(
        () => llm_client.callLLM(cfgFor(server.baseUrl), 'prompt'),
      );
      final text = err.toString();

      expect(text, contains('Internal Server Error'));
      expect(text, contains('(400)'));
    });

    test('HTML-страница провайдера: как раньше — заголовок из <title>', () async {
      final server = await startServer(
        (_) => (
          status: 502,
          contentType: 'text/html',
          body: '<!DOCTYPE html><html><head><title>502 Bad Gateway</title></head>'
              '<body><h1>502 Bad Gateway</h1></body></html>',
        ),
      );

      final err = await catchError(
        () => llm_client.callLLM(cfgFor(server.baseUrl), 'prompt'),
      );
      final text = err.toString();

      expect(text, contains('HTML page: "502 Bad Gateway"'));
    });

    test('отказ 400 из-за reasoning всё ещё лечится внутри callLLM', () async {
      // Связка с политикой ретраев: scheduler такой отказ повторять не будет,
      // поэтому самовосстановление обязано произойти на транспортном уровне.
      final server = await startServer((body) {
        if (body.containsKey('reasoning')) {
          return (
            status: 400,
            contentType: 'application/json',
            body: jsonEncode({
              'error': {
                'message': "reasoning.effort 'none' is not supported by this model",
              },
            }),
          );
        }
        return (
          status: 200,
          contentType: 'application/json',
          body: jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '{"one_liner":"ок"}'},
              },
            ],
          }),
        );
      });

      final result = await llm_client.callLLM(cfgFor(server.baseUrl), 'prompt');

      expect(result.text, '{"one_liner":"ок"}');
      // Ровно один отказ 400 и один успешный повтор без поля reasoning.
      expect(server.bodies, hasLength(2));
      expect(server.bodies.first.containsKey('reasoning'), isTrue);
      expect(server.bodies.last.containsKey('reasoning'), isFalse);
    });
  });

  group('TreeScheduler: интеграция политики ретраев', () {
    test('перманентный 400: один логический вызов, причина видна как есть', () async {
      final server = await startServer(
        (_) => (
          status: 400,
          contentType: 'application/json',
          body: jsonEncode(modelNotFoundBody),
        ),
      );

      var logicalCalls = 0;
      final scheduler = TreeScheduler(
        configProvider: () => cfgFor(server.baseUrl),
        config: const SchedulerConfig(maxRetries: 3),
        // Проброс к настоящему транспорту: считаем логические попытки, а тело
        // ошибки формируется ровно тем же кодом, что и в приложении.
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          logicalCalls++;
          return llm_client.callLLM(
            cfg,
            prompt,
            model: model,
            temperature: temperature,
            seed: seed,
          );
        },
      );

      final err = await catchError(
        () => scheduler.execute<Map<String, dynamic>>(
          'content',
          () => 'prompt',
          (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
        ),
      );
      final text = err.toString();

      // Было 4 логические попытки (maxRetries: 3) — стало 1.
      expect(logicalCalls, 1);
      // И ровно 1 HTTP-запрос: перманентный 4xx не повторяется ни на уровне
      // scheduler, ни внутри клиента (было 3 попытки транспорта × 4 scheduler
      // = 12 запросов на заведомо мёртвый запрос).
      expect(server.bodies, hasLength(1));
      // Причина больше не прячется за «исчерпаны попытки».
      expect(err, isNot(isA<llm_client.LLMRetriesExhaustedException>()));
      expect(text, isNot(contains('исчерпаны попытки')));
      expect(text, contains('qwen3.5-flash'));
      expect(text, isNot(contains('{"error"')));
    });

    test('5xx: ровно maxRetries + 1 вызовов, ошибка обёрнута', () async {
      var calls = 0;
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(),
        config: const SchedulerConfig(maxRetries: 3),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          calls++;
          // Статус 500 с `Retry-After: 0` → `retryDelayMs` даёт нулевую паузу,
          // тест не ждёт реальные 10/20/30 с (см. группу retryDelayMs).
          throw llm_client.LLMRateLimitException(500, 'Internal Server Error', 0);
        },
      );

      final err = await catchError(
        () => scheduler.execute<Map<String, dynamic>>(
          'content',
          () => 'prompt',
          (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
        ),
      );

      expect(calls, 4, reason: 'maxRetries: 3 → одна начальная попытка + 3 повтора');
      expect(err, isA<llm_client.LLMRetriesExhaustedException>());
      final wrapped = err as llm_client.LLMRetriesExhaustedException;
      expect(wrapped.attempts, 4);
      expect(wrapped.toString(), contains('исчерпаны попытки запроса (4)'));
      expect(wrapped.toString(), contains('Internal Server Error'));
    });

    test('400 на первой модели: fallback на следующую модель', () async {
      final seenModels = <String>[];
      var calls = 0;
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(
          modelStrong: 'qwen3.5-flash',
          modelStrongFallback: 'qwen3.8-flash',
        ),
        config: const SchedulerConfig(maxRetries: 3),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          calls++;
          final m = model ?? '';
          seenModels.add(m);
          if (m == 'qwen3.5-flash') {
            throw transportError(400, modelNotFoundMessage);
          }
          return const llm_client.LLMResult(text: '{"one_liner":"ок"}');
        },
      );

      // `structure` — операция тира strong, у неё есть fallback-модель.
      final res = await scheduler.execute<Map<String, dynamic>>(
        'structure',
        () => 'prompt',
        (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
      );

      expect(seenModels, ['qwen3.5-flash', 'qwen3.8-flash']);
      expect(calls, 2);
      expect(res.result['one_liner'], 'ок');
    });
  });
}