import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useTopicStore, useGraphStore } from "../stores";
import { Button, Input, Select, Textarea, ProgressBar, ErrorBanner, Spinner } from "@mindtree/ui";
import type { TreeGenProgress } from "../api";

const PHASE_LABELS: Record<string, string> = {
  structure: "Структурирование",
  expand: "Построение дерева",
  validate: "Проверка",
  repair: "Исправление",
  content: "Контент",
  done: "Готово",
};

export function NewTopicScreen() {
  const navigate = useNavigate();
  const createTopic = useTopicStore((s) => s.createTopic);
  const generateTree = useGraphStore((s) => s.generateTree);
  const pipeline = useGraphStore((s) => s.pipeline);

  const heightClass =
    typeof window !== "undefined" && "__TAURI_INTERNALS__" in window ? "min-h-full" : "min-h-screen";

  const [name, setName] = useState("");
  const [goal, setGoal] = useState("overview");
  const [level, setLevel] = useState("solid_understanding");
  const [timeBudget, setTimeBudget] = useState("60");
  const [query, setQuery] = useState("");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [phase, setPhase] = useState<TreeGenProgress | null>(null);
  const [running, setRunning] = useState(false);

  const canStart = name.trim() !== "" && query.trim() !== "" && !running;

  async function handleStart() {
    setError(null);
    setRunning(true);
    try {
      const topic = await createTopic({
        name: name.trim(),
        goal,
        target_level: level,
        time_budget_minutes: Number(timeBudget) || 60,
      });
      // bind graph store to new topic
      useGraphStore.setState({ topicId: topic.id, topicName: topic.name });

      const fullQuery = [query.trim(), notes.trim()].filter(Boolean).join("\n\n---\n\n");
      const ok = await generateTree(fullQuery, goal, level);
      if (ok) {
        navigate(`/topic/${topic.id}/graph`);
      } else {
        setError("Не удалось построить дерево. Проверьте конфигурацию LLM и попробуйте снова.");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Ошибка");
    } finally {
      setRunning(false);
    }
  }

  // Live progress from pipeline store (same phase info mirrored into local state)
  const progressLive = pipeline.status === "running" ? pipeline : null;

  return (
    <div className={`bg-canvas text-ink ${heightClass}`}>
      <div className="mx-auto max-w-xl px-6 py-10">
        <Link to="/" className="text-sm font-semibold text-accent-ink hover:text-accent-hover">
          ← Назад
        </Link>
        <h1 className="mt-4 text-2xl font-bold">Новая тема</h1>
        <p className="mt-1 text-sm text-ink-4">
          Создайте тему и постройте дерево знаний с помощью ИИ.
        </p>

        <div className="mt-8 space-y-4">
          <Input
            label="Название темы"
            placeholder="Например: Квантовая механика"
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={running}
          />
          <Input
            label="Запрос для дерева (подробный)"
            placeholder="Опишите, что должно охватывать дерево…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            disabled={running}
          />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Цель"
              options={[
                { value: "overview", label: "Обзор" },
                { value: "deep", label: "Глубокое изучение" },
                { value: "exam", label: "Подготовка к экзамену" },
              ]}
              value={goal}
              onChange={(e) => setGoal(e.target.value)}
              disabled={running}
            />
            <Select
              label="Целевой уровень"
              options={[
                { value: "awareness", label: "Осведомлённость" },
                { value: "basic_understanding", label: "Базовое понимание" },
                { value: "solid_understanding", label: "Уверенное понимание" },
                { value: "practical_application", label: "Практика" },
                { value: "advanced", label: "Продвинутый" },
                { value: "expert", label: "Эксперт" },
              ]}
              value={level}
              onChange={(e) => setLevel(e.target.value)}
              disabled={running}
            />
          </div>
          <Textarea
            label="Замечания/уточнения (необязательно)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            disabled={running}
          />

          <ErrorBanner message={error || (pipeline.status === "error" ? pipeline.message : null)} />

          {running && (
            <div className="rounded-xl border border-border bg-surface p-4">
              <div className="flex items-center gap-3">
                <Spinner size="sm" />
                <span className="text-sm text-ink-3">
                  {PHASE_LABELS[phase?.phase ?? progressLive?.phase ?? ""] ?? "Построение дерева…"}
                </span>
              </div>
              <p className="mt-2 text-xs text-ink-4">
                {phase?.message || progressLive?.message || ""}
              </p>
              {phase?.stats && (
                <div className="mt-3">
                  <ProgressBar
                    value={Math.min(
                      100,
                      ((phase.stats.total ?? 0) > 0
                        ? (phase.stats.depth ?? 0) / 5
                        : 0) * 100,
                    )}
                    label={`Уровней: ${phase.stats.depth ?? 0} · Листьев: ${phase.stats.leaves ?? 0}`}
                  />
                </div>
              )}
            </div>
          )}

          <Button onClick={handleStart} disabled={!canStart} size="lg" className="w-full">
            {running ? "Построение…" : "Создать тему и построить дерево"}
          </Button>
        </div>
      </div>
    </div>
  );
}
