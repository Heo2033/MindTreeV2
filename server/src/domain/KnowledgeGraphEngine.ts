import type {
  KnowledgeNode,
  Relation,
  RelationType,
} from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson, LLMMockError, LLMRetriesExhaustedError } from "../llm/client.js";
import { scopeNodeIds } from "./scopedIds.js";
import {
  buildL1Prompt,
  type IStructurePromptOptions,
} from "../prompts/structure.js";
import { buildL2Prompt } from "../prompts/generateL2.js";
import { buildL3Prompt } from "../prompts/generateL3.js";
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
  /** §20/§52: метаданные для приоритизации и curriculum engine. */
  importance?: number;
  difficulty?: number;
  estimatedMinutes?: number;
  prerequisites?: string[];
  relations?: Relation[];
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
    options: { goal?: string; level?: string; timeBudgetMinutes?: number } = {},
    onProgress?: ProgressCallback,
    onBatch?: (added: NodeDraft[]) => Promise<void>,
  ): Promise<TreeBuildResult> {
    const warnings: string[] = [];
    const opts: IStructurePromptOptions = {
      goal: options.goal as IStructurePromptOptions["goal"],
      level: options.level as IStructurePromptOptions["level"],
      timeBudgetMinutes: options.timeBudgetMinutes,
    };

    // Пошаговый конвейер: L1 (корень) → L2 (разделы) → L3 (подразделы).
    // Каждый шаг — отдельный LLM-запрос с полным семантическим контекстом,
    // что гарантирует логическую согласованность (нет «Виды раскладов» как
    // L2 рядом с L2 «Расклады»). Валидация и ремонт выполняются на каждом этапе.
    let nodes: NodeDraft[] = [];

    // Шаг 1: корень (L1)
    onProgress?.("structure", "Определение корня темы...");
    try {
      const root = await this.generateRoot(query, opts);
      nodes = root;
    } catch (err) {
      const isOffline = err instanceof LLMMockError
        || (err instanceof LLMRetriesExhaustedError && err.lastError instanceof LLMMockError);
      if (isOffline) {
        nodes = fallbackStructure(query);
        warnings.push("Офлайн-режим: построено демо-дерево знаний вместо LLM.");
      } else {
        throw new Error(
          `Не удалось определить корень темы: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    if (!nodes.some((n) => n.level === 1 && !n.parentId)) {
      // Корня нет — без него дерево не построить.
      nodes = fallbackStructure(query);
      warnings.push("Корень темы не был определён; построено демо-дерево.");
    }

    // Инкрементальный персист: корень виден пользователю сразу, пока генерируются
    // следующие уровни. При сбое (закрытие вкладки и т.п.) в БД остаётся
    // сохранённая часть дерева, а не пустота.
    // Важно: dedupeNodeIds вызывается ДО onBatch, чтобы ID были стабильны
    // и reconcileTree в pipeline.ts не удалял инкрементально сохранённые узлы.
    if (onBatch) {
      nodes = dedupeNodeIds(nodes);
      const batch = nodes.filter((n) => n.level === 1 && !n.parentId);
      console.log(`[engine] onBatch L1: ${batch.length} узлов`);
      try {
        await onBatch(batch);
      } catch {
        // Не критично для генерации: финальный persist в route восстановит дерево.
      }
    }

    // Шаг 2: разделы (L2) — один запрос, полный контекст корня.
    onProgress?.("structure", "Генерация главных разделов (уровень 2)...");
    let l2: NodeDraft[] = [];
    try {
      l2 = await this.generateL2FromRoot(query, nodes, opts);
      nodes = nodes.concat(l2);
    } catch (err) {
      warnings.push(`Генерация разделов не завершена: ${err instanceof Error ? err.message : String(err)}`);
    }

    if (onBatch && l2.length > 0) {
      nodes = dedupeNodeIds(nodes);
      const l2Ids = new Set(nodes.filter((n) => n.level === 2).map((n) => n.id));
      const batch = nodes.filter((n) => l2Ids.has(n.id));
      console.log(`[engine] onBatch L2: ${batch.length} узлов`);
      try {
        await onBatch(batch);
      } catch {
        // финальный persist в route восстановит дерево
      }
    }

    // Валидация L1+L2 (и ремонт при необходимости).
    nodes = await this.validateAndRepair(nodes, opts, onProgress, warnings, "validate");

    // Шаг 3: подразделы (L3) — отдельный запрос на каждый L2-раздел,
    // чтобы LLM видел контекст конкретной ветви и не создавал противоречий.
    onProgress?.("structure", "Генерация подразделов (уровень 3)...");
    const l2Nodes = nodes.filter((n) => n.level === 2);
    for (const l2 of l2Nodes) {
      try {
        const l3 = await this.generateL3ForNode(query, l2, nodes, opts);
        if (l3.length > 0) {
          nodes = nodes.concat(l3);
          // Валидация только что созданных L3-детей этой ветви.
          const focusIds = l3.map((n) => n.id);
          nodes = await this.validateAndRepair(
            nodes,
            opts,
            onProgress,
            warnings,
            `validate-l3-${l2.id}`,
            focusIds,
          );
          // Инкрементальный персист L3-ветви: ветка появляется у пользователя
          // по мере завершения, а не только в конце всей генерации.
          if (onBatch) {
            nodes = dedupeNodeIds(nodes);
            const kept = nodes.filter((n) => n.parentId === l2.id && n.level === 3);
            if (kept.length > 0) {
              console.log(`[engine] onBatch L3 (ветка «${l2.title}»): ${kept.length} узлов`);
              await onBatch(kept);
            }
          }
        }
      } catch (err) {
        warnings.push(
          `Подразделы для «${l2.title}» не завершены: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    onProgress?.("content", "Заполнение контента узлов...");
    try {
      const withContent = await this.fillTopLevelContent(query, nodes, options.level, onProgress);
      nodes = withContent;
    } catch (err) {
      warnings.push(`Контент заполнен не полностью: ${err instanceof Error ? err.message : String(err)}`);
    }

    // Финальная дедупликация (на случай, если предыдущие вызовы dedupeNodeIds
    // не покрыли все коллизии — например, между L3-ветками разных L2).
    nodes = dedupeNodeIds(nodes);

    const stats = {
      total: nodes.length,
      depth: maxLevelOf(nodes),
      leaves: nodes.filter((n) => !nodes.some((c) => c.parentId === n.id)).length,
    };
    onProgress?.("done", "Дерево готово", stats);

    return { nodes, warnings };
  }

  /** Генерирует корневой узел (L1) отдельным запросом. */
  private async generateRoot(
    query: string,
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const scheduler = getScheduler();
    const prompt = buildL1Prompt(query, opts);
    const { result } = await scheduler.execute(
      "structure",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 1 && !n.parentId);
  }

  /** Генерирует разделы (L2) с контекстом корня. */
  private async generateL2FromRoot(
    query: string,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const root = current.find((n) => n.level === 1 && !n.parentId);
    if (!root) return [];
    const scheduler = getScheduler();
    const prompt = buildL2Prompt({
      userQuery: query,
      root: {
        id: root.id,
        title: root.title,
        canonical_definition: root.canonical_definition,
      },
      options: opts,
    });
    const { result } = await scheduler.execute(
      "structure-l2",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 2 && n.parentId);
  }

  /** Генерирует подразделы (L3) для одного L2-узла отдельным запросом. */
  private async generateL3ForNode(
    query: string,
    parent: NodeDraft,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const root = current.find((n) => n.level === 1 && !n.parentId);
    const siblings = current
      .filter((n) => n.level === 2 && n.parentId === root?.id && n.id !== parent.id);
    const scheduler = getScheduler();
    const prompt = buildL3Prompt({
      userQuery: query,
      rootTitle: root?.title ?? parent.title,
      parent: {
        id: parent.id,
        title: parent.title,
        canonical_definition: parent.canonical_definition,
        semantic_axis: parent.semantic_axis,
      },
      siblings: siblings.map((s) => ({
        id: s.id,
        title: s.title,
        canonical_definition: s.canonical_definition,
      })),
      options: opts,
    });
    const { result } = await scheduler.execute(
      "structure-l3",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 3 && n.parentId === parent.id);
  }

  /** Валидирует (и ремонтирует) дерево, фокусно — на указанных узлах. */
  private async validateAndRepair(
    nodes: NodeDraft[],
    opts: IStructurePromptOptions,
    onProgress: ProgressCallback | undefined,
    warnings: string[],
    phase: string,
    focusIds?: string[],
  ): Promise<NodeDraft[]> {
    if (nodes.length === 0) return nodes;
    onProgress?.(phase, "Проверка структуры на дубли и логические ошибки...");
    try {
      const validation = await this.validate(nodes, focusIds);
      if (!validation.valid) {
        onProgress?.("repair", "Исправление проблем дерева...");
        const repaired = await this.repair(validation.issues, nodes, opts);
        if (repaired.repairedNodes.length > 0) {
          nodes = mergeRepairs(nodes, repaired.repairedNodes);
        }
        if (repaired.warnings.length > 0) warnings.push(...repaired.warnings);
      }
    } catch (err) {
      warnings.push(`Валидация не завершена: ${err instanceof Error ? err.message : String(err)}`);
    }
    return nodes;
  }

  private async expandNodes(
    query: string,
    allNodes: NodeDraft[],
    nodesToExpand: NodeDraft[],
    onProgress?: ProgressCallback,
    options?: IStructurePromptOptions,
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
      existingTree: allNodes.map((n) => ({
        id: n.id,
        title: n.title,
        parentId: n.parentId,
        level: n.level,
      })),
      options,
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
          ...parseNodeMetadata(c),
        });
      }
    }
    return added;
  }

  private async validate(
    nodes: NodeDraft[],
    focusIds?: string[],
  ): Promise<{
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

    const prompt = buildValidatePrompt(validationNodes, focusIds ? { focusIds } : undefined);
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
    opts?: IStructurePromptOptions,
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
      level: opts?.level,
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
      knowledgeLevel?: string;
      goal?: string;
      nodeLevel?: number;
      isRoot?: boolean;
    },
  ): Promise<{ one_liner: string; details: string; analogy?: string; relations: unknown[]; sources?: string[] }> {
    const scheduler = getScheduler();
    const { buildContentPrompt, isCriticalDomain } = await import("../prompts/content.js");

    const prompt = buildContentPrompt({
      rootTopic: query,
      nodePath: context.nodePath,
      siblings: context.siblings,
      knowledgeLevel: context.knowledgeLevel,
      goal: context.goal,
      nodeLevel: context.nodeLevel,
      isRoot: context.isRoot,
      isCriticalDomain: isCriticalDomain(query, context.nodePath),
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
        parseLLMJson<{ one_liner?: string; details?: string; analogy?: string; relations?: unknown[]; sources?: string[] }>(
          raw,
        ),
    );

    return {
      one_liner: String(result.one_liner ?? node.title),
      details: String(result.details ?? ""),
      analogy: typeof result.analogy === "string" && result.analogy !== "" ? result.analogy : undefined,
      relations: Array.isArray(result.relations) ? result.relations : [],
      sources: Array.isArray(result.sources) ? result.sources.map(String) : [],
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

    const nodeLevel = Number(nodeRow.level);
    if (nodeLevel >= MAX_DEPTH) {
      throw new Error(`Достигнута максимальная глубина (${MAX_DEPTH})`);
    }

    const topicRow = db.prepare(`SELECT name, goal, target_level FROM topics WHERE id = ?`).get(topicId) as
      | { name: string; goal?: string | null; target_level?: string | null }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";
    const expandOptions: IStructurePromptOptions = {
      goal: typeof topicRow?.goal === "string" ? topicRow.goal : undefined,
      level: typeof topicRow?.target_level === "string" ? topicRow.target_level : undefined,
    };

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

    // У узла уже есть дети (в т.ч. скрытые) — не запускаем повторную генерацию.
    // «Углубить» в этом случае раскрывает существующих детей, а не зовёт LLM.
    const hasChildren = allNodes.some((n) => n.parentId === nodeId);
    if (hasChildren) {
      return [];
    }

    const added = await this.expandNodes(
      rootTopic,
      allNodes,
      [target],
      undefined,
      expandOptions,
    );

    // Согласование с полным деревом (§63): отбрасываем дубли уже существующих
    // понятий и коллизии id, чтобы не вносить противоречия.
    const consistent = consistencyCheckAgainstTree(allNodes, added);

    // Уникализация id: LLM может вернуть те же id что и в другой теме.
    // Суффикс topicId делает id глобально уникальными.
    const scoped = scopeNodeIds(consistent.nodes, topicId);

    const insert = db.prepare(
      `INSERT OR IGNORE INTO knowledge_nodes
         (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
          estimated_time_minutes, relations_json, state, content_loaded, leaf, level, created_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    );

    const relationByTo = new Map<string, Relation[]>();
    for (const c of scoped) {
      if (c.relations && c.relations.length > 0) {
        relationByTo.set(c.id, c.relations);
      }
    }

    const tx = db.transaction((items: NodeDraft[]) => {
      for (const c of items) {
        const childLevel = nodeLevel + 1;
        const leaf = childLevel >= MAX_DEPTH ? 1 : 0;
        const relations = relationByTo.get(c.id) ?? [];
        insert.run(
          c.id,
          topicId,
          nodeId,
          c.title.trim(),
          c.canonical_definition ?? "",
          c.conceptType ? String(c.conceptType) : null,
          c.importance ?? 0.5,
          c.difficulty ?? 0.5,
          c.estimatedMinutes ?? 5,
          JSON.stringify(relations),
          "structure_generated",
          0,
          leaf,
          childLevel,
          new Date().toISOString(),
        );
      }
      // update parent state; если детей не появилось — узел оказался естественным
      // листом (терминальным), помечаем его как leaf=1
      const gotChildren = items.length > 0;
      db.prepare("UPDATE knowledge_nodes SET state = 'expanded', leaf = ? WHERE id = ?").run(
        gotChildren ? 0 : 1,
        nodeId,
      );
    });

    tx(scoped);
    return scoped;
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
    sources?: string[];
  }> {
    const { getDb } = await import("../db/connection.js");
    const db = getDb();

    const nodeRow = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    const topicRow = db.prepare(`SELECT name, goal, target_level FROM topics WHERE id = ?`).get(topicId) as
      | { name: string; goal?: string | null; target_level?: string | null }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";
    const { masteryLevelToKnowledgeLevel } = await import("../prompts/structure.js");
    const knowledgeLevel =
      typeof topicRow?.target_level === "string"
        ? masteryLevelToKnowledgeLevel(topicRow.target_level)
        : undefined;

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
      knowledgeLevel,
      goal: topicRow?.goal ?? undefined,
      nodeLevel: Number(nodeRow.level),
      isRoot: Number(nodeRow.level) <= 1 && !nodeRow.parent_id,
    });

    db.prepare(
      `UPDATE knowledge_nodes SET one_liner = ?, details = ?, analogy = ?, relations_json = ?, sources_json = ?,
         state = 'content_generated', content_loaded = 1
       WHERE id = ?`,
    ).run(
      content.one_liner,
      content.details,
      content.analogy ?? null,
      JSON.stringify(content.relations),
      JSON.stringify(content.sources ?? []),
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
      ...parseNodeMetadata(rec),
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

  // Сироты: узлы, чей parentId указывает на узел не из этой партии
  // (например, L2-узлы в ответе, где корень генерировался отдельным запросом).
  for (const d of drafts) {
    if (!visited.has(d.id)) {
      result.push({ ...d, level: d.level || guessLevel(d as unknown as Record<string, unknown>) });
    }
  }

  return result;
}

function guessLevel(rec: Record<string, unknown>): number {
  if (rec.parentId === null || rec.parentId === undefined) return 1;
  return 2;
}

/**
 * Извлекает метаданные узла (importance/difficulty/estimated_time/prerequisites/relations)
 * из ответа LLM. Возвращает undefined-поля, если значения отсутствуют или невалидны.
 * relations — массив объектов { to, type, label? }, при невалидной записи пропускается.
 */
export function parseNodeMetadata(rec: Record<string, unknown>): Partial<NodeDraft> {
  const importance = typeof rec.importance === "number" ? clamp01(rec.importance) : undefined;
  const difficulty = typeof rec.difficulty === "number" ? clamp01(rec.difficulty) : undefined;
  const estimatedMinutes =
    typeof rec.estimated_time_minutes === "number" && rec.estimated_time_minutes > 0
      ? Math.round(rec.estimated_time_minutes)
      : typeof rec.estimated_time_minutes === "string" &&
        Number(rec.estimated_time_minutes) > 0
        ? Math.round(Number(rec.estimated_time_minutes))
        : undefined;

  const prerequisites = Array.isArray(rec.prerequisites)
    ? (rec.prerequisites as unknown[]).filter((p): p is string => typeof p === "string")
    : undefined;

  const relations = Array.isArray(rec.relations)
    ? (rec.relations as unknown[]).flatMap((rel) => {
        const r = rel as Record<string, unknown>;
        if (!r || typeof r.to !== "string" || !r.to) return [];
        const type = String(r.type ?? "related");
        return [
          {
            from: String(rec.id ?? ""),
            to: r.to,
            type: (VALID_RELATION_TYPES.has(type) ? type : "related") as RelationType,
            label: typeof r.label === "string" && r.label !== "" ? r.label : undefined,
          } satisfies Relation,
        ];
      })
    : undefined;

  return {
    ...(importance !== undefined ? { importance } : {}),
    ...(difficulty !== undefined ? { difficulty } : {}),
    ...(estimatedMinutes !== undefined ? { estimatedMinutes } : {}),
    ...(prerequisites !== undefined && prerequisites.length > 0 ? { prerequisites } : {}),
    ...(relations !== undefined && relations.length > 0 ? { relations } : {}),
  };
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}

const VALID_RELATION_TYPES = new Set<string>([
  "related",
  "depends_on",
  "requires",
  "example_of",
  "similar_to",
  "contrasts_with",
  "causes",
  "enables",
  "used_for",
  "alternative_to",
]);


function maxLevelOf(nodes: NodeDraft[]): number {
  return nodes.reduce((max, n) => Math.max(max, n.level), 0);
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

/**
 * Согласует новые узлы (дети при расширении) с уже существующим деревом:
 * - отбрасывает узлы, чьё понятие уже присутствует в дереве (по нормализованному title);
 * - отбрасывает коллизии id с существующими узлами;
 * - отбрасывает детей, дублирующих title среди своих же сиблингов.
 * Возвращает согласованный список и число отброшенных узлов.
 */
export function consistencyCheckAgainstTree(
  existing: NodeDraft[],
  incoming: NodeDraft[],
): { nodes: NodeDraft[]; skipped: number } {
  const existingTitles = new Set<string>();
  for (const n of existing) {
    const t = normalizeTitle(n.title);
    if (t) existingTitles.add(t);
  }
  const existingIds = new Set(existing.map((n) => n.id));

  const seenTitles = new Map<string, string>(); // нормализованный title -> id в этой партии
  const seenIds = new Set<string>();
  const nodes: NodeDraft[] = [];

  for (const n of incoming) {
    const t = normalizeTitle(n.title);
    if (!t) continue;
    if (existingTitles.has(t)) continue; // дубль с существующим понятием
    if (n.id && existingIds.has(n.id)) continue; // коллизия id
    if (seenTitles.has(t)) continue; // дубль title среди сиблингов
    const id = n.id || `c_${nodes.length + 1}`;
    if (seenIds.has(id)) continue; // коллизия id внутри партии
    seenIds.add(id);
    seenTitles.set(t, id);
    nodes.push({ ...n, id });
  }

  return { nodes, skipped: incoming.length - nodes.length };
}

function normalizeTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * Применяет результаты repair-шага к дереву.
 * Проблемный узел заменяется исправленной версией ТОЛЬКО если repair вернул
 * узел с тем же id; в противном случае исходный узел сохраняется, чтобы
 * repair, опустивший часть узлов (в т.ч. корень), не удалял их из дерева
 * (иначе дети становились сиротами без родителя).
 * Новые узлы, которых не было в исходном дереве, добавляются.
 */
export function mergeRepairs(nodes: NodeDraft[], repaired: NodeDraft[]): NodeDraft[] {
  const byId = new Map(repaired.map((r) => [r.id, r]));
  const out: NodeDraft[] = nodes.map((n) => {
    const rep = byId.get(n.id);
    return rep ? { ...rep } : n;
  });
  const existingIds = new Set(out.map((o) => o.id));
  for (const r of repaired) {
    if (!existingIds.has(r.id)) out.push(r);
  }
  return out;
}

/**
 * Детерминированное демо-дерево для офлайн-режима (LLM_MOCK=1).
 * Возвращает скелет уровня 1–2 с гарантированно уникальными id,
 * чтобы persistNodes не падал на UNIQUE constraint.
 */
export function fallbackStructure(query: string): NodeDraft[] {
  const topic = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";
  return [
    {
      id: "n1",
      title: topic,
      parentId: null,
      level: 1,
      canonical_definition: `Общий обзор темы «${topic}» и её ключевых разделов.`,
      semantic_axis: "theory",
      conceptType: "topic",
    },
    {
      id: "n2_1",
      title: "Основы",
      parentId: "n1",
      level: 2,
      canonical_definition: "Базовые понятия и определения, с которых начинается изучение темы.",
      semantic_axis: "theory",
      conceptType: "concept",
    },
    {
      id: "n2_2",
      title: "Ключевые направления",
      parentId: "n1",
      level: 2,
      canonical_definition: "Главные подтемы и принципы, составляющие ядро предмета.",
      semantic_axis: "architecture",
      conceptType: "concept",
    },
    {
      id: "n2_3",
      title: "Применение",
      parentId: "n1",
      level: 2,
      canonical_definition: "Практические области использования знаний по теме.",
      semantic_axis: "application",
      conceptType: "example",
    },
  ];
}

/**
 * Схлопывает точные дубли узлов и переименовывает оставшиеся коллизии id,
 * обновляя ссылки parentId, чтобы дерево было внутренне согласованным и
 * персистентность не падала на UNIQUE constraint.
 */
export function dedupeNodeIds(nodes: NodeDraft[]): NodeDraft[] {
  const seen = new Set<string>();
  const out: NodeDraft[] = [];
  // исходный id -> новый уникальный id (для всех, включая неизменённые)
  const idMap = new Map<string, string>();

  for (const n of nodes) {
    if (!n.id) continue;
    // Точный дубль (тот же id и тот же контент) — пропускаем.
    const existing = out.find((o) => o.id === n.id);
    const isExactDup = existing !== undefined
      && existing.title === n.title
      && existing.level === n.level
      && existing.parentId === n.parentId;
    if (isExactDup) {
      idMap.set(n.id, n.id);
      continue;
    }

    let newId = n.id;
    if (seen.has(n.id)) {
      const base = n.id.replace(/-\d+$/, "");
      let i = 1;
      do {
        newId = `${base}-${i}`;
        i++;
      } while (seen.has(newId));
    }
    seen.add(newId);
    // parentId-ссылки должны указывать на первый (канонический) узел с данным id,
    // поэтому маппинг исходного id сохраняем только при первом вхождении.
    if (!idMap.has(n.id)) {
      idMap.set(n.id, newId);
    }
    out.push({ ...n, id: newId });
  }

  // Обновляем parentId по переименованию.
  for (const n of out) {
    if (n.parentId && idMap.has(n.parentId) && n.parentId !== n.id) {
      const mapped = idMap.get(n.parentId)!;
      if (mapped !== n.parentId) {
        n.parentId = mapped;
      }
    }
  }

  return out;
}

