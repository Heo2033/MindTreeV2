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
    // Сразу создаём сообщение-заглушку ответа, чтобы даже при пустом/ошибочном
    // стриме пользователь видел, что ответ обрабатывается, а не «ничего».
    const assistantId = `a_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
    const placeholder: ChatMessage = {
      id: assistantId,
      role: "assistant",
      content: "",
      createdAt: new Date().toISOString(),
    };
    set({
      messages: [...get().messages, userMsg, placeholder],
      sending: true,
      error: null,
    });

    let assistantContent = "";
    let usedFallback = false;
    let timeRemainingMinutes: number | null = null;
    let receivedFirstToken = false;
    let finalError: string | null = null;

    try {
      const stream = tutorApi.stream({
        topic_id: topicId,
        session_id: opts?.sessionId,
        message,
        node_id: opts?.nodeId,
      });

      for await (const ev of stream.events) {
        const { event, data } = ev;
        if (event === "token" && data && typeof (data as { text?: unknown }).text === "string") {
          receivedFirstToken = true;
          assistantContent += (data as { text: string }).text;
          const id = assistantId;
          set({
            messages: get().messages.map((m) =>
              m.id === id ? { ...m, content: assistantContent } : m,
            ),
          });
        } else if (event === "done" && data) {
          const done = data as { usedFallback?: unknown; timeRemainingMinutes?: unknown };
          usedFallback = Boolean(done.usedFallback);
          if (done.timeRemainingMinutes != null) {
            timeRemainingMinutes = Number(done.timeRemainingMinutes);
          }
        } else if (event === "error" || event === "__error__") {
          const errData = data as { message?: unknown } | Error | undefined;
          const msg =
            typeof errData?.message === "string" && errData.message.trim()
              ? errData.message
              : "Ошибка чата";
          finalError = msg;
          throw new Error(msg);
        }
      }

      // Стрим завершился без единого токена и без явной ошибки — считаем это
      // сбоем, чтобы не оставлять пустое сообщение и мёртвый спиннер.
      if (!receivedFirstToken && assistantContent === "" && !finalError) {
        finalError = "Не удалось получить ответ (пустой стрим)";
      }
    } catch (err) {
      finalError = err instanceof Error ? err.message : "Ошибка чата";
    }

    set((s) => ({
      sending: false,
      timeRemainingMinutes,
      error: finalError,
      messages: s.messages.map((m) => {
        if (m.id !== assistantId) return m;
        return { ...m, content: assistantContent || m.content, usedFallback };
      }),
    }));
  },

  reset() {
    set({ messages: [], sending: false, error: null, timeRemainingMinutes: null });
  },
}));
