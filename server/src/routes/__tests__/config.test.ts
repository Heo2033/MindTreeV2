import { afterEach, beforeEach, describe, expect, it } from "vitest";
import Fastify, { type FastifyInstance } from "fastify";
import { configRoutes, mergeProvisionConfig } from "../config.js";
import {
  applyRuntimeConfig,
  clearRuntimeConfig,
  getConfigFilePath,
  getRuntimeConfig,
  type RuntimeLLMConfig,
} from "../../config/runtimeConfig.js";

const CONFIG_FILE_ENV = "MINDTREE_SERVER_CONFIG";
const TMP_CONFIG = "data/__test_runtime_config__.json";

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(configRoutes, { prefix: "/api/config" });
  return app;
}

beforeEach(() => {
  clearRuntimeConfig();
  process.env[CONFIG_FILE_ENV] = TMP_CONFIG;
  delete process.env.LLM_API_KEY;
  delete process.env.OPENAI_API_KEY;
});

afterEach(() => {
  clearRuntimeConfig();
  delete process.env[CONFIG_FILE_ENV];
  delete process.env.LLM_API_KEY;
  delete process.env.OPENAI_API_KEY;
});

describe("configRoutes: apiKeyConfigured", () => {
  it("без runtime-конфига и env ключ не сконфигурирован", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "GET", url: "/api/config" });
    expect(res.statusCode).toBe(200);
    expect(res.json().effective.apiKeyConfigured).toBe(false);
    await app.close();
  });

  it("env LLM_API_KEY отражается в apiKeyConfigured", async () => {
    process.env.LLM_API_KEY = "sk-env-key";
    const app = await buildApp();
    const res = await app.inject({ method: "GET", url: "/api/config" });
    expect(res.statusCode).toBe(200);
    expect(res.json().effective.apiKeyConfigured).toBe(true);
    await app.close();
  });

  it("POST /api/config с apiKey переключает флаг, ключ на диск не попадает", async () => {
    const app = await buildApp();
    const post = await app.inject({
      method: "POST",
      url: "/api/config",
      payload: { provider: "openai", apiKey: "sk-secret-123" },
    });
    expect(post.json().ok).toBe(true);

    const get = await app.inject({ method: "GET", url: "/api/config" });
    expect(get.json().effective.apiKeyConfigured).toBe(true);

    const fs = await import("fs");
    const file = getConfigFilePath();
    const onDisk = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
    expect(onDisk).not.toContain("sk-secret-123");
    await app.close();
  });
});

describe("mergeProvisionConfig", () => {
  it("мержит пробный конфиг поверх runtime", () => {
    const runtime: RuntimeLLMConfig = {
      provider: "openai",
      baseUrl: "https://api.openai.com/v1",
      model: "gpt-4o",
    };
    const provisional: RuntimeLLMConfig = { apiKey: "sk-tmp" };
    const merged = mergeProvisionConfig(runtime, provisional);
    expect(merged).toEqual({
      provider: "openai",
      baseUrl: "https://api.openai.com/v1",
      model: "gpt-4o",
      apiKey: "sk-tmp",
    });
  });

  it("пустой runtime не мешает пробному конфигу", () => {
    const merged = mergeProvisionConfig(null, { baseUrl: "http://x" });
    expect(merged).toEqual({ baseUrl: "http://x" });
  });
});

describe("configRoutes: частичный apply сохраняет остальной конфиг", () => {
  it("apply({model, baseUrl}) затем apply({apiKey}) — модель и baseUrl не стираются, ключ на диск не попадает", async () => {
    const app = await buildApp();
    await app.inject({
      method: "POST",
      url: "/api/config",
      payload: { provider: "openai", baseUrl: "https://api.openrouter.ai/v1", model: "gpt-4o-test" },
    });
    await app.inject({
      method: "POST",
      url: "/api/config",
      payload: { apiKey: "sk-secret-123" },
    });

    const get = await app.inject({ method: "GET", url: "/api/config" });
    expect(get.json().effective.apiKeyConfigured).toBe(true);
    // Модель из прошлого apply сохранилась (не упала в дефолт gpt-4o).
    expect(get.json().effective.model).toBe("gpt-4o-test");

    const fs = await import("fs");
    const onDisk = fs.existsSync(getConfigFilePath())
      ? (JSON.parse(fs.readFileSync(getConfigFilePath(), "utf8")) as { config?: RuntimeLLMConfig })
      : {};
    expect(onDisk.config?.baseUrl).toBe("https://api.openrouter.ai/v1");
    expect(onDisk.config?.model).toBe("gpt-4o-test");
    expect(onDisk.config?.apiKey).toBeUndefined();
    await app.close();
  });

  it("applyRuntimeConfig мержит частичный конфиг поверх текущего", () => {
    applyRuntimeConfig({ provider: "openai", baseUrl: "https://api.openrouter.ai/v1", model: "gpt-4o" });
    applyRuntimeConfig({ apiKey: "sk-1" });
    expect(getRuntimeConfig()).toEqual({
      provider: "openai",
      baseUrl: "https://api.openrouter.ai/v1",
      model: "gpt-4o",
      apiKey: "sk-1",
    });
  });
});

describe("configRoutes: /test", () => {
  it("test с пробным конфигом использует его, а не runtime (ошибка про недоступный адрес, а не про ключ)", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "POST",
      url: "/api/config/test",
      payload: {
        provider: "openai",
        baseUrl: "http://127.0.0.1:1",
        model: "test-model",
        apiKey: "sk-provisional",
      },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.ok).toBe(false);
    // Проваливаться должны сетевые подключения, а не отсутствие ключа.
    expect(body.error).not.toContain("не задан");
    expect(body.error).not.toContain("LLM_API_KEY");
    await app.close();
  });

  it("test без тела падает с сообщением о ключе, если runtime без ключа", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "POST", url: "/api/config/test" });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toContain("не задан");
    await app.close();
  });
});