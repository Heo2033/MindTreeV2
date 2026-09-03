import { create } from "zustand";
import { tutorApi } from "../api";

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  usedFallback?: boolean;
  createdAt: string;
}

interface TutorState {
  messages: ChatMessage[];
  sending: boolean;
  error: string | null;
  timeRemainingMinutes: number | null;
  send: (topicId: string, message: string, opts?: { sessionId?: string; nodeId?: string }) => Promise<void>;
  reset: () => void;
}

export const useTutorStore = create<TutorState>((set, get) => ({
  messages: [],
  sending: false,
  error: null,
  timeRemainingMinutes: null,

  async send(topicId, message, opts) {
    const userMsg: ChatMessage = {
      id: `u_${Date.now()}`,
      role: "user",
      content: message,
      createdAt: new Date().toISOString(),
    };
    set({ messages: [...get().messages, userMsg], sending: true, error: null });
    try {
      const res = await tutorApi.chat({
        topic_id: topicId,
        session_id: opts?.sessionId,
        message,
        node_id: opts?.nodeId,
      });
      const assistantMsg: ChatMessage = {
        id: `a_${Date.now()}`,
        role: "assistant",
        content: res.response,
        usedFallback: res.usedFallback,
        createdAt: new Date().toISOString(),
      };
      set({
        messages: [...get().messages, assistantMsg],
        sending: false,
        timeRemainingMinutes: res.timeRemainingMinutes ?? null,
      });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : "Ошибка чата", sending: false });
    }
  },

  reset() {
    set({ messages: [], sending: false, error: null, timeRemainingMinutes: null });
  },
}));
