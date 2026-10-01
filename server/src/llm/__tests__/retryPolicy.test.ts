import http from "node:http";
import type { AddressInfo } from "node:net";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { LLMMockError, LLMRateLimitError, callLLM } from "../client.js";
import { isPermanentLLMErrorStatus, retryDelayMs, shouldRetry } from "../scheduler.js";

/**
 * Политика повторных попыток и читаемость сообщения об ошибке LLM-транспорта.
 *
 * Пользовательский баг (провайдер aitunnel):
 * `LLM: исчерпаны попытки запроса (4); последняя ошибка: ... LLM API ошибка
 * (400): {"error":{"message":"Указанная модель (qwen3.5-flash) не найдена, ...
 *
 * Два дефекта, которые закрывает этот файл:
 *
 * 1. Перманентный 400 «модель не найдена» ретраился 4 раза при `maxRetries: 3`
 *    — запрос заведомо не мог стать валидным, время тратилось впустую.
 * 2. Сообщение было нечитаемым: обрезка тела до 300 символов резала его ровно на
 *    имени модели — самом полезном куске.
 *
 * Зеркало flutter-теста `test/data/llm/retry_policy_test.dart`.
 * Сквозной сценарий через TreeScheduler — в `scheduler.test.ts`.
 */

const savedEnv: Record<string, string | undefined> = {};

function setEnv(key: string, value: string | undefined): void {
  if (!(key in savedEnv)) savedEnv[key] = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

/** Сырое тело ответа провайдера на несуществующее имя модели (AITUNNEL). */
const modelNotFoundBody = {
  error: {
    message:
      'Указанная модель (qwen3.5-flash) не найдена, либо сейчас недоступна. ' +
      'Возможно вы хотели использовать модель "qwen3.8-flash"?',
    code: 400,
  },
};

/**
 * Тот же текст, но уже сплющенный `compactErrorBody` — ровно то, что видит
 * пользователь в сообщении об ошибке (обёртка JSON убрана, хвост не обрезан).
 */
const modelNotFoundMessage =
  'Указанная модель (qwen3.5-flash) не найдена, либо сейчас недоступна. ' +
  'Возможно вы хотели использовать модель "qwen3.8-flash"?';

/** Ошибка того же вида, что бросает транспорт client.ts. */
function transportError(status: number, body: string): Error {
  return new Error(`LLM API ошибка (${status}): ${body}`);
}

interface Reply {
  status: number;
  contentType: string;
  body: string;
}

const openServers: http.Server[] = [];

/**
 * Локальный сервер: копит тела POST-запросов и отвечает по `respond`.
 *
 * `LLM_PROVIDER=openai` обязателен — по умолчанию адрес на 127.0.0.1
 * распознаётся как Ollama и уходит в другую ветку вызова.
 */
async function startServer(
  respond: (body: Record<string, unknown>) => Reply,
): Promise<{ baseUrl: string; bodies: Record<string, unknown>[] }> {
  const bodies: Record<string, unknown>[] = [];
  const server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      const body = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
      bodies.push(body);
      const out = respond(body);
      res.writeHead(out.status, {
        "content-type": `${out.contentType}; charset=utf-8`,
      });
      res.end(out.body);
    });
  });
  openServers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return { baseUrl: `http://127.0.0.1:${port}/v1`, bodies };
}

beforeEach(() => {
  setEnv("LLM_BASE_URL", undefined);
  setEnv("LLM_API_KEY", "test-key");
  setEnv("LLM_MODEL", "test-model");
  setEnv("LLM_PROVIDER", "openai");
  setEnv("LLM_MOCK", undefined);
  setEnv("LLM_REASONING_EFFORT", undefined);
  setEnv("LLM_REASONING_MAX_TOKENS", undefined);
});

afterEach(async () => {
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  const servers = openServers.splice(0, openServers.length);
  for (const server of servers) {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

describe("isPermanentLLMErrorStatus", () => {
  it("перманентные 4xx: 400, 401, 403, 404, 422", () => {
    for (const status of [400, 401, 403, 404, 422]) {
      expect(isPermanentLLMErrorStatus(status)).toBe(true);
    }
  });

  it("408 и 429 — временные, перманентными не считаются", () => {
    expect(isPermanentLLMErrorStatus(408)).toBe(false);
    expect(isPermanentLLMErrorStatus(429)).toBe(false);
  });

  it("5xx и статусы вне 4xx — не перманентные", () => {
    for (const status of [500, 502, 503, 504]) {
      expect(isPermanentLLMErrorStatus(status)).toBe(false);
    }
    expect(isPermanentLLMErrorStatus(399)).toBe(false);
    expect(isPermanentLLMErrorStatus(200)).toBe(false);
  });

  it("границы диапазона: 400 и 499 перманентны, 500 — нет", () => {
    expect(isPermanentLLMErrorStatus(400)).toBe(true);
    expect(isPermanentLLMErrorStatus(499)).toBe(true);
    expect(isPermanentLLMErrorStatus(500)).toBe(false);
  });
});

describe("shouldRetry", () => {
  it("400 не ретраится ни на одной из четырёх попыток (главный фикс)", () => {
    const err = transportError(400, modelNotFoundMessage);
    for (let attempt = 0; attempt <= 3; attempt++) {
      expect(shouldRetry(err, attempt, 3)).toBe(false);
    }
  });

  it("401, 403, 404, 422 тоже не ретраятся", () => {
    for (const status of [401, 403, 404, 422]) {
      for (let attempt = 0; attempt <= 3; attempt++) {
        expect(shouldRetry(transportError(status, "отказ"), attempt, 3)).toBe(false);
      }
    }
  });

  it("408 и 429 ретраятся", () => {
    expect(shouldRetry(transportError(408, "таймаут"), 0, 3)).toBe(true);
    expect(shouldRetry(transportError(429, "лимит"), 0, 3)).toBe(true);
    // …но 408/429 отдельно гоняет `execute` до дедлайна операции, потолок
    // maxRetries к ним не относится.
    expect(shouldRetry(new LLMRateLimitError(429, "cooldown", 0), 0, 3)).toBe(true);
  });

  it("5xx ретраится до потолка maxRetries", () => {
    const err = transportError(500, "Internal Server Error");
    expect(shouldRetry(err, 0, 3)).toBe(true);
    expect(shouldRetry(err, 1, 3)).toBe(true);
    expect(shouldRetry(err, 2, 3)).toBe(true);
    expect(shouldRetry(err, 3, 3)).toBe(false);
  });

  it("502/503/504 не ретраится начиная с attempt >= 2 (старое поведение)", () => {
    for (const status of [502, 503, 504]) {
      const err = transportError(status, "шлюз недоступен");
      expect(shouldRetry(err, 0, 3)).toBe(true);
      expect(shouldRetry(err, 1, 3)).toBe(true);
      expect(shouldRetry(err, 2, 3)).toBe(false);
    }
  });

  it("LLMMockError не ретраится", () => {
    expect(shouldRetry(new LLMMockError("офлайн-режим"), 0, 3)).toBe(false);
  });

  it("ошибка без распознаваемого статуса ретраится", () => {
    expect(shouldRetry(new Error("boom"), 0, 3)).toBe(true);
    expect(shouldRetry(new Error("boom"), 2, 3)).toBe(true);
    expect(shouldRetry(new Error("boom"), 3, 3)).toBe(false);
  });

  it("отказ 400 из-за reasoning тоже перманентный для scheduler", () => {
    // Граница ответственности: scheduler такой отказ не повторяет, самовосстановление
    // обязано произойти внутри callLLM (см. группу «сообщение об ошибке»).
    const err = transportError(400, "reasoning.effort 'none' is not supported by this model");
    expect(isPermanentLLMErrorStatus(400)).toBe(true);
    expect(shouldRetry(err, 0, 3)).toBe(false);
  });
});

describe("retryDelayMs", () => {
  it("для 5xx пауза фиксирована: 10 с на любой попытке", () => {
    // У 5xx нет retry-after, поэтому берётся дефолт 10 с, обрезанный потолком
    // `(attempt + 1) * 10`. На первой попытке потолок равен самому дефолту,
    // дальше он перестаёт влиять — пауза не растёт.
    expect(retryDelayMs(transportError(500, "сбой"), 0)).toBe(10_000);
    expect(retryDelayMs(transportError(500, "сбой"), 1)).toBe(10_000);
    expect(retryDelayMs(transportError(500, "сбой"), 3)).toBe(10_000);
  });

  it("без статуса — линейный рост", () => {
    expect(retryDelayMs(new Error("boom"), 0)).toBe(2_000);
    expect(retryDelayMs(new Error("boom"), 1)).toBe(4_000);
  });
});

describe("сообщение об ошибке читаемо (реальный транспорт)", () => {
  it("400 «модель не найдена»: оба имени модели видны, JSON-обёртки нет", async () => {
    const server = await startServer(() => ({
      status: 400,
      contentType: "application/json",
      body: JSON.stringify(modelNotFoundBody),
    }));
    setEnv("LLM_BASE_URL", server.baseUrl);

    const err = await callLLM("prompt").then(
      () => new Error("ожидалась ошибка"),
      (e: unknown) => e as Error,
    );
    const text = err.message;

    // Имя запрошенной модели и подсказка провайдера — именно они терялись
    // при обрезке тела до 300 символов.
    expect(text).toContain("qwen3.5-flash");
    expect(text).toContain("qwen3.8-flash");
    // Сырая обёртка убрана.
    expect(text).not.toContain('{"error"');
    expect(text).not.toContain('"message"');
    // И добавлена подсказка про build-time конфиг.
    expect(text).toContain("provider-config.json");
  });

  it("400 не про модель: подсказки про пересборку нет", async () => {
    const server = await startServer(() => ({
      status: 400,
      contentType: "application/json",
      body: JSON.stringify({ error: { message: "context length exceeded", code: 400 } }),
    }));
    setEnv("LLM_BASE_URL", server.baseUrl);

    const err = await callLLM("prompt").then(
      () => new Error("ожидалась ошибка"),
      (e: unknown) => e as Error,
    );
    const text = err.message;

    expect(text).toContain("context length exceeded");
    expect(text).toContain("(400)");
    expect(text).not.toContain("provider-config.json");
    expect(text).not.toContain('{"error"');
  });

  it("тело не-JSON не ломается и сохраняется как есть", async () => {
    const server = await startServer(() => ({
      status: 400,
      contentType: "text/plain",
      body: "Internal Server Error",
    }));
    setEnv("LLM_BASE_URL", server.baseUrl);

    const err = await callLLM("prompt").then(
      () => new Error("ожидалась ошибка"),
      (e: unknown) => e as Error,
    );
    const text = err.message;

    expect(text).toContain("Internal Server Error");
    expect(text).toContain("(400)");
  });

  it("HTML-страница провайдера: как раньше — заголовок из <title>", async () => {
    const server = await startServer(() => ({
      status: 502,
      contentType: "text/html",
      body:
        "<!DOCTYPE html><html><head><title>502 Bad Gateway</title></head>" +
        "<body><h1>502 Bad Gateway</h1></body></html>",
    }));
    setEnv("LLM_BASE_URL", server.baseUrl);

    const err = await callLLM("prompt").then(
      () => new Error("ожидалась ошибка"),
      (e: unknown) => e as Error,
    );

    expect(err.message).toContain('HTML-страница провайдера: "502 Bad Gateway"');
  });

  it("отказ 400 из-за reasoning всё ещё лечится внутри callLLM", async () => {
    // Связка с политикой ретраев: scheduler такой отказ повторять не будет,
    // поэтому самовосстановление обязано произойти на транспортном уровне.
    const server = await startServer((body) => {
      if (body.reasoning !== undefined) {
        return {
          status: 400,
          contentType: "application/json",
          body: JSON.stringify({
            error: { message: "reasoning.effort 'none' is not supported by this model" },
          }),
        };
      }
      return {
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          choices: [{ message: { role: "assistant", content: '{"one_liner":"ок"}' } }],
        }),
      };
    });
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "none");

    const result = await callLLM("prompt");

    expect(result.text).toBe('{"one_liner":"ок"}');
    // Ровно один отказ 400 и один успешный повтор без поля reasoning.
    expect(server.bodies).toHaveLength(2);
    expect(server.bodies[0]?.reasoning).toBeDefined();
    expect(server.bodies[1]?.reasoning).toBeUndefined();
  });
});