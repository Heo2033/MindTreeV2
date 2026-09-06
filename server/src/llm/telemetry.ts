export interface OperationTelemetry {
  ts: string;
  operation: string;
  node_ids: string[];
  model: string;
  input_tokens: number;
  output_tokens: number;
  latency_ms: number;
  retry_count: number;
  cache_hit: boolean;
  estimated_cost: number;
}

const ops: OperationTelemetry[] = [];

export function trackOperation(telemetry: Omit<OperationTelemetry, "ts">): void {
  ops.push({ ...telemetry, ts: new Date().toISOString() });
  // Keep memory bounded
  if (ops.length > 10_000) ops.shift();
}

export function aggregateStats() {
  if (ops.length === 0) return { count: 0, totalCost: 0, totalInput: 0, totalOutput: 0 };
  return {
    count: ops.length,
    totalCost: ops.reduce((s, o) => s + o.estimated_cost, 0),
    totalInput: ops.reduce((s, o) => s + o.input_tokens, 0),
    totalOutput: ops.reduce((s, o) => s + o.output_tokens, 0),
  };
}

export function recentOperations(limit = 50): OperationTelemetry[] {
  return ops.slice(-limit).reverse();
}

export function estimateCostForUsage(model: string, inputTokens: number, outputTokens: number): number {
  const m = model.toLowerCase();
  if (m.includes("gpt-4o")) return (inputTokens * 2.5 + outputTokens * 10) / 1_000_000;
  if (m.includes("gpt-4o-mini")) return (inputTokens * 0.15 + outputTokens * 0.6) / 1_000_000;
  if (m.includes("gpt-3.5")) return (inputTokens * 0.5 + outputTokens * 1.5) / 1_000_000;
  return 0;
}
