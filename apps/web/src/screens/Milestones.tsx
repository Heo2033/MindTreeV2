import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useGraphStore, useSessionStore } from "../stores";
import { milestonesApi, learnerModelApi } from "../api";
import type { MilestoneDto, MasteryEvaluationDto } from "../api";
import type { MasteryLevel } from "@mindtree/types";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

const LEVEL_LABEL: Record<MasteryLevel, string> = {
  awareness: "Ознакомление",
  basic_understanding: "Базовое понимание",
  solid_understanding: "Уверенное понимание",
  practical_application: "Практическое применение",
  advanced: "Продвинутый",
  expert: "Эксперт",
};

export function MilestonesScreen() {
  const { topicId } = useGraphStore();
  const { session, createSession } = useSessionStore();
  const navigate = useNavigate();

  const [milestones, setMilestones] = useState<MilestoneDto[]>([]);
  const [currentLevel, setCurrentLevel] = useState<MasteryLevel | null>(null);
  const [loading, setLoading] = useState(false);
  const [starting, setStarting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const journeyId = session?.journeyId ?? null;

  async function load() {
    if (!topicId) return;
    setLoading(true);
    setError(null);
    try {
      let jid = journeyId;
      if (!jid) {
        const created = await createSession(topicId).catch(() => null);
        jid = created?.journeyId ?? null;
      }
      if (!jid) throw new Error("Не удалось получить путешествие темы");

      const [{ milestones: ms }, model] = await Promise.all([
        milestonesApi.generate(jid, topicId),
        learnerModelApi.get(topicId).catch(() => null),
      ]);
      setMilestones(ms);
      setCurrentLevel(model?.model.overallLevel ?? null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось загрузить путь");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [topicId, journeyId]);

  async function startMilestone(m: MilestoneDto) {
    if (!topicId) return;
    setStarting(m.id);
    try {
      await createSession(topicId, "deep", m.id, undefined);
      navigate("../session");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось начать веху");
    } finally {
      setStarting(null);
    }
  }

  const currentIndex = currentLevel
    ? milestones.findIndex((m) => m.level === currentLevel)
    : -1;
  const activeId = milestones[currentIndex]?.id;

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="border-b border-border px-6 py-3">
        <h2 className="text-sm font-semibold text-ink">Путь обучения</h2>
        <p className="text-xs text-ink-4">Вехи от начального уровня до эксперта.</p>
      </div>

      <div className="flex-1 px-6 py-6">
        <ErrorBanner message={error} />

        {loading && !milestones.length && (
          <div className="flex justify-center py-16"><Spinner /></div>
        )}

        {!loading && milestones.length === 0 && (
          <div className="mx-auto max-w-xl rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
            Пока нет вех для этой темы.
            <div className="mt-4"><Button onClick={() => void load()}>Сгенерировать путь</Button></div>
          </div>
        )}

        {milestones.length > 0 && (
          <div className="mx-auto max-w-3xl">
            {currentLevel && (
              <Badge variant="info" className="mb-4">
                Текущий уровень: {LEVEL_LABEL[currentLevel] ?? currentLevel}
              </Badge>
            )}

            <div className="relative space-y-4 before:absolute before:left-[15px] before:top-2 before:bottom-2 before:w-px before:bg-surface-3">
              {milestones.map((m, idx) => {
                const isActive = m.id === activeId;
                const isCompleted = idx < currentIndex || m.status === "completed";
                const isNext = idx === currentIndex + 1;
                return (
                  <div key={m.id} className="relative flex gap-4">
                    <div
                      className={`z-10 mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border text-xs font-bold ${
                        isCompleted
                          ? "border-ok bg-ok text-ink"
                          : isActive
                            ? "border-accent bg-accent text-ink"
                            : "border-border-strong bg-surface-2 text-ink-4"
                      }`}
                    >
                      {isCompleted ? "✓" : idx + 1}
                    </div>

                    <div className={`flex-1 rounded-xl border p-4 ${isActive ? "border-accent bg-surface-2" : "border-border bg-surface"}`}>
                      <div className="mb-1 flex flex-wrap items-center gap-2">
                        <span className="text-sm font-semibold text-ink">{m.title}</span>
                        <Badge variant={isNext ? "warning" : isActive ? "info" : "muted"}>
                          {isNext ? "Следующая" : isActive ? "Активная" : LEVEL_LABEL[m.level] ?? m.level}
                        </Badge>
                        <span className="ml-auto text-xs text-ink-4">≈ {m.estimatedHours} ч</span>
                      </div>
                      <p className="text-sm text-ink-4">{m.description}</p>

                      {m.capabilities.length > 0 && (
                        <div className="mt-2 flex flex-wrap gap-1.5">
                          {m.capabilities.map((c, i) => (
                            <span key={i} className="rounded-full border border-border-strong px-2.5 py-0.5 text-xs text-ink-3">
                              {c}
                            </span>
                          ))}
                        </div>
                      )}

                      {!isCompleted && (
                        <div className="mt-3">
                          <Button size="sm" variant={isActive ? "primary" : "secondary"} disabled={starting === m.id} onClick={() => void startMilestone(m)}>
                            {starting === m.id ? "Начинаем…" : isActive ? "Продолжить обучение" : "Начать эту веху"}
                          </Button>
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
