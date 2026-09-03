import Database from "better-sqlite3";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let _db: Database.Database | null = null;

export function initDatabase(): Database.Database {
  if (_db) return _db;
  const dbPath = process.env.DB_PATH || path.resolve(__dirname, "../../data/mindtree.db");

  const dir = path.dirname(dbPath);
  fs.mkdirSync(dir, { recursive: true });

  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");

  migrate(db);

  _db = db;
  return db;
}

export function getDb(): Database.Database {
  if (!_db) _db = initDatabase();
  return _db;
}

function migrate(db: Database.Database) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS topics (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      goal TEXT NOT NULL DEFAULT 'overview',
      target_level TEXT NOT NULL DEFAULT 'basic_understanding',
      time_budget_minutes INTEGER NOT NULL DEFAULT 60,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS knowledge_nodes (
      id TEXT PRIMARY KEY,
      topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
      parent_id TEXT REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
      label TEXT NOT NULL,
      one_liner TEXT NOT NULL DEFAULT '',
      details TEXT NOT NULL DEFAULT '',
      analogy TEXT,
      concept_type TEXT,
      importance REAL DEFAULT 0.5,
      difficulty REAL DEFAULT 0.5,
      estimated_time_minutes INTEGER DEFAULT 5,
      state TEXT NOT NULL DEFAULT 'new',
      content_loaded INTEGER NOT NULL DEFAULT 0,
      leaf INTEGER NOT NULL DEFAULT 0,
      level INTEGER NOT NULL DEFAULT 1,
      relations_json TEXT DEFAULT '[]',
      sequences_json TEXT DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS learning_journeys (
      id TEXT PRIMARY KEY,
      topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS learning_milestones (
      id TEXT PRIMARY KEY,
      journey_id TEXT NOT NULL REFERENCES learning_journeys(id) ON DELETE CASCADE,
      level TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      capabilities_json TEXT DEFAULT '[]',
      estimated_hours REAL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'not_started',
      alternative_paths_json TEXT DEFAULT '[]'
    );

    CREATE TABLE IF NOT EXISTS learning_sessions (
      id TEXT PRIMARY KEY,
      journey_id TEXT NOT NULL REFERENCES learning_journeys(id) ON DELETE CASCADE,
      milestone_id TEXT REFERENCES learning_milestones(id),
      topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
      goal TEXT NOT NULL DEFAULT 'overview',
      time_budget_minutes INTEGER NOT NULL DEFAULT 60,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      completed_at TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      curriculum_json TEXT DEFAULT '{}',
      current_index INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS learning_events (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES learning_sessions(id) ON DELETE CASCADE,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      type TEXT NOT NULL,
      node_id TEXT,
      data_json TEXT DEFAULT '{}',
      duration_ms INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS learner_models (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL DEFAULT 'default',
      topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
      overall_level TEXT NOT NULL DEFAULT 'awareness',
      concept_masteries_json TEXT DEFAULT '[]',
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(user_id, topic_id)
    );

    CREATE TABLE IF NOT EXISTS assessments (
      id TEXT PRIMARY KEY,
      session_id TEXT REFERENCES learning_sessions(id) ON DELETE CASCADE,
      type TEXT NOT NULL DEFAULT 'quiz',
      questions_json TEXT DEFAULT '[]',
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      completed_at TEXT,
      score REAL
    );

    CREATE TABLE IF NOT EXISTS assessment_attempts (
      id TEXT PRIMARY KEY,
      assessment_id TEXT NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
      question_id TEXT NOT NULL,
      answer TEXT NOT NULL,
      correct INTEGER NOT NULL DEFAULT 0,
      time_spent_ms INTEGER DEFAULT 0,
      feedback TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_knowledge_nodes_topic ON knowledge_nodes(topic_id);
    CREATE INDEX IF NOT EXISTS idx_knowledge_nodes_parent ON knowledge_nodes(parent_id);
    CREATE INDEX IF NOT EXISTS idx_learning_sessions_topic ON learning_sessions(topic_id);
    CREATE INDEX IF NOT EXISTS idx_learning_events_session ON learning_events(session_id);
    CREATE INDEX IF NOT EXISTS idx_learner_models_topic ON learner_models(topic_id);
  `);

  ensureColumn(db, "learning_sessions", "activity_json", "TEXT DEFAULT '[]'");
  ensureColumn(db, "learning_sessions", "current_activity_step", "INTEGER DEFAULT 0");
  ensureColumn(db, "knowledge_nodes", "sources_json", "TEXT DEFAULT '[]'");
  ensureColumn(db, "learner_models", "initial_overall_level", "TEXT DEFAULT 'awareness'");
}

function ensureColumn(
  db: Database.Database,
  table: string,
  column: string,
  ddl: string,
) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all() as Array<{
    name: string;
  }>;
  if (!cols.some((c) => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${ddl}`);
  }
}

declare module "fastify" {
  interface FastifyInstance {
    db: Database.Database;
  }
}
