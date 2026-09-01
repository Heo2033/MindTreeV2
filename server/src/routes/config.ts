import type { FastifyInstance } from "fastify";
import {
  applyRuntimeConfig,
  clearRuntimeConfig,
  getAppliedAt,
  getConfigFilePath,
  type RuntimeLLMConfig,
} from "../config/runtimeConfig.js";
import { getModelName, getModelForTier, callLLM } from "../llm/client.js";

const FLAT_KEYS: Array<keyof RuntimeLLMConfig> = [
  "baseUrl",
  "apiKey",
  "model",
  "modelStrong",
  "modelFast",
  "temperature",
  "numCtx",
  "provider",
];

function sanitize(raw: Record<string, unknown>): RuntimeLLMConfig {
  const out: RuntimeLLMConfig = {};
  for (const key of FLAT_KEYS) {
    const v = raw[key];
    if (v === undefined || v === null) continue;
    if (key === "provider") {
      const p = String(v).trim().toLowerCase();
      if (p === "ollama" || p === "openai" || p === "auto") out.provider = p;
      continue;
    }
    if (key === "temperature" || key === "numCtx") {
      const n = Number(v);
      if (Number.isFinite(n)) (out as Record<string, number>)[key] = n;
      continue;
    }
    const s = String(v).trim();
    if (s !== "") (out as Record<string, string>)[key] = s;
  }
  return out;
}

export async function configRoutes(app: FastifyInstance) {
  app.get("/", async (_request, reply) => {
    const effective: Record<string, unknown> = { runtimeConfigured: getAppliedAt() !== null };
    try {
      effective.model = getModelName();
      effective.modelStrong = getModelForTier("strong");
      effective.modelFast = getModelForTier("fast");
    } catch {
      // config not usable yet (e.g. no API key) — leave partial
    }
    return reply.send({
      source: "runtime",
      appliedAt: getAppliedAt(),
      effective,
      configFile: getConfigFilePath(),
    });
  });

  app.post("/", async (request, reply) => {
    const body = (request.body ?? {}) as Record<string, unknown>;

    // Support flat overrides and optional full AppSettings object
    const flatSource = typeof body.flat === "object" && body.flat !== null
      ? (body.flat as Record<string, unknown>)
      : body;
    const flat = sanitize(flatSource);

    try {
      applyRuntimeConfig(flat);
    } catch (err) {
      return reply.status(400).send({
        error: err instanceof Error ? err.message : String(err),
      });
    }

    return reply.send({
      ok: true,
      appliedAt: getAppliedAt(),
      source: "runtime",
    });
  });

  app.delete("/", async (_request, reply) => {
    clearRuntimeConfig();
    return reply.send({ ok: true, appliedAt: null });
  });

  app.post("/test", async (_request, reply) => {
    const started = Date.now();
    try {
      const model = getModelName();
      const result = await callLLM(
        'Ответь ровно одним словом "ok".',
        { timeoutMs: 30_000 },
      );
      return reply.send({
        ok: true,
        model,
        latencyMs: Date.now() - started,
        preview: result.text.trim().slice(0, 200),
      });
    } catch (err) {
      return reply.status(400).send({
        ok: false,
        latencyMs: Date.now() - started,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });
}
