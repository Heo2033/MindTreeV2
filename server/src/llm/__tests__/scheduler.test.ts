import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TreeScheduler, isRateLimitError } from "../scheduler.js";
import { LLMCache } from "../cache.js";
import { LLMRateLimitError, LLMRetriesExhaustedError, defaultTemperatureForOperation } from "../client.js";
// callLLM подменяем, чтобы управлять сценариями «рейт-лимит / обычная ошибка /
// успех». Прочие экспорты client.js (классы ошибок и т.п.) — реальные.
vi.mock("../client.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../client.js")>();
  return { ...mod, callLLM: vi.fn() };
});

import { callLLM } from "../client.js";

const mockedCallLLM = vi.mocked(callLLM);

function makeScheduler(options?: {
  maxRetries?: number;
  opDeadlineMs?: number;
}): TreeScheduler {
  return new TreeScheduler(
    {
      maxRetries: options?.maxRetries ?? 2,
      opDeadlineMs: options?.opDeadlineMs ?? 60_000,
      maxRPM: 1000,
      maxRPD: 100_000,
      maxConcurrency: 1,
      batchSize: 3,
    },
    new LLMCache({ persistDir: null }),
  );
}

const parse = (raw: string): string => raw;

beforeEach(() => {
  mockedCallLLM.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("isRateLimitError", () => {
  it("истина для 429/408 (класс и текст ошибки)", () => {
    expect(isRateLimitError(new LLMRateLimitError(429, "cooldown", 5))).toBe(true);
    expect(isRateLimitError(new LLMRateLimitError(408, "timeout", null))).toBe(true);
    expect(isRateLimitError(new Error("LLM API ошибка (429): Incorrect..."))).toBe(true);
  });

  it("ложь для прочих статусов и обычных ошибок", () => {
    expect(isRateLimitError(new LLMRateLimitError(500, "bad", null))).toBe(false);
    expect(isRateLimitError(new Error("LLM API ошибка (503): busy"))).toBe(false);
    expect(isRateLimitError(new Error("просто текст"))).toBe(false);
  });
});

describe("TreeScheduler.execute: ретраи при рейт-лимите", () => {
  it("429-ошибки ретраятся за пределами maxRetries и не тратят бюджет", async () => {
    const scheduler = makeScheduler({ maxRetries: 1 });
    const backoff = vi.fn();
    scheduler.onBackoff = backoff;

    mockedCallLLM
      .mockRejectedValueOnce(new LLMRateLimitError(429, "cooldown", 0))
      .mockRejectedValueOnce(new LLMRateLimitError(429, "cooldown", 0))
      .mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    const res = await scheduler.execute("structure", () => "prompt", parse, {
      model: "test-model",
    });

    expect(res.result).toBe('"ok"');
    expect(mockedCallLLM).toHaveBeenCalledTimes(3);
    expect(backoff).toHaveBeenCalledTimes(2);
  });

  it("обычная (не рейт-лимит) ошибка ограничена maxRetries", async () => {
    const scheduler = makeScheduler({ maxRetries: 1 });
    const backoff = vi.fn();
    scheduler.onBackoff = backoff;

    mockedCallLLM
      .mockRejectedValueOnce(new Error("LLM API ошибка: разлом"))
      .mockRejectedValueOnce(new Error("LLM API ошибка: разлом"));

    vi.useFakeTimers();
    const promise = scheduler
      .execute("structure", () => "prompt", parse, { model: "test-model" })
      .then(
        () => {
          throw new Error("ожидалось исключение");
        },
        (err) => err,
      );

    await vi.advanceTimersByTimeAsync(10_000);
    await expect(promise).resolves.toBeInstanceOf(LLMRetriesExhaustedError);
    expect(mockedCallLLM).toHaveBeenCalledTimes(2);
    expect(backoff).not.toHaveBeenCalled();
  });

  it("при персистентном рейт-лимите исчерпывается защитный потолок и падает LLMRetriesExhaustedError", async () => {
    const scheduler = makeScheduler({ opDeadlineMs: 0 }); // дедлайн отключён
    const backoff = vi.fn();
    scheduler.onBackoff = backoff;

    mockedCallLLM.mockRejectedValue(new LLMRateLimitError(429, "cooldown", 0));

    await expect(
      scheduler.execute("structure", () => "prompt", parse, { model: "test-model" }),
    ).rejects.toBeInstanceOf(LLMRetriesExhaustedError);

    expect(mockedCallLLM.mock.calls.length).toBeGreaterThan(1);
    expect(backoff.mock.calls.length).toBeGreaterThan(1);
  });

  it("onBackoff не дергается при мгновенном успехе", async () => {
    const scheduler = makeScheduler();
    const backoff = vi.fn();
    scheduler.onBackoff = backoff;

    mockedCallLLM.mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    const res = await scheduler.execute("structure", () => "prompt", parse, {
      model: "test-model",
    });

    expect(res.result).toBe('"ok"');
    expect(backoff).not.toHaveBeenCalled();
  });
});

// Регрессия транспортных параметров (зеркало flutter
// test/data/llm/transport_params_test.dart).
//
// Температура была одна на все операции. Для детерминированных операций
// (`validate`, `structure*`, `assessment`, ...) это и качество — мусор на
// границах JSON-схемы, и деньги — лишние токены на сильной модели.
describe("TreeScheduler.execute: per-op температура", () => {
  it("детерминированная операция уходит с temperature=0", async () => {
    mockedCallLLM.mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    await makeScheduler().execute("validate", () => "prompt", parse, { model: "m" });

    expect(mockedCallLLM.mock.calls[0]?.[1]?.temperature).toBe(0);
  });

  it("прочие операции оставляют дефолт конфига (undefined)", async () => {
    mockedCallLLM.mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    await makeScheduler().execute("content", () => "prompt", parse, { model: "m" });

    expect(mockedCallLLM.mock.calls[0]?.[1]?.temperature).toBeUndefined();
  });

  it("явный temperature важнее per-op правила", async () => {
    mockedCallLLM.mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    await makeScheduler().execute("validate", () => "prompt", parse, {
      model: "m",
      temperature: 0.35,
    });

    expect(mockedCallLLM.mock.calls[0]?.[1]?.temperature).toBe(0.35);
  });
});

describe("defaultTemperatureForOperation", () => {
  it("детерминированные операции получают 0", () => {
    for (const op of [
      "structure",
      "structure-l2",
      "structure-l3",
      "validate",
      "curriculum",
      "assessment",
      "mastery",
    ]) {
      expect(defaultTemperatureForOperation(op)).toBe(0);
    }
  });

  it("остальные операции возвращают undefined", () => {
    for (const op of ["content", "activity", "repair", "quiz", "tutor", "milestone", "неизвестная"]) {
      expect(defaultTemperatureForOperation(op)).toBeUndefined();
    }
  });
});

// ─── Регрессия транспорта: перманентные 4xx не повторяются ────────────────────
//
// Пользовательский баг: провайдер отвечал 400 «модель не найдена», и на него
// тратились все попытки подряд, а пользователю показывали «исчерпаны попытки».
// Чистая политика ретраев разобрана в `retryPolicy.test.ts`, здесь — сквозной
// сценарий через TreeScheduler: сколько раз реально позвали LLM и что ушло
// наружу. Зеркало flutter-теста `test/data/llm/retry_policy_test.dart`.

const MODEL_NOT_FOUND_MESSAGE =
  "Указанная модель (qwen3.5-flash) не найдена, либо сейчас недоступна. " +
  'Возможно вы хотели использовать модель "qwen3.8-flash"?';

const savedEnv: Record<string, string | undefined> = {};

function setEnv(key: string, value: string | undefined): void {
  if (!(key in savedEnv)) savedEnv[key] = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

describe("TreeScheduler.execute: перманентные 4xx и fallback", () => {
  beforeEach(() => {
    setEnv("LLM_MOCK", undefined);
    setEnv("LLM_API_KEY", "test-key");
    setEnv("LLM_PROVIDER", "openai");
  });

  afterEach(() => {
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it("400 «модель не найдена»: один вызов LLM, причина не теряется", async () => {
    const scheduler = makeScheduler({ maxRetries: 3 });
    mockedCallLLM.mockRejectedValue(
      new Error(`LLM API ошибка (400): ${MODEL_NOT_FOUND_MESSAGE}`),
    );

    let thrown: unknown;
    try {
      await scheduler.execute("content", () => "prompt", parse, { model: "qwen3.5-flash" });
    } catch (err) {
      thrown = err;
    }

    // Было 4 логические попытки (maxRetries: 3) — стало 1.
    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    // Текст причины сохраняется дословно: имя модели видно пользователю.
    expect((thrown as Error).message).toContain("qwen3.5-flash");
    expect((thrown as Error).message).toContain("qwen3.8-flash");
    expect((thrown as Error).message).not.toContain('{"error"');

    // Перманентный отказ повторами не лечится, поэтому сервер, как и flutter,
    // бросает исходную ошибку, а не обёртку «исчерпаны попытки»: обёртка с
    // attempts === 1 прятала бы от пользователя саму причину отказа.
    expect(thrown).not.toBeInstanceOf(LLMRetriesExhaustedError);
    expect((thrown as Error).message).toContain("Указанная модель");
  });

  it("5xx: ровно maxRetries + 1 вызовов и LLMRetriesExhaustedError", async () => {
    // Дедлайн операции отключён: иначе он срежет последнюю попытку раньше, чем
    // израсходуется maxRetries (паузы retryDelayMs для 5xx — 10/20/30 с).
    const scheduler = makeScheduler({ maxRetries: 3, opDeadlineMs: 0 });
    mockedCallLLM.mockRejectedValue(new Error("LLM API ошибка (500): Internal Server Error"));

    vi.useFakeTimers();
    const promise = scheduler
      .execute("content", () => "prompt", parse, { model: "qwen3.5-flash" })
      .then(
        () => {
          throw new Error("ожидалось исключение");
        },
        (err: unknown) => err,
      );

    await vi.advanceTimersByTimeAsync(90_000);
    const thrown = (await promise) as LLMRetriesExhaustedError;

    expect(mockedCallLLM).toHaveBeenCalledTimes(4);
    expect(thrown).toBeInstanceOf(LLMRetriesExhaustedError);
    expect(thrown.attempts).toBe(4);
    expect(thrown.message).toContain("Internal Server Error");
  });

  it("400 на первой модели: fallback на следующую модель", async () => {
    setEnv("LLM_MODEL_STRONG", "qwen3.5-flash");
    setEnv("LLM_MODEL_STRONG_FALLBACK", "qwen3.8-flash");

    mockedCallLLM
      .mockRejectedValueOnce(new Error(`LLM API ошибка (400): ${MODEL_NOT_FOUND_MESSAGE}`))
      .mockResolvedValueOnce({ text: '"ok"', usage: { input_tokens: 1, output_tokens: 1 } });

    // `structure` — операция тира strong, у неё есть fallback-модель.
    // Модель не передаём: берётся список из конфига.
    const res = await makeScheduler({ maxRetries: 3 }).execute(
      "structure",
      () => "prompt",
      parse,
    );

    expect(mockedCallLLM).toHaveBeenCalledTimes(2);
    expect(mockedCallLLM.mock.calls[0]?.[1]?.model).toBe("qwen3.5-flash");
    expect(mockedCallLLM.mock.calls[1]?.[1]?.model).toBe("qwen3.8-flash");
    expect(res.result).toBe('"ok"');
  });
});