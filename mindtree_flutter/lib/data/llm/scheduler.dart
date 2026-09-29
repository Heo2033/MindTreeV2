import 'dart:async';

import 'client.dart';
import 'cache.dart';
import 'telemetry.dart';

// ─── Scheduler config ─────────────────────────────────────────────────────────

class SchedulerConfig {
  final int maxRPM;
  final int maxRPD;
  final int maxConcurrency;
  final int maxRetries;
  final int batchSize;
  /// Общий дедлайн одной LLM-операции (мс): ограничивает ожидание слота и
  /// старт новых попыток/моделей. Сам уже запущенный запрос дедлайном НЕ
  /// прерывается — его жёсткая граница — клиентский LLMConfig.timeoutMs
  /// (по умолчанию 180 с), зеркально server client.ts (controller.abort()).
  /// 0 — без лимита. По умолчанию 120 с (как серверный readOpDeadlineMs()).
  final int opDeadlineMs;

  const SchedulerConfig({
    this.maxRPM = 10,
    this.maxRPD = 500,
    this.maxConcurrency = 2,
    this.maxRetries = 3,
    this.batchSize = 3,
    this.opDeadlineMs = 120000,
  });
}

// ─── Rate tracker ─────────────────────────────────────────────────────────────

class _RateTracker {
  final List<int> timestamps = [];
  final int windowMs;

  _RateTracker({required this.windowMs});

  void cleanup() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - windowMs;
    timestamps.removeWhere((t) => t <= cutoff);
  }

  bool get isFull => timestamps.length >= _limit;
  int _limit = 999;
  set limit(int v) => _limit = v;

  int get waitMs {
    if (timestamps.isEmpty) return 0;
    final oldest = timestamps.first;
    return windowMs - (DateTime.now().millisecondsSinceEpoch - oldest);
  }
}

// ─── Execute result ───────────────────────────────────────────────────────────

class ExecuteResult<T> {
  final T result;
  final LLMResult llmResult;
  final bool cached;
  const ExecuteResult({required this.result, required this.llmResult, this.cached = false});
}

/// Точка инъекции LLM-вызова (для тестов дедлайна): заменяет глобальный callLLM.
typedef LLMInvoke = Future<LLMResult> Function(
  LLMConfig cfg,
  String prompt, {
  String? model,
  double? temperature,
  int? seed,
});

// ─── TreeScheduler ────────────────────────────────────────────────────────────

class TreeScheduler {
  final SchedulerConfig config;
  final LLMCache cache;
  final LLMTelemetry telemetry;
  final LLMConfig Function() _configProvider;
  final LLMInvoke? _llmCallOverride;
  final _rpmTracker = _RateTracker(windowMs: 60000);
  final _rpdTracker = _RateTracker(windowMs: 86400000);
  int _running = 0;

  /// FIFO-очередь ожидающих слот. Без неё слот достаётся тому, кто чаще
  /// пере-поллит, а не тому, кто ждал дольше: при параллельных воркерах один
  /// быстрый воркер мог монополизировать `maxConcurrency=1` и морить остальных
  /// (реальный дедлок в probe при пуле контента 4×1).
  final _waitQueue = <Object>[];

  TreeScheduler({
    required LLMConfig Function() configProvider,
    SchedulerConfig? config,
    LLMCache? cache,
    LLMTelemetry? telemetry,
    LLMInvoke? llmCall,
  })  : config = config ?? const SchedulerConfig(),
        cache = cache ?? LLMCache(),
        telemetry = telemetry ?? LLMTelemetry(),
        _llmCallOverride = llmCall,
        _configProvider = configProvider {
    _rpmTracker.limit = this.config.maxRPM;
    _rpdTracker.limit = this.config.maxRPD;
  }

  Future<LLMResult> _invokeLLM(
    LLMConfig cfg,
    String prompt, {
    String? model,
    double? temperature,
    int? seed,
  }) =>
      _llmCallOverride != null
          ? _llmCallOverride(cfg, prompt, model: model, temperature: temperature, seed: seed)
          : callLLM(cfg, prompt, model: model, temperature: temperature, seed: seed);

  int get runningCount => _running;
  int get batchLimit => config.batchSize;
  int get maxConcurrency => config.maxConcurrency;

  bool _canExecute() {
    _rpmTracker.cleanup();
    _rpdTracker.cleanup();
    return _running < config.maxConcurrency &&
        !_rpmTracker.isFull &&
        !_rpdTracker.isFull;
  }

  Future<void> _waitForSlot([DateTime? deadline]) async {
    // Свободный слот и пустая очередь — берём без ожидания.
    if (_canExecute() && _waitQueue.isEmpty) return;

    // Встаём в очередь. Разбудить нас может только собственная пере-проверка
    // после паузы (поллинг остаётся), но выход из цикла разрешён лишь тому,
    // кто стоит первым в очереди: слот отдаётся в порядке ожидания, а не
    // «кто быстрее поллит».
    final token = Object();
    _waitQueue.add(token);
    try {
      while (!_canExecute() || _waitQueue.first != token) {
        if (deadline != null && !DateTime.now().isBefore(deadline)) {
          throw Exception('Timed out waiting for LLM scheduler slot');
        }
        final wait = _timeToNextSlotMs();
        if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      }
    } finally {
      _waitQueue.remove(token);
    }
  }

  int _timeToNextSlotMs() {
    var wait = 50;
    for (final tracker in [_rpmTracker, _rpdTracker]) {
      // Лимит блокирует только когда трекер полон. `waitMs` — время, через
      // которое старейший вызов покинет окно; для неполного трекера это
      // бессмысленные 60 с / 24 ч, и спать столько нельзя (реальный дедлок:
      // первый же воркер в очереди уходил в сон на сутки).
      if (!tracker.isFull) continue;
      final remaining = tracker.waitMs;
      if (remaining > wait) wait = remaining;
    }
    if (_running >= config.maxConcurrency && wait < 50) wait = 50;
    return wait;
  }

  void _acquire() {
    _running++;
    _rpmTracker.timestamps.add(DateTime.now().millisecondsSinceEpoch);
    _rpdTracker.timestamps.add(DateTime.now().millisecondsSinceEpoch);
  }

  void _release() {
    _running--;
  }

  /// Execute a non-streaming LLM call with caching, rate limiting, retry, and model fallback.
  Future<ExecuteResult<T>> execute<T>(
    String operation,
    String Function() promptFn,
    T Function(String raw) parseFn, {
    String? cacheKey,
    List<String>? nodeIds,
    String? promptVersion,
    String? model,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final deadline = config.opDeadlineMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(startTime + config.opDeadlineMs)
        : null;
    Object? lastError;
    var attemptsMade = 0;

    final cfg = _configProvider();
    final allModels = model != null
        ? [model]
        : modelsForTier(cfg, tierForOperation(operation));

    for (final m in allModels) {
      final key = cacheKey != null
          ? LLMCache.buildKey(model: m, operation: operation, promptVersion: promptVersion ?? '1', contextHash: cacheKey)
          : null;

      if (key != null) {
        final cached = cache.get<T>(key);
        if (cached != null) {
          return ExecuteResult(
            result: cached,
            llmResult: const LLMResult(text: '', usage: LLMUsage()),
            cached: true,
          );
        }
      }

      var modelFailed = false;
      for (var attempt = 0; attempt <= config.maxRetries; attempt++) {
        // Дедлайн операции: не начинаем новую попытку, если лимит исчерпан
        // (зеркально server scheduler: Date.now() >= deadline → break).
        if (deadline != null && !DateTime.now().isBefore(deadline)) {
          modelFailed = true;
          break;
        }
        await _waitForSlot(deadline);
        _acquire();

        try {
          final prompt = promptFn();
          // Запущенный запрос дедлайном не прерывается (зеркально server):
          // если провайдер отвечает медленно, но успешно (L2/L3-структура),
          // вызов должен завершиться. Жёсткая граница «висящего» запроса —
          // клиентский LLMConfig.timeoutMs (по умолчанию 180 с).
          final attemptStart = DateTime.now().millisecondsSinceEpoch;
          final llmResult = await _invokeLLM(cfg, prompt, model: m);
          final attemptMs = DateTime.now().millisecondsSinceEpoch - attemptStart;
          final result = parseFn(llmResult.text);
          attemptsMade = attempt + 1;

          telemetry.trackTiming(CallTiming(
            operation: operation,
            model: m,
            durationMs: attemptMs,
            ok: true,
          ));

          if (key != null) cache.set(key, result);

          telemetry.track(OperationTelemetry(
            ts: DateTime.now().toIso8601String(),
            operation: operation,
            nodeIds: nodeIds ?? [],
            model: m,
            inputTokens: llmResult.usage.inputTokens,
            outputTokens: llmResult.usage.outputTokens,
            latencyMs: DateTime.now().millisecondsSinceEpoch - startTime,
            retryCount: attempt,
            estimatedCost: estimateCostForUsage(m, llmResult.usage.inputTokens, llmResult.usage.outputTokens),
          ));

          _release();
          return ExecuteResult(result: result, llmResult: llmResult, cached: false);
        } catch (e) {
          _release();
          lastError = e;
          attemptsMade = attempt + 1;

          // Проваленная попытка тоже стоила времени (таймаут, 5xx, битый
          // JSON) — пишем её длительность, иначе вклад ошибок в латентность
          // не виден в метриках.
          telemetry.trackTiming(CallTiming(
            operation: operation,
            model: m,
            durationMs: DateTime.now().millisecondsSinceEpoch - startTime,
            ok: false,
          ));

          if (shouldRetry(e, attempt, config.maxRetries)) {
            final delay = retryDelayMs(e, attempt);
            if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
            continue;
          }
          modelFailed = true;
          break;
        }
      }
      if (modelFailed && allModels.indexOf(m) < allModels.length - 1) continue;
    }

    throw LLMRetriesExhaustedException(
      lastError is Exception ? lastError : Exception(lastError?.toString() ?? 'LLM request failed'),
      attemptsMade,
    );
  }

  /// Streaming execute: yields tokens one by one, with same rate limiting/retry/fallback.
  Stream<String> executeStream(
    String operation,
    String Function() promptFn, {
    String? model,
  }) async* {
    final cfg = _configProvider();
    final allModels = model != null
        ? [model]
        : modelsForTier(cfg, tierForOperation(operation));

    final startTime = DateTime.now().millisecondsSinceEpoch;
    final deadline = config.opDeadlineMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(startTime + config.opDeadlineMs)
        : null;
    Object? lastError;

    for (final m in allModels) {
      var modelFailed = false;
      for (var attempt = 0; attempt <= config.maxRetries; attempt++) {
        if (deadline != null && DateTime.now().isAfter(deadline)) {
          throw LLMRetriesExhaustedException(
            lastError is Exception ? lastError : Exception('Operation timeout'),
            attempt,
          );
        }
        await _waitForSlot(deadline);
        _acquire();
        var released = false;
        void doRelease() {
          if (released) return;
          released = true;
          _release();
        }

        try {
          final prompt = promptFn();
          var any = false;
          // Чтение стрима ограничено клиентским callLLMStream (LLMConfig.timeoutMs),
          // зеркально server (controller.abort() по истечении timeoutMs).
          await for (final token in callLLMStream(cfg, prompt, model: m)) {
            any = true;
            yield token;
          }
          if (!any) throw Exception('LLM returned empty stream');
          doRelease();

          telemetry.track(OperationTelemetry(
            ts: DateTime.now().toIso8601String(),
            operation: operation,
            model: m,
            inputTokens: (prompt.length / 4).ceil(),
            outputTokens: 0,
            latencyMs: DateTime.now().millisecondsSinceEpoch - startTime,
            retryCount: attempt,
          ));
          return;
        } catch (e) {
          lastError = e;
          doRelease();

          if (e is LLMMockException) {
            throw LLMRetriesExhaustedException(e, attempt);
          }
          if (shouldRetry(e, attempt, config.maxRetries)) {
            final delay = retryDelayMs(e, attempt);
            if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
            continue;
          }
          modelFailed = true;
          break;
        }
      }
      if (modelFailed && allModels.indexOf(m) < allModels.length - 1) continue;
    }

    throw LLMRetriesExhaustedException(
      lastError is Exception ? lastError : Exception('LLM request failed'),
      0,
    );
  }

  Map<String, dynamic> stats() {
    _rpmTracker.cleanup();
    _rpdTracker.cleanup();
    final timings = telemetry.callTimings();
    return {
      'rpm': _rpmTracker.timestamps.length,
      'rpd': _rpdTracker.timestamps.length,
      'running': _running,
      'cache': cache.stats(),
      // Проваленные попытки раньше нигде не учитывались: телеметрия писалась
      // только после успеха, и по ней нельзя было отличить «долго, но верно»
      // от «долго, потому что трижды упало».
      'transportAttempts': timings.length,
      'failedAttempts': timings.where((t) => !t.ok).length,
    };
  }
}
