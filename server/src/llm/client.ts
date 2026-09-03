import { getRuntimeConfig, type RuntimeLLMConfig } from "../config/runtimeConfig.js";

const DEFAULT_BASE_URL = "https://api.openai.com/v1";
const DEFAULT_MODEL = "gpt-4o";
const DEFAULT_TEMPERATURE = 0.4;
const DEFAULT_NUM_CTX = 16384;
const DEFAULT_TIMEOUT_MS = 180_000;

export interface ILLMUsage {
  input_tokens: number;
  output_tokens: number;
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

function readLLMConfig(): LLMConfig {
  const runtime = getRuntimeConfig();

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
    provider,
    isMock,
  };
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

function compactErrorBody(text: string): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (/<!DOCTYPE html|<html[\s>]/i.test(flat)) {
    const title = /<title[^>]*>(.*?)<\/title>/i.exec(flat)?.[1]?.trim();
    if (title) return `HTML-страница провайдера: "${title}"`;
    const stripped = flat.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    return (stripped || "HTML-страница провайдера").slice(0, 200);
  }
  return flat.length > 300 ? `${flat.slice(0, 300)}…` : flat;
}

const DEFAULT_RATE_LIMIT_COOLDOWN_S = 30;
const cooldowns = new Map<string, number>();

interface ChatUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
}

interface ChatPayload {
  choices?: Array<{
    message?: { content?: unknown; reasoning_content?: unknown };
    delta?: { content?: unknown; reasoning_content?: unknown };
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
  const content = typeof message?.content === "string" ? message.content : "";
  const reasoning =
    typeof message?.reasoning_content === "string" ? message.reasoning_content : "";
  const text = content.trim() !== "" ? content : reasoning;
  if (text.trim() === "") return null;
  return {
    text,
    usage: {
      input_tokens: payload?.usage?.prompt_tokens ?? Math.ceil(promptChars / 4),
      output_tokens: payload?.usage?.completion_tokens ?? Math.ceil(text.length / 4),
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
  let reasoning = "";
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
        if (typeof delta?.reasoning_content === "string") reasoning += delta.reasoning_content;
        if (
          chunk?.usage &&
          (chunk.usage.prompt_tokens !== undefined || chunk.usage.completion_tokens !== undefined)
        ) {
          usage = chunk.usage;
        }
      }
    }
  }

  const text = content.trim() !== "" ? content : reasoning;
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
): Promise<ILLMResult> {
  const cfg = readLLMConfig();

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

  const baseBody: Record<string, unknown> = {
    model,
    messages: [{ role: "system", content: systemPrompt }],
    temperature,
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
  });

  const timeoutMs = options.timeoutMs ?? cfg.timeoutMs;
  const url = `${cfg.baseUrl}/chat/completions`;
  const promptChars = systemPrompt.length;

  let lastError: Error | null = null;
  let streamRejected = false;

  for (const body of candidates) {
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
    if (res.kind === "next-candidate") continue;
    break;
  }

  throw lastError ?? new Error("Ошибка вызова LLM");
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
