import { useCallback, useEffect, useState } from "react";
import { Outlet, useParams, Link, useLocation } from "react-router-dom";
import { useGraphStore } from "../stores";
import { Spinner, Button, Select } from "@mindtree/ui";
import { topicsApi } from "../api";

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
  { to: "analytics", label: "Метрики" },
  { to: "final", label: "Итоговый тест" },
];

const GOAL_OPTIONS = [
  { value: "overview", label: "Обзор" },
  { value: "deep", label: "Глубокое изучение" },
  { value: "exam", label: "Подготовка к экзамену" },
];

const GOAL_LABELS: Record<string, string> = Object.fromEntries(
  GOAL_OPTIONS.map((o) => [o.value, o.label]),
);

function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

export function TopicShell() {
  const { topicId } = useParams<{ topicId: string }>();
  const { topicName, goal, nodes, loading, error, loadTopic, setGoal } = useGraphStore();
  const location = useLocation();
  const [goalEditorOpen, setGoalEditorOpen] = useState(false);
  const [goalDraft, setGoalDraft] = useState("overview");
  const [goalBusy, setGoalBusy] = useState(false);
  const [goalResult, setGoalResult] = useState<{
    message: string;
    count: number;
  } | null>(null);

  useEffect(() => {
    if (topicId) void loadTopic(topicId);
  }, [topicId, loadTopic]);

  useEffect(() => {
    if (goal) setGoalDraft(goal);
  }, [goal]);

  const segment = location.pathname.split("/").pop() ?? "graph";
  const activeTab = TABS.find((t) => t.to === segment)?.to ?? "graph";

  const handleChangeGoal = useCallback(async () => {
    if (!topicId || goalDraft === goal) {
      setGoalEditorOpen(false);
      return;
    }
    setGoalBusy(true);
    setGoalResult(null);
    try {
      const res = await topicsApi.changeGoal(topicId, goalDraft);
      setGoal(goalDraft);
      setGoalResult({
        message:
          res.alreadyKnown.length > 0
            ? `${res.alreadyKnown.length} узлов уже освоено — пропущено, ${res.plan.items.length} узлов в новом плане`
            : `План перестроен: ${res.plan.items.length} узлов`,
        count: res.plan.items.length,
      });
      setGoalEditorOpen(false);
    } catch (err) {
      setGoalResult({
        message: `Ошибка: ${err instanceof Error ? err.message : String(err)}`,
        count: -1,
      });
    } finally {
      setGoalBusy(false);
    }
  }, [topicId, goalDraft, goal, setGoal]);

  return (
    <div className={`flex flex-col bg-canvas text-ink ${isTauri() ? "h-full" : "h-screen"}`}>
      <header className="flex items-center gap-4 border-b border-border px-5 py-3">
        <Link to="/" className="text-sm font-semibold text-accent-ink hover:text-accent-hover">
          ← Темы
        </Link>
        <h1 className="truncate text-lg font-semibold">{topicName || "Тема"}</h1>

        <button
          onClick={() => {
            setGoalEditorOpen((v) => !v);
            setGoalResult(null);
          }}
          className="ml-2 flex items-center gap-1 rounded-full border border-border bg-surface-2 px-2.5 py-0.5 text-xs text-ink-3 transition-colors hover:border-accent/50 hover:text-ink"
          title="Сменить цель"
        >
          <span className="font-medium">{GOAL_LABELS[goal ?? ""] ?? goal ?? "…"}</span>
          <span className="text-ink-4">▾</span>
        </button>

        <span className="ml-auto rounded-full bg-surface-2 px-2.5 py-0.5 text-xs text-ink-4">
          {nodes.length} узлов
        </span>
      </header>

      {goalEditorOpen && (
        <div className="flex items-center gap-3 border-b border-border bg-surface px-5 py-3">
          <span className="text-sm text-ink-4">Новая цель:</span>
          <Select
            options={GOAL_OPTIONS}
            value={goalDraft}
            onChange={(e) => setGoalDraft(e.target.value)}
          />
          <Button
            size="sm"
            onClick={handleChangeGoal}
            disabled={goalBusy || goalDraft === goal}
          >
            {goalBusy ? "Перестроение…" : "Применить"}
          </Button>
          <button
            onClick={() => {
              setGoalEditorOpen(false);
              if (goal) setGoalDraft(goal);
            }}
            className="text-sm text-ink-4 hover:text-ink"
          >
            Отмена
          </button>
        </div>
      )}

      {goalResult && (
        <div
          className={`border-b border-border px-5 py-2 text-sm ${
            goalResult.count >= 0 ? "text-ink-3" : "text-danger"
          }`}
        >
          {goalResult.message}
        </div>
      )}

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
