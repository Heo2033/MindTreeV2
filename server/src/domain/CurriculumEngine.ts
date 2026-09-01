import type { KnowledgeNode, CurriculumItem, Curriculum } from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildCurriculumPrompt,
  parseCurriculumResult,
  type CurriculumPromptContext,
} from "../prompts/curriculum.js";
import { LearnerModelService } from "./LearnerModelService.js";
import crypto from "crypto";

export interface CurriculumRequest {
  topicId: string;
  topicName: string;
  goal: string;
  targetLevel: string;
  currentLevel?: string;
  timeBudgetMinutes: number;
  nodes: KnowledgeNode[];
}

export class CurriculumEngine {
  constructor(private learnerModel: LearnerModelService = new LearnerModelService()) {}

  /**
   * Из полного графа выбирает минимально достаточный набор понятий.
   * Сначала пробует урезанный детерминированный отбор по времени/важности,
   * затем LLM строит обоснованный curriculum.
   */
  async generate(req: CurriculumRequest): Promise<Curriculum> {
    // Deterministic conservative baseline: choose high-importance nodes within budget
    const baseline = this.deterministicSelect(req);

    let llmItems = baseline;
    try {
      llmItems = await this.llmSelect(req);
    } catch {
      // fall back to deterministic baseline
    }

    const items: CurriculumItem[] = llmItems.map((item) => ({
      id: `ci_${crypto.randomUUID().slice(0, 8)}`,
      nodeId: item.node_id,
      order: item.order,
      type: this.itemTypeFor(req.nodes.find((n) => n.id === item.node_id)),
      estimatedMinutes: item.estimated_minutes,
      priority: this.priority(item),
      status: "pending",
    }));

    const sessionId = `curriculum_${crypto.randomUUID().slice(0, 8)}`;

    return {
      sessionId,
      items,
      totalEstimatedMinutes: items.reduce((s, i) => s + i.estimatedMinutes, 0),
    };
  }

  private deterministicSelect(req: CurriculumRequest) {
    const budget = req.timeBudgetMinutes || 60;
    const sorted = req.nodes
      .filter((n) => n.level >= 2)
      .sort((a, b) => b.importance * (1 / Math.max(1, a.estimatedTimeMinutes)) - a.importance * (1 / Math.max(1, b.estimatedTimeMinutes)));

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
    return selected;
  }

  private async llmSelect(req: CurriculumRequest) {
    const scheduler = getScheduler();
    const currentLevel = await this.learnerModel.getCurrentLevel(req.topicId);

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
        prerequisites: [],
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

  private priority(item: { estimated_minutes: number; why: string }): number {
    // Higher priority for quicker concepts with clear rationale
    return Math.round(100 / Math.max(1, item.estimated_minutes));
  }
}
