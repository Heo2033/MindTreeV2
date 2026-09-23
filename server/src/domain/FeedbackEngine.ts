import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildActivityFeedbackPrompt,
  sanitizeFeedbackResult,
} from "../prompts/activity.js";
import type { MisconceptionType } from "@mindtree/types";
import { LearnerModelService, type SkillDimension } from "./LearnerModelService.js";
import { ReviewScheduler } from "./ReviewScheduler.js";

export type FeedbackQuality = "correct" | "incorrect" | "again";

export interface AnswerFeedback {
  correct: boolean;
  quality: FeedbackQuality;
  score: number;
  feedback: string;
  misconception?: string;
}

export interface RecallStepInput {
  options?: string[];
  correctIndex?: number;
}

export class FeedbackEngine {
  constructor(
    private learnerModel = new LearnerModelService(),
    private reviewScheduler = new ReviewScheduler(),
  ) {}

  async evaluateApply(
    topicId: string,
    topicName: string,
    nodeId: string,
    nodeLabel: string,
    nodeOneLiner: string,
    instruction: string,
    referenceAnswer: string,
    userAnswer: string,
  ): Promise<AnswerFeedback> {
    const prompt = buildActivityFeedbackPrompt({
      nodeLabel,
      nodeOneLiner,
      instruction,
      referenceAnswer,
      userAnswer,
    });

    let assessment: "correct" | "partial" | "incorrect" = "partial";
    let feedback = "";
    let misconception: string | null = null;
    try {
      const res = await getScheduler().execute(
        "feedback",
        () => prompt,
        (raw) =>
          parseLLMJson<{
            assessment?: string;
            feedback?: string;
            misconception?: string | null;
          }>(raw),
        { cacheKey: `activity_fb:${nodeId}:${hash(userAnswer)}` },
      );
      const parsed = sanitizeFeedbackResult({
        assessment: res.result.assessment as "correct" | "partial" | "incorrect" | "partial",
        feedback: res.result.feedback ?? "",
        misconception: res.result.misconception ?? null,
      });
      assessment = parsed.assessment;
      feedback = parsed.feedback;
      misconception = parsed.misconception;
    } catch {
      feedback = "";
    }

    let base = feedback;
    if (base === "") {
      base = heuristicApplyFeedback(referenceAnswer, userAnswer);
    }
    const score = assessment === "correct" ? 1 : assessment === "partial" ? 0.5 : 0;
    const correct = assessment === "correct";
    const miscType: MisconceptionType | null = correct ? null : score === 0 ? "application_failure" : "incomplete";

    this.record(topicId, nodeId, "application", score, correct, miscType, misconception);

    return {
      correct,
      quality: assessment === "correct" ? "correct" : "incorrect",
      score,
      feedback: base,
      misconception: misconception ?? undefined,
    };
  }

  evaluateRecall(
    topicId: string,
    topicName: string,
    nodeId: string,
    nodeLabel: string,
    step: RecallStepInput,
    chosenIndex: number,
  ): AnswerFeedback {
    const correct = chosenIndex === step.correctIndex;
    const chosen = step.options?.[chosenIndex] ?? "";
    const correctOption = step.options?.[step.correctIndex ?? 0] ?? "";

    const score = correct ? 1 : 0;
    const feedback = correct
      ? "Верно! Вы правильно припомнили понятие."
      : `Не совсем. Правильный ответ: «${correctOption}». Перечитайте объяснение понятия и попробуйте ещё раз.`;

    const misconception = correct
      ? null
      : `Выбрано «${chosen.slice(0, 80)}», правильным было «${correctOption.slice(0, 80)}»`;

    this.record(topicId, nodeId, "recall", score, correct, correct ? null : "confused", misconception);

    return {
      correct,
      quality: correct ? "correct" : "incorrect",
      score,
      feedback,
      misconception: misconception ?? undefined,
    };
  }

  private record(
    topicId: string,
    nodeId: string,
    dim: SkillDimension,
    score: number,
    correct: boolean,
    misconceptionType: MisconceptionType | null,
    description: string | null,
  ) {
    const prev = this.learnerModel.getConceptProfile(nodeId, topicId);
    const blended = prev ? prev[dim] * 0.5 + score * 0.5 : score;
    this.learnerModel.updateMasteryDimensions(topicId, nodeId, { [dim]: blended });
    if (!correct && misconceptionType && description) {
      this.learnerModel.addMisconception(topicId, nodeId, misconceptionType, description);
    }
    this.reviewScheduler.onAnswered(topicId, nodeId, correct ? "correct" : "incorrect");
  }
}

export function heuristicApplyFeedback(referenceAnswer: string, userAnswer: string): string {
  const refTokens = tokenize(referenceAnswer);
  const userTokens = tokenize(userAnswer);
  if (userTokens.size === 0) return "Ответ пустой или слишком короткий. Сформулируйте мысль своими словами.";
  if (refTokens.size === 0) return "Проверьте ответ по эталонному решению ниже.";
  let hits = 0;
  for (const t of userTokens) {
    if (refTokens.has(t)) hits++;
  }
  const ratio = hits / refTokens.size;
  if (ratio >= 0.4) return "Ответ частично совпадает с эталоном. Сверьтесь с вариантом ниже и дополните недостающее.";
  return "Ответ пока не совпадает с эталоном. Сверьтесь с вариантом ниже и попробуйте переформулировать.";
}

function tokenize(text: string): Set<string> {
  return new Set(
    text
      .toLowerCase()
      .replace(/[«»"(),.;:!?—–-]/g, " ")
      .split(/\s+/)
      .filter((w) => w.length > 3),
  );
}

function hash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}