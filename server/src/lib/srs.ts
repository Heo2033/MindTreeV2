export interface SrsState {
  interval: number;
  ease: number;
  reps: number;
  dueAt: string;
}

const MIN_EASE = 1.3;
const MAX_EASE = 2.8;

export function createSrsState(): SrsState {
  return { interval: 0, ease: 2.5, reps: 0, dueAt: new Date().toISOString() };
}

/**
 * SM-2-подобный интервальный повтор.
 * correct: interval 1 → 3 → interval*ease; ease ±0.1 (clamp 1.3–2.8).
 * incorrect: interval сброс в 0, ease −0.2.
 */
export function scheduleReview(
  prev: SrsState | null,
  quality: "correct" | "incorrect" | "again",
): SrsState {
  if (!prev) prev = createSrsState();

  if (quality === "incorrect" || quality === "again") {
    return {
      interval: 0,
      ease: Math.max(MIN_EASE, prev.ease - 0.2),
      reps: 0,
      dueAt: new Date().toISOString(),
    };
  }

  let interval: number;
  if (prev.reps === 0) interval = 1;
  else if (prev.reps === 1) interval = 3;
  else interval = Math.round(prev.interval * prev.ease);

  const ease = Math.min(MAX_EASE, prev.ease + 0.1);

  const due = new Date();
  due.setDate(due.getDate() + interval);

  return {
    interval,
    ease,
    reps: prev.reps + 1,
    dueAt: due.toISOString(),
  };
}

export function isDue(state: SrsState | null): boolean {
  if (!state) return true;
  return new Date(state.dueAt).getTime() <= Date.now();
}

/** Mastery приблизительно: interval / 21, clamp 0..1. */
export function estimateMastery(state: SrsState | null): number {
  if (!state || state.reps === 0) return 0;
  return Math.min(1, state.interval / 21);
}
