// Чистые DTO эффективного LLM-конфига.
//
// Файл существует отдельно от `provider_config_service.dart` намеренно: сервис
// хранит API-ключ через `flutter_secure_storage` и `shared_preferences`, а его
// импорт тянет `dart:ui`. Данным слою (`data/llm/client.dart`) нужен только
// сам конфиг, поэтому мост `configFromEffective` импортирует ЭТОТ файл и
// остаётся пригодным для pure-Dart запусков (headless probe, dart-скрипты).
//
// `provider_config_service.dart` реэкспортирует этот файл, поэтому весь
// существующий код, импортирующий `EffectiveConfig` оттуда, продолжает
// работать без правок.

/// Effective LLM config used by the runtime.
class EffectiveConfig {
  final String baseUrl;
  final String? apiKey;
  final String model;
  final String modelStrong;
  final String modelStrongFallback;
  final String modelFast;

  /// `auto | openai | ollama`.
  final String provider;
  final double temperature;
  final int numCtx;

  /// Лимит выходных токенов одного запроса (было жёстко 4096).
  final int maxOutputTokens;

  /// Бюджет токенов рассуждений; `null` — не отправлять поле `reasoning`.
  final int? reasoningMaxTokens;

  /// Уровень усилий рассуждений (`reasoning.effort`).
  ///
  /// Значения: `none | minimal | low | medium | high | xhigh | max`.
  /// `null` — объект `reasoning` не отправляется вовсе.
  ///
  /// Замер на живом провайдере (AITUNNEL, задача с ответом ~30 токенов):
  /// без `effort` модель вернула 4106 выходных токенов, из них 4077 — reasoning;
  /// с `effort: none` — 35 токенов и 0 reasoning. `minimal` не помогает
  /// (провайдер мапит уровень, Qwen всё равно думает 3209 токенов).
  ///
  /// По умолчанию `none`: все операции MindTree возвращают строгий JSON-контракт,
  /// поэтому рассуждения обычно не нужны, но тарифицируются как вывод.
  final String? reasoningEffort;

  final bool runtimeConfigured;

  const EffectiveConfig({
    required this.baseUrl,
    this.apiKey,
    required this.model,
    required this.modelStrong,
    this.modelStrongFallback = '',
    required this.modelFast,
    this.provider = 'auto',
    this.temperature = 0.7,
    this.numCtx = 8192,
    this.maxOutputTokens = 16384,
    this.reasoningMaxTokens,
    this.reasoningEffort = 'none',
    this.runtimeConfigured = false,
  });

  factory EffectiveConfig.fromJson(Map<String, dynamic> json) => EffectiveConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String?,
        model: json['model'] as String? ?? '',
        modelStrong: json['modelStrong'] as String? ?? '',
        modelStrongFallback: json['modelStrongFallback'] as String? ?? '',
        modelFast: json['modelFast'] as String? ?? '',
        provider: json['provider'] as String? ?? 'auto',
        temperature: (json['temperature'] as num? ?? 0.7).toDouble(),
        numCtx: (json['numCtx'] as num? ?? 8192).toInt(),
        maxOutputTokens: (json['maxOutputTokens'] as num? ?? 16384).toInt(),
        reasoningMaxTokens: (json['reasoningMaxTokens'] as num?)?.toInt(),
        reasoningEffort: json['reasoningEffort'] as String? ?? 'none',
        runtimeConfigured: json['runtimeConfigured'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        if (apiKey != null) 'apiKey': apiKey,
        'model': model,
        'modelStrong': modelStrong,
        'modelStrongFallback': modelStrongFallback,
        'modelFast': modelFast,
        'provider': provider,
        'temperature': temperature,
        'numCtx': numCtx,
        'maxOutputTokens': maxOutputTokens,
        if (reasoningMaxTokens != null) 'reasoningMaxTokens': reasoningMaxTokens,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
        'runtimeConfigured': runtimeConfigured,
      };
}
