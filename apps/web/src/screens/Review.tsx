import { useEffect, useState } from "react";
import { useGraphStore } from "../stores";
import { learnerModelApi, quizApi } from "../api";
import type { LearnerModelDto } from "../api";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

interface ReviewCard {
  nodeId: string;
  label: string;
  oneLiner: string;
  details: string;
  correct: boolean | null;
}

export function ReviewScreen() {
  const { topicId, nodes, loadTopic } = useGraphStore();

  const [cards, setCards] = useState<ReviewCard[]>([]);
  const [current, setCurrent] = useState(0);
  const [revealed, setRevealed] = useState(false);
  const [data, setData] = useState<LearnerModelDto | null>(null);
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!topicId) return;
    setLoading(true);
    setError(null);
    try {
      const d = await learnerModelApi.get(topicId);
      setData(d);
      const ids = [...d.dueConcepts];
      for (const w of d.weakConcepts) if (!ids.includes(w)) ids.push(w);
      const unique = ids.filter((id) => nodes.some((n) => n.id === id));
      setCards(unique.map((id) => {
        const n = nodes.find((x) => x.id === id)!;
        return { nodeId: id, label: n.label, oneLiner: n.oneLiner, details: n.details, correct: null };
      }));
      setCurrent(0);
      setRevealed(false);
      setDone(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось загрузить повторение");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load() пересоздаётся каждый рендер; нужен только при смене topicId.
  }, [topicId]);

  function mark(correct: boolean) {
    const next = [...cards];
    next[current] = { ...next[current], correct };
    setCards(next);
    setRevealed(false);
    if (current < cards.length - 1) {
      setCurrent(current + 1);
    } else {
      setDone(true);
    }
  }

  async function finish() {
    if (!topicId) return;
    setBusy(true);
    setError(null);
    const results = cards.map((c) => ({ nodeId: c.nodeId, correct: c.correct === true }));
    try {
      await quizApi.apply("", topicId, results);
      await loadTopic(topicId).catch(() => {});
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сохранить повторение");
    } finally {
      setBusy(false);
    }
  }

  const card = cards[current];
  const answeredCount = cards.filter((c) => c.correct !== null).length;

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="border-b border-border px-6 py-3">
        <h2 className="text-sm font-semibold text-ink">Повторение</h2>
        <p className="text-xs text-ink-4">Вспомните понятия, требующие повторения.</p>
      </div>

      <div className="flex-1 px-6 py-6">
        <ErrorBanner message={error} />

        {loading && !cards.length && (
          <div className="flex justify-center py-16"><Spinner /></div>
        )}

        {!loading && cards.length === 0 && (
          <div className="mx-auto max-w-xl rounded-xl border border-border bg-surface p-8 text-center text-ink-4">
            Нет понятий, требующих повторения. Отличная работа!
            <div className="mt-4"><Button variant="secondary" onClick={() => void load()}>Обновить</Button></div>
          </div>
        )}

        {data && cards.length > 0 && (
          <div className="mx-auto max-w-2xl">
            {!done ? (
              <>
                <div className="mb-4 flex items-center justify-between text-xs text-ink-4">
                  <span>Карточка {current + 1} / {cards.length}</span>
                  <span>
                    <Badge variant="info">К повторению: {data.dueConcepts.length}</Badge>
                  </span>
                </div>
                <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-surface-2">
                  <div className="h-full rounded-full bg-accent" style={{ width: `${((current + 1) / cards.length) * 100}%` }} />
                </div>

                <div className="rounded-xl border border-border bg-surface p-6">
                  <h3 className="mb-3 text-lg font-bold text-ink">{card.label}</h3>

                  {!revealed ? (
                    <>
                      <p className="text-sm text-ink-4">
                        Попробуйте вспомнить, что означает это понятие, затем откройте ответ и оцените себя.
                      </p>
                      <div className="mt-4">
                        <Button variant="secondary" onClick={() => setRevealed(true)}>Показать ответ</Button>
                      </div>
                    </>
                  ) : (
                    <div className="space-y-3">
                      <p className="whitespace-pre-wrap text-sm text-ink-2">{card.oneLiner || "Нет краткого описания."}</p>
                      {card.details && (
                        <details className="rounded-lg border border-border">
                          <summary className="cursor-pointer p-2 text-sm text-ink-3">Подробнее</summary>
                          <div className="border-t border-border px-3 pb-3 pt-2 text-sm text-ink-4">{card.details}</div>
                        </details>
                      )}
                      <div className="flex gap-3 pt-2">
                        <Button variant="secondary" className="flex-1" onClick={() => mark(false)}>Вспомнил неточно</Button>
                        <Button className="flex-1" onClick={() => mark(true)}>Вспомнил верно</Button>
                      </div>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <div className="rounded-xl border border-border bg-surface p-8 text-center">
                <p className="text-lg font-semibold text-ink">Повторение завершено</p>
                <p className="mt-1 text-sm text-ink-4">
                  Отвечено: {answeredCount} из {cards.length}.
                </p>
                <div className="mt-4">
                  <Button disabled={busy} onClick={() => void finish()}>Сохранить результаты</Button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
