import { loadSettings, saveSettings } from "./settings";

// Единая схема локальных настроек MindTree. Все потребители (веб-настройки
// и Studio) читают и пишут один и тот же namespace `mindtree`, чтобы файл
// settings.json был взаимно-совместимым. Устаревшее плоское хранение (Studio
// до миграции писало ключи в корень) поддерживается при чтении как fallback.
export const SETTINGS_NAMESPACE = "mindtree";

export type MindTreeProvider = "ollama" | "openai" | "auto";

export interface MindTreeSettings {
  provider?: MindTreeProvider;
  baseUrl?: string;
  model?: string;
  modelStrong?: string;
  modelFast?: string;
  temperature?: number;
  numCtx?: number;
}

const STRING_KEYS = ["baseUrl", "model", "modelStrong", "modelFast"] as const;
const NUMBER_KEYS = ["temperature", "numCtx"] as const;

export async function loadMindTreeSettings(): Promise<MindTreeSettings> {
  const raw = (await loadSettings()) as Record<string, unknown>;
  const ns = raw[SETTINGS_NAMESPACE];
  // Если namespace ещё нет — читаем legacy-плоское хранение (Studio).
  const src: Record<string, unknown> =
    ns && typeof ns === "object" && ns !== null ? (ns as Record<string, unknown>) : raw;

  const out: MindTreeSettings = {};
  const provider = src.provider;
  if (provider === "ollama" || provider === "openai" || provider === "auto") {
    out.provider = provider;
  }
  for (const k of STRING_KEYS) {
    const v = src[k];
    if (typeof v === "string" && v.trim() !== "") out[k] = v.trim();
  }
  for (const k of NUMBER_KEYS) {
    const v = src[k];
    const n = typeof v === "number" ? v : Number(v);
    if (Number.isFinite(n)) out[k] = n;
  }
  return out;
}

export async function saveMindTreeSettings(settings: MindTreeSettings): Promise<void> {
  const raw = (await loadSettings()) as Record<string, unknown>;
  raw[SETTINGS_NAMESPACE] = { ...settings };
  await saveSettings(raw);
}