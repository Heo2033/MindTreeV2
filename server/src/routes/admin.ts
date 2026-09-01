import type { FastifyInstance } from "fastify";
import {
  getConfigFilePath,
  getAppliedAt,
  getRuntimeConfig,
} from "../config/runtimeConfig.js";
import { getModelName, getModelForTier } from "../llm/client.js";
import { aggregateStats, recentOperations } from "../llm/telemetry.js";
import { getCache } from "../llm/scheduler.js";
import { recentAppLogs } from "../lib/appLog.js";

const startedAt = Date.now();

export async function adminRoutes(app: FastifyInstance) {
  app.get("/status", async (_request, reply) => {
    const topicCount = (
      (app.db.prepare("SELECT COUNT(*) AS n FROM topics").get() as { n: number }) ?? { n: 0 }
    ).n;

    const effective: Record<string, unknown> = {
      runtimeConfigured: getAppliedAt() !== null,
    };
    try {
      effective.model = getModelName();
      effective.modelStrong = getModelForTier("strong");
      effective.modelFast = getModelForTier("fast");
    } catch {
      // config not usable yet
    }

    const runtimeCfg = getRuntimeConfig();

    return reply.send({
      uptimeMs: Date.now() - startedAt,
      startedAt: new Date(startedAt).toISOString(),
      config: {
        source: runtimeCfg ? "runtime" : "env",
        appliedAt: getAppliedAt(),
        configFile: getConfigFilePath(),
        configuredBaseUrl: Boolean(runtimeCfg?.baseUrl || process.env.LLM_BASE_URL),
        apiKeySet: Boolean(
          runtimeCfg?.apiKey || process.env.LLM_API_KEY,
        ),
        effective,
      },
      topics: { count: topicCount },
      llm: {
        stats: aggregateStats(),
        recent: recentOperations(20),
      },
      cache: getCache().stats(),
    });
  });

  app.get("/logs", async (_request, reply) => {
    const limit = Number((_request.query as { limit?: string })?.limit) || 100;
    return reply.send({
      logs: recentAppLogs(limit),
      llm: recentOperations(limit),
    });
  });
}
