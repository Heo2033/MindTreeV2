import type { FastifyInstance } from "fastify";
import { AnalyticsService } from "../domain/AnalyticsService.js";

export async function analyticsRoutes(app: FastifyInstance) {
  const analytics = new AnalyticsService();

  // §71: общая сводка по всем темам (продуктовые метрики).
  app.get("/", async (_request, reply) => {
    return reply.send(analytics.summary());
  });

  // §71: метрики конкретной темы.
  app.get("/topic/:id", async (request, reply) => {
    const { id } = request.params as { id: string };
    const metrics = analytics.topicMetrics(id);
    if (!metrics) return reply.status(404).send({ error: "Тема не найдена" });
    return reply.send(metrics);
  });
}
