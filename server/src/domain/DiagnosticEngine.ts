import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildDiagnosticPrompt,
  parseDiagnosticResult,
} from "../prompts/diagnostic.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { getDb } from "../db/connection.js";

export interface DiagnosticAnswer {
  questionId: string;
  nodeId: string;
  selectedIndex: number;
  correctIndex: number;
}

export interface DiagnosticResult {
  questions: Array<{
    id: string;
    nodeId: string;
    question: string;
    options: string[];
    correctIndex: number;
    explanation: string;
  }>;
  currentLevel: string;
  knownConcepts: string[];
  unknownConcepts: string[];
  score: number;
}

export class DiagnosticEngine {
  private learnerModel = new LearnerModelService();

  async generate(topicId: string): Promise<DiagnosticResult["questions"]> {
    const topic = getDb().prepare("SELECT name, goal, target_level FROM topics WHERE id = ?").get(topicId) as
      | { name: string; goal: string; target_level: string }
      | undefined;
    const nodes = getDb()
      .prepare("SELECT id, label, one_liner FROM knowledge_nodes WHERE topic_id = ? AND level >= 1 LIMIT 8")
      .all(topicId) as Array<{ id: string; label: string; one_liner: string }>;

    const prompt = buildDiagnosticPrompt({
      topic: topic?.name ?? "",
      goal: topic?.goal ?? "выяснить текущий уровень понимания",
      targetLevel: topic?.target_level ?? "basic_understanding",
      nodes: nodes.map((n) => ({ id: n.id, label: n.label, one_liner: n.one_liner })),
    });

    const res = await getScheduler().execute(
      "diagnostic",
      () => prompt,
      (raw) => parseDiagnosticResult(parseLLMJson(raw)),
    );

    return res.result.slice(0, 6);
  }

  async evaluate(
    topicId: string,
    answers: DiagnosticAnswer[],
  ): Promise<DiagnosticResult> {
    const correctCount = answers.filter(
      (a) => a.selectedIndex === a.correctIndex,
    ).length;
    const score = answers.length > 0 ? correctCount / answers.length : 0;

    const knownConcepts = answers
      .filter((a) => a.selectedIndex === a.correctIndex)
      .map((a) => a.nodeId);
    const unknownConcepts = answers
      .filter((a) => a.selectedIndex !== a.correctIndex)
      .map((a) => a.nodeId);

    let currentLevel: string;
    if (score >= 0.8) currentLevel = "practical_application";
    else if (score >= 0.6) currentLevel = "solid_understanding";
    else if (score >= 0.4) currentLevel = "basic_understanding";
    else currentLevel = "awareness";

    this.learnerModel.setOverallLevel(topicId, currentLevel as never);

    // Record known concepts as baseline mastery
    for (const nodeId of knownConcepts) {
      this.learnerModel.updateMasteryDimensions(topicId, nodeId, {
        understanding: 0.6,
        recall: 0.6,
        application: 0.4,
        transfer: 0.3,
      });
    }

    return {
      questions: [],
      currentLevel,
      knownConcepts,
      unknownConcepts,
      score,
    };
  }
}
