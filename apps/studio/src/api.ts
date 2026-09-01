const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";

export interface RuntimeConfigBody {
  provider?: "ollama" | "openai" | "auto";
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  modelStrong?: string;
  modelFast?: string;
  temperature?: number;
  numCtx?: number;
}

export interface ServerConfigState {
  source: string;
  appliedAt: string | null;
  effective: {
    model?: string;
    modelStrong?: string;
    modelFast?: string;
    runtimeConfigured: boolean;
  };
  configFile: string;
}

export interface TestResult {
  ok: boolean;
  model?: string;
  latencyMs?: number;
  preview?: string;
  error?: string;
}

async function request<T>(path: string, options: RequestInit & { json?: unknown } = {}): Promise<T> {
  const { json, ...fetchOptions } = options;
  const headers: Record<string, string> = {
    ...(fetchOptions.headers as Record<string, string>),
  };
  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    fetchOptions.body = JSON.stringify(json);
  }
  const res = await fetch(`${API_BASE}${path}`, { ...fetchOptions, headers });
  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  return res.json();
}

export const configApi = {
  get: () => request<ServerConfigState>("/api/config"),
  apply: (body: RuntimeConfigBody) =>
    request<{ ok: boolean; appliedAt: string; source: string }>("/api/config", {
      method: "POST",
      json: body,
    }),
  clear: () => request<{ ok: boolean; appliedAt: null }>("/api/config", { method: "DELETE" }),
  test: () => request<TestResult>("/api/config/test", { method: "POST", json: {} }),
};

export function apiBase(): string {
  return API_BASE;
}

export interface AdminStatus {
  uptimeMs: number;
  startedAt: string;
  config: {
    source: string;
    appliedAt: string | null;
    configFile: string;
    configuredBaseUrl: boolean;
    apiKeySet: boolean;
    effective: {
      model?: string;
      modelStrong?: string;
      modelFast?: string;
      runtimeConfigured: boolean;
    };
  };
  topics: { count: number };
  llm: {
    stats: { count: number; totalCost: number; totalInput: number; totalOutput: number };
    recent: Array<Record<string, unknown>>;
  };
  cache: Record<string, unknown>;
}

export interface AdminLogEntry {
  ts: string;
  level: "info" | "warn" | "error";
  message: string;
}

export interface AdminLogs {
  logs: AdminLogEntry[];
  llm: Array<Record<string, unknown>>;
}

export const adminApi = {
  status: () => request<AdminStatus>("/api/admin/status"),
  logs: () => request<AdminLogs>("/api/admin/logs"),
};
