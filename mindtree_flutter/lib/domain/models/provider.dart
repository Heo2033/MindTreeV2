/// Provider configuration for an LLM backend.
class ProviderConfig {
  final String id;
  final String name;
  final String title;
  final String baseUrl;
  final bool apiKeyStored;
  final String kind; // 'openai-compatible' | 'ollama'
  final Map<String, dynamic> parameters;
  final bool enabled;

  const ProviderConfig({
    required this.id,
    required this.name,
    required this.title,
    required this.baseUrl,
    this.apiKeyStored = false,
    this.kind = 'openai-compatible',
    this.parameters = const {},
    this.enabled = true,
  });

  bool get isOllama => kind == 'ollama' || baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1');

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        title: json['title'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKeyStored: json['apiKeyStored'] as bool? ?? false,
        kind: json['kind'] as String? ?? 'openai-compatible',
        parameters: json['parameters'] as Map<String, dynamic>? ?? {},
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'baseUrl': baseUrl,
        'apiKeyStored': apiKeyStored,
        'kind': kind,
        'parameters': parameters,
        'enabled': enabled,
      };
}

/// LLM capabilities.
class LLMCapabilities {
  final bool textGeneration;
  final bool streaming;
  final bool functionCalling;
  final bool vision;
  final bool jsonMode;
  final int contextWindow;

  const LLMCapabilities({
    this.textGeneration = true,
    this.streaming = true,
    this.functionCalling = false,
    this.vision = false,
    this.jsonMode = false,
    this.contextWindow = 128000,
  });

  factory LLMCapabilities.fromJson(Map<String, dynamic> json) => LLMCapabilities(
        textGeneration: json['textGeneration'] as bool? ?? true,
        streaming: json['streaming'] as bool? ?? true,
        functionCalling: json['functionCalling'] as bool? ?? false,
        vision: json['vision'] as bool? ?? false,
        jsonMode: json['jsonMode'] as bool? ?? false,
        contextWindow: (json['contextWindow'] as num? ?? 128000).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'textGeneration': textGeneration,
        'streaming': streaming,
        'functionCalling': functionCalling,
        'vision': vision,
        'jsonMode': jsonMode,
        'contextWindow': contextWindow,
      };

  const LLMCapabilities.defaults() : this();
}

/// An LLM model.
class LLMModel {
  final String id;
  final String name;
  final String providerId;
  final LLMCapabilities capabilities;
  final bool enabled;
  final bool isDefault;

  const LLMModel({
    required this.id,
    required this.name,
    required this.providerId,
    this.capabilities = const LLMCapabilities.defaults(),
    this.enabled = true,
    this.isDefault = false,
  });

  factory LLMModel.fromJson(Map<String, dynamic> json) => LLMModel(
        id: json['id'] as String,
        name: json['name'] as String,
        providerId: json['providerId'] as String,
        capabilities: json['capabilities'] != null
            ? LLMCapabilities.fromJson(json['capabilities'] as Map<String, dynamic>)
            : const LLMCapabilities.defaults(),
        enabled: json['enabled'] as bool? ?? true,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerId': providerId,
        'capabilities': capabilities.toJson(),
        'enabled': enabled,
        'isDefault': isDefault,
      };
}

/// Application settings for providers and models.
class AppSettings {
  final int version;
  final List<ProviderConfig> providers;
  final List<LLMModel> models;
  final String? defaultModelId;
  final String? defaultProviderId;
  final bool autoFallbackModels;

  const AppSettings({
    this.version = 1,
    this.providers = const [],
    this.models = const [],
    this.defaultModelId,
    this.defaultProviderId,
    this.autoFallbackModels = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        version: (json['version'] as num? ?? 1).toInt(),
        providers: (json['providers'] as List<dynamic>? ?? [])
            .map((e) => ProviderConfig.fromJson(e as Map<String, dynamic>))
            .toList(),
        models: (json['models'] as List<dynamic>? ?? [])
            .map((e) => LLMModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        defaultModelId: json['defaultModelId'] as String?,
        defaultProviderId: json['defaultProviderId'] as String?,
        autoFallbackModels: json['autoFallbackModels'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'providers': providers.map((e) => e.toJson()).toList(),
        'models': models.map((e) => e.toJson()).toList(),
        'defaultModelId': defaultModelId,
        'defaultProviderId': defaultProviderId,
        'autoFallbackModels': autoFallbackModels,
      };
}

/// LLM usage token counts.
class LLMUsage {
  final int inputTokens;
  final int outputTokens;

  const LLMUsage({this.inputTokens = 0, this.outputTokens = 0});

  factory LLMUsage.fromJson(Map<String, dynamic> json) => LLMUsage(
        inputTokens: (json['input_tokens'] as num? ?? 0).toInt(),
        outputTokens: (json['output_tokens'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
      };
}

/// Result of an LLM call.
class LLMResult {
  final String text;
  final LLMUsage usage;

  const LLMResult({required this.text, this.usage = const LLMUsage()});
}
