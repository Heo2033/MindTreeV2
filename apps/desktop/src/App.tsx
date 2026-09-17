import { useCallback, useEffect, useRef, useState } from "react";
import MindTreeApp, { setApiBase, setAuthToken } from "@mindtree/web";
import { Button } from "@mindtree/ui";

const DEFAULT_API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";

const RECONNECT_MIN_INTERVAL_MS = 15_000;

function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

type ServerStatus = "checking" | "online" | "offline";

const SERVER_STATUS_LABEL: Record<ServerStatus, string> = {
  checking: "…",
  online: "сервер онлайн",
  offline: "сервер недоступен",
};

type BootstrapStatus = "loading" | "ready" | "error";

function useApiBase(): {
  apiBase: string;
  status: BootstrapStatus;
  error: string | null;
  retry: () => void;
} {
  const [apiBase, setBase] = useState(DEFAULT_API_BASE);
  const [status, setStatus] = useState<BootstrapStatus>(isTauri() ? "loading" : "ready");
  const [error, setApiError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const lastRetryAt = useRef(0);

  const run = useCallback(async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const info = await invoke<{ port: number; token: string }>("get_server_info");
      const base = `http://127.0.0.1:${info.port}`;
      setApiBase(base);
      setAuthToken(info.token);
      setBase(base);
      setStatus("ready");
      setApiError(null);
    } catch (e) {
      setApiError(e instanceof Error ? e.message : String(e));
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    if (!isTauri()) return;
    void run();
  }, [run, tick]);

  // Сервер перезапускается на новом порту/токене после нештатной смерти
  // (watchdog в Rust шлёт server://status { running: false }). Повторное
  // обращение к get_server_info поднимает сервер заново и возвращает свежий
  // адрес — иначе все запросы фронтенда падают с "Failed to fetch".
  const retry = useCallback(() => {
    const now = Date.now();
    if (now - lastRetryAt.current < RECONNECT_MIN_INTERVAL_MS) return;
    lastRetryAt.current = now;
    setTick((t) => t + 1);
  }, []);

  useEffect(() => {
    if (!isTauri()) return;
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/event").then(async ({ listen }) => {
      unlisten = await listen<{ running: boolean }>("server://status", (e) => {
        if (!e.payload.running) retry();
      });
    });
    return () => {
      void unlisten?.();
    };
  }, [retry]);

  return { apiBase, status, error, retry };
}

function useServerStatus(
  apiBase: string,
  onRecover?: () => void,
  pollMs = 5000,
): { status: ServerStatus; checkedAt: string | null } {
  const [status, setStatus] = useState<ServerStatus>("checking");
  const [checkedAt, setCheckedAt] = useState<string | null>(null);
  const [, setOfflineStreak] = useState(0);
  const onRecoverRef = useRef(onRecover);
  onRecoverRef.current = onRecover;

  const check = useCallback(async () => {
    let ok = false;
    try {
      const res = await fetch(`${apiBase}/api/health`);
      const body = await res.json().catch(() => null);
      ok = res.ok && body?.status === "ok";
    } catch {
      ok = false;
    }
    setStatus(ok ? "online" : "offline");
    if (ok) {
      setOfflineStreak(0);
    } else {
      setOfflineStreak((s) => {
        if (s >= 3) return s;
        const next = s + 1;
        if (next >= 3) onRecoverRef.current?.();
        return next;
      });
    }
    setCheckedAt(new Date().toISOString());
  }, [apiBase]);

  useEffect(() => {
    setStatus("checking");
    setOfflineStreak(0);
    void check();
    const id = setInterval(() => void check(), pollMs);
    return () => clearInterval(id);
  }, [check, pollMs]);

  return { status, checkedAt };
}

function TitleBar({ status }: { status: ServerStatus }) {
  const [maximized, setMaximized] = useState(false);

  useEffect(() => {
    if (!isTauri()) return;
    let mounted = true;
    void import("@tauri-apps/api/window").then(async ({ getCurrentWindow }) => {
      const win = getCurrentWindow();
      const refresh = async () => {
        if (mounted) setMaximized(await win.isMaximized());
      };
      await refresh();
      win.onResized(() => void refresh());
      window.addEventListener("resize", () => void refresh());
    });
    return () => {
      mounted = false;
    };
  }, []);

  const winOp = () => import("@tauri-apps/api/window").then(({ getCurrentWindow }) => getCurrentWindow());

  const minimize = () => void winOp().then((w) => w.minimize());
  const toggleMax = () => void winOp().then((w) => w.toggleMaximize());
  const close = () => void winOp().then((w) => w.close());

  const dot = status === "online" ? "bg-ok" : status === "offline" ? "bg-danger" : "bg-ink-4";

  return (
    <div
      data-tauri-drag-region
      className="flex h-10 shrink-0 select-none items-center border-b border-border bg-surface pl-4 text-ink-2"
    >
      <span data-tauri-drag-region className="flex items-center gap-2 text-sm font-semibold text-ink">
        <span className="text-accent-ink">◆</span>
        MindTree
        <span className="text-[10px] font-normal uppercase tracking-wide text-ink-4">Desktop</span>
      </span>

      <div data-tauri-drag-region className="ml-3 flex items-center gap-1.5 rounded-full border border-border px-2 py-0.5">
        <span className={`h-1.5 w-1.5 rounded-full ${dot}`} />
        <span className="text-[11px] text-ink-3">{SERVER_STATUS_LABEL[status]}</span>
      </div>

      <div className="ml-auto flex h-full items-center">
        <TitleBarButton label="Свернуть" onClick={minimize}>
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M1 6h10" /></svg>
        </TitleBarButton>
        <TitleBarButton label={maximized ? "Восстановить" : "Развернуть"} onClick={toggleMax}>
          {maximized ? (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="3.5" y="3.5" width="6" height="6" rx="1" /><path d="M3 6.5v-3.5h3.5" /></svg>
          ) : (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="2" y="2" width="8" height="8" rx="1" /></svg>
          )}
        </TitleBarButton>
        <TitleBarButton label="Закрыть" onClick={close} danger>
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M2 2l8 8M10 2l-8 8" /></svg>
        </TitleBarButton>
      </div>
    </div>
  );
}

function TitleBarButton({
  label,
  onClick,
  danger,
  children,
}: {
  label: string;
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      title={label}
      aria-label={label}
      onClick={onClick}
      className={`flex h-full w-11 items-center justify-center transition-colors ${
        danger ? "hover:bg-danger hover:text-white" : "hover:bg-surface-3 hover:text-ink"
      }`}
    >
      {children}
    </button>
  );
}

function StartupError({ error, onRetry }: { error: string; onRetry: () => void }) {
  const openLogs = () => {
    if (!isTauri()) return;
    void import("@tauri-apps/api/core").then(({ invoke }) => {
      void invoke("open_app_data_dir");
    });
  };

  return (
    <div className="flex h-screen items-center justify-center bg-canvas px-6 text-ink">
      <div className="w-full max-w-md rounded-xl border border-danger/30 bg-danger-soft p-6 text-sm">
        <h2 className="mb-2 text-base font-semibold text-danger">Не удалось запустить встроенный сервер</h2>
        <p className="mb-4 text-ink-2">{error}</p>
        <p className="mb-4 text-xs text-ink-3">
          Подробности — в файле <code className="rounded bg-surface-3 px-1 py-0.5">server.log</code> в папке данных приложения.
        </p>
        <div className="flex flex-wrap gap-3">
          <Button onClick={onRetry}>Повторить</Button>
          <Button variant="secondary" onClick={openLogs}>
            Открыть папку с логами
          </Button>
        </div>
      </div>
    </div>
  );
}

function LoadingScreen() {
  return (
    <div className="flex h-screen items-center justify-center bg-canvas text-ink">
      <span className="text-sm text-ink-4">Запуск встроенного сервера…</span>
    </div>
  );
}

export default function App() {
  const { apiBase, status, error, retry } = useApiBase();
  const { status: serverStatus } = useServerStatus(apiBase, retry);

  if (status === "error") {
    return <StartupError error={error ?? "Неизвестная ошибка"} onRetry={retry} />;
  }

  if (status === "loading") {
    return <LoadingScreen />;
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-canvas text-ink">
      <TitleBar status={serverStatus} />
      <div className="min-h-0 flex-1 overflow-auto">
        <MindTreeApp />
      </div>
    </div>
  );
}