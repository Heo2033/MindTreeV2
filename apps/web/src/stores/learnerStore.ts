import { create } from "zustand";
import type { LearnerModel, ConceptMastery, MasteryLevel } from "@mindtree/types";
import { quizApi, diagnosticApi } from "../api";

interface LearnerState {
  model: LearnerModel | null;
  quizResults: Array<{ nodeId: string; correct: boolean }>;
  lastScore: number | null;
  lastTotal: number | null;
  evaluating: boolean;
  error: string | null;
  setMastery: (model: LearnerModel) => void;
  recordQuizResults: (topicId: string, quizId: string, nodeId: string, correct: boolean) => void;
  submitQuizResults: (topicId: string) => Promise<void>;
  runDiagnostic: (topicId: string) => Promise<unknown[]>;
  clear: () => void;
}

const emptyMasteryLevel: MasteryLevel = "awareness";

export const useLearnerStore = create<LearnerState>((set, get) => ({
  model: null,
  quizResults: [],
  lastScore: null,
  lastTotal: null,
  evaluating: false,
  error: null,

  setMastery(model) {
    set({ model });
  },

  recordQuizResults(_topicId, quizId, nodeId, correct) {
    set({ quizResults: [...get().quizResults, { nodeId, correct }] });
    void quizId;
  },

  async submitQuizResults(topicId) {
    // Re-apply recorded results to SRS via a fresh quiz apply with a placeholder id.
    const { quizResults } = get();
    if (quizResults.length === 0) return;
    await quizApi.apply("bulk", topicId, quizResults);
    const correct = quizResults.filter((r) => r.correct).length;
    set({
      lastScore: quizResults.length > 0 ? correct / quizResults.length : 0,
      lastTotal: quizResults.length,
    });
  },

  async runDiagnostic(topicId) {
    set({ evaluating: true, error: null });
    try {
      const { questions } = await diagnosticApi.generate(topicId);
      set({ evaluating: false });
      return questions ?? [];
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка диагностики", evaluating: false });
      return [];
    }
  },

  clear() {
    set({ model: null, quizResults: [], lastScore: null, lastTotal: null, error: null });
  },
}));

export type { ConceptMastery };
export type { LearnerModel };
export { emptyMasteryLevel };
