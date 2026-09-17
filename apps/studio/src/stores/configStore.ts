import { create } from "zustand";
import {
  loadMindTreeSettings,
  saveMindTreeSettings,
  storeKey,
  fetchKey,
  forgetKey,
  type MindTreeSettings,
} from "@mindtree/tauri-common";
import {
  adminApi,
  configApi,
  type RuntimeConfigBody,
  type ServerConfigState,
  type TestResult,
  type AdminStatus,
  type AdminLogs,
} from "../api";

const SECRET_KEY_ID = "default";

interface FormState {
  provider: "ollama" | "openai" | "auto";
  baseUrl: string;
  apiKey: string;
  model: string;
  modelStrong: string;
  modelFast: string;
  temperature: string;
  numCtx: string;
}

interface StudioConfigState extends FormState {
  apiKeyStored: boolean;
  persistedLocal: boolean;
  server: ServerConfigState | null;
  savingLocal: boolean;
  applying: boolean;
  testing: boolean;
  loadError: string | null;
  serverError: string | null;
  testResult: TestResult | null;
  adminStatus: AdminStatus | null;
  adminLogs: AdminLogs | null;
  adminLoading: boolean;
  adminError: string | null;
  setField: <K extends keyof FormState>(key: K, value: FormState[K]) => void;
  setApiKeyStored: (v: boolean) => void;
  clearApiKey: () => Promise<void>;
  loadLocal: () => Promise<void>;
  saveLocal: () => Promise<void>;
  applyToServer: () => Promise<void>;
  fetchServerState: () => Promise<void>;
  clearServer: () => Promise<void>;
  testConnection: () => Promise<void>;
  fetchAdmin: () => Promise<void>;
}

const emptyForm = (): FormState => ({
  provider: "auto",
  baseUrl: "",
  apiKey: "",
  model: "",
  modelStrong: "",
  modelFast: "",
  temperature: "",
  numCtx: "",
});

function num(raw: string): number | undefined {
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
}

function toConfig(f: FormState): RuntimeConfigBody {
  const out: RuntimeConfigBody = { provider: f.provider };
  if (f.baseUrl.trim()) out.baseUrl = f.baseUrl.trim();
  if (f.model.trim()) out.model = f.model.trim();
  if (f.modelStrong.trim()) out.modelStrong = f.modelStrong.trim();
  if (f.modelFast.trim()) out.modelFast = f.modelFast.trim();
  const temperature = num(f.temperature);
  if (temperature !== undefined) out.temperature = temperature;
  const numCtx = num(f.numCtx);
  if (numCtx !== undefined) out.numCtx = numCtx;
  return out;
}

export const useConfigStore = create<StudioConfigState>((set, get) => ({
  ...emptyForm(),
  apiKeyStored: false,
  persistedLocal: false,
  server: null,
  savingLocal: false,
  applying: false,
  testing: false,
  loadError: null,
  serverError: null,
  testResult: null,
  adminStatus: null,
  adminLogs: null,
  adminLoading: false,
  adminError: null,

  setField(key, value) {
    set({ [key]: value } as Pick<StudioConfigState, keyof FormState>);
  },

  setApiKeyStored(v) {
    set({ apiKeyStored: v });
  },

  async clearApiKey() {
    try {
      await forgetKey(SECRET_KEY_ID);
      set({ apiKeyStored: false, apiKey: "" });
    } catch (err) {
      set({ loadError: err instanceof Error ? err.message : "Ошибка удаления ключа" });
    }
  },

  async loadLocal() {
    set({ loadError: null });
    try {
      const [settings, storedKey] = await Promise.all([loadMindTreeSettings(), fetchKey(SECRET_KEY_ID)]);
      set({
        provider: settings.provider || "auto",
        baseUrl: settings.baseUrl ?? "",
        model: settings.model ?? "",
        modelStrong: settings.modelStrong ?? "",
        modelFast: settings.modelFast ?? "",
        temperature: settings.temperature !== undefined ? String(settings.temperature) : "",
        numCtx: settings.numCtx !== undefined ? String(settings.numCtx) : "",
        apiKeyStored: Boolean(storedKey),
        persistedLocal: Object.keys(settings).length > 0,
        apiKey: "",
      });
    } catch (err) {
      set({ loadError: err instanceof Error ? err.message : "Ошибка загрузки настроек" });
    }
  },

  async saveLocal() {
    set({ savingLocal: true, loadError: null });
    try {
      const s = get();
      const settings: MindTreeSettings = {
        provider: s.provider,
        ...(s.baseUrl.trim() ? { baseUrl: s.baseUrl.trim() } : {}),
        ...(s.model.trim() ? { model: s.model.trim() } : {}),
        ...(s.modelStrong.trim() ? { modelStrong: s.modelStrong.trim() } : {}),
        ...(s.modelFast.trim() ? { modelFast: s.modelFast.trim() } : {}),
        ...(s.temperature.trim() ? { temperature: num(s.temperature) } : {}),
        ...(s.numCtx.trim() ? { numCtx: num(s.numCtx) } : {}),
      };
      await saveMindTreeSettings(settings);
      if (s.apiKey.trim()) {
        await storeKey(SECRET_KEY_ID, s.apiKey.trim());
        set({ apiKeyStored: true, apiKey: "" });
      }
      set({ persistedLocal: true, savingLocal: false });
    } catch (err) {
      set({ loadError: err instanceof Error ? err.message : "Ошибка сохранения", savingLocal: false });
    }
  },

  async applyToServer() {
    set({ applying: true, serverError: null });
    try {
      const cfg = toConfig(get());
      if (get().apiKey.trim()) cfg.apiKey = get().apiKey.trim();
      await configApi.apply(cfg);
      set({ apiKey: "", applying: false });
      await get().fetchServerState();
    } catch (err) {
      set({ serverError: err instanceof Error ? err.message : "Ошибка применения к серверу", applying: false });
    }
  },

  async fetchServerState() {
    try {
      const server = await configApi.get();
      set({ server });
    } catch (err) {
      set({ serverError: err instanceof Error ? err.message : "Ошибка запроса состояния сервера" });
    }
  },

  async clearServer() {
    try {
      await configApi.clear();
      set({ serverError: null });
      await get().fetchServerState();
    } catch (err) {
      set({ serverError: err instanceof Error ? err.message : "Ошибка очистки" });
    }
  },

  async testConnection() {
    set({ testing: true, serverError: null, testResult: null });
    try {
      const result = await configApi.test();
      set({ testResult: result, testing: false });
    } catch (err) {
      set({ testResult: { ok: false, error: err instanceof Error ? err.message : "Ошибка" }, testing: false });
    }
  },

  async fetchAdmin() {
    set({ adminLoading: true, adminError: null });
    try {
      const [adminStatus, adminLogs] = await Promise.all([adminApi.status(), adminApi.logs()]);
      set({ adminStatus, adminLogs, adminLoading: false });
    } catch (err) {
      set({ adminError: err instanceof Error ? err.message : "Ошибка запроса данных сервера", adminLoading: false });
    }
  },
}));
