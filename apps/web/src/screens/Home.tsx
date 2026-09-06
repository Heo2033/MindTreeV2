import { useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useTopicStore } from "../stores";
import { Button, Spinner, ErrorBanner } from "@mindtree/ui";

export function HomeScreen() {
  const { topics, loading, error, loadTopics, removeTopic } = useTopicStore();
  const navigate = useNavigate();

  useEffect(() => {
    void loadTopics();
  }, [loadTopics]);

  const heightClass =
    typeof window !== "undefined" && "__TAURI_INTERNALS__" in window ? "min-h-full" : "min-h-screen";

  return (
    <div className={`bg-canvas text-ink ${heightClass}`}>
      <div className="mx-auto max-w-3xl px-6 py-10">
        <header className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold">MindTree</h1>
            <p className="mt-1 text-ink-4">Адаптивный движок обучения</p>
          </div>
          <div className="flex items-center gap-2">
            <Link
              to="/settings"
              className="rounded-lg border border-border bg-surface px-4 py-2 text-sm text-ink-2 transition-colors hover:border-accent hover:text-accent-ink"
            >
              Настройки провайдера
            </Link>
            <Button onClick={() => navigate("/new")}>+ Новая тема</Button>
          </div>
        </header>

        <div className="mt-8">
          <ErrorBanner message={error} />
          {loading && (
            <div className="flex justify-center py-16">
              <Spinner />
            </div>
          )}
          {!loading && topics.length === 0 && (
            <div className="rounded-xl border border-dashed border-border-strong p-10 text-center text-ink-4">
              Пока нет тем. Создайте первую, чтобы начать обучение.
            </div>
          )}
          <ul className="mt-4 space-y-3">
            {topics.map((topic) => (
              <li
                key={topic.id}
                className="group flex items-center justify-between rounded-xl border border-border bg-surface p-4 transition-colors hover:border-accent"
              >
                <Link to={`/topic/${topic.id}`} className="min-w-0 flex-1">
                  <div className="flex items-center gap-3">
                    <span className="truncate font-medium">{topic.name}</span>
                    <span className="shrink-0 rounded-full bg-surface-2 px-2 py-0.5 text-xs text-ink-4">
                      {topic.target_level}
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-ink-4">
                    Цель: {topic.goal} · {topic.time_budget_minutes} мин
                  </p>
                </Link>
                <button
                  onClick={() => {
                    if (confirm(`Удалить тему «${topic.name}»?`)) {
                      void removeTopic(topic.id);
                    }
                  }}
                  className="ml-3 shrink-0 rounded-md px-2 py-1 text-xs text-ink-4 opacity-0 transition-opacity hover:bg-surface-2 hover:text-danger group-hover:opacity-100"
                >
                  Удалить
                </button>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
