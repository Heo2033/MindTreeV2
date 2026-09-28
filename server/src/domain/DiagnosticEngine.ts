import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildDiagnosticPrompt,
  parseDiagnosticResult,
} from "../prompts/diagnostic.js";
import { LearnerModelService } from "./LearnerModelService.js";
import { rotateOptions, rotateIndex } from "./LearningActivityService.js";
import { shortIdWith } from "./shortIds.js";
import { getDb } from "../db/connection.js";

type DiagnosticQuestion = DiagnosticResult["questions"][number];

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

    let questions: DiagnosticQuestion[];
    try {
      const res = await getScheduler().execute(
        "diagnostic",
        () => prompt,
        (raw) => parseDiagnosticResult(parseLLMJson(raw)),
      );
      questions = res.result;
    } catch (e) {
      // LLM недоступен (сеть/ключ/лимиты) — отдаём детерминированный набор
      // вопросов из уже загруженного дерева: экран диагностики не должен падать.
      console.warn("[diagnostic] LLM generation failed", {
        topicId,
        error: e instanceof Error ? e.message : String(e),
      });
      questions = fallbackQuestions(topic?.name ?? "", nodes);
    }

    return questions.slice(0, 6);
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

/**
 * Детерминированный fallback-диагностики без LLM: вопрос на каждый узел
 * («что означает понятие X»), варианты — подписи узлов. Без Math.random и без
 * DateTime: и порядок узлов, и сдвиг вариантов задаются индексом узла,
 * поэтому один и тот же вход всегда даёт один и тот же набор вопросов.
 * Зеркало `_fallbackQuestions` в lib/domain/engines/diagnostic_engine.dart
 * (mindtree_flutter). Вынесено на уровень модуля — как `fallbackExample`
 * в LearningActivityService, — чтобы тестировалось без LLM и без БД.
 */
export function fallbackQuestions(
  topicName: string,
  nodes: Array<{ id: string; label: string; one_liner: string }>,
): DiagnosticQuestion[] {
  // Один узел — вопрос в одном варианте бессмыслен, без узлов — тоже.
  if (nodes.length < 2) return [];

  // Подпись узла — и вопрос, и варианты; без label берём one_liner.
  const labels = nodes.map((n) => (n.label ?? "").trim() || (n.one_liner ?? "").trim());

  const questions: DiagnosticQuestion[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]!;
    const correct = labels[i]!;
    if (!correct) continue;

    // Дистракторы — подписи следующих по обходу узлов (циклически), без
    // пустых строк и повторов правильного варианта.
    const distractors: string[] = [];
    for (let k = 1; distractors.length < 3 && k < nodes.length; k++) {
      const candidate = labels[(i + k) % nodes.length]!;
      if (!candidate || candidate === correct) continue;
      if (distractors.includes(candidate)) continue;
      distractors.push(candidate);
    }

    const options = [correct, ...distractors];
    // Меньше двух вариантов — вопрос без выбора, пропускаем узел.
    if (options.length < 2) continue;

    // Сдвиг по индексу узла: правильный вариант не всегда первый, но для
    // одного и того же узла его позиция всегда одна и та же.
    const shift = i % options.length;
    const oneLiner = (node.one_liner ?? "").trim();
    questions.push({
      id: shortIdWith("d_"),
      nodeId: node.id,
      question: `Что означает понятие «${correct}»?`,
      options: rotateOptions(options, shift),
      correctIndex: rotateIndex(0, shift, options.length),
      explanation: oneLiner || `Понятие «${correct}» — часть темы «${topicName}».`,
    });
  }
  return questions;
}
