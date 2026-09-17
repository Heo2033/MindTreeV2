import { describe, expect, it } from "vitest";
import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";

// Список методов в точности повторяет регистрацию в server/src/index.ts
// (app.register(cors, { origin: true, methods: [...] })). Фронт и десктоп-обвязка
// обращаются к серверу с другого origin, поэтому для DELETE/PATCH обязателен
// разрешающий preflight — иначе браузер/WebView2 блокирует запрос ещё до отправки.
const METHODS = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"];

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(cors, { origin: true, methods: METHODS });
  app.delete("/api/topics/:id", async () => ({ ok: true }));
  app.patch("/api/milestones/:id", async () => ({ ok: true }));
  return app;
}

describe("CORS: preflight для не-GET/POST методов", () => {
  it("OPTIONS c Access-Control-Request-Method: DELETE → 204 и Allow-Methods содержит DELETE", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "OPTIONS",
      url: "/api/topics/topic-1",
      headers: {
        origin: "http://localhost:5173",
        "access-control-request-method": "DELETE",
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-methods"]).toContain("DELETE");
    expect(res.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
    await app.close();
  });

  it("OPTIONS c Access-Control-Request-Method: PATCH → 204 и Allow-Methods содержит PATCH", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "OPTIONS",
      url: "/api/milestones/m-1",
      headers: {
        origin: "http://localhost:5173",
        "access-control-request-method": "PATCH",
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-methods"]).toContain("PATCH");
    await app.close();
  });

  it("preflight без Origin/Access-Control-Request-Method → 400 (strict mode)", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "OPTIONS", url: "/api/topics/topic-1" });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it("прямой DELETE с Origin проходит с отражённым источником", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "DELETE",
      url: "/api/topics/topic-1",
      headers: { origin: "http://localhost:5173" },
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
    await app.close();
  });

  it("Allow-Methods не должен перекрывать GET/POST (регрессия базовых методов)", async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: "OPTIONS",
      url: "/api/topics/topic-1",
      headers: {
        origin: "http://localhost:5173",
        "access-control-request-method": "POST",
      },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers["access-control-allow-methods"]).toContain("POST");
    await app.close();
  });
});