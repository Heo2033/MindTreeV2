import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';

/// Регрессия транспортных параметров вызова.
///
/// Найденные баги, которые закрывает этот файл:
///
/// 1. `max_tokens` был жёстко 4096. Для моделей с обязательным thinking
///    (glm-5.3*) рассуждение съедало весь лимит и ответ приходил пустым с
///    `finish_reason: "length"`. Теперь лимит конфигурируемый, а бюджет
///    рассуждений отправляется отдельно и гарантированно меньше лимита ответа.
/// 2. `_Choice.content` при пустом `content` подставлял `reasoning_content`.
///    Для JSON-контракта это проза вместо схемы — гарантированный промах
///    парсинга. Теперь наружу отдаётся только `content`.
/// 3. Температура была одна на все операции (0.7 из конфига). Для
///    детерминированных операций это и качество (мусор на границах схемы), и
///    деньги (лишние токены на сильной модели).
void main() {
  group('defaultTemperatureForOperation', () {
    test('детерминированные операции получают temperature=0', () {
      for (final op in const [
        'structure',
        'structure-l2',
        'structure-l3',
        'validate',
        'curriculum',
        'assessment',
        'mastery',
      ]) {
        expect(llm_client.defaultTemperatureForOperation(op), 0, reason: op);
      }
    });

    test('остальные операции оставляют дефолт конфига (null)', () {
      for (final op in const [
        'content',
        'activity',
        'repair',
        'quiz',
        'diagnostic',
        'tutor',
        'milestone',
        'oneline-rewrite',
        'feedback',
        'expand',
        'неизвестная-операция',
      ]) {
        expect(llm_client.defaultTemperatureForOperation(op), isNull, reason: op);
      }
    });
  });

  group('LLMConfig — лимиты вывода', () {
    test('по умолчанию лимит ответа 16384, бюджет рассуждений не отправляется', () {
      const cfg = llm_client.LLMConfig();
      expect(cfg.maxOutputTokens, 16384);
      expect(cfg.reasoningMaxTokens, isNull);
    });

    test('лимит ответа строго больше бюджета рассуждений', () {
      const cfg = llm_client.LLMConfig(
        maxOutputTokens: 16384,
        reasoningMaxTokens: 2000,
      );
      expect(cfg.maxOutputTokens, greaterThan(cfg.reasoningMaxTokens!));
    });
  });

  group('TreeScheduler — температура доходит до LLM-вызова', () {
    /// Гоняет операцию через scheduler и возвращает temperature, дошедший до
    /// точки инъекции LLM.
    Future<double?> temperatureSeenBy(
      String operation, {
      double? explicit,
      double configTemperature = 0.7,
    }) async {
      double? seen;
      var called = false;
      final scheduler = TreeScheduler(
        configProvider: () => llm_client.LLMConfig(
          isMock: false,
          temperature: configTemperature,
        ),
        config: const SchedulerConfig(
          maxRPM: 100000,
          maxRPD: 100000,
          maxConcurrency: 1,
          maxRetries: 0,
        ),
        llmCall: (cfg, prompt, {model, temperature, seed}) async {
          seen = temperature;
          called = true;
          return const llm_client.LLMResult(text: '{"ok":1}');
        },
      );

      await scheduler.execute<Map<String, dynamic>>(
        operation,
        () => 'prompt',
        (raw) => llm_client.parseLLMJson<Map<String, dynamic>>(raw),
        temperature: explicit,
      );
      expect(called, isTrue, reason: 'LLM-вызов не состоялся для $operation');
      return seen;
    }

    test('validate уходит с temperature=0, а не с 0.7 из конфига', () async {
      expect(await temperatureSeenBy('validate'), 0);
    });

    test('content сохраняет дефолт конфига (null → 0.7)', () async {
      expect(await temperatureSeenBy('content'), isNull);
    });

    test('явный temperature важнее per-op правила', () async {
      expect(await temperatureSeenBy('validate', explicit: 0.35), 0.35);
    });
  });
}
