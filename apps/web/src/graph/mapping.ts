import type { KnowledgeNode } from "@mindtree/types";
import type { KnowledgeNodeRow } from "../api/types";

function parseRelations(json?: string | null): KnowledgeNode["relations"] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? (parsed as KnowledgeNode["relations"]) : [];
  } catch {
    return [];
  }
}

function parseSources(json?: string | null): string[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}

export function rowToKnowledgeNode(row: KnowledgeNodeRow): KnowledgeNode {
  const sources = parseSources(row.sources_json);
  return {
    id: row.id,
    topicId: row.topic_id,
    parentId: row.parent_id,
    level: row.level,
    label: row.label,
    oneLiner: row.one_liner,
    details: row.details,
    analogy: row.analogy ?? undefined,
    sources: sources.length > 0 ? sources : undefined,
    conceptType: (row.concept_type as KnowledgeNode["conceptType"]) ?? undefined,
    importance: row.importance,
    difficulty: row.difficulty,
    estimatedTimeMinutes: row.estimated_time_minutes,
    state: row.state as KnowledgeNode["state"],
    contentLoaded: row.content_loaded === 1,
    leaf: row.leaf === 1,
    relations: parseRelations(row.relations_json),
    sequences: [],
  };
}

export function rowsToKnowledgeNodes(rows: KnowledgeNodeRow[]): KnowledgeNode[] {
  return rows.map(rowToKnowledgeNode);
}
