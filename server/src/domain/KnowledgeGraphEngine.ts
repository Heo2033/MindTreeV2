import type { KnowledgeNode } from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildStructurePrompt,
  type IStructurePromptOptions,
} from "../prompts/structure.js";
import { buildExpandPrompt } from "../prompts/expand.js";
import {
  buildValidatePrompt,
  parseValidationResult,
  type ValidationNode,
  type ValidationIssueType,
} from "../prompts/validate.js";
import {
  buildRepairPrompt,
  type ProblemNode,
} from "../prompts/repair.js";

export interface NodeDraft {
  id: string;
  title: string;
  parentId: string | null;
  level: number;
  canonical_definition?: string;
  semantic_axis?: string;
  conceptType?: string;
  forbidden_interpretations?: string[];
}

export interface TreeBuildResult {
  nodes: NodeDraft[];
  warnings: string[];
}

export interface ProgressCallback {
  (phase: string, message: string, stats?: { total: number; depth: number; leaves: number }): void;
}

const MAX_DEPTH = 5;

export class KnowledgeGraphEngine {
  /**
   * Полный конвейер: structure → expand → validate → repair → content.
   * content генерируется лениво (just-in-time), здесь строится скелет с контентом верхних уровней.
   */
  async generate(
    query: string,
    options: { goal?: string; level?: string } = {},
    onProgress?: ProgressCallback,
  ): Promise<TreeBuildResult> {
    const scheduler = getScheduler();
    const warnings: string[] = [];

    onProgress?.("structure", "Генерация скелета дерева знаний...");
    let nodes: NodeDraft[] = [];
    try {
      const structurePrompt = buildStructurePrompt(query, {
        goal: options.goal as IStructurePromptOptions["goal"],
        level: options.level as IStructurePromptOptions["level"],
      });
      const { result } = await scheduler.execute(
        "structure",
        () => structurePrompt,
        (raw) => {
          const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
          return Array.isArray(data?.nodes) ? data.nodes : [];
        },
      );
      nodes = normalizeDrafts(result);
    } catch (err) {
      throw new Error(
        `Не удалось построить дерево: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    // expand to depth
    let maxLevel = maxLevelOf(nodes);
    onProgress?.("expand", "Углубление веток...");
    try {
      for (let level = maxLevel; level < MAX_DEPTH; level++) {
        const expandable = nodes.filter((n) => n.level === level && needsExpand(n));
        if (expandable.length === 0) break;
        const expanded = await this.expandNodes(query, nodes, expandable, onProgress);
        if (expanded.length > 0) {
          nodes = [...nodes, ...expanded];
          maxLevel = maxLevelOf(nodes);
        } else {
          break;
        }
      }
    } catch (err) {
      warnings.push(`Углубление не завершено: ${err instanceof Error ? err.message : String(err)}`);
    }

    // validate
    onProgress?.("validate", "Проверка дерева на дубли и структуру...");
    try {
      const validation = await this.validate(nodes);
      if (!validation.valid) {
        onProgress?.("repair", "Исправление проблем дерева...");
        const repaired = await this.repair(validation.issues, nodes);
        if (repaired.repairedNodes.length > 0) {
          nodes = mergeRepairs(nodes, repaired.repairedNodes);
        }
        if (repaired.warnings.length > 0) warnings.push(...repaired.warnings);
      }
    } catch (err) {
      warnings.push(`Валидация не завершена: ${err instanceof Error ? err.message : String(err)}`);
    }

    onProgress?.("content", "Заполнение контента узлов...");
    try {
      const withContent = await this.fillTopLevelContent(query, nodes, options.level, onProgress);
      nodes = withContent;
    } catch (err) {
      warnings.push(`Контент заполнен не полностью: ${err instanceof Error ? err.message : String(err)}`);
    }

    const stats = {
      total: nodes.length,
      depth: maxLevelOf(nodes),
      leaves: nodes.filter((n) => !nodes.some((c) => c.parentId === n.id)).length,
    };
    onProgress?.("done", "Дерево готово", stats);

    return { nodes, warnings };
  }

  private async expandNodes(
    query: string,
    allNodes: NodeDraft[],
    nodesToExpand: NodeDraft[],
    onProgress?: ProgressCallback,
  ): Promise<NodeDraft[]> {
    const scheduler = getScheduler();
    const paths = new Map<string, string[]>();
    const ctxPaths: string[] = [];

    for (const target of nodesToExpand) {
      const path = buildPath(allNodes, target.id);
      paths.set(target.id, path);
      ctxPaths.push(`${target.title}: ${path.join(" → ")}`);
    }

    const prompt = buildExpandPrompt({
      rootTopic: query,
      contextPaths: ctxPaths,
      nodesToExpand: nodesToExpand.map((n) => ({
        id: n.id,
        title: n.title,
        path: (paths.get(n.id) ?? []).join(" → "),
      })),
    });

    const { result } = await scheduler.execute(
      "expand",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );

    const added: NodeDraft[] = [];
    const targets = new Set(nodesToExpand.map((n) => n.id));
    for (const item of result as unknown[]) {
      const rec = item as Record<string, unknown>;
      if (!rec || typeof rec.id !== "string") continue;
      const parentLevel = allNodes.find((n) => n.id === rec.id)?.level ?? 0;
      const children = Array.isArray(rec.children) ? rec.children : [];
      for (const child of children as unknown[]) {
        const c = child as Record<string, unknown>;
        if (!c || typeof c.id !== "string") continue;
        const level = parentLevel + 1;
        if (level > MAX_DEPTH) continue;
        added.push({
          id: String(c.id),
          title: String(c.title ?? c.label ?? ""),
          parentId: String(rec.id),
          level,
          canonical_definition:
            typeof c.canonical_definition === "string" ? c.canonical_definition : undefined,
          semantic_axis: typeof c.semantic_axis === "string" ? c.semantic_axis : undefined,
          conceptType: typeof c.conceptType === "string" ? c.conceptType : undefined,
          forbidden_interpretations: Array.isArray(c.forbidden_interpretations)
            ? (c.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
            : undefined,
        });
      }
    }
    return added;
  }

  private async validate(nodes: NodeDraft[]): Promise<{
    valid: boolean;
    issues: Array<{ type: ValidationIssueType; node_id: string; reason: string }>;
  }> {
    const scheduler = getScheduler();
    const validationNodes: ValidationNode[] = nodes.map((n) => ({
      id: n.id,
      parentId: n.parentId,
      level: n.level,
      label: n.title,
      one_liner: "",
      semantic_axis: n.semantic_axis,
      canonical_definition: n.canonical_definition,
      conceptType: n.conceptType,
      forbidden_interpretations: n.forbidden_interpretations,
    }));

    const prompt = buildValidatePrompt(validationNodes);
    const { result } = await scheduler.execute(
      "validate",
      () => prompt,
      (raw) => parseValidationResult(parseLLMJson(raw)),
    );

    return {
      valid: result.valid,
      issues: result.issues.map((i) => ({
        type: i.type as ValidationIssueType,
        node_id: i.node_id,
        reason: i.reason,
      })),
    };
  }

  private async repair(
    issues: Array<{ type: ValidationIssueType; node_id: string; reason: string }>,
    nodes: NodeDraft[],
  ): Promise<{ repairedNodes: NodeDraft[]; warnings: string[] }> {
    const scheduler = getScheduler();
    const warnings: string[] = [];
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const issuesByNode = new Map<string, typeof issues>();

    for (const issue of issues) {
      if (!issue.node_id) continue;
      const arr = issuesByNode.get(issue.node_id) ?? [];
      arr.push(issue);
      issuesByNode.set(issue.node_id, arr);
    }

    const problemIds = [...issuesByNode.keys()];
    const problemNodes: ProblemNode[] = [];
    for (const id of problemIds) {
      const node = byId.get(id);
      if (!node) continue;
      problemNodes.push({
        id: node.id,
        parentId: node.parentId,
        level: node.level,
        label: node.title,
        one_liner: "",
        details: "",
        conceptType: node.conceptType,
        semantic_axis: node.semantic_axis,
        canonical_definition: node.canonical_definition,
        forbidden_interpretations: node.forbidden_interpretations,
      });
    }

    const prompt = buildRepairPrompt({
      problemNodes,
      issues: issues.map((i) => ({
        type: i.type,
        node_id: i.node_id,
        reason: i.reason,
      })),
    });

    try {
      const { result } = await scheduler.execute(
        "repair",
        () => prompt,
        (raw) => parseLLMJson<unknown[]>(raw),
      );

      const repaired: NodeDraft[] = (result as unknown[]).map((r) => {
        const rec = r as Record<string, unknown>;
        return {
          id: String(rec.id),
          title: String(rec.label ?? rec.title ?? ""),
          parentId: rec.parentId !== null && rec.parentId !== undefined ? String(rec.parentId) : null,
          level: typeof rec.level === "number" ? rec.level : 1,
          canonical_definition:
            typeof rec.canonical_definition === "string" ? rec.canonical_definition : undefined,
          semantic_axis: typeof rec.semantic_axis === "string" ? rec.semantic_axis : undefined,
          conceptType: typeof rec.conceptType === "string" ? rec.conceptType : undefined,
          forbidden_interpretations: Array.isArray(rec.forbidden_interpretations)
            ? (rec.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
            : undefined,
        };
      });
      return { repairedNodes: repaired, warnings };
    } catch (err) {
      warnings.push(`Ремонт не завершён: ${err instanceof Error ? err.message : String(err)}`);
      return { repairedNodes: [], warnings };
    }
  }

  private async fillTopLevelContent(
    query: string,
    nodes: NodeDraft[],
    level?: string,
    onProgress?: ProgressCallback,
  ): Promise<NodeDraft[]> {
    // For MVP, top-level nodes get one_liner content; deep content is lazy/just-in-time.
    // Content generation is handled by generateNodeContent on demand.
    return nodes;
  }

  async generateNodeContent(
    query: string,
    node: NodeDraft,
    context: {
      nodePath: string[];
      siblings: string[];
      canonical_definition?: string;
      semantic_axis?: string;
      forbidden_interpretations?: string[];
      level?: string;
    },
  ): Promise<{ one_liner: string; details: string; analogy?: string; relations: unknown[] }> {
    const scheduler = getScheduler();
    const { buildContentPrompt } = await import("../prompts/content.js");

    const prompt = buildContentPrompt({
      rootTopic: query,
      nodePath: context.nodePath,
      siblings: context.siblings,
      level: context.level,
      ontologyContext: {
        canonical_definition: context.canonical_definition,
        semantic_axis: context.semantic_axis,
        forbidden_interpretations: context.forbidden_interpretations,
      },
      node: { id: node.id, label: node.title },
    });

    const { result } = await scheduler.execute(
      "content",
      () => prompt,
      (raw) =>
        parseLLMJson<{ one_liner?: string; details?: string; analogy?: string; relations?: unknown[] }>(
          raw,
        ),
    );

    return {
      one_liner: String(result.one_liner ?? node.title),
      details: String(result.details ?? ""),
      analogy: typeof result.analogy === "string" && result.analogy !== "" ? result.analogy : undefined,
      relations: Array.isArray(result.relations) ? result.relations : [],
    };
  }

  /**
   * Углубление ветки для узла, хранящегося в БД: читает узел и соседей,
   * генерирует детей и персистит их в knowledge_nodes.
   */
  async expandNodeFromDb(topicId: string, nodeId: string): Promise<NodeDraft[]> {
    const { getDb } = await import("../db/connection.js");
    const db = getDb();

    const nodeRow = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    if (Number(nodeRow.leaf) === 1) {
      throw new Error("Узел является листом и не требует расширения");
    }
    const nodeLevel = Number(nodeRow.level);
    if (nodeLevel >= MAX_DEPTH) {
      throw new Error(`Достигнута максимальная глубина (${MAX_DEPTH})`);
    }

    const topicRow = db.prepare(`SELECT name FROM topics WHERE id = ?`).get(topicId) as
      | { name: string }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";

    const allRows = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<Record<string, unknown>>;

    const allNodes: NodeDraft[] = allRows
      .map((r) => ({
        id: String(r.id),
        title: String(r.label),
        parentId: r.parent_id ? String(r.parent_id) : null,
        level: Number(r.level),
        conceptType: r.concept_type ? String(r.concept_type) : undefined,
      }))
      .filter((n) => n.id !== "");

    const target = allNodes.find((n) => n.id === nodeId);
    if (!target) throw new Error("Узел не найден");

    const added = await this.expandNodes(
      rootTopic,
      allNodes,
      [target],
    );

    const insert = db.prepare(
      `INSERT OR IGNORE INTO knowledge_nodes
         (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
          estimated_time_minutes, state, content_loaded, leaf, level, created_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    );

    const tx = db.transaction((items: NodeDraft[]) => {
      for (const c of items) {
        const childLevel = nodeLevel + 1;
        const leaf = childLevel >= MAX_DEPTH ? 1 : 0;
        insert.run(
          c.id,
          topicId,
          nodeId,
          c.title.trim(),
          "",
          c.conceptType ? String(c.conceptType) : null,
          0.5,
          0.5,
          5,
          "structure_generated",
          0,
          leaf,
          childLevel,
          new Date().toISOString(),
        );
      }
      // update parent state
      db.prepare("UPDATE knowledge_nodes SET state = 'expanded' WHERE id = ?").run(nodeId);
    });

    tx(added);
    return added;
  }

  /**
   * Ленивая генерация контента для узла в БД: генерирует one_liner/details/analogy
   * и персистит их, помечая content_loaded.
   */
  async generateNodeContentFromDb(topicId: string, nodeId: string, level?: string): Promise<{
    one_liner: string;
    details: string;
    analogy?: string;
    relations: unknown[];
  }> {
    const { getDb } = await import("../db/connection.js");
    const db = getDb();

    const nodeRow = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    const topicRow = db.prepare(`SELECT name FROM topics WHERE id = ?`).get(topicId) as
      | { name: string }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";

    const allRows = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<Record<string, unknown>>;

    const path = this.nodePathFromRows(allRows, nodeId);
    const parentId = nodeRow.parent_id ? String(nodeRow.parent_id) : null;
    const siblings = parentId
      ? allRows
          .filter((r) => String(r.parent_id ?? "") === parentId && String(r.id) !== nodeId)
          .map((r) => String(r.label))
          .slice(0, 8)
      : [];

    const content = await this.generateNodeContent(rootTopic, {
      id: nodeId,
      title: String(nodeRow.label),
      parentId,
      level: Number(nodeRow.level),
    }, {
      nodePath: path,
      siblings,
      canonical_definition:
        typeof nodeRow.one_liner === "string" && nodeRow.one_liner !== ""
          ? String(nodeRow.one_liner)
          : undefined,
      semantic_axis: nodeRow.concept_type ? String(nodeRow.concept_type) : undefined,
      level,
    });

    db.prepare(
      `UPDATE knowledge_nodes SET one_liner = ?, details = ?, analogy = ?, relations_json = ?,
         state = 'content_generated', content_loaded = 1
       WHERE id = ?`,
    ).run(
      content.one_liner,
      content.details,
      content.analogy ?? null,
      JSON.stringify(content.relations),
      nodeId,
    );

    return content;
  }

  private nodePathFromRows(rows: Array<Record<string, unknown>>, nodeId: string): string[] {
    const byId = new Map(rows.map((r) => [String(r.id), r]));
    const path: string[] = [];
    let current = byId.get(nodeId);
    let guard = 0;
    while (current && guard < 50) {
      path.unshift(String(current.label));
      current = current.parent_id ? byId.get(String(current.parent_id)) : undefined;
      guard++;
    }
    return path;
  }
}

function normalizeDrafts(raw: unknown[]): NodeDraft[] {
  const drafts: NodeDraft[] = raw.map((r) => {
    const rec = r as Record<string, unknown>;
    return {
      id: String(rec.id ?? ""),
      title: String(rec.title ?? rec.label ?? ""),
      parentId: rec.parentId !== null && rec.parentId !== undefined ? String(rec.parentId) : null,
      level: typeof rec.level === "number" ? rec.level : guessLevel(rec),
      canonical_definition:
        typeof rec.canonical_definition === "string" ? rec.canonical_definition : undefined,
      semantic_axis: typeof rec.semantic_axis === "string" ? rec.semantic_axis : undefined,
      conceptType: typeof rec.conceptType === "string" ? rec.conceptType : undefined,
      forbidden_interpretations: Array.isArray(rec.forbidden_interpretations)
        ? (rec.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
        : undefined,
    };
  });

  // fix levels via DFS from root
  const byId = new Map(drafts.map((d) => [d.id, d]));
  const roots = drafts.filter((d) => !d.parentId);
  const result: NodeDraft[] = [];
  const visited = new Set<string>();

  const visit = (d: NodeDraft, level: number) => {
    if (visited.has(d.id)) return;
    visited.add(d.id);
    const fixed = { ...d, level: d.level || level };
    result.push(fixed);
    const children = drafts
      .filter((c) => c.parentId === d.id)
      .sort((a, b) => a.title.localeCompare(b.title));
    for (const child of children) visit(child, level + 1);
  };

  for (const root of roots) visit(root, 1);

  return result;
}

function guessLevel(rec: Record<string, unknown>): number {
  if (rec.parentId === null || rec.parentId === undefined) return 1;
  return 2;
}

function maxLevelOf(nodes: NodeDraft[]): number {
  return nodes.reduce((max, n) => Math.max(max, n.level), 0);
}

function needsExpand(n: NodeDraft): boolean {
  // heuristic: nodes that seem to be categories need children
  return true;
}

function buildPath(nodes: NodeDraft[], nodeId: string): string[] {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const path: string[] = [];
  let current = byId.get(nodeId);
  let guard = 0;
  while (current && guard < 50) {
    path.unshift(current.title);
    current = current.parentId ? byId.get(current.parentId) : undefined;
    guard++;
  }
  return path;
}

function mergeRepairs(nodes: NodeDraft[], repaired: NodeDraft[]): NodeDraft[] {
  const repairedIds = new Set(repaired.map((r) => r.id));
  return [
    ...nodes.filter((n) => !repairedIds.has(n.id)), // remove repaired nodes
    ...repaired, // add repaired versions
  ];
}
