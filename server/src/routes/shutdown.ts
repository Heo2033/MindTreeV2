import type { FastifyInstance } from "fastify";

// Штатное завершение сервера по запросу Rust-обвязки (нужен токен — маршрут
// не в белом списке auth.ts). Ответ клиенту уходит до закрытия, чтобы десктоп
// успел его получить, затем сервер зовёт onClose (checkpoint WAL и закрытие
// лучше-sqlite3) и выходит с кодом 0.
export async function shutdownRoutes(app: FastifyInstance) {
  app.post("/api/shutdown", async (_request, reply) => {
    await reply.send({ ok: true });
    setTimeout(() => {
      app
        .close()
        .catch(() => {})
        .finally(() => process.exit(0));
    }, 50);
  });
}