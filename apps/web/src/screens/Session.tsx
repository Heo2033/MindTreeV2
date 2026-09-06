import { useEffect, useState } from "react";
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
  const { topicId, topicName, loadTopic } = useGraphStore();
  const {
    session,
    currentItem,
    currentIndex,
    adaptive,
    activity,
    answeredStepView,
    loading,
    error,
    createSession,
    resume,
    startStudy,
    ensureActivity,
    answerStep,
    clearAnsweredView,
    completeConcept,
    finalize,
  } = useSessionStore();
  const navigate = useNavigate();

  const [goal, setGoal] = useState(GOAL_OPTIONS[0].value);
  const [budget, setBudget] = useState("45");
  const [busy, setBusy] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [answerText, setAnswerText] = useState("");
  const [showPlan, setShowPlan] = useState(true);
  const [finalizeError, setFinalizeError] = useState<string | null>(null);
  const [advancing, setAdvancing] = useState(false);

  // загрузка активности при смене шага
  // Гвард на error: не зацикливать ensureActivity, когда текущий концепт не найден
  // (например, после завершения последнего концепта до перехода на итоговый тест).
  useEffect(() => {
    if (session && !activity && !loading && !error && !advancing) {
      void ensureActivity();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- ensureActivity стабилен из стора, session отслеживается по id; явное добавление объекта зациклит вызов.
  }, [session?.id, activity, loading, error, advancing]);

  // Восстановление сессии после перезагрузки/персиста: session есть, а currentItem ещё нет.
  useEffect(() => {
    if (session && !currentItem && !loading && !error) {
      void resume();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- resume() стабилен; восстановление нужно только при смене сессии.
  }, [session?.id]);

  async function onStart() {
    if (!topicId) return;
    setBusy(true);
    try {
      await createSession(topicId, goal, undefined, Number(budget));
    } catch {
      // ошибка уже в сторе
    } finally {
      setBusy(false);
    }
  }

  async function onStudyFirst() {
    if (!currentItem?.nodeId) return;
    setBusy(true);
    try {
      await startStudy(currentItem.nodeId);
    } finally {
      setBusy(false);
    }
  }

  async function onAnswer() {
    if (!activity || activity.currentStep < 0) return;
    const step = activity.steps[activity.currentStep];
    if (!step) return;
    if (step.type === "recall" && selectedIndex === null) return;
    const answer =
      step.type === "recall" ? String(selectedIndex) : answerText;
    setBusy(true);
    try {
      await answerStep(activity.currentStep, answer);
    } finally {
      setSelectedIndex(null);
      setAnswerText("");
      setBusy(false);
    }
  }

  async function onClearFeedback() {
    clearAnsweredView();
  }

  // Нажатие в блоке «все шаги пройдены»: следующий концепт либо итоговый тест.
  async function onComplete() {
    // На последнем концепте «Завершить сессию» уводит сразу на итоговый тест.
    if (session && currentIndex >= session.curriculum.items.length - 1) {
      return onFinalize();
    }
    if (!currentItem) return;
    setBusy(true);
    setAdvancing(true);
    setFinalizeError(null);
    try {
      await completeConcept(currentItem.id, currentItem.nodeId);
      if (topicId) await loadTopic(topicId);
    } finally {
      setSelectedIndex(null);
      setAnswerText("");
      setBusy(false);
      setAdvancing(false);
    }
  }

  async function onFinalize() {
    setBusy(true);
    setAdvancing(true);
    setFinalizeError(null);
    try {
      const res = await finalize();
      if (res && typeof res === "object" && "assessmentId" in res && res.assessmentId) {
        navigate("../final", { state: { assessmentId: res.assessmentId } });
      } else if (!error) {
        // Ошибка не ушла в стор (напр. ответ без assessmentId) — показываем локально.
        setFinalizeError("Не удалось завершить сессию: итоговая проверка не была создана. Попробуйте ещё раз.");
      }
    } finally {
      setBusy(false);
      setAdvancing(false);
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

  const isActivityLoading = loading && !activity;
  const isComplete = activity?.isComplete;
  const feedbackViewStep = answeredStepView !== null && activity ? activity.steps[answeredStepView] : null;
  const currentStep = activity && activity.currentStep >= 0 ? activity.steps[activity.currentStep] : null;

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-border px-6 py-3">
        <div>
          <span className="text-sm font-semibold text-ink">
            Сессия {session.goal ? `· ${session.goal}` : ""}
          </span>
          <span className="ml-2 text-xs text-ink-4">
            шаг {currentIndex + 1} / {session.curriculum.items.length}
          </span>
          {adaptive?.eta && (
            <span className="ml-2 text-xs text-ink-4">
              · осталось ≈ {adaptive.eta.remainingMinutesMin}–{adaptive.eta.remainingMinutesMax} мин
            </span>
          )}
          <button
            className="ml-3 text-xs text-accent hover:underline"
            onClick={() => setShowPlan((s) => !s)}
          >
            {showPlan ? "Скрыть план" : "Показать план"}
          </button>
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

      {/* Session place / «Достаточно» recommendation */}
      {adaptive && (adaptive.recommendedAction === "final_assessment" || adaptive.recommendedAction === "complete") && (
        <div className="border-b border-ok/40 bg-ok-soft px-6 py-3">
          <div className="mx-auto flex max-w-3xl flex-wrap items-center gap-3">
            <span className="text-sm font-semibold text-ok">Достаточно для твоей цели</span>
            <p className="flex-1 text-sm text-ink-2">
              Тебе, вероятно, не нужно изучать дальше для этой цели. Пройди итоговый тест,
              чтобы зафиксировать результат.
            </p>
            <div className="flex gap-2">
              <Button size="sm" onClick={onFinalize}>Итоговый тест</Button>
              <Button size="sm" variant="secondary" onClick={() => navigate("../milestones")}>
                Следующая веха
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Session plan */}
      {showPlan && (
        <div className="border-b border-border bg-surface-2 px-6 py-3">
          <div className="mx-auto max-w-3xl">
            <div className="mb-2 flex items-center justify-between text-xs">
              <span className="font-semibold text-ink-3">План сессии</span>
              <span className="text-ink-4">Всего ≈ {session.curriculum.totalEstimatedMinutes} мин · цель: {session.goal}</span>
              {adaptive?.eta && (
                <span className="text-ink-4">
                  · {adaptive.eta.pace === "faster"
                    ? "темп быстрее ожидаемого"
                    : adaptive.eta.pace === "slower"
                      ? "темп медленнее ожидаемого"
                      : "в графике"}
                </span>
              )}
            </div>
            <div className="grid gap-1.5">
              {session.curriculum.items.map((it, i) => {
                const done = it.status === "completed" || i < currentIndex;
                return (
                  <div
                    key={it.id}
                    className={`flex items-center gap-3 rounded-lg border px-3 py-1.5 ${
                      i === currentIndex
                        ? "border-accent bg-surface"
                        : done
                          ? "border-border bg-surface opacity-60"
                          : "border-border bg-surface"
                    }`}
                  >
                    <span className={`w-6 shrink-0 text-center text-xs font-bold ${i === currentIndex ? "text-accent" : "text-ink-4"}`}>
                      {done ? "✓" : i + 1}
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-medium text-ink">{it.label ?? it.nodeId}</div>
                      {it.reason && <div className="truncate text-xs text-ink-4">{it.reason}</div>}
                    </div>
                    <span className="shrink-0 text-xs tabular-nums text-ink-4">{it.estimatedMinutes}м</span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Steps breadcrumb */}
      {activity && (
        <div className="flex gap-1 overflow-x-auto border-b border-border bg-surface-2 px-6 py-2">
          {activity.steps.map((step: typeof activity.steps[number], i: number) => {
            const isActive = i === activity.currentStep;
            const isDone = step.status === "answered";
            return (
              <Badge
                key={i}
                variant={isActive ? "info" : isDone ? "success" : "muted"}
                className="whitespace-nowrap"
              >
                {isDone && !isActive ? "✓ " : ""}
                {step.title || (TYPE_LABEL[step.type] ?? step.type)}
              </Badge>
            );
          })}
        </div>
      )}

      {/* Body */}
      <div className="flex-1 px-6 py-6">
        {error && <div className="mb-4"><ErrorBanner message={error} /></div>}
        {finalizeError && <div className="mb-4"><ErrorBanner message={finalizeError} /></div>}

        {isActivityLoading && (
          <div className="flex flex-col items-center gap-3 py-16">
            <Spinner />
            <p className="text-sm text-ink-4">Подготавливаем шаг…</p>
          </div>
        )}

        {/* Feedback view after answered step with feedback */}
        {!isActivityLoading && feedbackViewStep && (
          <div className="mx-auto max-w-2xl space-y-4">
            <Badge variant={feedbackViewStep.correct ? "success" : "warning"}>
              {feedbackViewStep.correct ? "Верно" : "Есть ошибки"}
            </Badge>
            <h2 className="text-lg font-bold text-ink">
              {feedbackViewStep.title || TYPE_LABEL[feedbackViewStep.type]}
            </h2>
            <div className="rounded-lg border border-border bg-surface p-4 text-sm leading-relaxed text-ink-2">
              <FormattedText text={feedbackViewStep.feedback ?? ""} />
            </div>
            {feedbackViewStep.bestAnswer && !feedbackViewStep.correct && (
              <div className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-warn">
                <span className="font-semibold">Эталонный ответ (для самостоятельной проверки):</span>
                <div className="mt-1"><FormattedText text={feedbackViewStep.bestAnswer} /></div>
              </div>
            )}
            <Button onClick={() => void onClearFeedback()}>Далее</Button>
          </div>
        )}

        {/* Current step */}
        {!isActivityLoading && !feedbackViewStep && currentStep && !isComplete && (
          <div className="mx-auto max-w-2xl space-y-4">
            <Badge>{TYPE_LABEL[currentStep.type] ?? currentStep.type}</Badge>
            {activity?.nodeLabel && (
              <p className="text-sm font-medium text-ink-4">
                Концепт: {activity.nodeLabel}
              </p>
            )}
            <h2 className="text-xl font-bold text-ink">{currentStep.title || TYPE_LABEL[currentStep.type]}</h2>

            {/* explain / example — body */}
            {(currentStep.type === "explain" || currentStep.type === "example") && currentStep.body && (
              <div className="whitespace-pre-wrap text-[15px] leading-relaxed text-ink-2">
                <FormattedText text={currentStep.body} />
              </div>
            )}

            {/* recall — options */}
            {currentStep.type === "recall" && (
              <div className="space-y-3">
                <p className="text-[15px] leading-relaxed text-ink-2">
                  <FormattedText text={currentStep.instruction ?? ""} />
                </p>
                <div className="space-y-2">
                  {currentStep.options?.map((opt: string, i: number) => (
                    <button
                      key={i}
                      disabled={busy}
                      onClick={() => setSelectedIndex(i)}
                      className={`block w-full rounded-lg border px-4 py-3 text-left text-sm transition-colors ${
                        selectedIndex === i
                          ? "border-blue bg-blue-soft text-blue"
                          : "border-border bg-surface hover:border-ink-3 text-ink-2"
                      }`}
                    >
                      <span className="mr-2 font-semibold">{String.fromCharCode(65 + i)}.</span>
                      {opt}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* apply — textarea */}
            {currentStep.type === "apply" && (
              <div className="space-y-3">
                <p className="text-[15px] leading-relaxed text-ink-2">
                  <FormattedText text={currentStep.instruction ?? ""} />
                </p>
                <textarea
                  className="w-full rounded-lg border border-border bg-surface px-4 py-3 text-sm text-ink-2 outline-none placeholder:text-ink-4 focus:border-blue"
                  rows={4}
                  disabled={busy}
                  value={answerText}
                  onChange={(e) => setAnswerText(e.target.value)}
                  placeholder={currentStep.placeholder || "Введите ответ…"}
                />
              </div>
            )}

            <div className="flex gap-3 pt-2">
              {(currentStep.type === "recall" || currentStep.type === "apply") && (
                <Button
                  disabled={busy || (currentStep.type === "recall" && selectedIndex === null)}
                  onClick={() => void onAnswer()}
                >
                  {busy ? <Spinner size="sm" /> : "Проверить"}
                </Button>
              )}
              {(currentStep.type === "explain" || currentStep.type === "example") && (
                <Button disabled={busy} onClick={() => void onAnswer()}>
                  Продолжить
                </Button>
              )}
              <Button variant="secondary" disabled={busy} onClick={onComplete}>
                Завершить концепт
              </Button>
            </div>
          </div>
        )}

        {/* Генерация следующего концепта / итогового теста */}
        {!isActivityLoading && advancing && (
          <div className="flex flex-col items-center gap-4 py-16 text-center">
            <Spinner />
            <p className="text-sm text-ink-4">
              {currentIndex >= session.curriculum.items.length - 1
                ? "Формируем итоговый тест…"
                : "Генерируем следующий концепт…"}
            </p>
          </div>
        )}

        {/* All steps complete — prompt completeConcept / finalize */}
        {!isActivityLoading && !advancing && isComplete && (
          <div className="flex flex-col items-center gap-4 py-16 text-center">
            <p className="text-ink-2">Все шаги этого концепта пройдены.</p>
            <Button disabled={busy} onClick={onComplete}>
              {currentIndex < session.curriculum.items.length - 1 ? "Следующий концепт" : "Завершить сессию"}
            </Button>
          </div>
        )}

        {/* Все концепты завершены — предложить итоговый тест */}
        {!isActivityLoading && !advancing && !activity && !error &&
          session && currentIndex >= session.curriculum.items.length - 1 && (
          <div className="flex flex-col items-center gap-4 py-16 text-center">
            <p className="text-ink-2">Все концепты сессии пройдены.</p>
            <Button disabled={busy} onClick={onFinalize}>
              Пройти итоговый тест
            </Button>
          </div>
        )}

        {!isActivityLoading && !activity && !error &&
          session && currentIndex < session.curriculum.items.length - 1 && (
          <div className="flex flex-col items-center gap-4 py-16 text-center">
            <p className="text-ink-4">Не удалось загрузить активность.</p>
            <Button variant="secondary" onClick={() => void onStudyFirst()}>
              Повторить попытку
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}