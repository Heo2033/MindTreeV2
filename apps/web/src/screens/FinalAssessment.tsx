import { useEffect, useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useGraphStore, useSessionStore } from "../stores";
import { assessmentsApi, sessionsApi } from "../api";
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

const MCQ_TYPES = new Set(["recognition", "recall"]);
const OPEN_TYPES = new Set(["explanation", "diagnosis", "application", "transfer"]);

const TYPE_LABEL: Record<string, string> = {
  recognition: "Узнавание",
  recall: "Припоминание",
  explanation: "Объяснение",
  diagnosis: "Диагностика ошибки",
  application: "Применение",
  transfer: "Перенос",
};

export function FinalAssessmentScreen() {
  const { topicId } = useGraphStore();
  const { session } = useSessionStore();
  const navigate = useNavigate();
  const location = useLocation();
  const passedId = (location.state as { assessmentId?: string } | null)?.assessmentId;

  const [phase, setPhase] = useState<Phase>("loading");
  const [assessment, setAssessment] = useState<AssessmentDto | null>(null);
  const [current, setCurrent] = useState(0);
  const [mcqAnswers, setMcqAnswers] = useState<(number | null)[]>([]);
  const [openAnswers, setOpenAnswers] = useState<string[]>([]);
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
        try {
          const prepared = await sessionsApi.finalize(session.id);
          a = await assessmentsApi.get(prepared.assessmentId);
        } catch {
          a = await assessmentsApi.create({
            session_id: session.id,
            type: "final",
            question_count: 6,
          });
        }
      }
      setAssessment(a);
      setMcqAnswers(new Array(a.questions.length).fill(null));
      setOpenAnswers(new Array(a.questions.length).fill(""));
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
    if (mcqAnswers[current] !== null) return;
    const next = [...mcqAnswers];
    next[current] = i;
    setMcqAnswers(next);
  };

  const setOpen = (text: string) => {
    const next = [...openAnswers];
    next[current] = text;
    setOpenAnswers(next);
  };

  const isAnswered = (idx: number) => {
    const q = assessment!.questions[idx];
    if (OPEN_TYPES.has(q.type ?? "")) return (openAnswers[idx] ?? "").trim().length > 0;
    if (MCQ_TYPES.has(q.type ?? "")) return mcqAnswers[idx] !== null;
    // unknown type: require MCQ if options exist, else text
    return q.options.length > 0 ? mcqAnswers[idx] !== null : (openAnswers[idx] ?? "").trim().length > 0;
  };

  async function submit() {
    if (!assessment) return;
    setBusy(true);
    setError(null);
    const attempts = assessment.questions.map((q, i) => {
      if (MCQ_TYPES.has(q.type ?? "")) {
        const sel = mcqAnswers[i];
        const selectedOption = sel === null ? "" : q.options[sel] ?? "";
        const correctIndex = Number(q.correctAnswer);
        const correct = sel !== null && (Number.isFinite(correctIndex) ? sel === correctIndex : selectedOption === q.correctAnswer);
        return {
          question_id: q.id,
          answer: selectedOption,
          correct,
        };
      }
      // open-ended: send text; correctness is judged server-side via mastery rubric
      return {
        question_id: q.id,
        answer: openAnswers[i] ?? "",
        correct: false,
      };
    });
    try {
      const res = await assessmentsApi.submit(assessment.id, attempts);
      setResult(res);
      setPhase("result");
      // Сессия завершается на сервере при сабмите финального assessment.
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
  const isMcq = MCQ_TYPES.has(question.type ?? "");
  const answered = isAnswered(current);

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

        <div className="mb-2 flex items-center gap-2">
          <Badge variant="muted">{TYPE_LABEL[question.type ?? ""] ?? question.type ?? "Вопрос"}</Badge>
        </div>
        <p className="mb-4 text-sm font-medium text-ink">{question.question}</p>

        {isMcq ? (
          <div className="mb-4 space-y-2">
            {question.options.map((opt, i) => {
              const selected = mcqAnswers[current] === i;
              const cls = selected
                ? "border-accent bg-surface-2 text-accent-ink"
                : "border-border-strong bg-surface text-ink-2 hover:border-border-strong hover:bg-surface-2";
              return (
                <button
                  key={i}
                  className={`w-full rounded-lg border p-3 text-left text-sm transition-all ${cls}`}
                  disabled={answered}
                  onClick={() => select(i)}
                >
                  <span className="mr-2 font-semibold">{String.fromCharCode(65 + i)})</span>
                  {opt}
                </button>
              );
            })}
          </div>
        ) : (
          <div className="mb-4">
            <textarea
              className="w-full rounded-lg border border-border bg-surface p-3 text-sm text-ink-2 outline-none placeholder:text-ink-4 focus:border-accent"
              rows={5}
              value={openAnswers[current] ?? ""}
              onChange={(e) => setOpen(e.target.value)}
              placeholder="Введите ответ своими словами…"
            />
            {question.explanation && (
              <p className="mt-1 text-xs text-ink-4">
                Рекомендация для проверки: {question.explanation}
              </p>
            )}
          </div>
        )}

        <ErrorBanner message={error} />

        {answered && (
          <Button className="w-full" disabled={busy} onClick={() => (current < assessment!.questions.length - 1 ? setCurrent(current + 1) : void submit())}>
            {current < assessment!.questions.length - 1 ? "Следующий вопрос" : "Завершить"}
          </Button>
        )}
      </div>
    </div>
  );
}