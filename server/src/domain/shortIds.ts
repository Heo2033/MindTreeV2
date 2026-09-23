/**
 * Короткие уникальные суффикс-id. Зеркало `lib/domain/lib/short_ids.dart`
 * (mindtree_flutter) — 1:1. Используется для id записей вне дерева знаний
 * (curriculum items, milestones, сессии, assessment'ы, попытки, вопросы).
 *
 * Та же проблема, что решали в Flutter: генераторы `_shortId()`/`_randomSuffix()`
 * на основе хвоста timestamp + random обрезали случайный суффикс и давали
 * одинаковые id в один миллисекундный тик. Здесь уникальность ВНУТРИ процесса/
 * прохода гарантирует атомарный счётчик (5 младших знаков из 8, до 60_466_176
 * значений подряд без повтора); старшие 3 знака — случайные, чтобы снизить
 * коллизии с id из прошлых запусков (межпроцессная детерминированность не
 * требуется, запрещены лишь коллизии в одном вызове).
 *
 * Node.js однопоточный — модульный счётчик атомарен без lock'ов.
 */

const BASE = 60466176; // 36^5
const RAND_BASE = 46656; // 36^3

let counter = Math.floor(Math.random() * BASE); // стартовая фаза, как в Dart

/** Уникальный 8-символьный суффикс (алфавит base36: 0-9a-z). */
export function shortId(): string {
  counter = (counter + 1) % BASE;
  const counterPart = counter.toString(36).padStart(5, "0");
  const randomPart = Math.floor(Math.random() * RAND_BASE).toString(36).padStart(3, "0");
  return `${randomPart}${counterPart}`;
}

/** Готовый уникальный id с префиксом: `ci_`, `ms_`, `session_`, ... */
export function shortIdWith(prefix: string): string {
  return `${prefix}${shortId()}`;
}