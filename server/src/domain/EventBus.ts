import type { LearningEventType } from "@mindtree/types";
import { getDb } from "../db/connection.js";
import { shortIdWith } from "./shortIds.js";

export interface LearningEventInput {
  sessionId: string;
  topicId: string;
  /** Типизирован видом события: опечатку в `kind` ловит компилятор. */
  kind: LearningEventType;
  nodeId?: string;
  payload?: Record<string, unknown>;
  durationMs?: number;
}

export class EventBus {
  private static db = () => getDb();

  /**
   * Отметки начала текущей единицы работы (шаг активности либо пункт
   * curriculum) по sessionId. Нужны, чтобы события, закрывающие единицу, несли
   * реальную длительность: сумма duration_ms по сессии = время изучения, на
   * котором считаются ETA и аналитика. Зеркало `markUnitStart`/`closeUnit`
   * в `lib/domain/engines/event_bus.dart` (mindtree_flutter).
   */
  private static unitStarts = new Map<string, number>();

  /** Запомнить момент старта единицы работы в сессии. */
  static markUnitStart(sessionId: string): void {
    this.unitStarts.set(sessionId, Date.now());
  }

  /**
   * Закрыть единицу работы: вернуть прошедшие миллисекунды и снять отметку,
   * чтобы следующая единица стартовала с текущего момента.
   * 0 — если отметки нет или системные часы ушли назад. Без исключений.
   */
  static closeUnit(sessionId: string): number {
    const start = this.unitStarts.get(sessionId);
    if (start === undefined) return 0;
    this.unitStarts.delete(sessionId);
    const elapsed = Date.now() - start;
    return elapsed > 0 ? elapsed : 0;
  }

  static emit(ev: LearningEventInput): string {
    // `id` обязан писаться явно: колонка объявлена `TEXT PRIMARY KEY` без
    // NOT NULL, и SQLite молча подставляет NULL — события, эмитнутые через
    // EventBus, сохранялись без идентификатора. Генератор общий с Flutter
    // (`shortIds.ts` ↔ `short_ids.dart`), поэтому два стека дают один формат id.
    const id = shortIdWith("ev_");
    this.db()
      .prepare(
        `INSERT INTO learning_events (id, session_id, node_id, type, data_json, duration_ms)
         VALUES (?,?,?,?,?,?)`,
      )
      .run(
        id,
        ev.sessionId,
        ev.nodeId ?? null,
        ev.kind,
        JSON.stringify(ev.payload ?? {}),
        ev.durationMs ?? 0,
      );
    return id;
  }

  static recent(topicId: string, kinds: string[], limit = 20): Array<Record<string, unknown>> {
    const marks = kinds.map(() => "?").join(",");
    const rows = this.db()
      .prepare(
        `SELECT e.* FROM learning_events e
         JOIN learning_sessions s ON s.id = e.session_id
         WHERE s.topic_id = ? AND e.type IN (${marks})
         ORDER BY e.timestamp DESC LIMIT ?`,
      )
      .all(topicId, ...kinds, limit);
    return rows.map((r: unknown) => {
      const row = r as Record<string, unknown>;
      return {
        ...row,
        data_json: row.data_json ? JSON.parse(String(row.data_json)) : {},
      };
    });
  }
}
