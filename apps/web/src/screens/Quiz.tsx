import { useState } from "react";
import { useGraphStore, useLearnerStore } from "../stores";
import { quizApi } from "../api";
import type { QuizDto } from "../api";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

type Phase = "idle" | "loading" | "playing" | "result";

export function QuizScreen() {
  const { nodes, topicId, topicName } = useGraphStore();
  const submitQuizResults = useLearnerStore((s) => s.submitQuizResults);

  const [phase, setPhase] = useState<Phase>("idle");
  const [quiz, setQuiz] = useState<QuizDto | null>(null);
  const [current, setCurrent] = useState(0);
  const [answers, setAnswers] = useState<(number | null)[]>([]);
  const [revealed, setRevealed] = useState<boolean[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<"learning" | "exam">("learning");
  const [submitting, setSubmitting] = useState(false);

  async function run() {
    if (!topicId) return;
    setError(null);
    setPhase("loading");
    try {
      const nodeIds = nodes.filter((n) => n.contentLoaded).map((n) => n.id);
      const q = await quizApi.generate({ topic_id: topicId, node_ids: nodeIds.length ? nodeIds : undefined });
      setQuiz(q);
      setAnswers(new Array(q.questions.length).fill(null));
      setRevealed(new Array(q.questions.length).fill(false));
      setCurrent(0);
      setPhase("playing");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сгенерировать тест");
      setPhase("playing");
      setQuiz(null);
    }
  }

  const select = (i: number) => {
    if (answers[current] !== null) return;
    const next = [...answers];
    next[current] = i;
    setAnswers(next);
    if (mode === "learning") {
      const r = [...revealed];
      r[current] = true;
      setRevealed(r);
    }
  };

  async function finish() {
    if (!topicId || !quiz) return;
    setSubmitting(true);
    const results = quiz.questions
      .map((q, i) => ({ nodeId: q.nodeId, correct: answers[i] === q.correctIndex }))
      .filter((r) => r.nodeId);
    try {
      await submitQuizResults(topicId);
      // apply to SRS directly
      await quizApi.apply(quiz.id, topicId, results);
    } catch {
      // ignore SRS apply errors
    }
    setSubmitting(false);
    setPhase("result");
  }

  const question = quiz?.questions[current];
  const correctCount =
    quiz?.questions.reduce((sum, q, i) => sum + (answers[i] === q.correctIndex ? 1 : 0), 0) ?? 0;
  const pct = quiz && quiz.questions.length > 0 ? Math.round((correctCount / quiz.questions.length) * 100) : 0;

  if (phase === "idle") {
    return (
      <div className="flex h-full flex-col items-center justify-center p-8">
        <div className="w-full max-w-md rounded-xl border border-border bg-surface p-6 text-center shadow-card">
          <h2 className="text-lg font-bold text-ink">Тест {topicName ? `· ${topicName}` : ""}</h2>
          <p className="mt-1 text-sm text-ink-4">
            {mode === "learning"
              ? "Вопросы с пояснениями — проверьте и закрепите знания по изученным понятиям."
              : "Экзаменационный режим без подсказок. Результат учтётся в модели ученика."}
          </p>
          <div className="mt-4">
            <Button variant="secondary" size="sm" onClick={() => setMode(mode === "learning" ? "exam" : "learning")}>
              {mode === "learning" ? "Экзамен" : "Обучение"}
            </Button>
          </div>
          <ErrorBanner message={error} />
          <Button className="mt-4 w-full" onClick={() => void run()}>
            Начать тест
          </Button>
        </div>
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

  return (
    <div className="flex h-full items-start justify-center overflow-y-auto p-8">
      <div className="w-full max-w-2xl">
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-bold text-ink">Тест {topicName ? `· ${topicName}` : ""}</h2>
            <p className="text-sm text-ink-4">{mode === "learning" ? "Обучение" : "Экзамен"}</p>
          </div>
          <Button variant="secondary" size="sm" onClick={() => setMode(mode === "learning" ? "exam" : "learning")}>
            {mode === "learning" ? "Экзамен" : "Обучение"}
          </Button>
        </div>

        <ErrorBanner message={error} />

        {!quiz || quiz.questions.length === 0 ? (
          <div className="rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
            Не удалось сгенерировать тест. Убедитесь, что у темы есть узлы с контентом.
            <div className="mt-4">
              <Button onClick={() => void run()}>Попробовать снова</Button>
            </div>
          </div>
        ) : phase === "result" ? (
          <div>
            <div className="mb-6 text-center">
              <div className="text-4xl font-bold text-ink">{pct}%</div>
              <div className="mt-2 h-3 overflow-hidden rounded-full bg-surface-2">
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{ width: `${pct}%`, backgroundColor: pct >= 80 ? "#22c55e" : pct >= 50 ? "#eab308" : "#ef4444" }}
                />
              </div>
              <p className="mt-2 text-sm text-ink-4">
                {correctCount} из {quiz.questions.length} верно{pct >= 80 ? " — отлично!" : pct >= 50 ? " — неплохо" : " — стоит повторить"}
              </p>
            </div>
            <div className="mb-6 space-y-2">
              {quiz.questions.map((q, i) => {
                const ok = answers[i] === q.correctIndex;
                return (
                  <details key={q.id} className="rounded-lg border border-border">
                    <summary className="flex cursor-pointer items-center gap-2 p-3 text-sm text-ink-2">
                      <span className={`flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold text-ink ${ok ? "bg-ok" : "bg-danger"}`}>
                        {ok ? "✓" : "✗"}
                      </span>
                      {q.misconception && <Badge variant="warning">Миф</Badge>}
                      <span className="min-w-0 flex-1 truncate">{q.question}</span>
                    </summary>
                    <div className="border-t border-border px-3 pb-3 pt-2 text-xs text-ink-4">
                      <p className="mb-1">Правильный ответ: {String.fromCharCode(65 + q.correctIndex)}) {q.options[q.correctIndex]}</p>
                      {!ok && answers[i] !== null && (
                        <p className="mb-1 text-danger">Ваш ответ: {String.fromCharCode(65 + answers[i]!)}) {q.options[answers[i]!]}</p>
                      )}
                      <p>{q.explanation}</p>
                    </div>
                  </details>
                );
              })}
            </div>
            <div className="flex gap-3">
              <Button variant="secondary" className="flex-1" onClick={() => { setQuiz(null); void run(); }}>Ещё раз</Button>
              <Button className="flex-1" disabled={submitting} onClick={() => setPhase("playing")}>К вопросам</Button>
            </div>
          </div>
        ) : question ? (
          <div>
            <div className="mb-4 flex items-center justify-between text-xs text-ink-4">
              <span>Вопрос {current + 1} / {quiz.questions.length}</span>
              <span>{mode === "learning" ? "Обучение" : "Экзамен"}</span>
            </div>
            <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-surface-2">
              <div className="h-full rounded-full bg-accent" style={{ width: `${((current + 1) / quiz.questions.length) * 100}%` }} />
            </div>

            <div className="mb-4 flex items-start gap-2">
              <p className="flex-1 text-sm font-medium text-ink">{question.question}</p>
              {question.misconception && <Badge variant="warning">Миф</Badge>}
            </div>

            <div className="mb-4 space-y-2">
              {question.options.map((opt, i) => {
                const selected = answers[current] === i;
                const isCorrect = question.correctIndex === i;
                const show = answers[current] !== null && (mode === "learning" || revealed[current]);
                let cls = "w-full rounded-lg border p-3 text-left text-sm transition-all ";
                if (show) {
                  if (isCorrect) cls += "border-ok bg-ok-soft text-ok";
                  else if (selected) cls += "border-danger bg-danger-soft text-danger";
                  else cls += "border-border bg-surface text-ink-4";
                } else if (selected) cls += "border-accent bg-surface-2 text-accent-ink";
                else cls += "border-border-strong bg-surface text-ink-2 hover:border-border-strong hover:bg-surface-2";
                return (
                  <button key={i} className={cls} disabled={answers[current] !== null} onClick={() => select(i)}>
                    <span className="mr-2 font-semibold">{String.fromCharCode(65 + i)})</span>
                    {opt}
                  </button>
                );
              })}
            </div>

            {mode === "learning" && revealed[current] && (
              <div className="mb-4 rounded-lg border border-accent bg-surface-2 p-3 text-sm text-accent-ink">
                💡 {question.explanation}
              </div>
            )}
            {mode === "exam" && answers[current] !== null && (
              <div className="mb-4 text-sm">
                {answers[current] === question.correctIndex ? (
                  <span className="text-ok">✓ Верно</span>
                ) : (
                  <span className="text-danger">✗ Неверно</span>
                )}
              </div>
            )}

            {answers[current] !== null && (
              <Button className="w-full" onClick={() => (current < quiz.questions.length - 1 ? setCurrent(current + 1) : void finish())}>
                {current < quiz.questions.length - 1 ? "Следующий вопрос" : "Завершить тест"}
              </Button>
            )}
          </div>
        ) : null}
      </div>
    </div>
  );
}
