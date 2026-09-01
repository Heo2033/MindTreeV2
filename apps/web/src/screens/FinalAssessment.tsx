import { useEffect, useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useGraphStore, useSessionStore } from "../stores";
import { assessmentsApi } from "../api";
import type { AssessmentDto, AssessmentSubmitResult } from "../api";
import type { MasteryLevel } from "@mindtree/types";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

type Phase = "loading" | "playing" | "result";

const LEVEL_LABEL: Record<MasteryLevel, string> = {
  awareness: "Ознакомление",
  basic_understanding: "Базовое понимание",
  solid_understanding: "Уверенное понимание",
  practical_application: "Практическое применение",
  advanced: "Продвинутый",
  expert: "Эксперт",
};

export function FinalAssessmentScreen() {
  const { topicId } = useGraphStore();
  const { session, finalize } = useSessionStore();
  const navigate = useNavigate();
  const location = useLocation();
  const passedId = (location.state as { assessmentId?: string } | null)?.assessmentId;

  const [phase, setPhase] = useState<Phase>("loading");
  const [assessment, setAssessment] = useState<AssessmentDto | null>(null);
  const [current, setCurrent] = useState(0);
  const [answers, setAnswers] = useState<(number | null)[]>([]);
  const [result, setResult] = useState<AssessmentSubmitResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function setup() {
    if (!session) {
      setError("Нет активной сессии. Сначала создайте сессию на вкладке «Сессия».");
      setPhase("result");
      return;
    }
    setPhase("loading");
    setError(null);
    try {
      let a: AssessmentDto;
      if (passedId) {
        a = await assessmentsApi.get(passedId);
      } else {
        a = await assessmentsApi.create({
          session_id: session.id,
          type: "final",
          question_count: 6,
        });
      }
      setAssessment(a);
      setAnswers(new Array(a.questions.length).fill(null));
      setCurrent(0);
      setPhase(a.questions.length ? "playing" : "result");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сформировать итоговый тест");
      setPhase("result");
    }
  }

  useEffect(() => {
    void setup();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.id]);

  const select = (i: number) => {
    if (answers[current] !== null) return;
    const next = [...answers];
    next[current] = i;
    setAnswers(next);
  };

  async function submit() {
    if (!assessment) return;
    setBusy(true);
    setError(null);
    const attempts = assessment.questions.map((q, i) => {
      const sel = answers[i];
      const selectedOption = sel === null ? "" : q.options[sel];
      return {
        question_id: q.id,
        answer: selectedOption,
        correct: selectedOption === q.correctAnswer,
      };
    });
    try {
      const res = await assessmentsApi.submit(assessment.id, attempts);
      setResult(res);
      setPhase("result");
      await finalize().catch(() => {});
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сохранить результаты");
    } finally {
      setBusy(false);
    }
  }

  if (phase === "loading") {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4">
        <Spinner />
        <p className="text-sm text-ink-4">Формируем итоговый тест…</p>
      </div>
    );
  }

  if (phase === "result") {
    return (
      <div className="flex h-full items-start justify-center overflow-y-auto p-8">
        <div className="w-full max-w-2xl">
          <ErrorBanner message={error} />

          {result ? (
            <div className="space-y-6">
              <div className="rounded-xl border border-border bg-surface p-6 text-center">
                <p className="text-sm text-ink-4">Результат итогового теста</p>
                <p className="mt-1 text-4xl font-bold text-ink">{Math.round(result.score * 100)}%</p>
                <p className="mt-1 text-sm text-ink-4">
                  {result.correct} из {result.total} верно
                </p>
                {result.mastery && (
                  <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
                    <Badge variant="info">Новый уровень: {LEVEL_LABEL[result.mastery.newLevel.label] ?? result.mastery.newLevel.label}</Badge>
                    <Badge variant={result.mastery.reachedTarget ? "success" : "warning"}>
                      {result.mastery.reachedTarget ? "Цель достигнута" : "Цель не достигнута"}
                    </Badge>
                  </div>
                )}
              </div>

              {result.mastery && result.mastery.gaps.length > 0 && (
                <div className="rounded-xl border border-border bg-surface p-4">
                  <h3 className="mb-2 text-sm font-semibold text-danger">Что стоит повторить</h3>
                  <ul className="space-y-1 text-sm text-ink-3">
                    {result.mastery.gaps.map((g, i) => (
                      <li key={i}>• {g}</li>
                    ))}
                  </ul>
                </div>
              )}

              <div className="flex gap-3">
                <Button variant="secondary" className="flex-1" onClick={() => navigate("../learner")}>
                  Модель ученика
                </Button>
                <Button className="flex-1" onClick={() => navigate("../session")}>
                  К сессии
                </Button>
              </div>
            </div>
          ) : (
            <div className="rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
              Не удалось выполнить итоговый тест.
              <div className="mt-4"><Button onClick={() => void setup()}>Попробовать снова</Button></div>
            </div>
          )}
        </div>
      </div>
    );
  }

  const question = assessment!.questions[current];

  return (
    <div className="flex h-full items-start justify-center overflow-y-auto p-8">
      <div className="w-full max-w-2xl">
        <div className="mb-4 flex items-center justify-between text-xs text-ink-4">
          <span>Вопрос {current + 1} / {assessment!.questions.length}</span>
          <span>Итоговый тест</span>
        </div>
        <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-surface-2">
          <div className="h-full rounded-full bg-accent" style={{ width: `${((current + 1) / assessment!.questions.length) * 100}%` }} />
        </div>

        <p className="mb-4 text-sm font-medium text-ink">{question.question}</p>

        <div className="mb-4 space-y-2">
          {question.options.map((opt, i) => {
            const selected = answers[current] === i;
            const cls = selected
              ? "border-accent bg-surface-2 text-accent-ink"
              : "border-border-strong bg-surface text-ink-2 hover:border-border-strong hover:bg-surface-2";
            return (
              <button
                key={i}
                className={`w-full rounded-lg border p-3 text-left text-sm transition-all ${cls}`}
                disabled={answers[current] !== null}
                onClick={() => select(i)}
              >
                <span className="mr-2 font-semibold">{String.fromCharCode(65 + i)})</span>
                {opt}
              </button>
            );
          })}
        </div>

        <ErrorBanner message={error} />

        {answers[current] !== null && (
          <Button className="w-full" disabled={busy} onClick={() => (current < assessment!.questions.length - 1 ? setCurrent(current + 1) : void submit())}>
            {current < assessment!.questions.length - 1 ? "Следующий вопрос" : "Завершить"}
          </Button>
        )}
      </div>
    </div>
  );
}
