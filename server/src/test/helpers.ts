import Fastify, { type FastifyInstance } from "fastify";
import { getDb } from "../db/connection.js";
import { milestoneRoutes } from "../routes/milestones.js";
import { analyticsRoutes } from "../routes/analytics.js";
import { topicRoutes } from "../routes/topics.js";
import { sessionRoutes } from "../routes/sessions.js";

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  app.decorate("db", getDb());
  await app.register(topicRoutes, { prefix: "/api/topics" });
  await app.register(sessionRoutes, { prefix: "/api/sessions" });
  await app.register(milestoneRoutes, { prefix: "/api/milestones" });
  await app.register(analyticsRoutes, { prefix: "/api/analytics" });
  return app;
}

export function seedTopic(
  id: string,
  name = "Test Topic",
  opts: { goal?: string; target_level?: string } = {},
): void {
  getDb()
    .prepare(
      `INSERT INTO topics (id, name, goal, target_level)
       VALUES (?, ?, ?, ?)`,
    )
    .run(id, name, opts.goal ?? "overview", opts.target_level ?? "basic_understanding");
}

export function seedJourney(id: string, topicId: string): void {
  getDb()
    .prepare(`INSERT INTO learning_journeys (id, topic_id) VALUES (?, ?)`)
    .run(id, topicId);
}
