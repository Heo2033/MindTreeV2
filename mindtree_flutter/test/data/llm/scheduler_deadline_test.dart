import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';

/// Детерминированные тесты дедлайна операции TreeScheduler (зеркально
/// server/scheduler.ts): дедлайн ограничивает ожидание слота и старт новых
/// попыток, но НЕ прерывает уже запущенный LLM-запрос — его жёсткая граница —
/// клиентский LLMConfig.timeoutMs.
void main() {
  group('TreeScheduler — дедлайн операции', () {
    test('медленный, но успешный вызов не прерывается дедлайном', () async {
      // Регрессия «генерируется только корень»: структура L2/L3 — большие
      // промпты, которые могут отвечать дольше opDeadlineMs. Вызов должен
      // завершиться успешно, а не падать по таймауту дедлайна.
      var calls = 0;
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: false),
        config: const SchedulerConfig(opDeadlineMs: 50, maxRetries: 0),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          calls++;
          // Ответ приходит ПОСЛЕ истечения дедлайна операции.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return const llm_client.LLMResult(text: '{"nodes": []}');
        },
      );

      final res = await scheduler.execute<List<dynamic>>(
        'structure-l2',
        () => 'prompt',
        (raw) {
          // Как в _nodesFromJson: конверт {"nodes": [...]}.
          final data = llm_client.parseLLMJson<Map<String, dynamic>>(raw);
          final nodes = data['nodes'];
          return nodes is List ? nodes : <dynamic>[];
        },
      );
      expect(res.result, isEmpty);
      expect(calls, 1);
    });

    test('быстрый вызов в пределах дедлайна возвращает результат', () async {
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: false),
        config: const SchedulerConfig(opDeadlineMs: 1000, maxRetries: 0),
        llmCall: (cfg, prompt, {model, temperature, seed}) async =>
            const llm_client.LLMResult(text: '{"ok":1}'),
      );

      final res = await scheduler.execute<Map<String, dynamic>>(
        'activity',
        () => 'prompt',
        (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
      );
      expect(res.result['ok'], 1);
    });

    test('не начинаем новую попытку после истечения дедлайна', () async {
      var calls = 0;
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: false),
        // maxRetries высокий, но дедлайн не даёт лишних попыток после истечения.
        config: const SchedulerConfig(opDeadlineMs: 40, maxRetries: 5),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          calls++;
          throw Exception('LLM error');
        },
      );

      final sw = Stopwatch()..start();
      await expectLater(
        scheduler.execute<Map<String, dynamic>>(
          'activity',
          () => 'prompt',
          (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
        ),
        throwsA(isA<llm_client.LLMRetriesExhaustedException>()),
      );
      sw.stop();
      // Первая попытка падает, ретрай-пауза (~2 с), после неё дедлайн
      // блокирует старт новых попыток (calls == 1 вопреки maxRetries: 5).
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(calls, 1);
    });
  });
}