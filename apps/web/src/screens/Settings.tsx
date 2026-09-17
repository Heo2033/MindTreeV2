import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { configApi, type RuntimeConfigBody } from "../api";
import {
  loadMindTreeSettings,
  saveMindTreeSettings,
  storeKey,
  fetchKey,
  forgetKey,
  isTauriMode,
  type MindTreeSettings,
} from "@mindtree/tauri-common";
import { Button, Input, Select, Field, Badge, Spinner, ErrorBanner } from "@mindtree/ui";

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

type TestResult =
  | { ok: boolean; model?: string; latencyMs?: number; preview?: string; error?: string }
  | null;

const PROVIDER_OPTIONS = [
  { value: "auto", label: "Авто" },
  { value: "ollama", label: "Ollama" },
  { value: "openai", label: "OpenAI" },
];

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

export function SettingsScreen() {
  const [form, setForm] = useState<FormState>(emptyForm);
  const [serverAppliedAt, setServerAppliedAt] = useState<string | null>(null);
  const [apiKeyStored, setApiKeyStored] = useState(false);
  const [storedApiKey, setStoredApiKey] = useState<string | null>(null);
  const [persistedLocal, setPersistedLocal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [applying, setApplying] = useState(false);
  const [testing, setTesting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<TestResult>(null);

  const setField = useCallback(<K extends keyof FormState>(key: K, value: FormState[K]) => {
    setForm((f) => ({ ...f, [key]: value }));
  }, []);

  const loadLocal = useCallback(async (): Promise<MindTreeSettings | null> => {
    try {
      const s = await loadMindTreeSettings();
      const next = emptyForm();
      if (s.provider) {
        next.provider = s.provider;
      }
      next.baseUrl = s.baseUrl ?? "";
      next.model = s.model ?? "";
      next.modelStrong = s.modelStrong ?? "";
      next.modelFast = s.modelFast ?? "";
      next.temperature = s.temperature !== undefined ? String(s.temperature) : "";
      next.numCtx = s.numCtx !== undefined ? String(s.numCtx) : "";
      setForm(next);
      setPersistedLocal(Object.keys(s).length > 0);
      return s;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return null;
    }
  }, []);

  const saveLocal = useCallback(async () => {
    setSaving(true);
    setError(null);
    try {
      const s: MindTreeSettings = {
        provider: form.provider,
        ...(form.baseUrl.trim() ? { baseUrl: form.baseUrl.trim() } : {}),
        ...(form.model.trim() ? { model: form.model.trim() } : {}),
        ...(form.modelStrong.trim() ? { modelStrong: form.modelStrong.trim() } : {}),
        ...(form.modelFast.trim() ? { modelFast: form.modelFast.trim() } : {}),
        ...(form.temperature.trim() ? { temperature: num(form.temperature) } : {}),
        ...(form.numCtx.trim() ? { numCtx: num(form.numCtx) } : {}),
      };
      await saveMindTreeSettings(s);
      if (form.apiKey) {
        await storeKey(SECRET_KEY_ID, form.apiKey);
        setApiKeyStored(true);
        setForm((f) => ({ ...f, apiKey: "" }));
      }
      setPersistedLocal(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }, [form]);

  const applyToServer = useCallback(async () => {
    setApplying(true);
    setError(null);
    try {
      const body: RuntimeConfigBody = { ...toConfig(form), apiKey: form.apiKey || undefined };
      const res = await configApi.apply(body);
      setServerAppliedAt(res.appliedAt);
      if (form.apiKey) {
        await storeKey(SECRET_KEY_ID, form.apiKey);
        setApiKeyStored(true);
        setForm((f) => ({ ...f, apiKey: "" }));
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setApplying(false);
    }
  }, [form]);

  const clearServer = useCallback(async () => {
    setError(null);
    try {
      await configApi.clear();
      setServerAppliedAt(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  const testConnection = useCallback(async () => {
    setTesting(true);
    setError(null);
    try {
      const r = await configApi.test({
        ...toConfig(form),
        apiKey: form.apiKey || storedApiKey || undefined,
      });
      setTestResult(r);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setTestResult({ ok: false, error: msg });
    } finally {
      setTesting(false);
    }
  }, [form, storedApiKey]);

  const clearApiKey = useCallback(async () => {
    setError(null);
    try {
      await forgetKey(SECRET_KEY_ID);
      setApiKeyStored(false);
      setStoredApiKey(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  const fetchServerState = useCallback(async (): Promise<{
    appliedAt: string | null;
    apiKeyConfigured: boolean;
  } | null> => {
    try {
      const s = await configApi.get();
      setServerAppliedAt(s.appliedAt);
      return { appliedAt: s.appliedAt, apiKeyConfigured: s.effective.apiKeyConfigured };
    } catch {
      // сервер может быть недоступен — это не ошибка настроек
      return null;
    }
  }, []);

  useEffect(() => {
    void (async () => {
      setLoading(true);
      const local = await loadLocal();
      const stored = await fetchKey(SECRET_KEY_ID).catch(() => null);
      setApiKeyStored(!!stored);
      setStoredApiKey(stored);
      const serverState = await fetchServerState();
      // Ключ из хранилища не переживает рестарт сервера: если в памяти сервера его нет,
      // возвращаем его сами — иначе «Проверка подключения» падает с «LLM_API_KEY не задан».
      if (stored && serverState && !serverState.apiKeyConfigured && local?.provider !== "ollama") {
        try {
          const res = await configApi.apply({ apiKey: stored });
          setServerAppliedAt(res.appliedAt);
        } catch {
          // оставляем как есть; тест подключения всё равно переиспользует ключ из формы
        }
      }
      setLoading(false);
    })();
  }, [loadLocal, fetchServerState]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Spinner />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-8">
      <Link to="/" className="mb-4 inline-block text-sm font-semibold text-accent-ink hover:text-accent-hover">
        ← Назад
      </Link>
      <header className="mb-6">
        <h1 className="text-2xl font-bold">Настройки провайдера</h1>
        <p className="mt-1 text-sm text-ink-3">
          LLM-провайдер для генерации контента: Ollama (локально) или OpenAI-совместимый API.
        </p>
      </header>

      {!isTauriMode() && (
        <div className="mb-4 rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-warn">
          Браузерный режим: настройки и API-ключ хранятся в localStorage и видны только в этом браузере.
        </div>
      )}

      {error && <div className="mb-4"><ErrorBanner message={error} /></div>}

      <div className="space-y-6">
        <section className="rounded-xl border border-border bg-surface p-5">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-ink-2">Провайдер и модели</h2>
            <Badge variant={persistedLocal ? "success" : "muted"}>
              {persistedLocal ? "сохранено локально" : "не сохранено"}
            </Badge>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label="Провайдер" hint="Авто — определение по Base URL. Ollama — локальный, OpenAI — облачный.">
              <Select
                value={form.provider}
                options={PROVIDER_OPTIONS}
                onChange={(e) => setField("provider", e.target.value as FormState["provider"])}
              />
            </Field>
            <Field label="Base URL" hint="Например http://localhost:11434/v1 (Ollama) или https://api.openai.com/v1">
              <Input
                value={form.baseUrl}
                onChange={(e) => setField("baseUrl", e.target.value)}
                placeholder="http://localhost:11434/v1"
              />
            </Field>
            <Field label="Model (default)">
              <Input value={form.model} onChange={(e) => setField("model", e.target.value)} placeholder="qwen3.6-flash" />
            </Field>
            <Field label="Model (strong)" hint="Для структуры, валидации, диагностики, квизов.">
              <Input value={form.modelStrong} onChange={(e) => setField("modelStrong", e.target.value)} placeholder="gpt-5.4" />
            </Field>
            <Field label="Model (fast)" hint="Для лёгких/дешёвых запросов.">
              <Input value={form.modelFast} onChange={(e) => setField("modelFast", e.target.value)} placeholder="qwen3.6-flash" />
            </Field>
            <Field label="Temperature (0–2)">
              <Input
                type="number"
                step="0.1"
                min="0"
                max="2"
                value={form.temperature}
                onChange={(e) => setField("temperature", e.target.value)}
              />
            </Field>
            <Field label="num_ctx" hint="Контекстное окно в токенах.">
              <Input
                type="number"
                min="0"
                value={form.numCtx}
                onChange={(e) => setField("numCtx", e.target.value)}
                placeholder="4096"
              />
            </Field>
            <Field label="API-ключ" hint="Хранится в системном хранилище и памяти сервера, в файл не пишется.">
              {apiKeyStored ? (
                <div className="flex items-center gap-2">
                  <span className="flex-1 truncate text-sm text-ok">Ключ сохранён</span>
                  <Button variant="secondary" size="sm" onClick={() => void clearApiKey()}>
                    Удалить
                  </Button>
                </div>
              ) : (
                <Input
                  type="password"
                  value={form.apiKey}
                  onChange={(e) => setField("apiKey", e.target.value)}
                  placeholder="sk-… (ключ не попадает в файл настроек)"
                />
              )}
            </Field>
          </div>

          <div className="mt-5 flex flex-wrap gap-3">
            <Button disabled={saving} onClick={() => void saveLocal()}>
              {saving ? <Spinner size="sm" /> : "Сохранить локально"}
            </Button>
            <Button variant="secondary" disabled={applying} onClick={() => void applyToServer()}>
              {applying ? "Применяю…" : "Применить к серверу"}
            </Button>
            <Button variant="ghost" onClick={() => void clearServer()}>
              Очистить runtime-конфиг
            </Button>
          </div>

          <p className="mt-4 text-xs text-ink-4">
            {serverAppliedAt
              ? `Runtime-конфиг применён к серверу: ${new Date(serverAppliedAt).toLocaleString()}`
              : "Runtime-конфиг сервера не задан (используются значения из env)."}
          </p>
        </section>

        <section className="rounded-xl border border-border bg-surface p-5">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-ink-2">Проверка подключения</h2>
            <Button variant="secondary" size="sm" disabled={testing} onClick={() => void testConnection()}>
              {testing ? <Spinner size="sm" /> : "Проверить подключение"}
            </Button>
          </div>
          {testResult && (
            <div className="text-sm">
              {testResult.ok ? (
                <div className="rounded-lg border border-ok/30 bg-ok-soft p-3 text-ok">
                  Подключение успешно · модель <span className="font-semibold">{testResult.model}</span> · {testResult.latencyMs} мс
                  {testResult.preview ? (
                    <div className="mt-1 text-xs opacity-70">«{testResult.preview}»</div>
                  ) : null}
                </div>
              ) : (
                <div className="rounded-lg border border-danger/30 bg-danger-soft p-3 text-danger">
                  Ошибка: {testResult.error}
                </div>
              )}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}