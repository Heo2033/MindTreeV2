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

// ─── TreeScheduler ────────────────────────────────────────────────────────────

class TreeScheduler {
  final SchedulerConfig config;
  final LLMCache cache;
  final LLMTelemetry telemetry;
  final LLMConfig Function() _configProvider;
  final _rpmTracker = _RateTracker(windowMs: 60000);
  final _rpdTracker = _RateTracker(windowMs: 86400000);
  int _running = 0;

  TreeScheduler({
    required LLMConfig Function() configProvider,
    SchedulerConfig? config,
    LLMCache? cache,
    LLMTelemetry? telemetry,
  })  : config = config ?? const SchedulerConfig(),
        cache = cache ?? LLMCache(),
        telemetry = telemetry ?? LLMTelemetry(),
        _configProvider = configProvider {
    _rpmTracker.limit = this.config.maxRPM;
    _rpdTracker.limit = this.config.maxRPD;
  }

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
    while (!_canExecute()) {
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        throw Exception('Timed out waiting for LLM scheduler slot');
      }
      final wait = _timeToNextSlotMs();
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
    }
  }

  int _timeToNextSlotMs() {
    var wait = 50;
    for (final tracker in [_rpmTracker, _rpdTracker]) {
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
        await _waitForSlot(deadline);
        _acquire();

        try {
          final prompt = promptFn();
          final llmResult = await callLLM(cfg, prompt, model: m);
          final result = parseFn(llmResult.text);
          attemptsMade = attempt + 1;

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
    return {
      'rpm': _rpmTracker.timestamps.length,
      'rpd': _rpdTracker.timestamps.length,
      'running': _running,
      'cache': cache.stats(),
    };
  }
}
