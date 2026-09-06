import { useEffect, useState } from "react";
import type { MasteryLevel } from "@mindtree/types";
import { analyticsApi, type TopicMetricsDto } from "../api";
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

function pct(v: number | null | undefined): string {
  if (v === null || v === undefined || !isFinite(v)) return "—";
  return `${Math.round(v * 100)}%`;
}

function minutesLabel(v: number | null | undefined): string {
  if (v === null || v === undefined) return "—";
  if (v < 60) return `${Math.round(v)} мин`;
  return `${(v / 60).toFixed(1)} ч`;
}

function MetricCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface px-4 py-3">
      <div className="text-[11px] uppercase tracking-wide text-ink-4">{label}</div>
      <div className="mt-1 text-xl font-semibold text-ink">{value}</div>
      {sub && <div className="mt-0.5 text-xs text-ink-4">{sub}</div>}
    </div>
  );
}

export function AnalyticsScreen() {
  const { topicId } = useGraphStore();
  const [data, setData] = useState<TopicMetricsDto | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!topicId) return;
    setLoading(true);
    setError(null);
    try {
      setData(await analyticsApi.topic(topicId));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Ошибка загрузки метрик");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load() создаётся заново каждый рендер; добавление в deps вызовет шторм запросов.
  }, [topicId]);

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="border-b border-border px-6 py-3">
        <h2 className="text-sm font-semibold text-ink">Метрики обучения</h2>
        <p className="text-xs text-ink-4">
          Реальный учебный прогресс (§71): освоение, точность, время до цели.
        </p>
      </div>

      <div className="flex-1 px-6 py-6">
        {error && <div className="mb-4"><ErrorBanner message={error} /></div>}
        {loading && !data && (
          <div className="flex justify-center py-16"><Spinner /></div>
        )}

        {data && (
          <div className="mx-auto max-w-4xl space-y-6">
            <div className="flex flex-wrap items-center gap-3">
              <Badge variant={data.masteryReached ? "success" : "info"}>
                {LEVEL_LABEL[data.currentLevel]}
                {data.masteryReached ? " · цель достигнута" : ""}
              </Badge>
              <span className="text-xs text-ink-4">
                Цель: {LEVEL_LABEL[data.targetLevel]} · понятий: {data.conceptCount}
              </span>
            </div>

            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              <MetricCard
                label="Learning Gain"
                value={`+${Math.round(data.learningGain * 100)}`}
                sub={`к уровню «${LEVEL_LABEL[data.currentLevel]}»`}
              />
              <MetricCard
                label="Gain / час"
                value={data.learningGainPerMinute.toFixed(2)}
              />
              <MetricCard
                label="Ср. освоение"
                value={pct(data.meanMastery)}
                sub={`время ${minutesLabel(data.studyMinutes)}`}
              />
              <MetricCard
                label="Время до цели"
                value={minutesLabel(data.timeToTargetMinutes)}
                sub={data.masteryReached ? "достигнуто" : "ещё не достигнуто"}
              />
            </div>

            <section>
              <h3 className="mb-3 text-sm font-semibold text-ink">Точность по типам</h3>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <MetricCard
                  label="Immediate Recall"
                  value={pct(data.immediateRecall)}
                  sub="воспроизведение сразу после изучения"
                />
                <MetricCard
                  label="Delayed Recall"
                  value={pct(data.delayedRecall)}
                  sub="отложенное воспроизведение"
                />
                <MetricCard
                  label="Application"
                  value={pct(data.applicationAccuracy)}
                  sub="применение в новых ситуациях"
                />
                <MetricCard
                  label="Transfer"
                  value={pct(data.transferAccuracy)}
                  sub="перенос знаний"
                />
              </div>
            </section>

            <section>
              <h3 className="mb-3 text-sm font-semibold text-ink">Прогресс</h3>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <MetricCard
                  label="Завершение сессий"
                  value={pct(data.sessionCompletion)}
                  sub="доля доведённых до конца"
                />
                <MetricCard
                  label="Путь (milestones)"
                  value={pct(data.milestoneProgression)}
                  sub="пройдено вех"
                />
              </div>
            </section>
          </div>
        )}
      </div>
    </div>
  );
}
