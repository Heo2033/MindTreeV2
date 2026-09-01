import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

export interface RuntimeLLMConfig {
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  modelStrong?: string;
  modelFast?: string;
  temperature?: number;
  numCtx?: number;
  provider?: "ollama" | "openai" | "auto";
}

interface RuntimeOverride {
  config: RuntimeLLMConfig;
  appliedAt: string;
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function getConfigFilePath(): string {
  return (
    process.env.MINDTREE_SERVER_CONFIG ||
    path.resolve(__dirname, "../../data/runtime-config.json")
  );
}

let override: RuntimeOverride | null = null;

function readFromFile(): RuntimeOverride | null {
  const file = getConfigFilePath();
  try {
    if (!fs.existsSync(file)) return null;
    const raw = JSON.parse(fs.readFileSync(file, "utf8")) as Partial<RuntimeOverride>;
    if (!raw || typeof raw !== "object" || !raw.config) return null;
    return {
      config: raw.config as RuntimeLLMConfig,
      appliedAt:
        typeof raw.appliedAt === "string"
          ? raw.appliedAt
          : new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

function persist(overrideToSave: RuntimeOverride | null): void {
  const file = getConfigFilePath();
  const dir = path.dirname(file);
  if (overrideToSave === null) {
    try {
      if (fs.existsSync(file)) fs.unlinkSync(file);
    } catch {
      // ignore fs errors on clear
    }
    return;
  }
  // API-ключ не пишем на диск: он берётся из env при чтении конфига.
  const { apiKey: _omitApiKey, ...configToSave } = overrideToSave.config;
  void _omitApiKey;
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      file,
      JSON.stringify({ config: configToSave, appliedAt: overrideToSave.appliedAt }, null, 2),
      "utf8",
    );
  } catch {
    // ignore fs errors on persist — runtime config still applies in-memory
  }
}

/** Загружает конфиг из файла при старте сервера. Вызывается до обработки запросов. */
export function initRuntimeConfigFromFile(): void {
  const saved = readFromFile();
  if (saved) {
    override = saved;
    console.log(`[config] загружен runtime-конфиг из ${getConfigFilePath()}`);
  }
}

export function applyRuntimeConfig(config: RuntimeLLMConfig): void {
  override = { config, appliedAt: new Date().toISOString() };
  persist(override);
}

export function clearRuntimeConfig(): void {
  override = null;
  persist(null);
}

export function getRuntimeConfig(): RuntimeLLMConfig | null {
  return override?.config ?? null;
}

export function getAppliedAt(): string | null {
  return override?.appliedAt ?? null;
}
