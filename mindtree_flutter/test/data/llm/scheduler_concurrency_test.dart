import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';

/// Регрессия параллельной очереди TreeScheduler.
///
/// Найденный баг: `_timeToNextSlotMs()` брал `waitMs` неполного rate-трекера
/// как время сна. Для RPD-трекера (окно 24 ч) это 86 400 000 мс — при первом
/// же конкурентном ожидании слота воркер уходил в сон на сутки, и пул контента
/// (4 воркера × maxConcurrency: 1) молча замирал. В последовательном прогоне
/// баг не проявлялся: там ожидание слота вообще не возникало.
void main() {
  group('TreeScheduler — конкурентная очередь', () {
    test('4 конкурентных вызова при maxConcurrency=1 завершаются быстро', () async {
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: false),
        // Ровно конфигурация probe --mock: один слот, щедрые rate-лимиты.
        config: const SchedulerConfig(
          maxRPM: 100000,
          maxRPD: 100000,
          maxConcurrency: 1,
          maxRetries: 0,
        ),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          // Имитируем «честный» LLM-вызов, чтобы конкуренция за слот
          // действительно возникала (при мгновенном ответе один воркер успевал
          // бы пере-поллить раньше остальных).
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const llm_client.LLMResult(text: '{"ok":1}');
        },
      );

      final sw = Stopwatch()..start();
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          scheduler.execute<Map<String, dynamic>>(
            'activity',
            () => 'prompt-$i',
            (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
          ),
      ]);
      sw.stop();

      expect(results, hasLength(4));
      for (final r in results) {
        expect(r.result['ok'], 1);
      }
      // 4 вызова по 20 мс + 4 полла по 50 мс — с большим запасом на CI.
      // Старый баг (сон на 86 400 000 мс) здесь не завершился бы никогда.
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('слот отдаётся в порядке очереди, а не «кто быстрее поллит»', () async {
      final scheduler = TreeScheduler(
        configProvider: () => const llm_client.LLMConfig(isMock: false),
        config: const SchedulerConfig(
          maxRPM: 100000,
          maxRPD: 100000,
          maxConcurrency: 1,
          maxRetries: 0,
        ),
        // Быстрый воркер не может затолкать медленных: слот зарезервирован
        // FIFO-очередью ожидания.
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return const llm_client.LLMResult(text: '{"ok":1}');
        },
      );

      final order = <int>[];
      final start = DateTime.now();
      final tasks = <Future<void>>[
        for (var i = 0; i < 4; i++) () async {
          await scheduler.execute<Map<String, dynamic>>(
            'activity',
            () => 'prompt-$i',
            (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
          );
          order.add(i);
        }(),
      ];
      await Future.wait(tasks);
      // Задачи стартуют почти одновременно; выполнение должно идти в порядке
      // создания (FIFO), иначе очередь-регрессия снова позволила бы одному
      // воркеру «застолбить» слот.
      expect(order, [0, 1, 2, 3]);
      expect(DateTime.now().difference(start).inMilliseconds, lessThan(3000));
    });
  });
}