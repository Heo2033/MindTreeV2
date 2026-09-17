import type { FastifyInstance } from "fastify";
import {
  applyRuntimeConfig,
  clearRuntimeConfig,
  getAppliedAt,
  getConfigFilePath,
  getRuntimeConfig,
  type RuntimeLLMConfig,
} from "../config/runtimeConfig.js";
import { getModelName, getModelForTier, getModelNameForConfig, callLLM } from "../llm/client.js";

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

/** Мержит пробный конфиг поверх текущего runtime-конфига (без персиста на диск). */
export function mergeProvisionConfig(
  runtime: RuntimeLLMConfig | null,
  provisional: RuntimeLLMConfig,
): RuntimeLLMConfig {
  return { ...(runtime ?? {}), ...provisional };
}

function hasApiKeyConfigured(): boolean {
  const runtimeKey = getRuntimeConfig()?.apiKey;
  if (runtimeKey !== undefined && runtimeKey.trim() !== "") return true;
  const envKey = process.env.LLM_API_KEY ?? process.env.OPENAI_API_KEY;
  return envKey !== undefined && envKey.trim() !== "";
}

function flatFromBody(body: unknown): Record<string, unknown> {
  if (typeof body !== "object" || body === null) return {};
  const b = body as Record<string, unknown>;
  return typeof b.flat === "object" && b.flat !== null
    ? (b.flat as Record<string, unknown>)
    : b;
}

export async function configRoutes(app: FastifyInstance) {
  app.get("/", async (_request, reply) => {
    const effective: Record<string, unknown> = {
      runtimeConfigured: getAppliedAt() !== null,
      apiKeyConfigured: hasApiKeyConfigured(),
    };
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
    const flat = sanitize(flatFromBody(body));

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

  app.post("/test", async (request, reply) => {
    const started = Date.now();
    const provisional = sanitize(flatFromBody(request.body));
    const testConfig =
      Object.keys(provisional).length > 0
        ? mergeProvisionConfig(getRuntimeConfig(), provisional)
        : undefined;
    let model: string | undefined;
    try {
      model = getModelNameForConfig(testConfig);
    } catch {
      model = undefined;
    }
    try {
      const result = await callLLM(
        'Ответь ровно одним словом "ok".',
        { timeoutMs: 30_000 },
        testConfig,
      );
      return reply.send({
        ok: true,
        ...(model ? { model } : {}),
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
