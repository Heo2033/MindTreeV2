import { invoke } from "@tauri-apps/api/core";

const LOCAL_KEY = "mindtree.settings";

export function isTauriMode(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/**
 * Настроечный файл приложения (settings.json в app-data dir),
 * хранится как JSON-строка. Возвращает пустой объект, если файла нет.
 * В браузерном режиме (без Tauri) дублируется в localStorage.
 */
export async function loadSettings(): Promise<Record<string, unknown>> {
  const raw = isTauriMode()
    ? await invoke<string>("load_settings")
    : (typeof localStorage !== "undefined" ? localStorage.getItem(LOCAL_KEY) : null) ?? "{}";
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === "object") return parsed as Record<string, unknown>;
    return {};
  } catch {
    return {};
  }
}

export async function saveSettings(settings: Record<string, unknown>): Promise<void> {
  if (isTauriMode()) {
    await invoke("save_settings", { settings: JSON.stringify(settings) });
  } else if (typeof localStorage !== "undefined") {
    localStorage.setItem(LOCAL_KEY, JSON.stringify(settings));
  }
}