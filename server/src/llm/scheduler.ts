import {
  callLLM,
  getModelsForTier,
  LLMMockError,
  LLMRateLimitError,
  LLMRetriesExhaustedError,
  type ModelTier,
} from "./client.js";
import { LLMCache } from "./cache.js";
import { trackOperation } from "./telemetry.js";
import type { ILLMResult } from "./client.js";

export interface SchedulerConfig {
  maxRPM?: number;
  maxRPD?: number;
  maxConcurrency?: number;
  maxRetries?: number;
  batchSize?: number;
  windowMs?: number;
}

interface RateTracker {
  timestamps: number[];
  windowMs: number;
}

type RequiredCoreConfig = Required<Omit<SchedulerConfig, "windowMs">>;

const DEFAULT_CONFIG: RequiredCoreConfig = {
  maxRPM: 10,
  maxRPD: 500,
  maxConcurrency: 2,
  maxRetries: 3,
  batchSize: 3,
};

function readEnvInt(name: string): number | undefined {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return undefined;
  const num = Number(raw);
  if (!Number.isFinite(num) || num <= 0) return undefined;
  return Math.trunc(num);
}

export function readSchedulerConfigFromEnv(): RequiredCoreConfig {
  return {
    maxRPM: readEnvInt("LLM_MAX_RPM") ?? DEFAULT_CONFIG.maxRPM,
    maxRPD: readEnvInt("LLM_MAX_RPD") ?? DEFAULT_CONFIG.maxRPD,
    maxConcurrency: readEnvInt("LLM_MAX_CONCURRENCY") ?? DEFAULT_CONFIG.maxConcurrency,
    maxRetries: readEnvInt("LLM_MAX_RETRIES") ?? DEFAULT_CONFIG.maxRetries,
    batchSize: readEnvInt("LLM_MAX_BATCH_SIZE") ?? DEFAULT_CONFIG.batchSize,
  };
}

const STRONG_OPERATIONS = new Set(["structure", "validate", "repair", "quiz", "curriculum", "diagnostic", "assessment", "mastery", "tutor", "milestone"]);

export function tierForOperation(operation: string): ModelTier {
  return STRONG_OPERATIONS.has(operation) ? "strong" : "fast";
}

const GATEWAY_RETRY_STATUSES = new Set([502, 503, 504]);

function extractStatus(err: Error): number | null {
  if (err instanceof LLMRateLimitError) return err.status;
  if (err.name === "LLMRateLimitError") {
    const status = (err as { status?: unknown }).status;
    if (typeof status === "number") return status;
  }
  const m = /\((\d{3})\)/.exec(err.message);
  return m ? Number(m[1]) : null;
}

function retryAfterOf(err: Error): number | null {
  if (err instanceof LLMRateLimitError) return err.retryAfter;
  if (err.name !== "LLMRateLimitError") return null;
  const v = (err as { retryAfter?: unknown }).retryAfter;
  return typeof v === "number" ? v : null;
}

export function retryDelayMs(err: Error, attempt: number): number {
  const status = extractStatus(err);
  if (status === null) return (attempt + 1) * 2000;
  if (status === 429) {
    const ra = retryAfterOf(err);
    return ra !== null
      ? Math.max(0, ra) * 1000
      : (attempt + 1) * 10_000;
  }
  const ra = retryAfterOf(err);
  const capS = (attempt + 1) * 10;
  const waitS = Math.min(Math.max(ra ?? 10, 0), capS);
  return waitS * 1000;
}

export function shouldRetry(err: Error, attempt: number, maxRetries: number): boolean {
  if (attempt >= maxRetries) return false;
  // В офлайн-режиме повторные попытки бессмысленны — сразу переходим к фолбэку.
  if (err instanceof LLMMockError) return false;
  const status = extractStatus(err);
  if (status !== null && GATEWAY_RETRY_STATUSES.has(status) && attempt >= 2) {
    return false;
  }
  return true;
}

export class TreeScheduler {
  private config: RequiredCoreConfig & { windowMs?: number };
  private rpmTracker: RateTracker;
  private rpdTracker: RateTracker;
  private running = 0;
  private cache: LLMCache;

  constructor(config?: SchedulerConfig, cache?: LLMCache) {
    this.config = { ...readSchedulerConfigFromEnv(), ...config };
    this.rpmTracker = { timestamps: [], windowMs: this.config.windowMs ?? 60_000 };
    this.rpdTracker = { timestamps: [], windowMs: this.config.windowMs ?? 86_400_000 };
    this.cache = cache ?? new LLMCache();
  }

  get cacheStore(): LLMCache {
    return this.cache;
  }

  get batchLimit(): number {
    return this.config.batchSize;
  }

  private canExecute(): boolean {
    this.cleanupTracker(this.rpmTracker);
    this.cleanupTracker(this.rpdTracker);
    return (
      this.running < this.config.maxConcurrency &&
      this.rpmTracker.timestamps.length < this.config.maxRPM &&
      this.rpdTracker.timestamps.length < this.config.maxRPD
    );
  }

  private cleanupTracker(tracker: RateTracker): void {
    const cutoff = Date.now() - tracker.windowMs;
    tracker.timestamps = tracker.timestamps.filter((t) => t > cutoff);
  }

  private async waitForSlot(): Promise<void> {
    while (!this.canExecute()) {
      await sleep(this.timeToNextSlotMs());
    }
  }

  private timeToNextSlotMs(): number {
    let wait = 50;
    for (const tracker of [this.rpmTracker, this.rpdTracker]) {
      const oldest = tracker.timestamps[0];
      if (oldest !== undefined) {
        const remaining = tracker.windowMs - (Date.now() - oldest);
        if (remaining > wait) wait = remaining;
      }
    }
    if (this.running >= this.config.maxConcurrency) wait = Math.max(wait, 50);
    return wait;
  }

  private acquire(): void {
    this.running++;
    this.rpmTracker.timestamps.push(Date.now());
    this.rpdTracker.timestamps.push(Date.now());
  }

  private release(): void {
    this.running--;
  }

  async execute<T>(
    operation: string,
    promptFn: () => string,
    parseFn: (raw: string) => T,
    options?: {
      cacheKey?: string;
      nodeIds?: string[];
      promptVersion?: string;
      model?: string;
    },
  ): Promise<{ result: T; llmResult: ILLMResult; cached: boolean }> {
    const startTime = Date.now();
    let lastError: Error | null = null;
    let attemptsMade = 0;
    let lastPromptLength = 0;

    const allModels = options?.model
      ? [options.model]
      : getModelsForTier(tierForOperation(operation));

    for (const model of allModels) {
      const key = options?.cacheKey
        ? LLMCache.buildKey({
            model,
            operation,
            promptVersion: options.promptVersion ?? "1",
            contextHash: options.cacheKey,
          })
        : undefined;

      if (key) {
        const cached = this.cache.get<T>(key);
        if (cached !== null) {
          const cachedResult: ILLMResult = { text: "", usage: { input_tokens: 0, output_tokens: 0 } };
          return { result: cached, llmResult: cachedResult, cached: true };
        }
      }

      let modelFailed = false;
      for (let attempt = 0; attempt <= this.config.maxRetries; attempt++) {
        await this.waitForSlot();
        this.acquire();

        try {
          const prompt = promptFn();
          lastPromptLength = prompt.length;
          const llmResult = await callLLM(prompt, { model });
          const result = parseFn(llmResult.text);
          attemptsMade = attempt + 1;

          if (key) {
            this.cache.set(key, result);
          }

          trackOperation({
            operation,
            node_ids: options?.nodeIds ?? [],
            model,
            input_tokens: llmResult.usage.input_tokens,
            output_tokens: llmResult.usage.output_tokens,
            latency_ms: Date.now() - startTime,
            retry_count: attempt,
            cache_hit: false,
            estimated_cost: estimateCost(model, llmResult.usage.input_tokens, llmResult.usage.output_tokens),
          });

          this.release();
          return { result, llmResult, cached: false };
        } catch (err) {
          this.release();
          lastError = err instanceof Error ? err : new Error("Ошибка LLM");
          attemptsMade = attempt + 1;
          console.warn(
            `[scheduler] ${operation}/${model} попытка ${attempt + 1}: ${lastError.message.slice(0, 120)} (промпт ${lastPromptLength} симв.)`,
          );

          if (shouldRetry(lastError, attempt, this.config.maxRetries)) {
            await sleep(retryDelayMs(lastError, attempt));
            continue;
          }
          modelFailed = true;
          break;
        }
        attemptsMade = attempt + 1;
      }
      if (modelFailed && allModels.indexOf(model) < allModels.length - 1) {
        console.warn(`[scheduler] ${operation}: модель ${model} исчерпана, пробуем fallback...`);
        continue;
      }
    }

    throw new LLMRetriesExhaustedError(
      lastError ?? new Error("Не удалось выполнить LLM-запрос"),
      attemptsMade,
    );
  }

  stats(): { rpm: number; rpd: number; running: number; cache: ReturnType<LLMCache["stats"]> } {
    this.cleanupTracker(this.rpmTracker);
    this.cleanupTracker(this.rpdTracker);
    return {
      rpm: this.rpmTracker.timestamps.length,
      rpd: this.rpdTracker.timestamps.length,
      running: this.running,
      cache: this.cache.stats(),
    };
  }
}

const SCHEDULER_GLOBAL_KEY = "__mindtree_scheduler__";
const CACHE_GLOBAL_KEY = "__mindtree_llm_cache__";

interface GlobalSchedulerStore {
  [SCHEDULER_GLOBAL_KEY]?: TreeScheduler;
  [CACHE_GLOBAL_KEY]?: LLMCache;
}

function globalStore(): GlobalSchedulerStore {
  return globalThis as unknown as GlobalSchedulerStore;
}

export function getScheduler(): TreeScheduler {
  const store = globalStore();
  if (!store[SCHEDULER_GLOBAL_KEY]) {
    store[SCHEDULER_GLOBAL_KEY] = new TreeScheduler({}, getCache());
  }
  return store[SCHEDULER_GLOBAL_KEY];
}

export function getCache(): LLMCache {
  const store = globalStore();
  if (!store[CACHE_GLOBAL_KEY]) {
    const dir = process.env.LLM_CACHE_DIR;
    const persistDir = dir === "off" || dir === "" ? null : dir || ".cache/llm";
    store[CACHE_GLOBAL_KEY] = new LLMCache({ persistDir });
  }
  return store[CACHE_GLOBAL_KEY];
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function estimateCost(model: string, inputTokens: number, outputTokens: number): number {
  const m = model.toLowerCase();
  if (m.includes("gpt-4o")) return (inputTokens * 2.5 + outputTokens * 10) / 1_000_000;
  if (m.includes("gpt-4o-mini")) return (inputTokens * 0.15 + outputTokens * 0.6) / 1_000_000;
  if (m.includes("gpt-3.5")) return (inputTokens * 0.5 + outputTokens * 1.5) / 1_000_000;
  return 0;
}
