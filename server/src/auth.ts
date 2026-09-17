import type { FastifyInstance } from "fastify";

// Однократный токен встроенного сервера десктопного приложения. Rust генерит
// случайный токен при спавне и передаёт его через env MINDTREE_AUTH_TOKEN;
// фронтенд получает его отдельной Tauri-командой и шлёт в заголовке
// Authorization: Bearer. Если env отсутствует (чистый `npm run dev:server`),
// авторизация выключена — dev-режим не ломается.
export const AUTH_TOKEN_ENV = "MINDTREE_AUTH_TOKEN";

export function configuredAuthToken(): string | null {
  const raw = process.env[AUTH_TOKEN_ENV];
  return raw && raw.trim() !== "" ? raw.trim() : null;
}

export function installAuth(app: FastifyInstance): void {
  const token = configuredAuthToken();
  if (token === null) return;

  app.addHook("preHandler", async (request, reply) => {
    // /api/health остаётся открытым: Rust по нему ждёт готовность сервера
    // до того, как выдаст токен фронтенду.
    if (request.routeOptions.url === "/api/health") return;
    const header = request.headers.authorization;
    if (header !== `Bearer ${token}`) {
      return reply.status(401).send({ error: "unauthorized" });
    }
  });
}