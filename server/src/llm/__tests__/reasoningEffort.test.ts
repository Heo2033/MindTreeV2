import http from "node:http";
import type { AddressInfo } from "node:net";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { callLLM, REASONING_EFFORT_VALUES } from "../client.js";

/**
 * Управление рассуждениями (`reasoning`) и учёт их стоимости.
 *
 * Найденные баги, которые закрывает этот файл:
 *
 * 1. Рассуждения модели никогда не отключались, при этом они входят в
 *    `completion_tokens` и тарифицируются. Замер на живом провайдере: задача с
 *    ответом ~30 токенов вернула 4106 выходных токенов, 4077 из них —
 *    reasoning; с `effort: "none"` — 35 токенов и ноль reasoning.
 * 2. `effort` и `max_tokens` внутри `reasoning` провайдер не принимает
 *    одновременно («что-то одно»), поэтому явный бюджет должен побеждать.
 * 3. У части моделей (семейство `glm-5.3*`) thinking обязателен и `effort` даёт
 *    400 — такой отказ не должен ронять пользовательский сценарий.
 * 4. `usage.cost_rub` (реальная стоимость в рублях) не читался.
 *
 * Зеркало flutter-теста `test/data/llm/reasoning_effort_test.dart`.
 */

interface Responder {
  status: number;
  body: Record<string, unknown>;
}

const savedEnv: Record<string, string | undefined> = {};

function setEnv(key: string, value: string | undefined): void {
  if (!(key in savedEnv)) savedEnv[key] = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

beforeEach(() => {
  setEnv("LLM_BASE_URL", undefined);
  setEnv("LLM_API_KEY", "test-key");
  setEnv("LLM_MODEL", "test-model");
  setEnv("LLM_PROVIDER", "openai");
  setEnv("LLM_REASONING_EFFORT", undefined);
  setEnv("LLM_REASONING_MAX_TOKENS", undefined);
});

afterEach(() => {
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

/**
 * Локальный сервер: копит тела POST-запросов и отвечает по `responder`.
 *
 * `provider: "openai"` обязателен — по умолчанию адрес на 127.0.0.1
 * распознаётся как Ollama и уходит в другую ветку вызова.
 */
async function startServer(responder: (body: Record<string, unknown>) => Responder): Promise<{
  baseUrl: string;
  bodies: Record<string, unknown>[];
}> {
  const bodies: Record<string, unknown>[] = [];
  const server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      const body = JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
      bodies.push(body);
      const out = responder(body);
      res.writeHead(out.status, { "content-type": "application/json" });
      res.end(JSON.stringify(out.body));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return { baseUrl: `http://127.0.0.1:${port}/v1`, bodies };
}

function answer(overrides: {
  content?: string;
  reasoningTokens?: number;
  costRub?: number;
} = {}): Record<string, unknown> {
  return {
    choices: [{ message: { role: "assistant", content: overrides.content ?? '{"one_liner":"скорость"}' } }],
    usage: {
      prompt_tokens: 100,
      completion_tokens: 40,
      completion_tokens_details: { reasoning_tokens: overrides.reasoningTokens ?? 0 },
      cost_rub: overrides.costRub ?? 0.5,
    },
  };
}

describe("допустимые уровни reasoning", () => {
  it("содержит none и запрещает мусорные значения", () => {
    expect(REASONING_EFFORT_VALUES.has("none")).toBe(true);
    expect(REASONING_EFFORT_VALUES.has("minimal")).toBe(true);
    expect(REASONING_EFFORT_VALUES.has("частично")).toBe(false);
    expect(REASONING_EFFORT_VALUES.has("")).toBe(false);
  });
});

describe("тело запроса и парсинг usage", () => {
  it("effort попадает в тело запроса, usage читается полностью", async () => {
    const server = await startServer(() => ({ status: 200, body: answer({ reasoningTokens: 12 }) }));
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "none");

    const result = await callLLM("prompt");

    expect(server.bodies).toHaveLength(1);
    expect(server.bodies[0].reasoning).toEqual({ effort: "none" });
    expect(server.bodies[0].max_tokens).toBe(16384);
    expect(result.usage.input_tokens).toBe(100);
    expect(result.usage.output_tokens).toBe(40);
    expect(result.usage.reasoning_tokens).toBe(12);
    expect(result.usage.cost_rub).toBe(0.5);
  });

  it("бюджет рассуждений не дублируется с уровнем усилий", async () => {
    const server = await startServer(() => ({ status: 200, body: answer() }));
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "high");
    setEnv("LLM_REASONING_MAX_TOKENS", "1000");

    await callLLM("prompt");

    expect(server.bodies[0].reasoning).toEqual({ max_tokens: 1000 });
  });

  it("пустое значение effort не отправляет поле reasoning", async () => {
    const server = await startServer(() => ({ status: 200, body: answer() }));
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "не-уровень");

    await callLLM("prompt");

    expect(server.bodies[0].reasoning).toBeUndefined();
  });

  it("отказ из-за reasoning не роняет вызов: один повтор без него", async () => {
    const server = await startServer((body) => {
      if (body.reasoning !== undefined) {
        return {
          status: 400,
          body: { error: { message: "reasoning.effort 'none' is not supported by this model" } },
        };
      }
      return { status: 200, body: answer({ content: '{"one_liner":"ок"}' }) };
    });
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "none");

    const result = await callLLM("prompt");

    expect(result.text).toBe('{"one_liner":"ок"}');
    expect(server.bodies).toHaveLength(2);
    expect(server.bodies[0].reasoning).toBeDefined();
    expect(server.bodies[1].reasoning).toBeUndefined();
  });

  it("после отказа поле reasoning больше не отправляется", async () => {
    const server = await startServer((body) => {
      if (body.reasoning !== undefined) {
        return { status: 422, body: { error: { message: "thinking is required for this model" } } };
      }
      return { status: 200, body: answer({ content: '{"one_liner":"ок"}' }) };
    });
    setEnv("LLM_BASE_URL", server.baseUrl);
    setEnv("LLM_REASONING_EFFORT", "none");

    await callLLM("первый");
    const afterFirst = server.bodies.length;
    await callLLM("второй");

    // Второй логический вызов не должен тратить ещё один отказ.
    expect(server.bodies.length - afterFirst).toBe(1);
    expect(server.bodies.at(-1)?.reasoning).toBeUndefined();
  });
});
