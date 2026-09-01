import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

interface CacheEntry<T = unknown> {
  value: T;
  expiresAt: number;
}

interface StoredEntry {
  key: string;
  value: unknown;
  expiresAt: number;
  createdAt: number;
}

export interface CacheConfig {
  maxEntries?: number;
  ttlMs?: number;
  persistDir?: string | null;
}

const DEFAULT_TTL_MS = 24 * 60 * 60 * 1000;
const DEFAULT_MAX_ENTRIES = 1000;

export class LLMCache {
  private store = new Map<string, CacheEntry>();
  private hits = 0;
  private misses = 0;
  private maxEntries: number;
  private ttlMs: number;
  protected persistDir: string | null;

  constructor(config?: CacheConfig) {
    this.maxEntries = config?.maxEntries ?? DEFAULT_MAX_ENTRIES;
    this.ttlMs = config?.ttlMs ?? DEFAULT_TTL_MS;
    this.persistDir = config?.persistDir === undefined ? null : config.persistDir;
    if (this.persistDir) this.loadFromDisk();
  }

  static buildKey(params: {
    model: string;
    operation: string;
    promptVersion: string;
    contextHash: string;
  }): string {
    return `${params.model}|${params.operation}|${params.promptVersion}|${params.contextHash}`;
  }

  get<T>(key: string): T | null {
    const entry = this.store.get(key);
    if (!entry) {
      this.misses++;
      return null;
    }
    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      this.deleteFile(key);
      this.misses++;
      return null;
    }
    this.hits++;
    return entry.value as T;
  }

  set(key: string, value: unknown, ttlMs?: number): void {
    if (this.store.size >= this.maxEntries && !this.store.has(key)) {
      this.evictOldest();
    }
    const expiresAt = Date.now() + (ttlMs ?? this.ttlMs);
    this.store.set(key, { value, expiresAt });
    if (this.persistDir) this.writeFile(key, value, expiresAt);
  }

  has(key: string): boolean {
    const entry = this.store.get(key);
    if (!entry) return false;
    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      this.deleteFile(key);
      return false;
    }
    return true;
  }

  invalidate(pattern?: string): void {
    if (!pattern) {
      const keys = [...this.store.keys()];
      this.store.clear();
      for (const key of keys) this.deleteFile(key);
      return;
    }
    for (const key of this.store.keys()) {
      if (key.includes(pattern)) {
        this.store.delete(key);
        this.deleteFile(key);
      }
    }
  }

  stats(): { hits: number; misses: number; size: number } {
    return { hits: this.hits, misses: this.misses, size: this.store.size };
  }

  private evictOldest(): void {
    const first = this.store.keys().next().value;
    if (first !== undefined) {
      this.store.delete(first);
      this.deleteFile(first);
    }
  }

  private loadFromDisk(): void {
    if (!this.persistDir) return;
    let dir: string;
    try {
      dir = resolve(this.persistDir);
      if (!existsSync(dir)) return;
    } catch {
      return;
    }

    let files: string[];
    try {
      files = readdirSync(dir).filter((f) => f.endsWith(".json"));
    } catch {
      return;
    }

    const now = Date.now();
    for (const file of files) {
      try {
        const raw = readFileSync(join(dir, file), "utf-8");
        const parsed = JSON.parse(raw) as StoredEntry;
        if (
          typeof parsed?.key !== "string" ||
          typeof parsed?.expiresAt !== "number" ||
          parsed.expiresAt <= now
        ) {
          continue;
        }
        if (!this.store.has(parsed.key)) {
          this.store.set(parsed.key, { value: parsed.value, expiresAt: parsed.expiresAt });
        }
      } catch {
        // skipped
      }
    }
  }

  private writeFile(key: string, value: unknown, expiresAt: number): void {
    if (!this.persistDir) return;
    try {
      const dir = resolve(this.persistDir);
      if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
      const entry: StoredEntry = {
        key,
        value,
        expiresAt,
        createdAt: Date.now(),
      };
      writeFileSync(join(dir, `${fileNameForKey(key)}.json`), JSON.stringify(entry), "utf-8");
    } catch {
      // ignore
    }
  }

  private deleteFile(key: string): void {
    if (!this.persistDir) return;
    try {
      const path = join(resolve(this.persistDir), `${fileNameForKey(key)}.json`);
      if (existsSync(path)) rmSync(path);
    } catch {
      // ignore
    }
  }
}

function fileNameForKey(key: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36) + "-" + key.length.toString(36);
}

function hashString(str: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36);
}

export function contextHash(data: unknown): string {
  return hashString(JSON.stringify(data));
}
