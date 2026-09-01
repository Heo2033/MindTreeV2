import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useGraphStore, useSessionStore } from "../stores";
import { FormattedText } from "../components/FormattedText";
import { Button, Spinner, ErrorBanner, Badge, Field, Select } from "@mindtree/ui";

const TYPE_LABEL: Record<string, string> = {
  explain: "Объяснение",
  example: "Пример",
  recall: "Припоминание",
  apply: "Применение",
  assessment: "Проверка",
  synthesis: "Синтез",
};

const GOAL_OPTIONS = [
  { value: "Разобраться во всех понятиях темы", label: "Обзор всей темы" },
  { value: "Глубокое изучение ключевых понятий", label: "Глубокое изучение" },
  { value: "Подготовка к тесту по теме", label: "Подготовка к тесту" },
];

const BUDGET_OPTIONS = [
  { value: "15", label: "15 минут" },
  { value: "30", label: "30 минут" },
  { value: "45", label: "45 минут" },
  { value: "60", label: "1 час" },
  { value: "90", label: "1,5 часа" },
];

export function SessionScreen() {
  const { topicId, topicName, nodes, loadTopic } = useGraphStore();
  const {
    session,
    currentItem,
    currentIndex,
    adaptive,
    studying,
    loading,
    error,
    createSession,
    loadCurrent,
    startStudy,
    completeItem,
    finalize,
  } = useSessionStore();
  const navigate = useNavigate();

  const [goal, setGoal] = useState(GOAL_OPTIONS[0].value);
  const [budget, setBudget] = useState("45");
  const [busy, setBusy] = useState(false);

  async function onStart() {
    if (!topicId) return;
    setBusy(true);
    try {
      await createSession(topicId, goal, undefined, Number(budget));
    } catch {
      // ошибка уже в сторе
    }
    setBusy(false);
  }

  const node = currentItem ? nodes.find((n) => n.id === currentItem.nodeId) || null : null;

  async function onComplete() {
    if (!currentItem) return;
    setBusy(true);
    await completeItem(currentItem.id, currentItem.nodeId);
    if (topicId) await loadTopic(topicId);
    setBusy(false);
  }

  async function onStudy(nodeId: string) {
    setBusy(true);
    await startStudy(nodeId);
    if (topicId) await loadTopic(topicId);
    setBusy(false);
  }

  async function onFinalize() {
    setBusy(true);
    const res = await finalize();
    setBusy(false);
    if (res && typeof res === "object" && "assessmentId" in res && res.assessmentId) {
      navigate("../final", { state: { assessmentId: res.assessmentId } });
    }
  }

  if (loading && !session) {
    return <div className="flex h-full items-center justify-center"><Spinner /></div>;
  }

  if (!session) {
    return (
      <div className="flex h-full flex-col items-center justify-center p-8">
        <div className="w-full max-w-md rounded-xl border border-border bg-surface p-6 shadow-card">
          <h2 className="text-lg font-bold text-ink">Сессия {topicName ? `· ${topicName}` : ""}</h2>
          <p className="mt-1 text-sm text-ink-4">
            Адаптивный курс: сессия построит персональный план изучения темы и подберёт шаги под вашу цель.
          </p>

          {error && <div className="mt-3"><ErrorBanner message={error} /></div>}

          <div className="mt-4 space-y-4">
            <Field label="Цель">
              <Select value={goal} options={GOAL_OPTIONS} onChange={(e) => setGoal(e.target.value)} />
            </Field>
            <Field label="Время">
              <Select value={budget} options={BUDGET_OPTIONS} onChange={(e) => setBudget(e.target.value)} />
            </Field>
            <Button className="w-full" disabled={busy || !topicId} onClick={() => void onStart()}>
              {busy ? <Spinner size="sm" /> : "Начать сессию"}
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="flex items-center justify-between border-b border-border px-6 py-3">
        <div>
          <span className="text-sm font-semibold text-ink">
            Сессия {session.goal ? `· ${session.goal}` : ""}
          </span>
          <span className="ml-2 text-xs text-ink-4">шаг {currentIndex + 1} / {session.curriculum.items.length}</span>
        </div>
        <div className="flex items-center gap-2">
          {adaptive && (
            <Badge variant="info">
              {adaptive.recommendedAction === "final_assessment"
                ? "Рекомендуется итоговый тест"
                : adaptive.recommendedAction === "complete"
                  ? "Можно завершить"
                  : "Рекомендуется: " + adaptive.recommendedAction}
            </Badge>
          )}
          <Button variant="secondary" size="sm" disabled={busy} onClick={onFinalize}>
            Завершить сессию
          </Button>
        </div>
      </div>

      <div className="flex-1 px-6 py-6">
        {error && <div className="mb-4"><ErrorBanner message={error} /></div>}

        {node && (
          <div className="mx-auto max-w-2xl">
            <div className="mb-2 flex items-center gap-2">
              <Badge>{TYPE_LABEL[currentItem?.type ?? ""] ?? currentItem?.type}</Badge>
              {currentItem?.priority === 1 && <Badge variant="warning">Приоритет</Badge>}
            </div>
            <h1 className="text-2xl font-bold text-ink">{node.label}</h1>

            {studying && (
              <div className="mt-6">
                <div className="mt-3 whitespace-pre-wrap text-[15px] leading-relaxed text-ink-2">
                  <FormattedText text={node.details || node.oneLiner} />
                </div>
                {node.analogy && (
                  <div className="mt-4 rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-warn">
                    <span className="font-semibold">Простыми словами: </span>
                    {node.analogy}
                  </div>
                )}
              </div>
            )}

{!studying && (
              <div className="mt-8">
                <p className="mb-4 text-sm text-ink-3">
                  {node.oneLiner || "Нажмите «Изучить», чтобы открыть содержание текущего шага."}
                </p>
                <div className="flex gap-3">
                  <Button onClick={() => void onStudy(node.id)} disabled={busy}>
                    {busy ? "Генерирую контент…" : "Изучить"}
                  </Button>
                  <Button variant="secondary" disabled={busy} onClick={onComplete}>
                    {currentIndex < session.curriculum.items.length - 1 ? "Шаг изучен" : "Завершить"}
                  </Button>
                </div>
                {busy && <p className="mt-3 text-xs text-ink-4">Контент подгружается, это может занять несколько секунд…</p>}
              </div>
            )}

            {studying && (
              <div className="mt-6">
                {!node.contentLoaded && !node.details && busy && (
                  <div className="mb-4 flex items-center gap-2 rounded-lg border border-border bg-surface-2 px-4 py-3 text-sm text-ink-3">
                    <Spinner size="sm" />
                    Генерирую контент раздела…
                  </div>
                )}
                <div className="flex gap-3">
                  <Button variant="secondary" disabled={busy} onClick={onComplete}>
                    {currentIndex < session.curriculum.items.length - 1 ? "Следующий шаг" : "Завершить"}
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}

        {!node && (
          <div className="flex flex-col items-center gap-4 py-16 text-center">
            <p className="text-ink-4">Для текущего шага нет узла в дереве.</p>
            <Button variant="secondary" onClick={() => void loadCurrent()}>
              Обновить
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
