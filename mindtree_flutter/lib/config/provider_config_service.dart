import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_env.dart';

/// Effective LLM config used by the runtime.
class EffectiveConfig {
  final String baseUrl;
  final String? apiKey;
  final String model;
  final String modelStrong;
  final String modelStrongFallback;
  final String modelFast;
  final String provider; // auto | openai | ollama
  final double temperature;
  final int numCtx;
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
        'runtimeConfigured': runtimeConfigured,
      };
}

/// Runtime config body (what the user enters in settings).
class RuntimeConfigBody {
  final String? provider;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? modelStrong;
  final String? modelStrongFallback;
  final String? modelFast;
  final double? temperature;
  final int? numCtx;

  const RuntimeConfigBody({
    this.provider,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.modelStrong,
    this.modelStrongFallback,
    this.modelFast,
    this.temperature,
    this.numCtx,
  });

  Map<String, dynamic> toJson() => {
        if (provider != null) 'provider': provider,
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (apiKey != null) 'apiKey': apiKey,
        if (model != null) 'model': model,
        if (modelStrong != null) 'modelStrong': modelStrong,
        if (modelStrongFallback != null) 'modelStrongFallback': modelStrongFallback,
        if (modelFast != null) 'modelFast': modelFast,
        if (temperature != null) 'temperature': temperature,
        if (numCtx != null) 'numCtx': numCtx,
      };
}

/// Manages the effective LLM provider configuration.
///
/// In "hardcoded" build mode, the provider is fixed at compile time and the
/// settings UI is hidden. In "configurable" mode, values can be edited and are
/// persisted (API key in secure storage, the rest in SharedPreferences).
class ProviderConfigService {
  static const _prefsKey = 'mindtree_llm_config';
  static const _storageKey = 'mindtree_llm_api_key';

  final FlutterSecureStorage _storage;

  ProviderConfigService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Whether the provider is configurable at runtime.
  bool get isConfigurable => !ProviderEnv.isHardcoded;

  /// Build-time defaults for the effective config.
  EffectiveConfig get buildDefaults => EffectiveConfig(
        baseUrl: ProviderEnv.baseUrl,
        model: ProviderEnv.model,
        modelStrong: ProviderEnv.modelStrong.isNotEmpty
            ? ProviderEnv.modelStrong
            : ProviderEnv.model,
        modelStrongFallback: ProviderEnv.modelStrongFallback,
        modelFast: ProviderEnv.modelFast.isNotEmpty
            ? ProviderEnv.modelFast
            : ProviderEnv.model,
        provider: ProviderEnv.provider,
        temperature: ProviderEnv.temperature,
        numCtx: ProviderEnv.numCtx,
      );

  /// Load the effective config: runtime overrides on top of build defaults.
  Future<EffectiveConfig> load() async {
    if (ProviderEnv.isHardcoded) {
      return EffectiveConfig(
        baseUrl: ProviderEnv.baseUrl,
        apiKey: ProviderEnv.apiKey.isNotEmpty ? ProviderEnv.apiKey : null,
        model: ProviderEnv.model,
        modelStrong: ProviderEnv.modelStrong.isNotEmpty
            ? ProviderEnv.modelStrong
            : ProviderEnv.model,
        modelStrongFallback: ProviderEnv.modelStrongFallback,
        modelFast: ProviderEnv.modelFast.isNotEmpty
            ? ProviderEnv.modelFast
            : ProviderEnv.model,
        provider: ProviderEnv.provider,
        temperature: ProviderEnv.temperature,
        numCtx: ProviderEnv.numCtx,
        runtimeConfigured: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final saved = raw != null ? jsonDecode(raw) as Map<String, dynamic> : null;
    final key = await _storage.read(key: _storageKey);
    final defaults = buildDefaults;

    return EffectiveConfig(
      baseUrl: saved?['baseUrl'] as String? ?? defaults.baseUrl,
      apiKey: key,
      model: saved?['model'] as String? ?? defaults.model,
      modelStrong: saved?['modelStrong'] as String? ?? defaults.modelStrong,
      modelStrongFallback:
          saved?['modelStrongFallback'] as String? ?? defaults.modelStrongFallback,
      modelFast: saved?['modelFast'] as String? ?? defaults.modelFast,
      provider: saved?['provider'] as String? ?? defaults.provider,
      temperature: (saved?['temperature'] as num?)?.toDouble() ?? defaults.temperature,
      numCtx: (saved?['numCtx'] as num?)?.toInt() ?? defaults.numCtx,
      runtimeConfigured: raw != null,
    );
  }

  /// Apply a runtime config (configurable mode only).
  Future<void> apply(RuntimeConfigBody body) async {
    final current = await load();
    final merged = EffectiveConfig(
      baseUrl: body.baseUrl ?? current.baseUrl,
      apiKey: body.apiKey ?? current.apiKey,
      model: body.model ?? current.model,
      modelStrong: body.modelStrong ?? current.modelStrong,
      modelStrongFallback:
          body.modelStrongFallback ?? current.modelStrongFallback,
      modelFast: body.modelFast ?? current.modelFast,
      provider: body.provider ?? current.provider,
      temperature: body.temperature ?? current.temperature,
      numCtx: body.numCtx ?? current.numCtx,
      runtimeConfigured: true,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'baseUrl': merged.baseUrl,
        'model': merged.model,
        'modelStrong': merged.modelStrong,
        'modelStrongFallback': merged.modelStrongFallback,
        'modelFast': merged.modelFast,
        'provider': merged.provider,
        'temperature': merged.temperature,
        'numCtx': merged.numCtx,
      }),
    );

    final key = body.apiKey;
    if (key != null) {
      if (key.isEmpty) {
        await _storage.delete(key: _storageKey);
      } else {
        await _storage.write(key: _storageKey, value: key);
      }
    }
  }

  /// Clear runtime overrides back to build defaults.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await _storage.delete(key: _storageKey);
  }
}
