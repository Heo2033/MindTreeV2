import type { KnowledgeNode, CurriculumItem, Curriculum } from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildCurriculumPrompt,
  parseCurriculumResult,
  type CurriculumPromptContext,
} from "../prompts/curriculum.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { shortIdWith } from "./shortIds.js";

export interface CurriculumRequest {
  topicId: string;
  topicName: string;
  goal: string;
  targetLevel: string;
  currentLevel?: string;
  timeBudgetMinutes: number;
  nodes: KnowledgeNode[];
  /**
   * §44: ids of nodes the learner has effectively already mastered.
   * When changing a goal, these are considered "known" and are NOT re-scheduled,
   * so the new curriculum builds only around the missing knowledge.
   */
  knownNodeIds?: Set<string>;
}

export interface CurriculumPlanResult {
  curriculum: Curriculum;
  /** §44: nodes that were already known/mastered and therefore skipped. */
  alreadyKnown: string[];
}

export class CurriculumEngine {
  constructor(private learnerModel: LearnerModelService = new LearnerModelService()) {}

  /**
   * Из полного графа выбирает минимально достаточный набор понятий.
   * Сначала пробует урезанный детерминированный отбор по времени/важности,
   * затем LLM строит обоснованный curriculum.
   *
   * §44: если заданы `knownNodeIds`, эти узлы считаются уже освоенными и
   * исключаются из нового плана обучения — новый curriculum строится только
   * вокруг недостающего знания.
   */
  async generate(req: CurriculumRequest): Promise<CurriculumPlanResult> {
    // Deterministic conservative baseline: choose high-importance nodes within budget
    const baseline = this.deterministicSelect(req);
    const knownIds = new Set(req.nodes.map((n) => n.id));

    // LLM-план принимаем только если он ссылается на реальные узлы дерева.
    // Модель часто возвращает либо пустой `items`, либо «сырые» id без
    // `~`-скоупа (n3_1 вместо n3_1~hash). Раньше такой результат молча
    // заменял детерминированный baseline, и сессия создавалась пустой:
    // элементов 0, учиться нечему — пользователь видит вечное «генерация…».
    let llmItems = baseline;
    try {
      const fromLlm = await this.llmSelect(req);
      const usable = fromLlm.filter((i) => knownIds.has(i.node_id));
      if (usable.length > 0) llmItems = usable;
    } catch {
      // fall back to deterministic baseline
    }

    const byId = new Map(req.nodes.map((n) => [n.id, n]));
    const known = req.knownNodeIds ?? new Set<string>();
    const alreadyKnown = req.nodes
      .map((n) => n.id)
      .filter((id) => known.has(id))
      .filter((id) => req.nodes.some((n) => n.id === id));

    const items: CurriculumItem[] = llmItems
      .filter((i) => !!i.node_id && !known.has(i.node_id))
      .map((item) => {
        const node = req.nodes.find((n) => n.id === item.node_id);
        const order = item.order;
        // Relevance: a goal-relevant high-leverage concept.
        const goalRelevance = goalRelevanceOf(node);
        // Prerequisite value: how many selected nodes depend on this one.
        const prerequisiteValue = prerequisiteValueOf(node, llmItems.map((i) => i.node_id), byId);
        const importance = node?.importance ?? 0.5;
        const est = Math.max(1, item.estimated_minutes);
        const priority = scorePriority(goalRelevance, prerequisiteValue, importance, est);
        return {
          id: shortIdWith("ci_"),
          nodeId: item.node_id,
          label: node?.label ?? item.node_id,
          order,
          type: this.itemTypeFor(node),
          estimatedMinutes: item.estimated_minutes,
          priority,
          status: "pending" as const,
          reason: item.why || undefined,
        };
      });

    // §63: repair prerequisite ordering before building the final curriculum.
    const issues = this.validate(items, req.nodes);
    if (issues.length > 0) {
      this.repairOrder(items, req.nodes);
    }

    // Детерминированный кап по бюджету времени: план не должен обещать
    // больше минут, чем пользователь выделил (зеркало fitPlanToBudget flutter).
    let fitted = fitPlanToBudget(items, req.timeBudgetMinutes || 60);

    // Последний рубеж: сессия без единого элемента — это не сессия, а
    // «генерация не создалась». План обязан быть непустым, пока в дереве
    // есть хотя бы один узел, который ещё не известен пользователю.
    if (fitted.length === 0 && baseline.length > 0) {
      fitted = fitPlanToBudget(
        baseline
          .filter((i) => knownIds.has(i.node_id))
          .map((item) => ({
            id: shortIdWith("ci_"),
            nodeId: item.node_id,
            label: byId.get(item.node_id)?.label ?? item.node_id,
            order: item.order,
            type: this.itemTypeFor(byId.get(item.node_id)),
            estimatedMinutes: item.estimated_minutes,
            priority: 50,
            status: "pending" as const,
          })),
        req.timeBudgetMinutes || 60,
      );
    }

    const sessionId = shortIdWith("curriculum_");

    return {
      curriculum: {
        sessionId,
        items: fitted,
        totalEstimatedMinutes: fitted.reduce((s, i) => s + i.estimatedMinutes, 0),
      },
      alreadyKnown,
    };
  }

  /**
   * §44: перестроить план по новой цели, не начиная с нуля.
   * Считает уже освоенные узлы по модели обучающегося (mastery >= {masteryThreshold})
   * и генерирует curriculum только вокруг недостающего знания.
   */
  async planForGoal(
    req: CurriculumRequest,
    learnerModel: LearnerModelService,
  ): Promise<CurriculumPlanResult> {
    const profiles = learnerModel.getConceptProfiles(req.topicId);
    const mastered = new Set(
      profiles.filter((p) => p.masteryScore >= 0.7).map((p) => p.nodeId),
    );
    return this.generate({ ...req, knownNodeIds: mastered });
  }

  private deterministicSelect(req: CurriculumRequest) {
    const budget = req.timeBudgetMinutes || 60;
    const byId = new Map(req.nodes.map((n) => [n.id, n]));
    const known = req.knownNodeIds ?? new Set<string>();
    const sorted = req.nodes
      .filter((n) => n.level >= 2 && !known.has(n.id))
      .map((n) => ({ n, score: scorePriority(goalRelevanceOf(n), prerequisiteValueOf(n, [], byId), n.importance, Math.max(1, n.estimatedTimeMinutes || 5)) }))
      .sort((a, b) => b.score - a.score || (a.n.estimatedTimeMinutes || 5) - (b.n.estimatedTimeMinutes || 5))
      .map((x) => x.n);

    const selected: Array<{ node_id: string; order: number; estimated_minutes: number; why: string }> = [];
    let used = 0;
    for (const node of sorted) {
      const est = Math.min(node.estimatedTimeMinutes || 5, 20);
      if (used + est > budget * 1.2) break;
      selected.push({
        node_id: node.id,
        order: selected.length + 1,
        estimated_minutes: est,
        why: "Важное понятие с высокой пользой на единицу времени",
      });
      used += est;
    }
    // Детерминированный guard (зеркало «первый пункт сохраняется» фиттера):
    // при коротком бюджете падать до пустого плана нельзя — берём лучший узел.
    if (selected.length === 0 && sorted.length > 0) {
      const node = sorted[0]!;
      selected.push({
        node_id: node.id,
        order: 1,
        estimated_minutes: Math.min(node.estimatedTimeMinutes || 5, 20),
        why: "Базовое понятие — план не может быть пустым",
      });
    }

    // Дерево из одного корня (или где все узлы уже известны): кандидатов
    // level>=2 нет, но сессия всё равно должна что-то предложить. Берём
    // корень — иначе пользователь видит «генерация не создалась».
    if (selected.length === 0) {
      const root = req.nodes
        .filter((n) => !known.has(n.id))
        .reduce<KnowledgeNode | null>(
          (best, n) => (best === null || n.level < best.level ? n : best),
          null,
        );
      if (root !== null) {
        selected.push({
          node_id: root.id,
          order: 1,
          estimated_minutes: Math.min(root.estimatedTimeMinutes || 5, 20),
          why: "Корень темы — базовое понятие для разбора",
        });
      }
    }
    return selected;
  }

  private async llmSelect(req: CurriculumRequest) {
    const scheduler = getScheduler();
    const currentLevel = await this.learnerModel.getCurrentLevel(req.topicId);

    const byId = new Map(req.nodes.map((n) => [n.id, n]));
    const ids = req.nodes.map((n) => n.id);
    const promptCtx: CurriculumPromptContext = {
      topic: req.topicName,
      goal: req.goal,
      targetLevel: req.targetLevel,
      currentLevel: req.currentLevel ?? currentLevel,
      timeBudgetMinutes: req.timeBudgetMinutes,
      nodes: req.nodes.map((n) => ({
        id: n.id,
        label: n.label,
        one_liner: n.oneLiner,
        importance: n.importance,
        difficulty: n.difficulty,
        estimated_time_minutes: n.estimatedTimeMinutes,
        prerequisites: prerequisitesOf(n, byId, ids),
      })),
    };

    const prompt = buildCurriculumPrompt(promptCtx);
    const { result } = await scheduler.execute(
      "curriculum",
      () => prompt,
      (raw) => parseCurriculumResult(parseLLMJson(raw)),
    );

    return result.items
      .filter((i) => i.node_id)
      .sort((a, b) => a.order - b.order)
      .map((i, idx) => ({ ...i, order: idx + 1 }));
  }

  private itemTypeFor(node?: KnowledgeNode): CurriculumItem["type"] {
    if (!node) return "explain";
    if (node.conceptType === "process" || node.conceptType === "mechanism") return "explain";
    if (node.leaf) return "recall";
    return "explain";
  }

  /**
   * §63 Validation: checked ordering of a curriculum against the prerequisite graph.
   * Returns a list of issues; empty means the curriculum is a valid topological order
   * (every selected concept appears after its selected prerequisites).
   */
  validate(items: CurriculumItem[], nodes: KnowledgeNode[]): string[] {
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const selectedIds = new Set(items.map((i) => i.nodeId));
    const orderPos = new Map<string, number>();
    items.forEach((i, idx) => {
      if (i.nodeId) orderPos.set(i.nodeId, idx);
    });

    const issues: string[] = [];
    for (const item of items) {
      const node = byId.get(item.nodeId);
      const deps = prerequisitesOf(node, byId, nodes.map((n) => n.id));
      for (const dep of deps) {
        if (selectedIds.has(dep)) {
          const depPos = orderPos.get(dep)!;
          const ownPos = orderPos.get(item.nodeId)!;
          if (depPos > ownPos) {
            issues.push(
              `Понятие «${node?.label ?? item.nodeId}» изучено раньше своего prerequisite «${byId.get(dep)?.label ?? dep}».`,
            );
          }
        }
      }
    }
    return issues;
  }

  /**
   * Reorders curriculum items into a topological order where every concept
   * appears after its selected prerequisites. Stable for items without edges.
   */
  private repairOrder(items: CurriculumItem[], nodes: KnowledgeNode[]): void {
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const allIds = nodes.map((n) => n.id);
    const selected = new Set(items.map((i) => i.nodeId));
    const index = new Map(items.map((i, idx) => [i.nodeId, idx]));

    const depsOf = (nodeId: string): string[] =>
      prerequisitesOf(byId.get(nodeId), byId, allIds)
        .filter((d) => selected.has(d) && index.has(d));

    const visited = new Set<string>();
    const inStack = new Set<string>();
    const ordered: CurriculumItem[] = [];

    const visit = (item: CurriculumItem) => {
      if (visited.has(item.nodeId) || inStack.has(item.nodeId)) return;
      inStack.add(item.nodeId);
      for (const dep of depsOf(item.nodeId)) {
        const depItem = items[index.get(dep)!];
        visit(depItem);
      }
      inStack.delete(item.nodeId);
      visited.add(item.nodeId);
      ordered.push(item);
    };

    for (const item of items) visit(item);

    ordered.forEach((item, idx) => {
      item.order = idx + 1;
    });
    items.length = 0;
    items.push(...ordered);
  }
}

export interface PriorityInput {
  goalRelevance: number;
  prerequisiteValue: number;
  importance: number;
  estimatedMinutes: number;
}

/**
 * §20 Priority Model:
 * priority = goal_relevance × prerequisite_value × importance ÷ estimated_time
 * Normalized to a 1..100 scale for display.
 */
export function scorePriority(
  goalRelevance: number,
  prerequisiteValue: number,
  importance: number,
  estimatedMinutes: number,
): number {
  const raw =
    (goalRelevance + 0.5) *
    (prerequisiteValue + 0.5) *
    (importance + 0.5) /
    Math.max(1, estimatedMinutes);
  return Math.max(1, Math.round(raw * 100));
}

/**
 * Детерминированный кап плана по бюджету: сортируем по order и набираем пункты,
 * пока сумма не превысит бюджет. Первый пункт сохраняется всегда, даже если
 * сам по себе длиннее бюджета (иначе план был бы пустым).
 */
export function fitPlanToBudget(items: CurriculumItem[], budgetMinutes: number): CurriculumItem[] {
  if (items.length === 0) return items;
  const sorted = [...items].sort((a, b) => a.order - b.order);
  const fitted: CurriculumItem[] = [];
  let sum = 0;
  for (const it of sorted) {
    if (fitted.length > 0 && sum + it.estimatedMinutes > budgetMinutes) break;
    fitted.push(it);
    sum += it.estimatedMinutes;
  }
  if (fitted.length === 0) fitted.push(sorted[0]);
  return fitted;
}

function goalRelevanceOf(node?: KnowledgeNode): number {
  if (!node) return 0;
  // Bogus placeholder: concept types "mechanism"/"process" are often core to a goal.
  const base = node.importance ?? 0.5;
  const typeBoost =
    node.conceptType === "mechanism" || node.conceptType === "process" ? 0.3 : 0;
  return Math.min(1, base + typeBoost);
}

/**
 * Prerequisite value: how many other concepts (selected or in the graph) directly
 * depend on this node (via depends_on / requires edges pointing to it).
 */
function prerequisiteValueOf(
  node: KnowledgeNode | undefined,
  selectedIds: string[],
  byId: Map<string, KnowledgeNode>,
): number {
  if (!node) return 0;
  let deps = 0;
  const seen = new Set<string>();
  for (const n of byId.values()) {
    for (const rel of n.relations ?? []) {
      if ((rel.type === "depends_on" || rel.type === "requires") && rel.from === node.id && !seen.has(n.id)) {
        seen.add(n.id);
        // A dependency only raises value if it's part of the chosen curriculum.
        if (selectedIds.includes(n.id)) deps++;
      }
    }
  }
  return Math.min(1, deps / 4);
}

/**
 * Prerequisites of a node = the ids of concepts that this node depends on
 * (edges with type depends_on / requires where "to" === node.id).
 */
function prerequisitesOf(
  node: Pick<KnowledgeNode, "relations"> | undefined,
  byId: Map<string, KnowledgeNode>,
  allIds: string[],
): string[] {
  const out: string[] = [];
  for (const rel of node?.relations ?? []) {
    if ((rel.type === "depends_on" || rel.type === "requires") && allIds.includes(rel.to)) {
      out.push(rel.to);
    }
  }
  return out;
}
