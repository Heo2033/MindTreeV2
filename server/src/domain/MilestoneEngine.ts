import { MASTERY_LEVELS, type MasteryLevel } from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildMilestonePrompt,
  parseMilestoneResult,
  type MilestoneResult,
} from "../prompts/milestone.js";
import crypto from "crypto";
import { getDb } from "../db/connection.js";

export interface Milestone {
  id: string;
  level: MasteryLevel;
  title: string;
  description: string;
  capabilities: string[];
  estimatedHours: number;
  status: "not_started" | "active" | "completed";
  alternativePaths: Array<{
    id: string;
    title: string;
    estimatedHours: number;
    description: string;
  }>;
}

export class MilestoneEngine {
  /**
   * Составляет карту уровней освоения (milestones) от текущего к более глубоким.
   */
  async generate(journeyId: string, topicId: string): Promise<Milestone[]> {
    const topic = this.getTopic(topicId);
    const currentLevel = this.getCurrentLevel(topicId);

    let milestones: MilestoneResult["milestones"] = [];
    try {
      const prompt = buildMilestonePrompt({
        topic: topic?.name ?? "",
        currentLevel,
        goal: topic?.goal ?? "",
      });
      const res = await getScheduler().execute(
        "milestone",
        () => prompt,
        (raw) => parseMilestoneResult(parseLLMJson(raw)),
      );
      milestones = res.result.milestones;
    } catch {
      milestones = fallbackMilestones(currentLevel);
    }

    const persisted = milestones.map((m): Milestone => {
      const id = `ms_${crypto.randomUUID().slice(0, 8)}`;
      getDb()
        .prepare(
          `INSERT INTO learning_milestones
             (id, journey_id, level, title, description, capabilities_json, estimated_hours, status, alternative_paths_json)
           VALUES (?,?,?,?,?,?,?,?,?)`,
        )
        .run(
          id,
          journeyId,
          m.level,
          m.title,
          m.description,
          JSON.stringify(m.capabilities),
          m.estimated_hours,
          m.level === currentLevel ? "active" : "not_started",
          JSON.stringify(m.alternative_paths),
        );
      return {
        id,
        level: m.level as MasteryLevel,
        title: m.title,
        description: m.description,
        capabilities: m.capabilities,
        estimatedHours: m.estimated_hours,
        status: m.level === currentLevel ? "active" : "not_started",
        alternativePaths: m.alternative_paths.map((a) => ({
          id: a.id,
          title: a.title,
          estimatedHours: a.estimated_hours,
          description: a.description,
        })),
      };
    });

    return persisted;
  }

  private getTopic(topicId: string): { name: string; goal: string } | undefined {
    const row = getDb()
      .prepare(`SELECT name, goal FROM topics WHERE id = ?`)
      .get(topicId) as Record<string, unknown> | undefined;
    return row
      ? { name: String(row.name), goal: String(row.goal) }
      : undefined;
  }

  private getCurrentLevel(topicId: string): MasteryLevel {
    const row = getDb()
      .prepare(`SELECT overall_level FROM learner_models WHERE topic_id = ? AND user_id = 'default'`)
      .get(topicId) as Record<string, unknown> | undefined;
    const level = row?.overall_level ? String(row.overall_level) : "awareness";
    return MASTERY_LEVELS.includes(level as MasteryLevel) ? (level as MasteryLevel) : "awareness";
  }
}

function fallbackMilestones(currentLevel: MasteryLevel): MilestoneResult["milestones"] {
  const startIdx = Math.max(0, MASTERY_LEVELS.indexOf(currentLevel));
  return MASTERY_LEVELS.slice(startIdx).map((level, i) => ({
    id: `ms_fallback_${i}`,
    level,
    title: beautifulTitle(level),
    description: `Достижение уровня ${beautifulTitle(level)}`,
    capabilities: [],
    estimated_hours: 2 + i * 2,
    alternative_paths: [],
  }));
}

function beautifulTitle(level: MasteryLevel): string {
  const map: Record<MasteryLevel, string> = {
    awareness: "Знакомство",
    basic_understanding: "Базовое понимание",
    solid_understanding: "Твёрдое понимание",
    practical_application: "Практическое применение",
    advanced: "Продвинутый",
    expert: "Эксперт",
  };
  return map[level] ?? level;
}
