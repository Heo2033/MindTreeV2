import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useGraphStore, useSessionStore } from "../stores";
import { milestonesApi, learnerModelApi } from "../api";
import type { MilestoneDto } from "../api";
import type { MasteryLevel } from "@mindtree/types";
import { Button, Spinner, ErrorBanner, Badge, Input, Textarea, Select } from "@mindtree/ui";

const LEVEL_LABEL: Record<MasteryLevel, string> = {
  awareness: "Ознакомление",
  basic_understanding: "Базовое понимание",
  solid_understanding: "Уверенное понимание",
  practical_application: "Практическое применение",
  advanced: "Продвинутый",
  expert: "Эксперт",
};

const LEVEL_OPTIONS = (Object.keys(LEVEL_LABEL) as MasteryLevel[]).map((lv) => ({
  value: lv,
  label: LEVEL_LABEL[lv],
}));

export function MilestonesScreen() {
  const { topicId } = useGraphStore();
  const { session, createSession } = useSessionStore();
  const navigate = useNavigate();

  const [milestones, setMilestones] = useState<MilestoneDto[]>([]);
  const [currentLevel, setCurrentLevel] = useState<MasteryLevel | null>(null);
  const [loading, setLoading] = useState(false);
  const [starting, setStarting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [formOpen, setFormOpen] = useState(false);
  const [formLevel, setFormLevel] = useState<MasteryLevel>("awareness");
  const [formTitle, setFormTitle] = useState("");
  const [formDescription, setFormDescription] = useState("");
  const [formCaps, setFormCaps] = useState("");
  const [formHours, setFormHours] = useState("2");
  const [deleting, setDeleting] = useState<string | null>(null);

  const journeyId = session?.journeyId ?? null;

  async function load() {
    if (!topicId) return;
    setLoading(true);
    setError(null);
    try {
      if (!journeyId) {
        setLoading(false);
        return;
      }

      let ms: MilestoneDto[] = [];
      const existing = await milestonesApi.journey(journeyId).catch(() => null);
      if (existing && existing.milestones.length > 0) {
        ms = existing.milestones;
      } else {
        const gen = await milestonesApi.generate(journeyId, topicId);
        ms = gen.milestones;
      }

      const model = await learnerModelApi.get(topicId).catch(() => null);
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
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load() пересоздаётся каждый рендер; изменения аккаунтируются через topicId/journeyId.
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

  async function setStatus(m: MilestoneDto, status: MilestoneDto["status"]) {
    try {
      await milestonesApi.patch(m.id, status);
      setMilestones((prev) =>
        prev.map((x) => (x.id === m.id ? { ...x, status } : x)),
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось обновить статус вехи");
    }
  }

  async function createMilestone() {
    if (!journeyId) return;
    if (formTitle.trim() === "") {
      setError("Укажите название вехи");
      return;
    }
    setCreating(true);
    setError(null);
    const capabilities = formCaps
      .split(",")
      .map((c) => c.trim())
      .filter(Boolean);
    const hours = Number(formHours);
    try {
      const { milestone } = await milestonesApi.create({
        journey_id: journeyId,
        level: formLevel,
        title: formTitle.trim(),
        description: formDescription.trim(),
        capabilities,
        estimatedHours: Number.isFinite(hours) && hours > 0 ? hours : 1,
      });
      setMilestones((prev) => [...prev, milestone]);
      setFormOpen(false);
      setFormTitle("");
      setFormDescription("");
      setFormCaps("");
      setFormHours("2");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось создать веху");
    } finally {
      setCreating(false);
    }
  }

  async function removeMilestone(m: MilestoneDto) {
    const confirmed = window.confirm(`Удалить веху «${m.title}»?`);
    if (!confirmed) return;
    setDeleting(m.id);
    setError(null);
    try {
      await milestonesApi.remove(m.id);
      setMilestones((prev) => prev.filter((x) => x.id !== m.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось удалить веху");
    } finally {
      setDeleting(null);
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

        {!loading && !journeyId && (
          <div className="mx-auto max-w-xl rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
            <p className="text-sm font-medium text-ink-3">Сессия не начата</p>
            <p className="mt-2 text-sm">Чтобы увидеть путь обучения, сначала начните сессию на вкладке «Сессия».</p>
            <div className="mt-4"><Button onClick={() => navigate("../session")}>Перейти к сессии</Button></div>
          </div>
        )}

        {!loading && journeyId && milestones.length === 0 && (
          <div className="mx-auto max-w-xl rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
            Пока нет вех для этой темы.
            <div className="mt-4"><Button onClick={() => void load()}>Сгенерировать путь</Button></div>
          </div>
        )}

        {milestones.length > 0 && (
          <div className="mx-auto max-w-3xl">
            <div className="mb-4 flex items-center gap-2">
              {currentLevel && (
                <Badge variant="info">
                  Текущий уровень: {LEVEL_LABEL[currentLevel] ?? currentLevel}
                </Badge>
              )}
              <div className="ml-auto">
                <Button size="sm" variant="secondary" onClick={() => setFormOpen((v) => !v)}>
                  {formOpen ? "Скрыть форму" : "+ Добавить веху"}
                </Button>
              </div>
            </div>

            {formOpen && (
              <div className="mb-4 space-y-3 rounded-xl border border-accent bg-surface p-4">
                <h4 className="text-sm font-semibold text-ink">Новая веха</h4>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <Input label="Название" value={formTitle} onChange={(e) => setFormTitle(e.target.value)} placeholder="Например: Основы диагностики" />
                  <Select label="Уровень" options={LEVEL_OPTIONS} value={formLevel} onChange={(e) => setFormLevel(e.target.value as MasteryLevel)} />
                </div>
                <Textarea label="Описание" value={formDescription} onChange={(e) => setFormDescription(e.target.value)} placeholder="Что ученик сможет после вехи…" />
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <Input label="Навыки (через запятую)" value={formCaps} onChange={(e) => setFormCaps(e.target.value)} placeholder="анализ, синтез" />
                  <Input label="Оценка времени (ч)" type="number" min="0" step="0.5" value={formHours} onChange={(e) => setFormHours(e.target.value)} />
                </div>
                <div className="flex items-center gap-2">
                  <Button size="sm" onClick={() => void createMilestone()} disabled={creating || !journeyId}>
                    {creating ? "Создание…" : "Создать"}
                  </Button>
                  <button onClick={() => setFormOpen(false)} className="text-sm text-ink-4 hover:text-ink">Отмена</button>
                </div>
              </div>
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
                        <button
                          onClick={() => void removeMilestone(m)}
                          disabled={deleting === m.id}
                          className="rounded-md border border-border px-2 py-0.5 text-xs text-danger hover:bg-danger-soft disabled:opacity-50"
                          title="Удалить веху"
                        >
                          {deleting === m.id ? "…" : "Удалить"}
                        </button>
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
                        <div className="mt-3 flex flex-wrap items-center gap-2">
                          <Button size="sm" variant={isActive ? "primary" : "secondary"} disabled={starting === m.id} onClick={() => void startMilestone(m)}>
                            {starting === m.id ? "Начинаем…" : isActive ? "Продолжить обучение" : "Начать эту веху"}
                          </Button>
                          {m.status === "active" && (
                            <Button size="sm" variant="secondary" onClick={() => void setStatus(m, "completed")}>
                              Завершить веху
                            </Button>
                          )}
                          {m.status === "not_started" && isActive && (
                            <Button size="sm" variant="secondary" onClick={() => void setStatus(m, "active")}>
                              Отметить активной
                            </Button>
                          )}
                        </div>
                      )}

                      {m.alternativePaths.length > 0 && (
                        <div className="mt-3 border-t border-border pt-3">
                          <div className="text-xs font-medium text-ink-4">
                            Альтернативные пути
                          </div>
                          <div className="mt-1.5 space-y-1.5">
                            {m.alternativePaths.map((ap, ai) => (
                              <div key={ai} className="rounded-md bg-surface-2 px-3 py-2 text-sm">
                                <div className="flex items-center gap-2">
                                  <span className="font-medium text-ink-2">{ap.title}</span>
                                  <span className="ml-auto text-xs text-ink-4">≈ {ap.estimatedHours} ч</span>
                                </div>
                                {ap.description && (
                                  <p className="mt-0.5 text-xs text-ink-4">{ap.description}</p>
                                )}
                              </div>
                            ))}
                          </div>
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
