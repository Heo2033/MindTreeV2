import {
  callLLM,
  callLLMStream,
  defaultTemperatureForOperation,
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
  /** Общий дедлайн одной операции (мс); 0/undefined — без лимита. */
  opDeadlineMs?: number;
}

interface RateTracker {
  timestamps: number[];
  windowMs: number;
}

type RequiredCoreConfig = Required<Omit<SchedulerConfig, "windowMs" | "opDeadlineMs">>;

const DEFAULT_CONFIG: RequiredCoreConfig = {
  // Потолок запросов в минуту и одновременных запросов. Раньше здесь стояли
  // 10 RPM и 2 одновременных запроса (один вызов каждые 6 секунд). Замер живым
  // бурстом показал, что провайдер держит заметно больше: 15 одновременных
  // запросов на fast-модели прошли без единого 429 (≈410 вызовов/мин), 8
  // одновременных на strong — тоже без 429 (≈88 вызовов/мин). На живом прогоне
  // дерева из 20 узлов старое ограничение давало ~234 с чистого ожидания лимита
  // из 320 с wall clock — скорость задавал темп запросов, а не алгоритм.
  maxRPM: 60,
  maxRPD: 500,
  maxConcurrency: 6,
  maxRetries: 3,
  batchSize: 3,
};

/**
 * Общий дедлайн на одну LLM-операцию (мс). По умолчанию 120 с, чтобы ни одна
 * операция (в т.ч. ожидание слота) не висла бесконечно. Переопределяется env
 * LLM_OP_TIMEOUT_MS; значение "0"/"off" отключает лимит.
 */
function readOpDeadlineMs(): number {
  const raw = process.env.LLM_OP_TIMEOUT_MS;
  if (raw === undefined || raw === "") return 120_000;
  const trimmed = raw.trim().toLowerCase();
  if (trimmed === "0" || trimmed === "off") return 0;
  const num = Number(raw);
  if (!Number.isFinite(num) || num <= 0) return 120_000;
  return Math.trunc(num);
}

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

// repair в fast-тиру (зеркало client.dart от 2026-09-30): работает только по
// проблемным узлам, а при неудаче дерево остаётся в прежнем состоянии.
const STRONG_OPERATIONS = new Set(["structure", "structure-l2", "structure-l3", "validate", "quiz", "curriculum", "diagnostic", "assessment", "mastery", "tutor", "milestone"]);

export function tierForOperation(operation: string): ModelTier {
  return STRONG_OPERATIONS.has(operation) ? "strong" : "fast";
}

const GATEWAY_RETRY_STATUSES = new Set([502, 503, 504]);

/**
 * Защитный потолок повторных попыток при рейт-лимите (429/408), если дедлайн
 * операции отключён (LLM_OP_TIMEOUT_MS=0). Ретраи при рейт-лимите НЕ расходуют
 * бюджет maxRetries — планировщик «пытается, пока не получится» в пределах
 * дедлайна операции (или этого потолка).
 */
const RATE_LIMIT_RETRY_CAP = 20;

function extractStatus(err: Error): number | null {
  if (err instanceof LLMRateLimitError) return err.status;
  if (err.name === "LLMRateLimitError") {
    const status = (err as { status?: unknown }).status;
    if (typeof status === "number") return status;
  }
  const m = /\((\d{3})\)/.exec(err.message);
  return m ? Number(m[1]) : null;
}

/** Ошибки рейт-лимита (429/408): их ретраим вплоть до дедлайна операции. */
export function isRateLimitError(err: Error): boolean {
  const status = extractStatus(err);
  return status === 408 || status === 429;
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
  // Перманентный 4xx повтором не лечится: реальный случай — провайдер отвечал
  // 400 «модель не найдена», и на него тратились все попытки впустую.
  if (status !== null && isPermanentLLMErrorStatus(status)) return false;
  if (status !== null && GATEWAY_RETRY_STATUSES.has(status) && attempt >= 2) {
    return false;
  }
  return true;
}

/** Ошибка, которую повтор не исправит: неверное имя модели, ключ, формат. */
export function isPermanentLLMErrorStatus(status: number): boolean {
  // 408/429 — временные, их ретраим.
  if (status === 408 || status === 429) return false;
  return status >= 400 && status < 500;
}

export class TreeScheduler {
  private config: RequiredCoreConfig & { windowMs?: number };
  private rpmTracker: RateTracker;
  private rpdTracker: RateTracker;
  private running = 0;
  private cache: LLMCache;
  private opDeadlineMs: number;

  /**
   * Хук прогресса при ожидании рейт-лимита (429/408): вызывается перед паузой
   * перед следующей попыткой. Позволяет отдавать в UI сообщение вроде
   * «Сервис ограничил частоту запросов — повторяю…» вместо «застрявшего» спиннера.
   */
  onBackoff: ((delayMs: number, attempt: number) => void) | null = null;

  constructor(config?: SchedulerConfig, cache?: LLMCache) {
    this.config = { ...readSchedulerConfigFromEnv(), ...config };
    this.rpmTracker = { timestamps: [], windowMs: this.config.windowMs ?? 60_000 };
    this.rpdTracker = { timestamps: [], windowMs: this.config.windowMs ?? 86_400_000 };
    this.opDeadlineMs = config?.opDeadlineMs ?? readOpDeadlineMs();
    this.cache = cache ?? new LLMCache();
  }

  get cacheStore(): LLMCache {
    return this.cache;
  }

  get batchLimit(): number {
    return this.config.batchSize;
  }

  /** Максимум одновременных LLM-запросов (слоты планировщика). */
  get maxConcurrency(): number {
    return this.config.maxConcurrency;
  }

  /** Текущее число выполняющихся LLM-запросов. */
  get runningCount(): number {
    return this.running;
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

  private async waitForSlot(deadline?: number): Promise<void> {
    while (!this.canExecute()) {
      if (deadline !== undefined && Date.now() >= deadline) {
        throw new Error("Таймаут ожидания слота LLM-планировщика");
      }
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
      temperature?: number;
    },
  ): Promise<{ result: T; llmResult: ILLMResult; cached: boolean }> {
    const startTime = Date.now();
    const deadline =
      this.opDeadlineMs > 0 ? startTime + this.opDeadlineMs : undefined;
    let lastError: Error | null = null;
    let attemptsMade = 0;
    // Последний отказ был перманентным (неверная модель/ключ/запрос) — такой
    // повторами не лечится, и его надо показать как есть, а не как
    // «исчерпаны попытки». Объявлено вне цикла по моделям.
    let permanentFailure = false;
    let lastPromptLength = 0;

    const allModels = options?.model
      ? [options.model]
      : getModelsForTier(tierForOperation(operation));

    // Детерминированные операции (`validate`, `structure*`, `assessment`, ...)
    // идут при temperature=0: контракт фиксирован, нужна воспроизводимость.
    // Явный `options.temperature` всегда важнее (зеркало flutter scheduler).
    const temperature = options?.temperature ?? defaultTemperatureForOperation(operation);

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
      for (let attempt = 0; ; attempt++) {
        if (deadline !== undefined && Date.now() >= deadline) {
          modelFailed = true;
          break;
        }
        await this.waitForSlot(deadline);
        this.acquire();

        try {
          const prompt = promptFn();
          lastPromptLength = prompt.length;
          const llmResult = await callLLM(prompt, { model, temperature });
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
            ...(llmResult.usage.reasoning_tokens !== undefined
              ? { reasoning_tokens: llmResult.usage.reasoning_tokens }
              : {}),
            ...(llmResult.usage.cost_rub !== undefined ? { cost_rub: llmResult.usage.cost_rub } : {}),
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

          // Рейт-лимит (429/408) ретраим до дедлайна операции, НЕ расходуя
          // бюджет maxRetries («пытаемся, пока не получится»). Прочие ошибки
          // по-прежнему ограничены maxRetries.
          const rateLimited = isRateLimitError(lastError);
          const timeLeft = deadline !== undefined ? deadline - Date.now() : Infinity;
          const retryAllowed = rateLimited
            ? attempt < RATE_LIMIT_RETRY_CAP
            : shouldRetry(lastError, attempt, this.config.maxRetries);

          if (!retryAllowed || timeLeft <= 0) {
            modelFailed = true;
            // Перманентный отказ (неверная модель/ключ/запрос) повторами не
            // лечится — запоминаем, чтобы показать его как есть, а не под
            // обёрткой «исчерпаны попытки» (зеркало flutter scheduler.execute).
            if (!rateLimited && isPermanentLLMErrorStatus(extractStatus(lastError) ?? 0)) {
              permanentFailure = true;
            }
            break;
          }

          const delay = Math.min(retryDelayMs(lastError, attempt), timeLeft);
          if (rateLimited) {
            this.onBackoff?.(delay, attempt);
          }
          await sleep(delay);
          continue;
        }
      }
      if (modelFailed && allModels.indexOf(model) < allModels.length - 1) {
        console.warn(`[scheduler] ${operation}: модель ${model} исчерпана, пробуем fallback...`);
        continue;
      }
    }

    const failure = lastError ?? new Error("Не удалось выполнить LLM-запрос");
    // Перманентный отказ повторами не лечится: обёртка «исчерпаны попытки» с
    // attempts=1 только прятала бы настоящую причину от пользователя.
    if (permanentFailure) throw failure;
    throw new LLMRetriesExhaustedError(failure, attemptsMade);
  }

  /**
   * Потоковая версия execute: отдаёт токены по мере генерации (SSE-тьютор).
   * Уважает те же ограничения (concurrency/RPM/RPD), перебирает кандидатов
   * моделей и ретраи, но ответ отдаётся построчно, а не целиком.
   * Внешний `signal` позволяет прервать запрос при закрытии соединения.
   */
  async *executeStream(
    operation: string,
    promptFn: () => string,
    options?: { model?: string; signal?: AbortSignal },
  ): AsyncIterableIterator<string> {
    const startTime = Date.now();
    const deadline =
      this.opDeadlineMs > 0 ? startTime + this.opDeadlineMs : null;
    let lastError: Error | null = null;

    if (deadline !== null && Date.now() >= deadline) {
      throw new LLMRetriesExhaustedError(
        new Error("Таймаут LLM-операции"),
        0,
      );
    }

    const allModels = options?.model
      ? [options.model]
      : getModelsForTier(tierForOperation(operation));

    for (const model of allModels) {
      let modelFailed = false;
      for (let attempt = 0; ; attempt++) {
        if (deadline !== null && Date.now() >= deadline) {
          throw new LLMRetriesExhaustedError(
            lastError ?? new Error("Таймаут LLM-операции"),
            attempt,
          );
        }
        await this.waitForSlot(deadline ?? undefined);
        if (deadline !== null && Date.now() >= deadline) {
          throw new LLMRetriesExhaustedError(
            lastError ?? new Error("Таймаут LLM-операции"),
            attempt,
          );
        }
        this.acquire();
        let released = false;
        const release = () => {
          if (released) return;
          released = true;
          this.release();
        };
        try {
          const prompt = promptFn();
          let any = false;
          for await (const token of callLLMStream(prompt, { model }, options?.signal)) {
            any = any || token.length > 0;
            yield token;
          }
          if (!any) {
            throw new Error("LLM API вернул пустой ответ");
          }
          release();
          trackOperation({
            operation,
            node_ids: [],
            model,
            input_tokens: Math.ceil(prompt.length / 4),
            output_tokens: 0,
            latency_ms: Date.now() - startTime,
            retry_count: attempt,
            cache_hit: false,
            estimated_cost: 0,
          });
          return;
        } catch (err) {
          lastError = err instanceof Error ? err : new Error("Ошибка LLM");
          if (err instanceof LLMMockError || lastError instanceof LLMMockError) {
            throw new LLMRetriesExhaustedError(lastError, attempt);
          }

          // Рейт-лимит (429/408) ретраим до дедлайна операции, не расходуя
          // бюджет maxRetries — как в execute().
          const rateLimited = isRateLimitError(lastError);
          const timeLeft = deadline !== null ? deadline - Date.now() : Infinity;
          const retryAllowed = rateLimited
            ? attempt < RATE_LIMIT_RETRY_CAP
            : shouldRetry(lastError, attempt, this.config.maxRetries);

          if (!retryAllowed || timeLeft <= 0) {
            modelFailed = true;
            break;
          }

          const delay = Math.min(retryDelayMs(lastError, attempt), timeLeft);
          if (rateLimited) {
            this.onBackoff?.(delay, attempt);
          }
          await sleep(delay);
        } finally {
          // Гарантированно освобождаем слот, в т.ч. при раннем прекращении
          // итерации потребителем (возврат/прерывание потока).
          release();
        }
      }
      if (modelFailed && allModels.indexOf(model) < allModels.length - 1) {
        continue;
      }
    }

    throw new LLMRetriesExhaustedError(
      lastError ?? new Error("Не удалось выполнить LLM-запрос"),
      0,
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
