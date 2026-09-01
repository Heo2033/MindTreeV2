import { getDb } from "../db/connection.js";

export interface LearningEventInput {
  sessionId: string;
  topicId: string;
  kind: string;
  nodeId?: string;
  payload?: Record<string, unknown>;
  durationMs?: number;
}

export class EventBus {
  private static db = () => getDb();

  static emit(ev: LearningEventInput): void {
    this.db()
      .prepare(
        `INSERT INTO learning_events (session_id, node_id, type, data_json, duration_ms)
         VALUES (?,?,?,?,?)`,
      )
      .run(
        ev.sessionId,
        ev.nodeId ?? null,
        ev.kind,
        JSON.stringify(ev.payload ?? {}),
        ev.durationMs ?? 0,
      );
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
