import { useEffect, useMemo, useState } from "react";
import { useConfigStore } from "./stores/configStore";
import { apiBase } from "./api";
import { isTauriMode } from "@mindtree/tauri-common";
import { Button, Input, Select, Field, Badge, Spinner, ErrorBanner } from "@mindtree/ui";

type Tab = "config" | "status" | "logs";

const PROVIDER_OPTIONS = [
  { value: "auto", label: "Авто" },
  { value: "ollama", label: "Ollama" },
  { value: "openai", label: "OpenAI" },
];

const TAB_OPTIONS: Array<{ value: Tab; label: string }> = [
  { value: "config", label: "Конфигурация" },
  { value: "status", label: "Состояние сервера" },
  { value: "logs", label: "Логи" },
];

function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s} с`;
  const m = Math.floor(s / 60);
  const rem = s % 60;
  if (m < 60) return `${m} мин ${rem} с`;
  const h = Math.floor(m / 60);
  return `${h} ч ${m % 60} мин`;
}

function fmtCost(cost: number): string {
  if (cost < 0.001) return "$0.00";
  return `$${cost.toFixed(3)}`;
}

export default function App() {
  const {
    provider, baseUrl, apiKey, model, modelStrong, modelFast, temperature, numCtx,
    apiKeyStored, persistedLocal, server, savingLocal, applying, testing,
    loadError, serverError, testResult,
    adminStatus, adminLogs, adminLoading, adminError,
    setField, loadLocal, saveLocal, applyToServer, fetchServerState, clearServer, testConnection, clearApiKey, fetchAdmin,
  } = useConfigStore();
  const [tab, setTab] = useState<Tab>("config");

  useEffect(() => {
    void loadLocal();
    void fetchServerState();
  }, []);

  useEffect(() => {
    if (tab === "status" || tab === "logs") void fetchAdmin();
  }, [tab]);

  const effective = useMemo(() => adminStatus?.config.effective ?? server?.effective, [adminStatus, server]);
  const uptime = useMemo(
    () => (adminStatus ? fmtDuration(adminStatus.uptimeMs) : null),
    [adminStatus],
  );

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <div className="mx-auto max-w-3xl px-6 py-8">
        <header className="mb-6">
          <h1 className="text-2xl font-bold">MindTree Studio</h1>
          <p className="mt-1 text-sm text-ink-3">Управление LLM-провайдером и мониторинг сервера</p>
        </header>

        {!isTauriMode() && (
          <div className="mb-4 rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-warn">
            Браузерный режим: локальные настройки и API-ключ хранятся в localStorage и видны только в этом браузере.
            Для системного хранилища и файла настроек запустите десктопную версию:{" "}
            <code className="font-mono text-xs">npm run tauri dev</code> в <code className="font-mono text-xs">apps/studio</code>.
          </div>
        )}

        {loadError && <div className="mb-4"><ErrorBanner message={loadError} /></div>}

        <div className="mb-6 flex gap-2 border-b border-border">
          {TAB_OPTIONS.map((t) => (
            <button
              key={t.value}
              onClick={() => setTab(t.value)}
              className={
                "-mb-px border-b-2 px-4 py-2 text-sm font-medium transition-colors " +
                (tab === t.value
                  ? "border-accent text-accent-ink"
                  : "border-transparent text-ink-3 hover:text-ink")
              }
            >
              {t.label}
            </button>
          ))}
        </div>

        {tab === "config" && (
          <div className="space-y-6">
            <section className="rounded-xl border border-border bg-surface p-5">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-sm font-semibold text-ink-2">Провайдер и модели</h2>
                <Badge variant={persistedLocal ? "success" : "muted"}>
                  {persistedLocal ? "сохранено локально" : "не сохранено"}
                </Badge>
              </div>

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Field label="Провайдер" hint="Авто — определение по Base URL. Ollama — локальный сервер, OpenAI — облачный.">
                  <Select
                    value={provider}
                    options={PROVIDER_OPTIONS}
                    onChange={(e) => setField("provider", e.target.value as never)}
                  />
                </Field>
                <Field label="Base URL" hint="Адрес API. Например http://localhost:11434/v1 (Ollama) или https://api.openai.com/v1">
                  <Input
                    value={baseUrl}
                    onChange={(e) => setField("baseUrl", e.target.value)}
                    placeholder="http://localhost:11434/v1"
                  />
                </Field>
                <Field label="Model (default)" hint="Основная модель для простых операций (по умолчанию).">
                  <Input value={model} onChange={(e) => setField("model", e.target.value)} placeholder="qwen3.6-flash" />
                </Field>
                <Field label="Model (strong)" hint="Мощная модель для структуры, валидации, диагностики, квизов.">
                  <Input value={modelStrong} onChange={(e) => setField("modelStrong", e.target.value)} placeholder="gpt-5.4" />
                </Field>
                <Field label="Model (fast)" hint="Быстрая модель для лёгких операций (дешёвых запросов).">
                  <Input value={modelFast} onChange={(e) => setField("modelFast", e.target.value)} placeholder="qwen3.6-flash" />
                </Field>
                <Field label="Temperature (0–2)" hint="Креативность ответов. 0 — детерминированно, выше — разнообразнее.">
                  <Input
                    type="number"
                    step="0.1"
                    min="0"
                    max="2"
                    value={temperature}
                    onChange={(e) => setField("temperature", e.target.value)}
                  />
                </Field>
                <Field label="num_ctx" hint="Контекстное окно в токенах (сколько текста модель учитывает).">
                  <Input
                    type="number"
                    min="0"
                    value={numCtx}
                    onChange={(e) => setField("numCtx", e.target.value)}
                    placeholder="4096"
                  />
                </Field>
                <Field label="API-ключ" hint="Ключ хранится в системном хранилище и в памяти сервера, в файл не пишется.">
                  {apiKeyStored ? (
                    <div className="flex items-center gap-2">
                      <span className="flex-1 truncate text-sm text-ok">🔒 Ключ сохранён в системном хранилище</span>
                      <Button variant="secondary" size="sm" onClick={() => void clearApiKey()}>
                        Удалить
                      </Button>
                    </div>
                  ) : (
                    <Input
                      type="password"
                      value={apiKey}
                      onChange={(e) => setField("apiKey", e.target.value)}
                      placeholder="sk-… (не пишется в файл настроек)"
                    />
                  )}
                </Field>
              </div>

              <div className="mt-5 flex flex-wrap gap-3">
                <Button disabled={savingLocal} onClick={() => void saveLocal()}>
                  {savingLocal ? <Spinner size="sm" /> : "Сохранить локально"}
                </Button>
                <Button variant="secondary" disabled={applying} onClick={() => void applyToServer()}>
                  {applying ? "Применяю…" : "Применить к серверу"}
                </Button>
                <Button variant="ghost" onClick={() => void clearServer()}>
                  Очистить runtime-конфиг сервера
                </Button>
              </div>

              <p className="mt-4 text-xs text-ink-4">
                API-ключ хранится только в системном хранилище ключей и в памяти сервера (при рестарте сервер берёт его из
                env). В файл настроек ключ не попадает.
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
                      ✓ Подключение успешно · модель <span className="font-semibold">{testResult.model}</span> · {testResult.latencyMs} мс
                      {testResult.preview ? <div className="mt-1 text-xs opacity-70">«{testResult.preview}»</div> : null}
                    </div>
                  ) : (
                    <div className="rounded-lg border border-danger/30 bg-danger-soft p-3 text-danger">
                      ✗ Ошибка: {testResult.error}
                    </div>
                  )}
                </div>
              )}
            </section>
          </div>
        )}

        {tab === "status" && (
          <section className="rounded-xl border border-border bg-surface p-5">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-ink-2">Состояние сервера</h2>
              <Button variant="secondary" size="sm" disabled={adminLoading} onClick={() => void fetchAdmin()}>
                {adminLoading ? <Spinner size="sm" /> : "Обновить"}
              </Button>
            </div>

            {adminError && <div className="mb-3"><ErrorBanner message={`${adminError} (${apiBase()})`} /></div>}

            {!adminStatus ? (
              <p className="text-sm text-ink-4">
                {adminLoading ? "Загрузка…" : "Не удалось получить состояние — сервер недоступен."}
              </p>
            ) : (
              <div className="space-y-5 text-sm">
                <div className="rounded-lg border border-border bg-surface-2 p-4">
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">Сервер</h3>
                  <dl className="space-y-2">
                    <div className="flex justify-between"><dt className="text-ink-3">Сервер</dt><dd className="font-mono text-xs text-ink-2">{apiBase()}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Запущен</dt><dd className="text-ink-2">{new Date(adminStatus.startedAt).toLocaleString()}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Аптайм</dt><dd className="text-ink-2">{uptime}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Темы</dt><dd className="text-ink-2">{adminStatus.topics.count}</dd></div>
                    <div className="flex justify-between">
                      <dt className="text-ink-3">API-ключ</dt>
                      <dd className={adminStatus.config.apiKeySet ? "text-ok" : "text-danger"}>
                        {adminStatus.config.apiKeySet ? "задан" : "не задан"}
                      </dd>
                    </div>
                  </dl>
                </div>

                <div className="rounded-lg border border-border bg-surface-2 p-4">
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">Конфигурация</h3>
                  <dl className="space-y-2">
                    <div className="flex justify-between"><dt className="text-ink-3">Источник</dt><dd className="text-ink-2">{adminStatus.config.source === "runtime" ? "runtime-конфиг" : "env"}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Применён</dt><dd className="text-ink-2">{adminStatus.config.appliedAt ? new Date(adminStatus.config.appliedAt).toLocaleString() : "—"}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Base URL</dt><dd className="text-ink-2">{adminStatus.config.configuredBaseUrl ? "задан" : "не задан"}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Model</dt><dd className="font-mono text-xs text-ink-2">{effective?.model ?? "—"}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Model strong</dt><dd className="font-mono text-xs text-ink-2">{effective?.modelStrong ?? "—"}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Model fast</dt><dd className="font-mono text-xs text-ink-2">{effective?.modelFast ?? "—"}</dd></div>
                  </dl>
                </div>

                <div className="rounded-lg border border-border bg-surface-2 p-4">
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">LLM-телеметрия</h3>
                  <dl className="space-y-2">
                    <div className="flex justify-between"><dt className="text-ink-3">Запросов</dt><dd className="text-ink-2">{adminStatus.llm.stats.count}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Стоимость</dt><dd className="text-ink-2">{fmtCost(adminStatus.llm.stats.totalCost)}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Входных токенов</dt><dd className="text-ink-2">{adminStatus.llm.stats.totalInput.toLocaleString()}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Выходных токенов</dt><dd className="text-ink-2">{adminStatus.llm.stats.totalOutput.toLocaleString()}</dd></div>
                  </dl>
                </div>

                <div className="rounded-lg border border-border bg-surface-2 p-4">
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">Кэш LLM</h3>
                  <dl className="space-y-2">
                    <div className="flex justify-between"><dt className="text-ink-3">Попаданий</dt><dd className="text-ink-2">{String(adminStatus.cache.hits ?? 0)}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Промахов</dt><dd className="text-ink-2">{String(adminStatus.cache.misses ?? 0)}</dd></div>
                    <div className="flex justify-between"><dt className="text-ink-3">Записей</dt><dd className="text-ink-2">{String(adminStatus.cache.size ?? 0)}</dd></div>
                  </dl>
                </div>

                <div className="rounded-lg border border-border bg-surface-2 p-4">
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">Последние операции</h3>
                  {adminStatus.llm.recent.length === 0 ? (
                    <p className="text-sm text-ink-4">Операций пока нет.</p>
                  ) : (
                    <ul className="divide-y divide-border">
                      {adminStatus.llm.recent.slice(0, 10).map((op, i) => (
                        <li key={i} className="flex items-center justify-between gap-3 py-2 text-xs">
                          <div>
                            <div className="text-ink-2">{String(op.operation)}</div>
                            <div className="text-ink-4">{new Date(String(op.ts)).toLocaleTimeString()} · {String(op.model)}</div>
                          </div>
                          <div className="text-right text-ink-3">
                            <div>{Number(op.input_tokens)}→{Number(op.output_tokens)} ток.</div>
                            <div>{Math.round(Number(op.latency_ms))} мс</div>
                          </div>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            )}
          </section>
        )}

        {tab === "logs" && (
          <section className="rounded-xl border border-border bg-surface p-5">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-ink-2">Логи сервера</h2>
              <Button variant="secondary" size="sm" disabled={adminLoading} onClick={() => void fetchAdmin()}>
                {adminLoading ? <Spinner size="sm" /> : "Обновить"}
              </Button>
            </div>

            {adminError && <div className="mb-3"><ErrorBanner message={`${adminError} (${apiBase()})`} /></div>}

            {!adminLogs ? (
              <p className="text-sm text-ink-4">
                {adminLoading ? "Загрузка…" : "Не удалось получить логи — сервер недоступен."}
              </p>
            ) : (
              <div className="space-y-4">
                <div>
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">События приложения</h3>
                  {adminLogs.logs.length === 0 ? (
                    <p className="text-sm text-ink-4">Событий нет.</p>
                  ) : (
                    <div className="max-h-80 overflow-auto rounded-lg border border-border bg-surface-2 p-3 font-mono text-xs">
                      {adminLogs.logs.map((log, i) => (
                        <div key={i} className="flex gap-2 border-b border-border py-1 last:border-0">
                          <span className="text-ink-4">{new Date(log.ts).toLocaleTimeString()}</span>
                          <span className={log.level === "error" ? "text-danger" : log.level === "warn" ? "text-warn" : "text-ink-2"}>
                            {log.level.toUpperCase()}
                          </span>
                          <span className="text-ink-2">{log.message}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                <div>
                  <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-4">Последние LLM-операции</h3>
                  {adminLogs.llm.length === 0 ? (
                    <p className="text-sm text-ink-4">Операций нет.</p>
                  ) : (
                    <div className="max-h-80 overflow-auto rounded-lg border border-border bg-surface-2 p-3 font-mono text-xs">
                      {adminLogs.llm.map((op, i) => (
                        <div key={i} className="flex gap-3 border-b border-border py-1 last:border-0">
                          <span className="text-ink-4">{new Date(String(op.ts)).toLocaleTimeString()}</span>
                          <span className="text-ink-2">{String(op.operation)}</span>
                          <span className="text-ink-4">{String(op.model)}</span>
                          <span className="text-ink-3">{Number(op.input_tokens)}→{Number(op.output_tokens)}</span>
                          <span className="text-ink-3">{Math.round(Number(op.latency_ms))} мс</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}
          </section>
        )}
      </div>
    </div>
  );
}
