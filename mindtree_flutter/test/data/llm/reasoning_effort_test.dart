import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;

/// Управление рассуждениями (`reasoning`) и учёт их стоимости.
///
/// Найденные баги, которые закрывает этот файл:
///
/// 1. Рассуждения модели никогда не отключались, при этом они входят в
///    `completion_tokens` и тарифицируются. Замер на живом провайдере: задача с
///    ответом ~30 токенов вернула 4106 выходных токенов, 4077 из них —
///    reasoning; с `effort: none` — 35 токенов и ноль reasoning. Операция
///    `oneline-rewrite` (переписывание одной фразы) стоила ~4.8k токенов.
/// 2. `effort` и `max_tokens` внутри `reasoning` провайдер не принимает
///    одновременно («что-то одно»), поэтому явный бюджет должен побеждать.
/// 3. У части моделей (семейство `glm-5.3*`) thinking обязателен и `effort`
///    даёт 400 — такой отказ не должен ронять пользовательский сценарий.
/// 4. `usage.cost_rub` (реальная стоимость в рублях) не читался, поэтому probe
///    был вынужден считать стоимость по каталогу.
void main() {
  group('LLMConfig.reasoningBlock', () {
    test('по умолчанию рассуждения выключены', () {
      const cfg = llm_client.LLMConfig();
      expect(cfg.reasoningEffort, 'none');
      expect(cfg.reasoningBlock, {'effort': 'none'});
    });

    test('явный бюджет токенов имеет приоритет над уровнем усилий', () {
      const cfg = llm_client.LLMConfig(
        reasoningEffort: 'high',
        reasoningMaxTokens: 2000,
      );
      expect(cfg.reasoningBlock, {'max_tokens': 2000});
      expect(cfg.reasoningBlock.containsKey('effort'), isFalse);
    });

    test('пустой уровень усилий = поле reasoning не отправляется', () {
      const cfg = llm_client.LLMConfig(reasoningEffort: null);
      expect(cfg.reasoningBlock, isEmpty);
    });

    test('пробелы в значении не превращаются в мусорный параметр', () {
      const cfg = llm_client.LLMConfig(reasoningEffort: '  ');
      expect(cfg.reasoningBlock, isEmpty);
    });
  });

  group('LLMUsage', () {
    test('reasoning — часть вывода, а не добавка сверху', () {
      const u = llm_client.LLMUsage(
        outputTokens: 1000,
        reasoningTokens: 900,
      );
      expect(u.reasoningShare, closeTo(0.9, 1e-9));
    });

    test('при нулевом выводе доля равна нулю, а не делению на ноль', () {
      const u = llm_client.LLMUsage(outputTokens: 0, reasoningTokens: 500);
      expect(u.reasoningShare, 0);
    });
  });

  group('тело запроса и парсинг usage', () {
    /// Локальный сервер: копит тела POST-запросов и отвечает по [respond].
    ///
    /// `provider: 'openai'` обязателен — по умолчанию адрес на 127.0.0.1
    /// распознаётся как Ollama и уходит в другую ветку вызова.
    Future<({String baseUrl, List<Map<String, dynamic>> bodies})> startServer(
      ({int status, Map<String, Object?> body}) Function(
        Map<String, dynamic> body,
      ) respond,
    ) async {
      final bodies = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        final body = jsonDecode(raw) as Map<String, dynamic>;
        bodies.add(body);
        final out = respond(body);
        req.response
          ..statusCode = out.status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(out.body));
        await req.response.close();
      });
      return (baseUrl: 'http://127.0.0.1:${server.port}/v1', bodies: bodies);
    }

    Map<String, Object?> answer({
      String content = '{"one_liner":"скорость обучения"}',
      int promptTokens = 100,
      int completionTokens = 40,
      int reasoningTokens = 0,
      double costRub = 0.5,
    }) =>
        {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content},
            },
          ],
          'usage': {
            'prompt_tokens': promptTokens,
            'completion_tokens': completionTokens,
            'completion_tokens_details': {'reasoning_tokens': reasoningTokens},
            'cost_rub': costRub,
          },
        };

    llm_client.LLMConfig cfgFor(String baseUrl, {String? effort, int? budget}) =>
        llm_client.LLMConfig(
          provider: 'openai',
          baseUrl: baseUrl,
          reasoningEffort: effort ?? 'none',
          reasoningMaxTokens: budget,
        );

    test('effort попадает в тело запроса, usage читается полностью', () async {
      final server = await startServer(
        (_) => (status: 200, body: answer(reasoningTokens: 12)),
      );
      final result = await llm_client.callLLM(
        cfgFor(server.baseUrl),
        'prompt',
      );

      expect(server.bodies, hasLength(1));
      expect(server.bodies.first['reasoning'], {'effort': 'none'});
      expect(server.bodies.first['max_tokens'], 16384);
      expect(result.usage.inputTokens, 100);
      expect(result.usage.outputTokens, 40);
      expect(result.usage.reasoningTokens, 12);
      expect(result.usage.costRub, 0.5);
    });

    test('бюджет рассуждений не дублируется с уровнем усилий', () async {
      final server = await startServer(
        (_) => (status: 200, body: answer()),
      );
      await llm_client.callLLM(
        cfgFor(server.baseUrl, effort: 'high', budget: 1000),
        'prompt',
      );
      expect(server.bodies.first['reasoning'], {'max_tokens': 1000});
    });

    test('отказ из-за reasoning не роняет вызов: один повтор без него', () async {
      final server = await startServer((body) {
        if (body.containsKey('reasoning')) {
          return (
            status: 400,
            body: {
              'error': {
                'message': "reasoning.effort 'none' is not supported by this model",
              },
            },
          );
        }
        return (status: 200, body: answer(content: '{"one_liner":"ок"}'));
      });

      final result = await llm_client.callLLM(cfgFor(server.baseUrl), 'prompt');

      expect(result.text, '{"one_liner":"ок"}');
      expect(server.bodies, hasLength(2));
      expect(server.bodies.first.containsKey('reasoning'), isTrue);
      expect(server.bodies.last.containsKey('reasoning'), isFalse);
    });

    test('после отказа поле reasoning больше не отправляется', () async {
      final server = await startServer((body) {
        if (body.containsKey('reasoning')) {
          return (
            status: 422,
            body: {
              'error': {'message': 'thinking is required for this model'},
            },
          );
        }
        return (status: 200, body: answer(content: '{"one_liner":"ок"}'));
      });

      final cfg = cfgFor(server.baseUrl);
      await llm_client.callLLM(cfg, 'первый');
      final bodiesAfterFirst = server.bodies.length;
      await llm_client.callLLM(cfg, 'второй');

      // Второй логический вызов не должен тратить ещё один отказ 400.
      expect(server.bodies.length - bodiesAfterFirst, 1);
      expect(server.bodies.last.containsKey('reasoning'), isFalse);
    });
  });
}
