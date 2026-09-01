import { create } from "zustand";
import { configApi } from "../api";
import type { ConfigEffectiveDto } from "../api";

interface UIState {
  configStatus: "unknown" | "configured" | "missing";
  effective: ConfigEffectiveDto | null;
  sidebarOpen: boolean;
  toasts: Array<{ id: string; kind: "error" | "success" | "info"; message: string }>;
  checkConfig: () => Promise<void>;
  applyConfig: (body: Parameters<typeof configApi.apply>[0]) => Promise<boolean>;
  clearConfig: () => Promise<void>;
  openSidebar: () => void;
  closeSidebar: () => void;
  toggleSidebar: () => void;
  toast: (kind: "error" | "success" | "info", message: string) => void;
  dismissToast: (id: string) => void;
}

export const useUIStore = create<UIState>((set, get) => ({
  configStatus: "unknown",
  effective: null,
  sidebarOpen: false,
  toasts: [],

  async checkConfig() {
    try {
      const res = await configApi.get();
      const runtimeConfigured = res.effective?.runtimeConfigured === true;
      set({
        effective: res.effective,
        configStatus: runtimeConfigured ? "configured" : "missing",
      });
    } catch {
      set({ configStatus: "missing", effective: null });
    }
  },

  async applyConfig(body) {
    try {
      await configApi.apply(body);
      await get().checkConfig();
      get().toast("success", "Конфигурация применена");
      return true;
    } catch (err) {
      get().toast("error", err instanceof Error ? err.message : "Ошибка применения конфигурации");
      return false;
    }
  },

  async clearConfig() {
    try {
      await configApi.clear();
      await get().checkConfig();
    } catch {
      // ignore
    }
  },

  openSidebar: () => set({ sidebarOpen: true }),
  closeSidebar: () => set({ sidebarOpen: false }),
  toggleSidebar: () => set({ sidebarOpen: !get().sidebarOpen }),

  toast(kind, message) {
    const id = `t_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
    set({ toasts: [...get().toasts, { id, kind, message }] });
    setTimeout(() => get().dismissToast(id), 5000);
  },

  dismissToast(id) {
    set({ toasts: get().toasts.filter((t) => t.id !== id) });
  },
}));
