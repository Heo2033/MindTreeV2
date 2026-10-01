/// Build-time overrides injected via `--dart-define`.
///
/// To hardcode an LLM provider into a specific build, provide a
/// `provider-config.json` file and build with:
///
/// ```
/// flutter build apk --dart-define-from-file=provider-config.json
/// ```
///
/// Example provider-config.json:
/// ```json
/// {
///   "PROVIDER_MODE": "hardcoded",
///   "LLM_BASE_URL": "https://api.openai.com/v1",
///   "LLM_API_KEY": "sk-...",
///   "LLM_MODEL": "gpt-4o",
///   "LLM_MODEL_STRONG": "gpt-4o",
///   "LLM_MODEL_FAST": "gpt-4o-mini",
///   "LLM_PROVIDER": "openai",
///   "LLM_TEMPERATURE": "0.7",
///   "LLM_NUM_CTX": "8192",
///   "LLM_MAX_OUTPUT_TOKENS": "16384",
///   "LLM_REASONING_MAX_TOKENS": "2000"
/// }
/// ```
class ProviderEnv {
  static const String _mode = String.fromEnvironment('PROVIDER_MODE', defaultValue: 'configurable');
  static const String baseUrl = String.fromEnvironment('LLM_BASE_URL');
  static const String apiKey = String.fromEnvironment('LLM_API_KEY');
  static const String model = String.fromEnvironment('LLM_MODEL');
  static const String modelStrong = String.fromEnvironment('LLM_MODEL_STRONG');
  static const String modelStrongFallback =
      String.fromEnvironment('LLM_MODEL_STRONG_FALLBACK');
  static const String modelFast = String.fromEnvironment('LLM_MODEL_FAST');
  static const String provider = String.fromEnvironment('LLM_PROVIDER', defaultValue: 'auto');
  static const String temperatureRaw = String.fromEnvironment('LLM_TEMPERATURE', defaultValue: '0.7');
  static const String numCtxRaw = String.fromEnvironment('LLM_NUM_CTX', defaultValue: '8192');
  static const String maxOutputTokensRaw =
      String.fromEnvironment('LLM_MAX_OUTPUT_TOKENS', defaultValue: '16384');
  static const String reasoningMaxTokensRaw = String.fromEnvironment('LLM_REASONING_MAX_TOKENS');

  /// Допустимые значения `LLM_REASONING_EFFORT` (AITUNNEL `reasoning.effort`).
  static const Set<String> reasoningEffortValues = {
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  };

  /// Пустая строка — не отправлять `reasoning` вовсе (значение по умолчанию).
  static const String reasoningEffortRaw =
      String.fromEnvironment('LLM_REASONING_EFFORT', defaultValue: '');

  /// Whether the provider is pre-configured at build time or user-configurable.
  static bool get isHardcoded => _mode.toLowerCase() == 'hardcoded';

  /// Whether a hardcoded API key is present.
  static bool get hasEmbeddedKey => apiKey.isNotEmpty;

  static double get temperature {
    final v = double.tryParse(temperatureRaw);
    return v ?? 0.7;
  }

  static int get numCtx {
    final v = int.tryParse(numCtxRaw);
    return v ?? 8192;
  }

  static int get maxOutputTokens {
    final v = int.tryParse(maxOutputTokensRaw);
    return (v == null || v <= 0) ? 16384 : v;
  }

  /// `null` — поле `reasoning` не отправляется (модель без thinking).
  static int? get reasoningMaxTokens {
    final v = int.tryParse(reasoningMaxTokensRaw);
    return (v == null || v <= 0) ? null : v;
  }

  /// Уровень усилений рассуждений.
  ///
  /// Пустая строка или недопустимое значение — поле `reasoning` не отправляется.
  static String? get reasoningEffort {
    final v = reasoningEffortRaw.trim().toLowerCase();
    return reasoningEffortValues.contains(v) ? v : null;
  }
}
