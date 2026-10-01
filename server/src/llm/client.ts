import { getRuntimeConfig, type RuntimeLLMConfig } from "../config/runtimeConfig.js";

const DEFAULT_BASE_URL = "https://api.openai.com/v1";
const DEFAULT_MODEL = "gpt-4o";
const DEFAULT_TEMPERATURE = 0.4;
const DEFAULT_NUM_CTX = 16384;
const DEFAULT_TIMEOUT_MS = 180_000;
// Лимит выходных токенов (зеркало flutter client.dart): без него провайдеры
// режут ответ дефолтным капом, и details обрывается на полуслове.
const DEFAULT_MAX_OUTPUT_TOKENS = 16384;

/** Допустимые значения `LLM_REASONING_EFFORT` (AITUNNEL `reasoning.effort`). */
export const REASONING_EFFORT_VALUES: ReadonlySet<string> = new Set([
  "none",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

/**
 * Ключи `baseUrl|model`, для которых провайдер уже отверг объект `reasoning`.
 *
 * У части моделей (семейство `glm-5.3*`) thinking обязателен и `effort: none`
 * даёт ошибку. Чтобы не платить за бесполезный отказ на каждом вызове,
 * достаточно одного отказа на пару «провайдер+модель».
 */
const reasoningUnsupported = new Set<string>();

/** Тело блока `reasoning` для конкретной модели, с учётом известных отказов. */
export function reasoningBlockFor(cfg: LLMConfig, model: string): Record<string, unknown> {
  if (reasoningUnsupported.has(`${cfg.baseUrl}|${model}`)) return {};
  if (cfg.reasoningMaxTokens !== null) return { max_tokens: cfg.reasoningMaxTokens };
  const effort = cfg.reasoningEffort?.trim();
  if (!effort) return {};
  return { effort };
}

/** Ответ провайдера означает, что объект `reasoning` неприемлем для модели? */
function isReasoningRejection(error: unknown): boolean {
  const text = error instanceof Error ? error.message : String(error);
  if (!/\b(400|422)\b/.test(text)) return false;
  return /reasoning|thinking|effort|思考/i.test(text);
}

export interface ILLMUsage {
  input_tokens: number;
  output_tokens: number;
  /**
   * Токены рассуждений — часть `output_tokens`, но отдельная и обычно бо́льшая
   * часть платного вывода. Зеркало flutter `LLMUsage`.
   */
  reasoning_tokens?: number;
  /**
   * Реальная стоимость запроса в рублях от провайдера (`usage.cost_rub`).
   * Считать стоимость по каталогу нельзя: фактический тариф провайдера может
   * отличаться от опубликованного.
   */
  cost_rub?: number;
}

export interface ILLMResult {
  text: string;
  usage: ILLMUsage;
}

interface LLMConfig {
  apiKey: string;
  baseUrl: string;
  model: string;
  modelStrong: string;
  modelFast: string;
  temperature: number;
  seedOverride: number | null;
  numCtx: number;
  timeoutMs: number;
  /** Лимит выходных токенов одного запроса (было жёстко 4096). */
  maxOutputTokens: number;
  /** Бюджет токенов рассуждений; null — поле `reasoning` не отправляется. */
  reasoningMaxTokens: number | null;
  /**
   * Уровень усилений рассуждений (`reasoning.effort`), null — не отправлять.
   * Взаимоисключающе с reasoningMaxTokens: провайдер требует «что-то одно».
   */
  reasoningEffort: string | null;
  provider: "ollama" | "openai" | "auto";
  isMock: boolean;
}

/** Таймаут одного HTTP-запроса к LLM (мс): env LLM_TIMEOUT_MS или 180 с. */
export function resolveTimeoutMs(raw: string | undefined): number {
  if (raw === undefined || raw === "") return DEFAULT_TIMEOUT_MS;
  const num = Number(raw);
  if (!Number.isFinite(num) || num <= 0) return DEFAULT_TIMEOUT_MS;
  return Math.trunc(num);
}

/**
 * Собирает эффективный LLM-конфиг из runtime-конфига и env.
 * `runtime` — текущий (применённый) конфиг по умолчанию; для пробной проверки
 * (POST /api/config/test) можно передать временный конфиг без персиста на диск.
 */
function readLLMConfig(runtime: RuntimeLLMConfig | null = getRuntimeConfig()): LLMConfig {
  const envOr = (runtimeKey: keyof RuntimeLLMConfig, envName: string, fallback: string): string => {
    const rt = runtime?.[runtimeKey];
    if (typeof rt === "string" && rt.trim() !== "") return rt.trim();
    const env = process.env[envName];
    if (env !== undefined && env.trim() !== "") return env.trim();
    return fallback;
  };

  const apiKey =
    runtime?.apiKey && runtime.apiKey.trim() !== ""
      ? runtime.apiKey.trim()
      : process.env.LLM_API_KEY ?? process.env.OPENAI_API_KEY ?? "";

  const baseUrl = envOr("baseUrl", "LLM_BASE_URL", DEFAULT_BASE_URL).replace(/\/+$/, "");
  const model = envOr("model", "LLM_MODEL", DEFAULT_MODEL);
  const providerRaw = (runtime?.provider ?? process.env.LLM_PROVIDER ?? "auto")
    .trim()
    .toLowerCase();
  const provider: LLMConfig["provider"] =
    providerRaw === "ollama" || providerRaw === "openai" ? providerRaw : "auto";

  const temperatureRaw =
    typeof runtime?.temperature === "number"
      ? runtime.temperature
      : process.env.LLM_TEMPERATURE !== undefined && process.env.LLM_TEMPERATURE !== ""
        ? Number(process.env.LLM_TEMPERATURE)
        : DEFAULT_TEMPERATURE;
  const temperature = Number.isFinite(temperatureRaw) ? temperatureRaw : DEFAULT_TEMPERATURE;

  const numCtx =
    typeof runtime?.numCtx === "number" && runtime.numCtx > 0
      ? runtime.numCtx
      : (() => {
          const raw = process.env.LLM_NUM_CTX;
          if (
            raw !== undefined &&
            raw !== "" &&
            Number.isFinite(Number(raw)) &&
            Number(raw) > 0
          ) {
            return Math.trunc(Number(raw));
          }
          return DEFAULT_NUM_CTX;
        })();

  const seedRaw = process.env.LLM_SEED;
  const seedOverride =
    seedRaw !== undefined &&
    seedRaw !== "" &&
    Number.isFinite(Number(seedRaw))
      ? Math.trunc(Number(seedRaw))
      : null;

  const isMock = (process.env.LLM_MOCK ?? "") === "1" || (process.env.LLM_MOCK ?? "").toLowerCase() === "true";

  const isOllama = provider === "ollama" || (provider === "auto" && isOllamaBaseUrl(baseUrl));

  // Режим демо без ключа: LLM_MOCK=1 включает офлайн-режим, в котором
  // callLLM возвращает заглушку, а движки используют собственные фолбэки.
  if (!apiKey && !isOllama && !isMock) {
    throw new Error(
      "LLM_API_KEY (или OPENAI_API_KEY) не задан. Задайте ключ либо включите офлайн-режим LLM_MOCK=1.",
    );
  }
  if (temperature < 0 || temperature > 2) {
    throw new Error("LLM_TEMPERATURE должен быть числом в диапазоне 0..2");
  }

  const maxOutputTokensRaw = process.env.LLM_MAX_OUTPUT_TOKENS;
  const parsedMaxOutputTokens =
    maxOutputTokensRaw === undefined || maxOutputTokensRaw === ""
      ? NaN
      : Number(maxOutputTokensRaw);
  const maxOutputTokens =
    Number.isFinite(parsedMaxOutputTokens) && parsedMaxOutputTokens > 0
      ? Math.floor(parsedMaxOutputTokens)
      : DEFAULT_MAX_OUTPUT_TOKENS;

  // Бюджет рассуждений: AITUNNEL требует, чтобы max_tokens ответа был строго
  // больше бюджета мыслей, иначе ответ приходит пустым (finish_reason: length).
  const reasoningMaxTokensRaw = process.env.LLM_REASONING_MAX_TOKENS;
  const parsedReasoningMaxTokens =
    reasoningMaxTokensRaw === undefined || reasoningMaxTokensRaw === ""
      ? NaN
      : Number(reasoningMaxTokensRaw);
  const reasoningMaxTokens =
    Number.isFinite(parsedReasoningMaxTokens) && parsedReasoningMaxTokens > 0
      ? Math.floor(parsedReasoningMaxTokens)
      : null;

  // Уровень усилений рассуждений. Замер на живом провайдере: задача с ответом
  // ~30 токенов без управления вернула 4106 выходных токенов (4077 — reasoning)
  // и стоила 0.11 руб; с `effort: "none"` — 35 токенов, 0.01 руб. `minimal` не
  // помогает, провайдер мапит уровень и Qwen всё равно думает тысячи токенов.
  const reasoningEffortRaw = (process.env.LLM_REASONING_EFFORT ?? "").trim().toLowerCase();
  const reasoningEffort = REASONING_EFFORT_VALUES.has(reasoningEffortRaw)
    ? reasoningEffortRaw
    : null;

  return {
    apiKey,
    baseUrl,
    model,
    modelStrong: runtime?.modelStrong
      ? runtime.modelStrong
      : process.env.LLM_MODEL_STRONG ?? model,
    modelFast: runtime?.modelFast
      ? runtime.modelFast
      : process.env.LLM_MODEL_FAST ?? model,
    temperature,
    seedOverride,
    numCtx,
    timeoutMs: resolveTimeoutMs(process.env.LLM_TIMEOUT_MS),
    maxOutputTokens,
    reasoningMaxTokens,
    reasoningEffort,
    provider,
    isMock,
  };
}

/**
 * Операции с детерминированным выводом: JSON-контракт фиксирован, нужна
 * воспроизводимость (зеркало flutter client.dart).
 */
const DETERMINISTIC_OPS = new Set([
  "structure",
  "structure-l2",
  "structure-l3",
  "validate",
  "curriculum",
  "assessment",
  "mastery",
]);

/**
 * Температура для операции: `0` — детерминированный вывод, `undefined` —
 * оставить дефолт из конфига (его подставит `callLLM`). Зеркало flutter
 * client.dart.
 */
export function defaultTemperatureForOperation(operation: string): number | undefined {
  return DETERMINISTIC_OPS.has(operation) ? 0 : undefined;
}

export type ModelTier = "strong" | "fast";

function isOllamaBaseUrl(baseUrl: string): boolean {
  return /localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]/.test(baseUrl);
}

export function hashSeed(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

export interface CallLLMOptions {
  seed?: number;
  temperature?: number;
  model?: string;
  timeoutMs?: number;
}

export function getModelName(): string {
  return readLLMConfig().model;
}

/** Имя модели для конкретного runtime-конфига без применения (для пробной проверки /test). */
export function getModelNameForConfig(runtime: RuntimeLLMConfig | null | undefined): string {
  return readLLMConfig(runtime).model;
}

export function getModelForTier(tier: ModelTier): string {
  const cfg = readLLMConfig();
  return tier === "strong" ? cfg.modelStrong : cfg.modelFast;
}

export function getModelsForTier(tier: ModelTier): string[] {
  const cfg = readLLMConfig();
  if (tier === "strong") {
    const fb = process.env.LLM_MODEL_STRONG_FALLBACK;
    return fb ? [cfg.modelStrong, fb] : [cfg.modelStrong];
  }
  return [cfg.modelFast];
}

export class LLMRateLimitError extends Error {
  readonly status: number;
  readonly retryAfter: number | null;

  constructor(status: number, message: string, retryAfter: number | null = null) {
    super(message);
    this.name = "LLMRateLimitError";
    this.status = status;
    this.retryAfter = retryAfter;
  }
}

/**
 * Бросается в офлайн-режиме (LLM_MOCK=1). Движки ловят его и используют
 * встроенные фолбэки; планировщик не делает лишних повторных попыток.
 */
export class LLMMockError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LLMMockError";
  }
}

export class LLMRetriesExhaustedError extends Error {
  readonly lastError: Error;
  readonly attempts: number;

  constructor(lastError: Error, attempts: number) {
    super(lastError.message);
    this.name = "LLMRetriesExhaustedError";
    this.lastError = lastError;
    this.attempts = attempts;
  }
}

function parseRetryAfter(value: string | null): number | null {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds;
  const date = Date.parse(value);
  if (!Number.isNaN(date)) return Math.max(0, Math.ceil((date - Date.now()) / 1000));
  return null;
}

const RATE_LIMIT_STATUSES = new Set([408, 429, 502, 503, 504]);

// Тело ошибки провайдера почти всегда — JSON-обёртка `{"error":{"message":
// "…","code":400}}`. Само сообщение полезнее обёртки: именно в нём имя
// модели и причина отказа, а резать его до 300 символов нельзя — хвост
// («Возможно вы хотели использовать модель …») как раз и объясняет отказ.
const MODEL_UNAVAILABLE_RE =
  /(модел\w*|model).{0,80}?(не найден|недоступен|неизвестен|not found|unknown|unavailable)|(не найден|not found).{0,40}?(модел\w*|model)/i;

function withModelHint(body: string): string {
  if (!MODEL_UNAVAILABLE_RE.test(body)) return body;
  return `${body}. Проверьте provider-config.json: имя модели вшивается в сборку ` +
    `(LLM_MODEL_FAST/STRONG), поэтому после правки конфига приложение нужно пересобрать.`;
}

/** Достаёт человекочитаемое сообщение провайдера из JSON-тела ошибки. */
function providerMessage(raw: string): string | null {
  const t = raw.trim();
  if (!t.startsWith("{")) return null;
  try {
    const decoded = JSON.parse(t) as Record<string, unknown>;
    const err = decoded.error;
    if (typeof err === "string" && err.trim()) return err.trim();
    if (err && typeof err === "object") {
      const msg = (err as { message?: unknown }).message;
      if (typeof msg === "string" && msg.trim()) return msg.trim();
    }
    const msg = decoded.message;
    if (typeof msg === "string" && msg.trim()) return msg.trim();
  } catch {
    // Не JSON — оставляем как есть.
  }
  return null;
}

function compactErrorBody(text: string): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (/<!DOCTYPE html|<html[\s>]/i.test(flat)) {
    const title = /<title[^>]*>(.*?)<\/title>/i.exec(flat)?.[1]?.trim();
    if (title) return `HTML-страница провайдера: "${title}"`;
    const stripped = flat.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    return (stripped || "HTML-страница провайдера").slice(0, 200);
  }
  const hinted = withModelHint(providerMessage(text) ?? flat);
  return hinted.length > 300 ? `${hinted.slice(0, 300)}…` : hinted;
}

const DEFAULT_RATE_LIMIT_COOLDOWN_S = 30;
const cooldowns = new Map<string, number>();

interface ChatUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  completion_tokens_details?: { reasoning_tokens?: number };
  cost_rub?: number;
}

interface ChatPayload {
  choices?: Array<{
    message?: { content?: unknown; reasoning?: unknown; reasoning_content?: unknown };
    delta?: { content?: unknown; reasoning?: unknown; reasoning_content?: unknown };
  }>;
  usage?: ChatUsage;
}

type ChatAttempt =
  | { kind: "success"; result: ILLMResult }
  | { kind: "rate-limit"; err: LLMRateLimitError }
  | { kind: "timeout"; error: Error }
  | { kind: "next-candidate"; error: Error }
  | { kind: "retry-without-stream"; error: Error }
  | { kind: "fatal"; error: Error };

function resultFromChatJson(payload: ChatPayload, promptChars: number): ILLMResult | null {
  const message = payload?.choices?.[0]?.message;
  // Только content: рассуждение — проза, для JSON-контракта это мусор (зеркало
  // flutter client.dart). Пустой content даёт null → штатный retry/fallback.
  const text = typeof message?.content === "string" ? message.content : "";
  if (text.trim() === "") return null;
  return {
    text,
    usage: {
      input_tokens: payload?.usage?.prompt_tokens ?? Math.ceil(promptChars / 4),
      output_tokens: payload?.usage?.completion_tokens ?? Math.ceil(text.length / 4),
      ...(payload?.usage?.completion_tokens_details?.reasoning_tokens !== undefined
        ? { reasoning_tokens: payload.usage.completion_tokens_details.reasoning_tokens }
        : {}),
      ...(payload?.usage?.cost_rub !== undefined ? { cost_rub: payload.usage.cost_rub } : {}),
    },
  };
}

async function consumeChatStream(response: Response, promptChars: number): Promise<ChatAttempt> {
  if (!response.body) {
    return { kind: "retry-without-stream", error: new Error("LLM API вернул пустой поток") };
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let content = "";
  let usage: ChatUsage | null = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split("\n\n");
    buffer = events.pop() ?? "";
    for (const event of events) {
      for (const line of event.split("\n")) {
        const trimmedLine = line.replace(/\r$/, "");
        if (!trimmedLine.startsWith("data:")) continue;
        const payload = trimmedLine.slice(5).trim();
        if (!payload || payload === "[DONE]") continue;
        let chunk: ChatPayload;
        try {
          chunk = JSON.parse(payload) as ChatPayload;
        } catch {
          continue;
        }
        const delta = chunk?.choices?.[0]?.delta;
        if (typeof delta?.content === "string") content += delta.content;
        if (
          chunk?.usage &&
          (chunk.usage.prompt_tokens !== undefined || chunk.usage.completion_tokens !== undefined)
        ) {
          usage = chunk.usage;
        }
      }
    }
  }

  const text = content;
  if (text.trim() === "") {
    return { kind: "retry-without-stream", error: new Error("LLM API вернул пустой ответ") };
  }
  return {
    kind: "success",
    result: {
      text,
      usage: {
        input_tokens: usage?.prompt_tokens ?? Math.ceil(promptChars / 4),
        output_tokens: usage?.completion_tokens ?? Math.ceil(text.length / 4),
        ...(usage?.completion_tokens_details?.reasoning_tokens !== undefined
          ? { reasoning_tokens: usage.completion_tokens_details.reasoning_tokens }
          : {}),
        ...(usage?.cost_rub !== undefined ? { cost_rub: usage.cost_rub } : {}),
      },
    },
  };
}

async function chatCompletionsOnce(
  providerKey: string,
  url: string,
  apiKey: string,
  body: Record<string, unknown>,
  stream: boolean,
  timeoutMs: number,
  promptChars: number,
): Promise<ChatAttempt> {
  const wireBody = stream ? { ...body, stream: true } : body;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let attempt: ChatAttempt;
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(wireBody),
      signal: controller.signal,
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      if (response.status === 429 || response.status === 408) {
        const retryAfter = parseRetryAfter(response.headers.get("Retry-After"));
        if (response.status === 429) {
          cooldowns.set(providerKey, Date.now() + (retryAfter ?? DEFAULT_RATE_LIMIT_COOLDOWN_S) * 1000);
        }
        attempt = {
          kind: "rate-limit",
          err: new LLMRateLimitError(
            response.status,
            `LLM API ошибка (${response.status}): ${compactErrorBody(text)}`,
            retryAfter,
          ),
        };
      } else if (response.status === 502 || response.status === 503 || response.status === 504) {
        attempt = {
          kind: "next-candidate",
          error: new Error(`LLM API ошибка (${response.status}): ${compactErrorBody(text)}`),
        };
      } else if (response.status === 400) {
        attempt = {
          kind: stream ? "retry-without-stream" : "next-candidate",
          error: new Error(`LLM API ошибка (400): ${compactErrorBody(text)}`),
        };
      } else {
        attempt = {
          kind: "fatal",
          error: new Error(`LLM API ошибка (${response.status}): ${compactErrorBody(text)}`),
        };
      }
    } else {
      const contentType = response.headers.get("Content-Type") ?? "";
      if (!stream || contentType.includes("application/json")) {
        const text = await response.text();
        let parsed: ChatPayload | null = null;
        let parseError: Error | null = null;
        try {
          parsed = JSON.parse(text) as ChatPayload;
        } catch {
          parseError = new Error("LLM API вернул невалидный ответ");
        }
        if (parseError !== null || parsed === null) {
          attempt = {
            kind: "fatal",
            error: parseError ?? new Error("LLM API вернул пустой ответ"),
          };
        } else {
          const result = resultFromChatJson(parsed, promptChars);
          attempt = result
            ? { kind: "success", result }
            : { kind: "fatal", error: new Error("LLM API вернул пустой ответ") };
        }
      } else {
        attempt = await consumeChatStream(response, promptChars);
      }
    }
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      attempt = { kind: "timeout", error: new Error("LLM API: таймаут запроса") };
    } else {
      attempt = {
        kind: "fatal",
        error: err instanceof Error ? err : new Error("Сетевая ошибка LLM API"),
      };
    }
  }

  clearTimeout(timeoutId);
  return attempt;
}

export async function callLLM(
  systemPrompt: string,
  options: CallLLMOptions = {},
  runtime: RuntimeLLMConfig | null | undefined = undefined,
): Promise<ILLMResult> {
  const cfg = readLLMConfig(runtime);

  // Офлайн-режим: вместо сетевых вызовов сообщаем движкам, что LLM недоступен.
  // Движки ловят эту ошибку и используют встроенные детерминированные фолбэки.
  if (cfg.isMock) {
    throw new LLMMockError(
      "Офлайн-режим (LLM_MOCK=1): LLM недоступен, используются встроенные заготовки.",
    );
  }

  const providerKey = cfg.baseUrl;
  const now = Date.now();
  const cooldownUntil = cooldowns.get(providerKey) ?? 0;

  if (now < cooldownUntil) {
    const remainingS = Math.ceil((cooldownUntil - now) / 1000);
    throw new LLMRateLimitError(
      429,
      "LLM API рейт-лимит: активен cooldown после предыдущего 429",
      remainingS,
    );
  }
  const temperature = options.temperature ?? cfg.temperature;
  const seed = options.seed ?? cfg.seedOverride;
  const model = options.model ?? cfg.model;

  const useOllama =
    cfg.provider === "ollama" ||
    (cfg.provider === "auto" && isOllamaBaseUrl(cfg.baseUrl));
  if (useOllama) {
    return callOllama(cfg, systemPrompt, temperature, seed, model);
  }

  const reasoningBlock = reasoningBlockFor(cfg, model);

  const baseBody: Record<string, unknown> = {
    model,
    messages: [{ role: "system", content: systemPrompt }],
    temperature,
    max_tokens: cfg.maxOutputTokens,
    ...(Object.keys(reasoningBlock).length > 0 ? { reasoning: reasoningBlock } : {}),
  };

  const candidates: Array<Record<string, unknown>> = [];
  if (seed !== null && seed !== undefined) {
    candidates.push({ ...baseBody, seed, response_format: { type: "json_object" } });
  }
  candidates.push({ ...baseBody, response_format: { type: "json_object" } });
  candidates.push({ ...baseBody });
  candidates.push({
    model,
    messages: [{ role: "user", content: systemPrompt }],
    temperature,
    max_tokens: cfg.maxOutputTokens,
    ...(Object.keys(reasoningBlock).length > 0 ? { reasoning: reasoningBlock } : {}),
  });

  const timeoutMs = options.timeoutMs ?? cfg.timeoutMs;
  const url = `${cfg.baseUrl}/chat/completions`;
  const promptChars = systemPrompt.length;

  /**
   * Прогоняет список тел-кандидатов. Возвращает результат либо пробрасывает
   * последнюю ошибку; при отказе именно из-за `reasoning` прерывается сразу,
   * чтобы не потратить лимит попыток на заведомо обречённые варианты.
   */
  const attemptAll = async (bodies: Array<Record<string, unknown>>): Promise<ILLMResult> => {
    let lastError: Error | null = null;
    let streamRejected = false;

    for (const body of bodies) {
      const hasReasoning = body.reasoning !== undefined;
      if (!streamRejected) {
        const res = await chatCompletionsOnce(
          providerKey,
          url,
          cfg.apiKey,
          body,
          true,
          timeoutMs,
          promptChars,
        );
        if (res.kind === "success") return res.result;
        if (res.kind === "rate-limit") throw res.err;
        lastError = res.error;
        if (hasReasoning && isReasoningRejection(res.error)) throw res.error;
        if (res.kind === "next-candidate") continue;
        if (res.kind === "retry-without-stream") streamRejected = true;
        else break;
      }

      const res = await chatCompletionsOnce(
        providerKey,
        url,
        cfg.apiKey,
        body,
        false,
        timeoutMs,
        promptChars,
      );
      if (res.kind === "success") return res.result;
      if (res.kind === "rate-limit") throw res.err;
      lastError = res.error;
      if (hasReasoning && isReasoningRejection(res.error)) throw res.error;
      if (res.kind === "next-candidate") continue;
      break;
    }

    throw lastError ?? new Error("Ошибка вызова LLM");
  };

  try {
    return await attemptAll(candidates);
  } catch (error) {
    // Модель с обязательным thinking (glm-5.3*) отвергает объект `reasoning`.
    // Помечаем пару «провайдер+модель» и повторяем ровно один раз без него.
    if (Object.keys(reasoningBlock).length === 0 || !isReasoningRejection(error)) throw error;
    reasoningUnsupported.add(`${cfg.baseUrl}|${model}`);
    const withoutReasoning = candidates.map((body) => {
      const copy = { ...body };
      delete copy.reasoning;
      return copy;
    });
    return attemptAll(withoutReasoning);
  }
}

async function callOllama(
  cfg: LLMConfig,
  systemPrompt: string,
  temperature: number,
  seed: number | null,
  model?: string,
): Promise<ILLMResult> {
  const baseUrl = cfg.baseUrl.replace(/\/v1\/?$/, "");
  const options: Record<string, unknown> = {
    temperature,
    num_ctx: cfg.numCtx,
    num_predict: cfg.maxOutputTokens,
  };
  if (seed !== null && seed !== undefined) {
    options.seed = seed;
  }

  const body = {
    model: model ?? cfg.model,
    messages: [{ role: "system", content: systemPrompt }],
    stream: false,
    options,
  };

  const res = await fetch(`${baseUrl}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const text = await res.text();

  if (!res.ok) {
    if (RATE_LIMIT_STATUSES.has(res.status)) {
      const retryAfter = parseRetryAfter(res.headers.get("Retry-After"));
      if (res.status === 429) {
        const cooldownS = retryAfter ?? DEFAULT_RATE_LIMIT_COOLDOWN_S;
        cooldowns.set(cfg.baseUrl, Date.now() + cooldownS * 1000);
      }
      throw new LLMRateLimitError(
        res.status,
        `LLM API ошибка (${res.status}): ${compactErrorBody(text)}`,
        retryAfter,
      );
    }
    throw new Error(`LLM API ошибка (${res.status}): ${compactErrorBody(text)}`);
  }

  let data: { error?: unknown; message?: { content?: unknown } };
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error("LLM API вернул невалидный ответ");
  }

  if (data.error) {
    throw new Error(`LLM API ошибка: ${String(data.error)}`);
  }

  const content = data?.message?.content;
  if (typeof content !== "string" || content.trim() === "") {
    throw new Error("LLM API вернул пустой ответ");
  }

  const estInput = Math.ceil(systemPrompt.length / 4);
  const estOutput = Math.ceil(content.length / 4);
  return {
    text: content,
    usage: { input_tokens: estInput, output_tokens: estOutput },
  };
}

/**
 * Потоковый вызов OpenAI-совместимого API: отдаёт токены (`delta.content`) по
 * мере генерации. Не поддерживает ollama (там нет SSE-потока / O(1)).
 * Используется тьютором для отображения ответа «на лету» как в ChatGPT.
 * Внешний `signal` позволяет прервать запрос при закрытии соединения клиентом.
 */
export async function* callLLMStream(
  systemPrompt: string,
  options: CallLLMOptions = {},
  signal?: AbortSignal,
  runtime: RuntimeLLMConfig | null | undefined = undefined,
): AsyncIterableIterator<string> {
  const cfg = readLLMConfig(runtime);

  if (cfg.isMock) {
    throw new LLMMockError(
      "Офлайн-режим (LLM_MOCK=1): LLM недоступен, используются встроенные заготовки.",
    );
  }

  if (
    cfg.provider === "ollama" ||
    (cfg.provider === "auto" && isOllamaBaseUrl(cfg.baseUrl))
  ) {
    throw new Error("Потоковый вызов недоступен для провайдера Ollama");
  }

  const model = options.model ?? cfg.model;
  const temperature = options.temperature ?? cfg.temperature;
  const timeoutMs = options.timeoutMs ?? cfg.timeoutMs;
  const url = `${cfg.baseUrl}/chat/completions`;

  const body: Record<string, unknown> = {
    model,
    messages: [{ role: "system", content: systemPrompt }],
    temperature,
    stream: true,
  };

  const controller = new AbortController();
  const onExternalAbort = () => controller.abort();
  signal?.addEventListener("abort", onExternalAbort, { once: true });
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    clearTimeout(timeoutId);
    signal?.removeEventListener("abort", onExternalAbort);
  };

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${cfg.apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (err) {
    release();
    throw err instanceof Error && err.name === "AbortError"
      ? new Error("LLM API: таймаут запроса")
      : err instanceof Error
        ? err
        : new Error("Сетевая ошибка LLM API");
  }

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    release();
    if (response.status === 429 || response.status === 408) {
      throw new LLMRateLimitError(
        response.status,
        `LLM API ошибка (${response.status}): ${compactErrorBody(text)}`,
        response.status === 429 ? parseRetryAfter(response.headers.get("Retry-After")) : null,
      );
    }
    throw new Error(`LLM API ошибка (${response.status}): ${compactErrorBody(text)}`);
  }

  if (!response.body) {
    release();
    throw new Error("LLM API вернул пустой поток");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let emitted = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const events = buffer.split("\n\n");
      buffer = events.pop() ?? "";
      for (const event of events) {
        for (const line of event.split("\n")) {
          const trimmedLine = line.replace(/\r$/, "");
          if (!trimmedLine.startsWith("data:")) continue;
          const payload = trimmedLine.slice(5).trim();
          if (!payload || payload === "[DONE]") continue;
          let chunk: ChatPayload;
          try {
            chunk = JSON.parse(payload) as ChatPayload;
          } catch {
            continue;
          }
          const delta = chunk?.choices?.[0]?.delta;
          // Только content (зеркало flutter client.dart): рассуждение в ответ не
          // отдаём — на стриме это проза вперемешку с JSON-контрактом.
          const piece = typeof delta?.content === "string" ? delta.content : "";
          if (piece.length > 0) {
            emitted += piece.length;
            yield piece;
          }
        }
      }
    }
  } finally {
    release();
  }

  if (emitted === 0) {
    throw new Error("LLM API вернул пустой ответ");
  }
}

export function findMatchingBracket(text: string, start: number): number {
  const open = text[start];
  const close = open === "{" ? "}" : "]";
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = start; i < text.length; i++) {
    const ch = text[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
    } else if (ch === open) {
      depth++;
    } else if (ch === close) {
      depth--;
      if (depth === 0) return i;
    }
  }

  return -1;
}

function repairControlChars(input: string): string {
  let out = "";
  let inString = false;
  let escaped = false;

  for (let i = 0; i < input.length; i++) {
    const ch = input[i];

    if (inString) {
      if (escaped) {
        escaped = false;
        out += ch;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        out += ch;
        continue;
      }
      if (ch === '"') {
        inString = false;
        out += ch;
        continue;
      }
      const code = ch.charCodeAt(0);
      if (code < 0x20) {
        out += "\\u" + code.toString(16).padStart(4, "0");
        continue;
      }
      out += ch;
      continue;
    }

    if (ch === '"') inString = true;
    out += ch;
  }

  return out;
}

function parseCandidate(candidate: string): unknown {
  try {
    return JSON.parse(candidate);
  } catch {
    return JSON.parse(repairControlChars(candidate));
  }
}

export function parseLLMJson<T = unknown>(raw: string): T {
  const trimmed = raw.trim();

  try {
    return JSON.parse(trimmed) as T;
  } catch {
    // continue below
  }

  const fence = trimmed.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (fence) {
    try {
      return parseCandidate(fence[1].trim()) as T;
    } catch {
      // continue below
    }
  }

  const start = trimmed.search(/[[{]/);
  if (start !== -1) {
    const end = findMatchingBracket(trimmed, start);
    if (end !== -1) {
      try {
        return parseCandidate(trimmed.slice(start, end + 1)) as T;
      } catch {
        // continue below
      }
    }
  }

  throw new Error("AI вернул невалидный JSON");
}
