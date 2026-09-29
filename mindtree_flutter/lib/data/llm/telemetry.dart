/// In-memory telemetry log for LLM operations.
class LLMTelemetry {
  final List<OperationTelemetry> _ops = [];
  final List<CallTiming> _timings = [];
  static const int _maxEntries = 10000;

  void track(OperationTelemetry op) {
    _ops.add(op);
    if (_ops.length > _maxEntries) _ops.removeAt(0);
  }

  /// Записывает длительность ОДНОЙ транспортной попытки — включая неуспешные.
  ///
  /// [OperationTelemetry] пишется только после успеха, поэтому по нему
  /// нельзя понять, сколько времени ушло на проваленные попытки: их вклад в
  /// латентность просто исчезал. Именно поэтому в `run-stats.json` было
  /// `retries: 0` при фактических трёх попытках.
  void trackTiming(CallTiming timing) {
    _timings.add(timing);
    if (_timings.length > _maxEntries) _timings.removeAt(0);
  }

  /// Длительности всех транспортных попыток, в порядке поступления.
  List<CallTiming> callTimings() => List.unmodifiable(_timings);

  AggregateStats aggregateStats() {
    if (_ops.isEmpty) {
      return const AggregateStats(count: 0, totalCost: 0, totalInput: 0, totalOutput: 0);
    }
    var totalCost = 0.0;
    var totalInput = 0;
    var totalOutput = 0;
    for (final op in _ops) {
      totalCost += op.estimatedCost;
      totalInput += op.inputTokens;
      totalOutput += op.outputTokens;
    }
    return AggregateStats(
      count: _ops.length,
      totalCost: totalCost,
      totalInput: totalInput,
      totalOutput: totalOutput,
    );
  }

  List<OperationTelemetry> recentOperations({int limit = 50}) {
    final start = _ops.length - limit;
    return _ops.getRange(start < 0 ? 0 : start, _ops.length).toList().reversed.toList();
  }
}

class OperationTelemetry {
  final String ts;
  final String operation;
  final List<String> nodeIds;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int latencyMs;
  final int retryCount;
  final bool cacheHit;
  final double estimatedCost;

  const OperationTelemetry({
    required this.ts,
    required this.operation,
    this.nodeIds = const [],
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.latencyMs,
    this.retryCount = 0,
    this.cacheHit = false,
    this.estimatedCost = 0,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'operation': operation,
        'node_ids': nodeIds,
        'model': model,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'latency_ms': latencyMs,
        'retry_count': retryCount,
        'cache_hit': cacheHit,
        'estimated_cost': estimatedCost,
      };
}

/// Длительность одной транспортной попытки `callLLM` (одна операция scheduler
/// может сделать несколько попыток: модели, retry, варианты тела запроса).
///
/// [ok] = `false` — попытка завершилась ошибкой (таймаут, битый JSON, 5xx).
class CallTiming {
  final String operation;
  final String model;
  final int durationMs;
  final bool ok;

  const CallTiming({
    required this.operation,
    required this.model,
    required this.durationMs,
    required this.ok,
  });

  Map<String, dynamic> toJson() => {
        'operation': operation,
        'model': model,
        'duration_ms': durationMs,
        'ok': ok,
      };
}

class AggregateStats {  final int count;
  final double totalCost;
  final int totalInput;
  final int totalOutput;

  const AggregateStats({
    required this.count,
    required this.totalCost,
    required this.totalInput,
    required this.totalOutput,
  });
}

/// Estimate cost for a model (USD).
double estimateCostForUsage(String model, int inputTokens, int outputTokens) {
  final m = model.toLowerCase();
  if (m.contains('gpt-4o')) return (inputTokens * 2.5 + outputTokens * 10) / 1000000;
  if (m.contains('gpt-4o-mini')) return (inputTokens * 0.15 + outputTokens * 0.6) / 1000000;
  if (m.contains('gpt-3.5')) return (inputTokens * 0.5 + outputTokens * 1.5) / 1000000;
  return 0;
}
