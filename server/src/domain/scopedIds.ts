import type { NodeDraft } from "./KnowledgeGraphEngine.js";

/**
 * Глобальная уникализация id узлов по теме.
 *
 * LLM по промпту генерирует статичные id (`n1_root`, `n2_<слово>` и т.п.),
 * одинаковые для каждой темы. Так как `knowledge_nodes.id` — это PK всей
 * таблицы, а персист использует `INSERT OR IGNORE`, вторая тема молча не
 * может занять уже занятый id (например корень `n1_root`) — дети записываются,
 * а корень остаётся у старой темы → «пропавший корень» и сироты.
 *
 * Решение: при записи в БД добавляем к id стабильный суффикс от topicId,
 * делая id уникальными в рамках всей БД, и переписываем внутренние ссылки
 * (parentId и relations.from/to), указывающие на узлы той же темы.
 */

const SUFFIX_SEPARATOR = "~";

/** Подпись «~`<hash8>`» по topicId: стабильна и компактна. */
export function scopedSuffix(topicId: string): string {
  return `${SUFFIX_SEPARATOR}${hash8(topicId)}`;
}

/** Добавляет topic-суффикс к «сырому» id (идемпотентно). */
export function scopeId(rawId: string, topicId: string): string {
  const suffix = scopedSuffix(topicId);
  if (rawId.includes(suffix)) return rawId;
  return `${rawId}${suffix}`;
}

/**
 * Переписывает массив узлов темы под scoped-id: id, parentId и relations
 * (from/to), если цель — узел из того же дерева.
 */
export function scopeNodeIds(nodes: NodeDraft[], topicId: string): NodeDraft[] {
  const suffix = scopedSuffix(topicId);
  const rawToScoped = new Map<string, string>();
  for (const n of nodes) {
    const id = String(n.id ?? "");
    if (!id) continue;
    if (!rawToScoped.has(id)) {
      rawToScoped.set(id, id.includes(suffix) ? id : `${id}${suffix}`);
    }
  }
  const remapId = (id: string): string => {
    if (!id) return id;
    const mapped = rawToScoped.get(id);
    if (mapped) return mapped;
    // Уже scoped или id вне партии (например parentId, указывающий на узел
    // другой темы) — оставляем как есть.
    return id;
  };

  return nodes
    .filter((n) => String(n.id ?? "") !== "")
    .map((n) => {
      const id = remapId(String(n.id));
      const parentId = n.parentId && n.parentId !== n.id ? remapId(String(n.parentId)) : null;
      const relations = Array.isArray(n.relations)
        ? n.relations.map((r) => {
            if (r && typeof r === "object" && "to" in r && typeof r.to === "string") {
              return { ...r, from: typeof r.from === "string" ? remapId(r.from) : r.from, to: remapId(r.to) };
            }
            return r;
          })
        : n.relations;
      return { ...n, id, parentId, relations };
    });
}

/** Короткий детерминированный хэш (FNV-1a), как в llm/client.ts. */
function hash8(input: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export type { NodeDraft };