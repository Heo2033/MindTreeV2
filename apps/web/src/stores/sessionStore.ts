import { create } from "zustand";
import { sessionsApi } from "../api";
import type { SessionDetailDto, CurriculumItemDto, AdaptiveDecisionDto, FinalizeResultDto, ActivityDto } from "../api";

interface SessionState {
  session: SessionDetailDto | null;
  currentItem: CurriculumItemDto | null;
  currentIndex: number;
  adaptive: AdaptiveDecisionDto | null;
  studying: boolean;
  activity: ActivityDto | null;
  answeredStepView: number | null;
  loading: boolean;
  error: string | null;
  createSession: (
    topicId: string,
    goal?: string,
    milestoneId?: string,
    timeBudget?: number,
  ) => Promise<SessionDetailDto>;
  loadCurrent: () => Promise<void>;
  startStudy: (nodeId: string) => Promise<unknown>;
  ensureActivity: () => Promise<ActivityDto | null>;
  answerStep: (stepIndex: number, answer: string) => Promise<void>;
  clearAnsweredView: () => void;
  completeConcept: (itemId: string, nodeId?: string, quality?: string) => Promise<void>;
  finalize: () => Promise<FinalizeResultDto | {}>;
  reset: () => void;
}

export const useSessionStore = create<SessionState>((set, get) => ({
  session: null,
  currentItem: null,
  currentIndex: 0,
  adaptive: null,
  studying: false,
  activity: null,
  answeredStepView: null,
  loading: false,
  error: null,

  async createSession(topicId, goal, milestoneId, timeBudget) {
    set({ loading: true, error: null });
    try {
      const session = await sessionsApi.create({
        topic_id: topicId,
        goal: goal ?? "overview",
        milestone_id: milestoneId,
        time_budget_minutes: timeBudget ?? 60,
      });
      set({
        session,
        currentItem: session.curriculum.items[0] ?? null,
        currentIndex: 0,
        loading: false,
      });
      return session;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка создания сессии", loading: false });
      throw err;
    }
  },

  async loadCurrent() {
    const { session } = get();
    if (!session) return;
    set({ loading: true, error: null });
    try {
      const { current, adaptive } = await sessionsApi.current(session.id);
      set({
        currentItem: current.item,
        currentIndex: current.index,
        adaptive,
        loading: false,
      });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка получения шага сессии", loading: false });
    }
  },

  async startStudy(nodeId) {
    const { session } = get();
    if (!session) return null;
    set({ studying: true, error: null });
    try {
      const result = await sessionsApi.study(session.id, nodeId);
      await get().loadCurrent();
      await get().ensureActivity();
      return result;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка study", studying: false });
      return null;
    }
  },

  async ensureActivity() {
    const { session } = get();
    if (!session) return null;
    set({ loading: true, error: null });
    try {
      const activity = await sessionsApi.activity(session.id);
      set({ activity, answeredStepView: null, studying: false, loading: false });
      return activity;
    } catch (err) {
      set({ activity: null, error: err instanceof Error ? err.message : "Ошибка загрузки активности", studying: false, loading: false });
      return null;
    }
  },

  async answerStep(stepIndex, answer) {
    const { session, activity } = get();
    if (!session || !activity) return;
    try {
      const updated = await sessionsApi.activityAnswer(session.id, { step_index: stepIndex, answer });
      const previousStep = activity.steps[stepIndex];
      const showFeedback =
        previousStep &&
        previousStep.status !== "answered" &&
        updated.steps[stepIndex]?.feedback &&
        updated.steps[stepIndex].feedback!.trim() !== "";
      set({
        activity: updated,
        answeredStepView: showFeedback ? stepIndex : null,
      });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка ответа" });
    }
  },

  clearAnsweredView() {
    set({ answeredStepView: null });
  },

  async completeConcept(itemId, nodeId, quality) {
    const { session } = get();
    if (!session) return;
    try {
      await sessionsApi.itemComplete(session.id, {
        item_id: itemId,
        node_id: nodeId,
        quality: quality ?? "correct",
      });
      await get().loadCurrent();
      await get().ensureActivity();
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка завершения концепта" });
    }
  },

  async finalize() {
    const { session } = get();
    if (!session) return {};
    try {
      const result = await sessionsApi.finalize(session.id);
      await get().loadCurrent();
      return result;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка финализации" });
      return {};
    }
  },

  reset() {
    set({ session: null, currentItem: null, currentIndex: 0, adaptive: null, activity: null, answeredStepView: null, error: null });
  },
}));
