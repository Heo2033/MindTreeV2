import { useCallback, useEffect, useState } from "react";
import MindTreeApp from "@mindtree/web";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";

function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

type ServerStatus = "checking" | "online" | "offline";

const SERVER_STATUS_LABEL: Record<ServerStatus, string> = {
  checking: "…",
  online: "сервер онлайн",
  offline: "сервер недоступен",
};

function useServerStatus(pollMs = 5000): { status: ServerStatus; checkedAt: string | null } {
  const [status, setStatus] = useState<ServerStatus>("checking");
  const [checkedAt, setCheckedAt] = useState<string | null>(null);

  const check = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/api/health`);
      const body = await res.json().catch(() => null);
      setStatus(res.ok && body?.status === "ok" ? "online" : "offline");
    } catch {
      setStatus("offline");
    }
    setCheckedAt(new Date().toISOString());
  }, []);

  useEffect(() => {
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

export default function App() {
  const { status } = useServerStatus();

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-canvas text-ink">
      <TitleBar status={status} />
      <div className="min-h-0 flex-1 overflow-auto">
        <MindTreeApp />
      </div>
    </div>
  );
}
