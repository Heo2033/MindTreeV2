import { afterEach, describe, expect, it } from "vitest";
import Fastify, { type FastifyInstance } from "fastify";
import { installAuth, configuredAuthToken, AUTH_TOKEN_ENV } from "../../auth.js";
import { healthRoutes } from "../health.js";
import { shutdownRoutes } from "../shutdown.js";
import { configRoutes } from "../config.js";

const TOKEN = "test-token-0123456789abcdef";

async function buildAuthApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  installAuth(app);
  await app.register(healthRoutes);
  await app.register(shutdownRoutes);
  await app.register(configRoutes, { prefix: "/api/config" });
  return app;
}

afterEach(() => {
  delete process.env[AUTH_TOKEN_ENV];
});

describe("installAuth", () => {
  it("configuredAuthToken возвращает env без пробелов", () => {
    process.env[AUTH_TOKEN_ENV] = `  ${TOKEN}  `;
    expect(configuredAuthToken()).toBe(TOKEN);
    process.env[AUTH_TOKEN_ENV] = "";
    expect(configuredAuthToken()).toBeNull();
    delete process.env[AUTH_TOKEN_ENV];
    expect(configuredAuthToken()).toBeNull();
  });

  it("health остаётся открытым, остальные маршруты — 401 без токена", async () => {
    process.env[AUTH_TOKEN_ENV] = TOKEN;
    const app = await buildAuthApp();

    const health = await app.inject({ method: "GET", url: "/api/health" });
    expect(health.statusCode).toBe(200);

    const config = await app.inject({ method: "GET", url: "/api/config" });
    expect(config.statusCode).toBe(401);

    const shutdown = await app.inject({ method: "POST", url: "/api/shutdown" });
    expect(shutdown.statusCode).toBe(401);

    await app.close();
  });

  it("неверный токен отклоняется", async () => {
    process.env[AUTH_TOKEN_ENV] = TOKEN;
    const app = await buildAuthApp();

    const res = await app.inject({
      method: "GET",
      url: "/api/config",
      headers: { authorization: "Bearer wrong" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "unauthorized" });

    await app.close();
  });

  it("верный токен пропускает запрос", async () => {
    process.env[AUTH_TOKEN_ENV] = TOKEN;
    const app = await buildAuthApp();

    const res = await app.inject({
      method: "GET",
      url: "/api/config",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(res.statusCode).toBe(200);

    await app.close();
  });

  it("без env токена авторизация выключена (dev-режим)", async () => {
    const app = await buildAuthApp();

    const res = await app.inject({ method: "GET", url: "/api/config" });
    expect(res.statusCode).toBe(200);

    await app.close();
  });
});