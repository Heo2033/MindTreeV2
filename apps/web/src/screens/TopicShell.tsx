import { useEffect } from "react";
import { Outlet, useParams, Link, useLocation } from "react-router-dom";
import { useGraphStore } from "../stores";
import { Spinner } from "@mindtree/ui";

const TABS = [
  { to: "graph", label: "Граф" },
  { to: "focus", label: "Фокус" },
  { to: "session", label: "Сессия" },
  { to: "quiz", label: "Тест" },
  { to: "tutor", label: "Репетитор" },
  { to: "learner", label: "Модель" },
  { to: "diagnostic", label: "Диагностика" },
  { to: "milestones", label: "Путь" },
  { to: "review", label: "Повторение" },
];

function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

export function TopicShell() {
  const { topicId } = useParams<{ topicId: string }>();
  const { topicName, nodes, loading, error, loadTopic } = useGraphStore();
  const location = useLocation();

  useEffect(() => {
    if (topicId) void loadTopic(topicId);
  }, [topicId, loadTopic]);

  const segment = location.pathname.split("/").pop() ?? "graph";
  const activeTab = TABS.find((t) => t.to === segment)?.to ?? "graph";

  return (
    <div className={`flex flex-col bg-canvas text-ink ${isTauri() ? "h-full" : "h-screen"}`}>
      <header className="flex items-center gap-4 border-b border-border px-5 py-3">
        <Link to="/" className="text-sm font-semibold text-accent-ink hover:text-accent-hover">
          ← Темы
        </Link>
        <h1 className="truncate text-lg font-semibold">{topicName || "Тема"}</h1>
        <span className="ml-auto rounded-full bg-surface-2 px-2.5 py-0.5 text-xs text-ink-4">
          {nodes.length} узлов
        </span>
      </header>

      <nav className="flex gap-1 overflow-x-auto border-b border-border px-3 py-2">
        {TABS.map((tab) => (
          <Link
            key={tab.to}
            to={tab.to}
            className={`rounded-md px-3 py-1.5 text-sm transition-colors ${
              activeTab === tab.to
                ? "bg-accent text-ink"
                : "text-ink-4 hover:bg-surface-2 hover:text-ink-2"
            }`}
          >
            {tab.label}
          </Link>
        ))}
      </nav>

      <main className="relative min-h-0 flex-1">
        {loading && (
          <div className="flex h-full items-center justify-center">
            <Spinner />
          </div>
        )}
        {!loading && error && (
          <div className="flex h-full items-center justify-center p-8 text-danger">
            {error}
          </div>
        )}
        {!loading && !error && <Outlet />}
      </main>
    </div>
  );
}
