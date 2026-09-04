import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useGraphStore } from "../stores";
import { diagnosticApi } from "../api";
import type { DiagnosticQuestionDto, DiagnosticResultDto } from "../api";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

type Phase = "idle" | "loading" | "playing" | "result";

const LEVEL_LABEL: Record<string, string> = {
  awareness: "Ознакомление",
  basic_understanding: "Базовое понимание",
  solid_understanding: "Уверенное понимание",
  practical_application: "Практическое применение",
  advanced: "Продвинутый",
  expert: "Эксперт",
};

export function DiagnosticScreen() {
  const { topicId, topicName } = useGraphStore();
  const navigate = useNavigate();

  const [phase, setPhase] = useState<Phase>("idle");
  const [questions, setQuestions] = useState<DiagnosticQuestionDto[]>([]);
  const [current, setCurrent] = useState(0);
  const [answers, setAnswers] = useState<(number | null)[]>([]);
  const [result, setResult] = useState<DiagnosticResultDto | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function start() {
    if (!topicId) return;
    setPhase("loading");
    setError(null);
    setResult(null);
    try {
      const { questions: qs } = await diagnosticApi.generate(topicId);
      setQuestions(qs);
      setAnswers(new Array(qs.length).fill(null));
      setCurrent(0);
      setPhase(qs.length ? "playing" : "result");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сгенерировать диагностику");
      setPhase("idle");
    }
  }

  const select = (i: number) => {
    if (answers[current] !== null) return;
    const next = [...answers];
    next[current] = i;
    setAnswers(next);
  };

  async function submit() {
    if (!topicId) return;
    setBusy(true);
    setError(null);
    const payload = questions
      .map((q, i) => ({
        questionId: q.id,
        nodeId: q.nodeId,
        selectedIndex: answers[i] ?? -1,
        correctIndex: q.correctIndex,
      }))
      .filter((a) => a.selectedIndex >= 0);
    try {
      const res = await diagnosticApi.evaluate(topicId, payload);
      setResult(res);
      setPhase("result");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось оценить диагностику");
    } finally {
      setBusy(false);
    }
  }

  if (phase === "idle") {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
        <h2 className="text-xl font-bold text-ink">Диагностика {topicName ? `· ${topicName}` : ""}</h2>
        <p className="max-w-md text-sm text-ink-4">
          Быстрая проверка текущего уровня знаний по теме. Результат определит отправную точку для учебного пути.
        </p>
        <ErrorBanner message={error} />
        <Button onClick={() => void start()}>Начать диагностику</Button>
      </div>
    );
  }

  if (phase === "loading") {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4">
        <Spinner />
        <p className="text-sm text-ink-4">Генерируем вопросы…</p>
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
                <p className="text-sm text-ink-4">Текущий уровень</p>
                <p className="mt-1 text-2xl font-bold text-accent-ink">{LEVEL_LABEL[result.currentLevel] ?? result.currentLevel}</p>
                <div className="mx-auto mt-3 max-w-xs">
                  <div className="h-2 overflow-hidden rounded-full bg-surface-2">
                    <div className="h-full rounded-full bg-accent" style={{ width: `${Math.round(result.score * 100)}%` }} />
                  </div>
                  <p className="mt-1 text-xs text-ink-4">{Math.round(result.score * 100)}% верных ответов</p>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-xl border border-ok bg-ok-soft p-4">
                  <p className="text-xs text-ok">Известные понятия</p>
                  <p className="mt-1 text-2xl font-bold text-ink">{result.knownConcepts.length}</p>
                </div>
                <div className="rounded-xl border border-danger bg-danger-soft p-4">
                  <p className="text-xs text-danger">Требуют изучения</p>
                  <p className="mt-1 text-2xl font-bold text-ink">{result.unknownConcepts.length}</p>
                </div>
              </div>

              <div className="flex gap-3">
                <Button variant="secondary" className="flex-1" onClick={() => navigate("session")}>
                  Начать сессию
                </Button>
                <Button variant="secondary" className="flex-1" onClick={() => { setPhase("idle"); setQuestions([]); }}>
                  Пройти ещё раз
                </Button>
              </div>
            </div>
          ) : (
            <div className="rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
              Недостаточно данных для диагностики. Убедитесь, что у темы есть узлы с контентом.
              <div className="mt-4"><Button onClick={() => void start()}>Попробовать снова</Button></div>
            </div>
          )}
        </div>
      </div>
    );
  }

  const question = questions[current];

  return (
    <div className="flex h-full items-start justify-center overflow-y-auto p-8">
      <div className="w-full max-w-2xl">
        <div className="mb-4 flex items-center justify-between text-xs text-ink-4">
          <span>Вопрос {current + 1} / {questions.length}</span>
          <span>Диагностика</span>
        </div>
        <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-surface-2">
          <div className="h-full rounded-full bg-accent" style={{ width: `${((current + 1) / questions.length) * 100}%` }} />
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
          <Button className="w-full" disabled={busy} onClick={() => (current < questions.length - 1 ? setCurrent(current + 1) : void submit())}>
            {current < questions.length - 1 ? "Следующий вопрос" : "Завершить и оценить"}
          </Button>
        )}
      </div>
    </div>
  );
}
