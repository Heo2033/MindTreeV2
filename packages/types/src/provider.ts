export interface ProviderConfig {
  id: string;
  name: string;
  title: string;
  baseUrl: string;
  apiKeyStored: boolean;
  kind: "openai-compatible" | "ollama";
  parameters: Record<string, unknown>;
  enabled: boolean;
}

export interface LLMModel {
  id: string;
  name: string;
  providerId: string;
  capabilities: LLMCapabilities;
  enabled: boolean;
  isDefault: boolean;
}

export interface LLMCapabilities {
  textGeneration: boolean;
  streaming: boolean;
  functionCalling: boolean;
  vision: boolean;
  jsonMode: boolean;
  contextWindow: number;
}

export const DEFAULT_LLM_CAPABILITIES: LLMCapabilities = {
  textGeneration: true,
  streaming: true,
  functionCalling: false,
  vision: false,
  jsonMode: false,
  contextWindow: 128000,
};

export interface AppSettings {
  version: number;
  providers: ProviderConfig[];
  models: LLMModel[];
  defaultModelId: string | null;
  defaultProviderId: string | null;
  autoFallbackModels: boolean;
}
