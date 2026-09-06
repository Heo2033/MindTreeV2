import { useEffect, useState } from "react";
import type { MasteryLevel } from "@mindtree/types";
import { learnerModelApi, type LearnerModelDto } from "../api";
import { useGraphStore } from "../stores";
import { Spinner, ErrorBanner, Badge } from "@mindtree/ui";

const LEVEL_LABEL: Record<MasteryLevel, string> = {
  awareness: "Ознакомление",
  basic_understanding: "Базовое понимание",
  solid_understanding: "Уверенное понимание",
  practical_application: "Практическое применение",
  advanced: "Продвинутый",
  expert: "Эксперт",
};

const DIM_LABEL: Record<string, string> = {
  understanding: "Понимание",
  recall: "Воспроизведение",
  application: "Применение",
  transfer: "Перенос",
};

function Bar({ value, color }: { value: number; color?: string }) {
  const pct = Math.round(value * 100);
  return (
    <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2">
      <div
        className="h-full rounded-full"
        style={{ width: `${pct}%`, backgroundColor: color ?? "#3b82f6" }}
      />
    </div>
  );
}

export function LearnerModelScreen() {
  const { topicId, nodes } = useGraphStore();
  const [data, setData] = useState<LearnerModelDto | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!topicId) return;
    setLoading(true);
    setError(null);
    try {
      setData(await learnerModelApi.get(topicId));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Ошибка загрузки модели ученика");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load() пересоздаётся каждый рендер; нужен только при смене topicId.
  }, [topicId]);

  const labelOf = (id: string) => nodes.find((n) => n.id === id)?.label ?? id.slice(0, 12);

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="border-b border-border px-6 py-3">
        <h2 className="text-sm font-semibold text-ink">Модель ученика</h2>
        <p className="text-xs text-ink-4">Текущий уровень освоения и детализация по узлам темы.</p>
      </div>

      <div className="flex-1 px-6 py-6">
        {error && <div className="mb-4"><ErrorBanner message={error} /></div>}
        {loading && !data && (
          <div className="flex justify-center py-16"><Spinner /></div>
        )}

        {data && (
          <div className="mx-auto max-w-3xl space-y-6">
            <div className="flex items-center gap-3">
              <Badge variant="info">Уровень: {LEVEL_LABEL[data.model.overallLevel]}</Badge>
              <span className="text-xs text-ink-4">
                узлов с оценкой: {data.profiles.length} · слабых: {data.weakConcepts.length} · к повторению: {data.dueConcepts.length}
              </span>
            </div>

            {data.weakConcepts.length > 0 && (
              <section>
                <h3 className="mb-2 text-sm font-semibold text-warn">Слабые места</h3>
                <div className="space-y-2">
                  {data.weakConcepts.map((id) => {
                    const p = data.profiles.find((x) => x.nodeId === id);
                    return (
                      <div key={id} className="flex items-center gap-3 rounded-lg border border-border bg-surface px-4 py-2">
                        <span className="min-w-0 flex-1 truncate text-sm text-ink-2">{labelOf(id)}</span>
                        <Bar value={p?.masteryScore ?? 0} color="#f59e0b" />
                        <span className="w-10 text-right text-xs text-ink-4">{Math.round((p?.masteryScore ?? 0) * 100)}%</span>
                      </div>
                    );
                  })}
                </div>
              </section>
            )}

            {data.dueConcepts.length > 0 && (
              <section>
                <h3 className="mb-2 text-sm font-semibold text-accent-ink">Просрочено повторение</h3>
                <div className="flex flex-wrap gap-2">
                  {data.dueConcepts.map((id) => (
                    <span key={id} className="rounded-full border border-border-strong px-3 py-1 text-xs text-ink-3">
                      {labelOf(id)}
                    </span>
                  ))}
                </div>
              </section>
            )}

            <section>
              <h3 className="mb-3 text-sm font-semibold text-ink">Детализация по узлам</h3>
              {data.profiles.length === 0 ? (
                <p className="text-sm text-ink-4">
                  Пока нет данных. Пройдите тест или завершите сессию, чтобы модель начала заполняться.
                </p>
              ) : (
                <div className="space-y-2">
                  {data.profiles.map((p) => (
                    <div key={p.nodeId} className="rounded-lg border border-border bg-surface p-4">
                      <div className="mb-2 flex items-center justify-between">
                        <span className="text-sm font-medium text-ink-2">{labelOf(p.nodeId)}</span>
                        <span className="text-xs text-ink-4">уверенность {Math.round(p.confidence * 100)}%</span>
                      </div>
                      <div className="space-y-1.5">
                        {(["understanding", "recall", "application", "transfer"] as const).map((d) => (
                          <div key={d} className="flex items-center gap-3">
                            <span className="w-28 shrink-0 text-xs text-ink-4">{DIM_LABEL[d]}</span>
                            <Bar value={p[d]} />
                            <span className="w-8 text-right text-xs text-ink-4">{Math.round(p[d] * 100)}</span>
                          </div>
                        ))}
                      </div>
                      {p.errors.length > 0 && (
                        <div className="mt-3 space-y-1 border-t border-border pt-2">
                          {p.errors.map((e, i) => (
                            <div key={i} className="text-xs text-warn">
                              • {e.description || e.type}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>
        )}
      </div>
    </div>
  );
}
