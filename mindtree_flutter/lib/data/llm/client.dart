import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// Импортируем ЧИСТЫЙ файл конфига, а не `provider_config_service.dart`:
// сервис тянет `flutter_secure_storage` → `dart:ui`, из-за чего весь граф
// `data/llm` перестаёт запускаться в pure-Dart (headless probe, dart-скрипты).
import '../../config/effective_config.dart';

// ─── Error types ──────────────────────────────────────────────────────────────

class LLMRateLimitException implements Exception {
  final int status;
  final String message;
  final int? retryAfter;
  LLMRateLimitException(this.status, this.message, [this.retryAfter]);

  @override
  String toString() {
    final extra = retryAfter != null ? ', retry-after: $retryAfter' : '';
    return 'LLM: превышен лимит запросов ($status)$extra${message.isNotEmpty ? ': $message' : ''}';
  }
}

class LLMMockException implements Exception {
  final String message;
  LLMMockException(this.message);

  @override
  String toString() => 'LLM: $message';
}

class LLMRetriesExhaustedException implements Exception {
  final Exception lastError;
  final int attempts;
  LLMRetriesExhaustedException(this.lastError, this.attempts);

  @override
  String toString() {
    final n = attempts < 1 ? 1 : attempts;
    return 'LLM: исчерпаны попытки запроса ($n); последняя ошибка: $lastError';
  }
}

// ─── Result type ──────────────────────────────────────────────────────────────

class LLMResult {
  final String text;
  final LLMUsage usage;
  const LLMResult({required this.text, this.usage = const LLMUsage()});
}

class LLMUsage {
  final int inputTokens;
  final int outputTokens;

  /// Токены рассуждений — часть `outputTokens`, но отдельная и обычно
  /// бо́льшая часть платного вывода. Провайдер отдаёт в
  /// `usage.completion_tokens_details.reasoning_tokens`; 0, если не отдаёт.
  final int reasoningTokens;

  /// Авторитетная стоимость запроса в рублях от провайдера (`usage.cost_rub`).
  /// `null`, если провайдер её не возвращает — тогда стоимость оценивается.
  final double? costRub;

  const LLMUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.costRub,
  });

  /// Доля вывода, потраченная на рассуждения (0..1).
  double get reasoningShare =>
      outputTokens <= 0 ? 0 : (reasoningTokens / outputTokens).clamp(0.0, 1.0);
}

// ─── Config ───────────────────────────────────────────────────────────────────

class LLMConfig {
  final String apiKey;
  final String baseUrl;
  final String model;
  final String modelStrong;
  final String modelStrongFallback;
  final String modelFast;
  final double temperature;
  final int numCtx;
  final int timeoutMs;

  /// Лимит выходных токенов на один запрос.
  ///
  /// Раньше жёстко 4096: этого не хватало `structure-l3` и `validate` на полном
  /// дереве — `details`/`analogy` обрезались на полуслове и JSON не парсился.
  final int maxOutputTokens;

  /// Бюджет токенов рассуждений (`reasoning.max_tokens`), если задан.
  ///
  /// Документация AITUNNEL: «max_tokens ответа должен быть строго больше бюджета
  /// мыслей, иначе на текст не останется места и ответ придёт пустым с
  /// finish_reason: "length"». Именно это ломало вызовы на glm-5.3* (thinking
  /// обязателен) при 4096. Оставляем `null` для моделей без thinking — лишний
  /// параметр в теле запроса не нужен.
  final int? reasoningMaxTokens;

  /// Уровень усилий рассуждений (`reasoning.effort`), если задан.
  ///
  /// Замер на живом провайдере: задача с ответом ~30 токенов без `effort`
  /// вернула 4106 выходных токенов (4077 из них — reasoning); с `effort: none`
  /// — 35 токенов и ноль reasoning, ответ остался валидным. `minimal` не
  /// помогает: провайдер мапит уровень и Qwen всё равно думает 3209 токенов.
  ///
  /// Взаимоисключающе с [reasoningMaxTokens]: провайдер требует «что-то одно».
  /// Приоритет у явного бюджета, тогда `effort` в тело запроса не попадает.
  final String? reasoningEffort;

  final String provider; // 'ollama' | 'openai' | 'auto'
  final bool isMock;

  const LLMConfig({
    this.apiKey = '',
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-4o',
    this.modelStrong = '',
    this.modelStrongFallback = '',
    this.modelFast = '',
    this.temperature = 0.4,
    this.numCtx = 16384,
    this.timeoutMs = 180000,
    this.maxOutputTokens = 16384,
    this.reasoningMaxTokens,
    this.reasoningEffort = 'none',
    this.provider = 'auto',
    this.isMock = false,
  });

  /// Блок `reasoning` для тела запроса.
  ///
  /// Провайдер (AITUNNEL) не принимает `effort` и `max_tokens` одновременно,
  /// поэтому явный бюджет токенов имеет приоритет. Пустая карта = поле
  /// `reasoning` не отправляем вообще.
  Map<String, dynamic> get reasoningBlock {
    if (reasoningMaxTokens != null) {
      return {'max_tokens': reasoningMaxTokens};
    }
    final effort = reasoningEffort?.trim();
    if (effort == null || effort.isEmpty) return const {};
    return {'effort': effort};
  }

  String get modelStrongResolved => modelStrong.isNotEmpty ? modelStrong : model;
  String get modelFastResolved => modelFast.isNotEmpty ? modelFast : model;
  bool get isOllama =>
      provider == 'ollama' || (provider == 'auto' && _isOllamaBaseUrl(baseUrl));

  static bool _isOllamaBaseUrl(String url) =>
      RegExp(r'localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]').hasMatch(url);
}

LLMConfig configFromEffective(EffectiveConfig ec) {
  return LLMConfig(
    apiKey: ec.apiKey ?? '',
    baseUrl: ec.baseUrl.isNotEmpty ? ec.baseUrl : 'https://api.openai.com/v1',
    model: ec.model.isNotEmpty ? ec.model : 'gpt-4o',
    modelStrong: ec.modelStrong,
    modelStrongFallback: ec.modelStrongFallback,
    modelFast: ec.modelFast,
    temperature: ec.temperature,
    numCtx: ec.numCtx,
    provider: ec.provider,
    timeoutMs: 180000,
    maxOutputTokens: ec.maxOutputTokens,
    reasoningMaxTokens: ec.reasoningMaxTokens,
    reasoningEffort: ec.reasoningEffort ?? 'none',
  );
}

/// Температура для операции: `0` — детерминированный вывод, `null` — оставить
/// дефолт из конфига (его подставит сам `callLLM`).
///
/// Температура 0 даёт здесь двойную выгоду: меньше невалидного JSON на границах
/// схемы и заметно меньше токенов на сильной модели (прямое следствие
/// спецификации sampling: p(T=0) — один токен на позицию вместо ветвления).
double? defaultTemperatureForOperation(String op) =>
    _deterministicOps.contains(op) ? 0 : null;

/// Детерминированные операции. Всё, что не попало сюда, использует `cfg.temperature`:
/// `quiz`/`diagnostic`/`tutor`/`milestone`/`content` выиграют от вариативности
/// формулировок, а детерминированный разбор дерева или вердикт по ответу — нет.
const _deterministicOps = {
  'structure', 'structure-l2', 'structure-l3', 'validate',
  'curriculum', 'assessment', 'mastery',
};

/// Жёсткий кап числа HTTP-запросов на один логический вызов `callLLM`.
///
/// Провайдер может отвергнуть конкретное тело запроса (нет `response_format`,
/// не принимает `system`), и раньше на каждый вариант приходилось пробовать ещё
/// и стриминг — до 8 запросов по `timeoutMs` каждый. Смысл капа: не дать одному
/// сломанному провайдеру раздуть латентность в разы. Дальше решает
/// `TreeScheduler` — у него свои retry и fallback на другую модель.
const int _maxTransportAttempts = 3;

// ─── Helpers ──────────────────────────────────────────────────────────────────

typedef ModelTier = String;
const tierStrong = 'strong';
const tierFast = 'fast';

const _strongOps = {
  'structure', 'structure-l2', 'structure-l3', 'validate',
  'quiz', 'curriculum', 'diagnostic', 'assessment', 'mastery',
  'tutor', 'milestone',
};

/// Операции, явно приписанные к быстрому тиру («остальное» по AGENTS.md).
/// Любая операция вне `_strongOps` тоже fast — список фиксирует намерение
/// (например, `feedback` — дешёвая оценка ответа шага, не LLM-мастерство)
/// и защищает от случайного переноса операции в strong.
///
/// `repair` в fast-тиру: работает только по проблемным узлам (не тащит всё
/// дерево), а при неудаче дерево остаётся в прежнем состоянии — доменная
/// логика не зависит от качества ремонта (решение от 2026-09-30).
const _fastOps = {
  'feedback', 'activity', 'content', 'expand', 'oneline-rewrite',
  'repair',
};

ModelTier tierForOperation(String op) {
  if (_fastOps.contains(op)) return tierFast;
  return _strongOps.contains(op) ? tierStrong : tierFast;
}

String modelForTier(LLMConfig cfg, ModelTier tier) =>
    tier == tierStrong ? cfg.modelStrongResolved : cfg.modelFastResolved;

List<String> modelsForTier(LLMConfig cfg, ModelTier tier) {
  final primary = modelForTier(cfg, tier);
  final result = <String>[primary];
  if (tier == tierStrong && cfg.modelStrongFallback.isNotEmpty &&
      cfg.modelStrongFallback != primary) {
    result.add(cfg.modelStrongFallback);
  }
  return result;
}

String hashSeed(String input) {
  var hash = 0x811c9dc5 & 0xffffffff;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash >>> 0).toString();
}

// ─── Cooldown map ─────────────────────────────────────────────────────────────

final Map<String, int> _cooldowns = {};
const _defaultCooldownSec = 30;
const _rateLimitStatuses = {408, 429, 502, 503, 504};

// ─── Reasoning-параметр и его несовместимость с моделью ────────────────────────

/// Ключи `baseUrl|model`, для которых провайдер уже отверг объект `reasoning`.
///
/// У части моделей (семейство `glm-5.3*`) thinking обязателен и
/// `reasoning: {effort: none}` возвращает ошибку. Чтобы не платить за
/// бесполезный отказ на каждом вызове, достаточно одного отказа на пару
/// «провайдер+модель» — дальше поле просто не отправляется.
final Set<String> _reasoningUnsupported = {};

final RegExp _reasoningRejectionRe = RegExp(
  r'reasoning|thinking|effort|思考',
  caseSensitive: false,
);

/// Тело блока `reasoning` для конкретной модели, с учётом уже известных отказов.
Map<String, dynamic> _reasoningBlockFor(LLMConfig cfg, String model) {
  if (_reasoningUnsupported.contains('${cfg.baseUrl}|$model')) {
    return const {};
  }
  return cfg.reasoningBlock;
}

/// Ответ провайдера означает, что объект `reasoning` неприемлем для модели?
bool _isReasoningRejection(Object error) {
  final text = error.toString();
  if (!RegExp(r'\b(400|422)\b').hasMatch(text)) return false;
  return _reasoningRejectionRe.hasMatch(text);
}

// ─── Retry logic ──────────────────────────────────────────────────────────────

bool shouldRetry(Object err, int attempt, int maxRetries) {
  if (attempt >= maxRetries) return false;
  if (err is LLMMockException) return false;
  final status = _extractStatus(err);
  if (status != null && _rateLimitStatuses.contains(status) && attempt >= 2) return false;
  return true;
}

int retryDelayMs(Object err, int attempt) {
  final status = _extractStatus(err);
  if (status == null) return (attempt + 1) * 2000;
  if (status == 429) {
    final ra = _retryAfterOf(err);
    return ra != null ? (ra * 1000).clamp(0, 60000) : (attempt + 1) * 10000;
  }
  final ra = _retryAfterOf(err);
  final capSec = (attempt + 1) * 10;
  final waitSec = (ra ?? 10).clamp(0, capSec);
  return waitSec * 1000;
}

int? _extractStatus(Object err) {
  if (err is LLMRateLimitException) return err.status;
  final m = RegExp(r'\((\d{3})\)').firstMatch(err.toString());
  return m != null ? int.tryParse(m.group(1) ?? '') : null;
}

int? _retryAfterOf(Object err) {
  if (err is LLMRateLimitException) return err.retryAfter;
  return null;
}

// ─── Chat payload parsing ─────────────────────────────────────────────────────

class _ChatPayload {
  final _Choice? choice;
  final _Usage? usage;
  _ChatPayload({this.choice, this.usage});

  factory _ChatPayload.fromJson(Map<String, dynamic> j) {
    final choices = j['choices'] as List?;
    final first = choices != null && choices.isNotEmpty ? choices[0] as Map<String, dynamic> : null;
    return _ChatPayload(
      choice: first != null ? _Choice.fromJson(first) : null,
      usage: j['usage'] != null ? _Usage.fromJson(j['usage'] as Map<String, dynamic>) : null,
    );
  }
}

class _Choice {
  final _Delta? delta;
  final _Delta? message;
  _Choice({this.delta, this.message});

  factory _Choice.fromJson(Map<String, dynamic> j) {
    return _Choice(
      delta: j['delta'] != null ? _Delta.fromJson(j['delta'] as Map<String, dynamic>) : null,
      message: j['message'] != null ? _Delta.fromJson(j['message'] as Map<String, dynamic>) : null,
    );
  }

  /// Текст ответа — и только он.
  ///
  /// Раньше здесь был fallback на `reasoningContent`, если `content` пуст. Для
  /// клиента с JSON-контрактом это гарантированный промах: рассуждение — проза,
  /// парсер получал мусор вместо схемы. Теперь пустой `content` даёт пустой
  /// результат и штатный путь ретрая / fallback на другую модель.
  String get content => delta?.content ?? message?.content ?? '';
}

class _Delta {
  final String content;
  final String reasoningContent;
  _Delta({this.content = '', this.reasoningContent = ''});

  /// AITUNNEL отдаёт цепочку мыслей в `reasoning`; `reasoning_content` —
  /// документированный алиас для DeepSeek-совместимых клиентов. Читаем оба,
  /// но наружу reasoning не отдаём (см. [_Choice.content]).
  factory _Delta.fromJson(Map<String, dynamic> j) => _Delta(
        content: j['content']?.toString() ?? '',
        reasoningContent:
            j['reasoning']?.toString() ?? j['reasoning_content']?.toString() ?? '',
      );
}

class _Usage {
  final int promptTokens;
  final int completionTokens;
  final int reasoningTokens;
  final double? costRub;
  _Usage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens = 0,
    this.costRub,
  });

  factory _Usage.fromJson(Map<String, dynamic> j) {
    final completionDetails =
        j['completion_tokens_details'] as Map<String, dynamic>?;
    return _Usage(
      promptTokens: (j['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (j['completion_tokens'] as num?)?.toInt() ?? 0,
      reasoningTokens:
          (completionDetails?['reasoning_tokens'] as num?)?.toInt() ?? 0,
      costRub: (j['cost_rub'] as num?)?.toDouble(),
    );
  }
}

// ─── SSE stream consumption ───────────────────────────────────────────────────

Stream<String> _parseSseStream(Stream<List<int>> byteStream) async* {
  String buffer = '';
  await for (final bytes in byteStream) {
    buffer += utf8.decode(bytes, allowMalformed: true);
    final events = buffer.split('\n\n');
    buffer = events.removeLast(); // keep incomplete last chunk
    for (final event in events) {
      for (final line in event.split('\n')) {
        final trimmed = line.replaceFirst(RegExp(r'\r$'), '');
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final chunk = _ChatPayload.fromJson(jsonDecode(payload) as Map<String, dynamic>);
          final piece = chunk.choice?.content ?? '';
          if (piece.isNotEmpty) yield piece;
        } catch (_) {
          // skip malformed chunk
        }
      }
    }
  }
}

// ─── JSON repair ──────────────────────────────────────────────────────────────

String _repairControlChars(String input) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inString) {
      if (escaped) {
        escaped = false;
        out.write(ch);
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        out.write(ch);
        continue;
      }
      if (ch == '"') {
        inString = false;
        out.write(ch);
        continue;
      }
      final code = ch.codeUnitAt(0);
      if (code < 0x20) {
        out.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        continue;
      }
      out.write(ch);
      continue;
    }
    if (ch == '"') inString = true;
    out.write(ch);
  }
  return out.toString();
}

int _findMatchingBracket(String text, int start) {
  final open = text[start];
  final close = open == '{' ? '}' : ']';
  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == open) {
      depth++;
    } else if (ch == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

T parseLLMJson<T>(String raw) {
  final trimmed = raw.trim();

  // Direct parse.
  try {
    return jsonDecode(trimmed) as T;
  } catch (_) {}

  // Code fence extraction.
  final fence = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(trimmed);
  if (fence != null) {
    try {
      return jsonDecode(fence.group(1)!.trim()) as T;
    } catch (_) {}
    try {
      return jsonDecode(_repairControlChars(fence.group(1)!.trim())) as T;
    } catch (_) {}
  }

  // Bracket matching.
  final start = trimmed.indexOf(RegExp(r'[\[{]'));
  if (start != -1) {
    final end = _findMatchingBracket(trimmed, start);
    if (end != -1) {
      try {
        return jsonDecode(trimmed.substring(start, end + 1)) as T;
      } catch (_) {}
      try {
        return jsonDecode(_repairControlChars(trimmed.substring(start, end + 1))) as T;
      } catch (_) {}
    }
  }

  // Обрезанный ответ (например, упёрся в `max_tokens`): вместо полного
  // повтора запроса на медленной модели отбрасываем недописанный хвост.
  final salvaged = _salvageTruncatedJson(trimmed);
  if (salvaged != null) {
    try {
      return jsonDecode(salvaged) as T;
    } catch (_) {}
  }

  throw Exception('AI returned invalid JSON');
}

/// Чинит JSON, оборванный на середине (обрезка по `max_tokens`).
///
/// Возвращает `null`, если чинить нечего: верхний уровень уже закрыт, границ
/// элементов нет, или результат всё равно не парсится. Сознательно НЕ
/// подставляет значения полей и заглушки — только отбрасывает недописанный
/// хвост и закрывает скобки, поэтому результат остаётся подмножеством того,
/// что реально вернула модель. Детерминированная чистая функция ответа.
String? _salvageTruncatedJson(String s) {
  final start = s.indexOf(RegExp(r'[\[{]'));
  if (start == -1) return null;
  final body = s.substring(start);

  // Границы завершённых элементов верхнего уровня и незакрытые скобки.
  // Цикл стартует с 0: так сам верхний `[`/`{` попадает в [openStack], и
  // запятая на глубине 1 (openStack.length == 1) корректно считается границей.
  var lastBoundary = -1;
  var closedTopLevel = false;
  final openStack = <String>[];
  var inString = false;
  var escaped = false;

  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '[' || ch == '{') {
      openStack.add(ch);
    } else if (ch == ']' || ch == '}') {
      if (openStack.isEmpty) return null; // лишняя закрывающая — не чинится
      openStack.removeLast();
      if (openStack.isEmpty) {
        // Верхний уровень закрыт: ответ целиком, ремонт не нужен.
        closedTopLevel = true;
      }
    } else if (ch == ',' && openStack.length == 1) {
      // Запятая на глубине 1 отделяет завершённый элемент/значение.
      lastBoundary = i;
    }
  }

  if (closedTopLevel) return null;

  // Предпочитаем срез по последней границе: так недописанный элемент
  // отбрасывается целиком. Если границ нет, пытаемся просто закрыть скобки.
  for (final candidate in <String?>[
    if (lastBoundary > 0) body.substring(0, lastBoundary),
    body,
  ]) {
    if (candidate == null) continue;
    final closed = _closeJson(candidate);
    if (closed == null) continue;
    try {
      jsonDecode(closed);
      return closed;
    } catch (_) {
      // Следующий кандидат.
    }
  }
  return null;
}

/// Закрывает незавершённую строку и все незакрытые скобки в порядке вложенности.
String? _closeJson(String body) {
  final open = <String>[];
  var inString = false;
  var escaped = false;

  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '[' || ch == '{') {
      open.add(ch);
    } else if (ch == ']' || ch == '}') {
      if (open.isEmpty) return null;
      open.removeLast();
    }
  }

  final tail = StringBuffer();
  if (inString) tail.write('"'); // недописанное значение отбрасываем
  for (var i = open.length - 1; i >= 0; i--) {
    tail.write(open[i] == '[' ? ']' : '}');
  }
  return '$body$tail';
}

// ─── Ollama call ──────────────────────────────────────────────────────────────

Future<LLMResult> _callOllama(LLMConfig cfg, String systemPrompt, double temperature, String? model) async {
  final baseUrl = cfg.baseUrl.replaceFirst(RegExp(r'/v1/?$'), '');
  final body = {
    'model': model ?? cfg.model,
    'messages': [{'role': 'system', 'content': systemPrompt}],
    'stream': false,
    'options': {
      'temperature': temperature,
      'num_ctx': cfg.numCtx,
      'num_predict': cfg.maxOutputTokens,
    },
  };

  final response = await http
      .post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(Duration(milliseconds: cfg.timeoutMs));

  if (response.statusCode == 429 || response.statusCode == 408) {
    final retryAfter = _parseRetryAfter(response.headers['retry-after']);
    if (response.statusCode == 429) {
      _cooldowns[cfg.baseUrl] = DateTime.now().millisecondsSinceEpoch +
          (retryAfter ?? _defaultCooldownSec) * 1000;
    }
    throw LLMRateLimitException(response.statusCode, _compactErrorBody(response.body), retryAfter);
  }
  if (!response.statusCode.toString().startsWith('2')) {
    throw Exception('LLM API error (${response.statusCode}): ${_compactErrorBody(response.body)}');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data['error'] != null) {
    throw Exception('LLM API error: ${data['error']}');
  }
  final content = data['message']?['content']?.toString().trim() ?? '';
  if (content.isEmpty) throw Exception('LLM API returned empty response');

  final estInput = (systemPrompt.length / 4).ceil();
  final estOutput = (content.length / 4).ceil();
  return LLMResult(
    text: content,
    usage: LLMUsage(inputTokens: estInput, outputTokens: estOutput),
  );
}

// ─── Single chat completions attempt ──────────────────────────────────────────

Future<LLMResult?> _chatCompletionsOnce(
  LLMConfig cfg,
  String url,
  Map<String, dynamic> body,
  bool stream,
  int timeoutMs,
  int promptChars,
) async {
  final wireBody = stream ? {...body, 'stream': true} : body;
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${cfg.apiKey}',
  };

  if (stream) {
    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll(headers);
    request.body = jsonEncode(wireBody);
    final response = await http.Client()
        .send(request)
        .timeout(Duration(milliseconds: timeoutMs));

    if (!response.statusCode.toString().startsWith('2')) {
      final errBody = await response.stream.bytesToString();
      final retryAfter = _parseRetryAfter(response.headers['retry-after']);
      if (response.statusCode == 429 || response.statusCode == 408) {
        throw LLMRateLimitException(response.statusCode, _compactErrorBody(errBody), retryAfter);
      }
      throw Exception('LLM API error (${response.statusCode}): ${_compactErrorBody(errBody)}');
    }

    final content = StringBuffer();
    await for (final piece in _parseSseStream(response.stream)) {
      content.write(piece);
    }
    final text = content.toString();
    if (text.trim().isEmpty) throw Exception('LLM API returned empty stream response');
    return LLMResult(
      text: text,
      usage: LLMUsage(
        inputTokens: (promptChars / 4).ceil(),
        outputTokens: (text.length / 4).ceil(),
      ),
    );
  }

  final response = await http
      .post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(wireBody),
      )
      .timeout(Duration(milliseconds: timeoutMs));

  if (!response.statusCode.toString().startsWith('2')) {
    final retryAfter = _parseRetryAfter(response.headers['retry-after']);
    if (response.statusCode == 429 || response.statusCode == 408) {
      throw LLMRateLimitException(response.statusCode, _compactErrorBody(response.body), retryAfter);
    }
    throw Exception('LLM API error (${response.statusCode}): ${_compactErrorBody(response.body)}');
  }

  final contentType = response.headers['content-type'] ?? '';
  if (contentType.contains('application/json') || contentType.isEmpty) {
    final parsed = _ChatPayload.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    final text = parsed.choice?.content ?? '';
    if (text.trim().isEmpty) throw Exception('LLM API returned empty response');
    return LLMResult(
      text: text,
      usage: LLMUsage(
        inputTokens: parsed.usage?.promptTokens ?? (promptChars / 4).ceil(),
        outputTokens: parsed.usage?.completionTokens ?? (text.length / 4).ceil(),
        reasoningTokens: parsed.usage?.reasoningTokens ?? 0,
        costRub: parsed.usage?.costRub,
      ),
    );
  }

  // Fallback: try to parse the buffered body as SSE text.
  final content = StringBuffer();
  for (final line in response.body.split('\n')) {
    final trimmed = line.replaceFirst(RegExp(r'\r$'), '');
    if (trimmed.startsWith('data:') && trimmed.substring(5).trim() != '[DONE]') {
      content.write(trimmed.substring(5));
    }
  }
  final text = content.toString();
  if (text.trim().isEmpty) throw Exception('LLM API returned empty response');
  return LLMResult(
    text: text,
    usage: LLMUsage(
      inputTokens: (promptChars / 4).ceil(),
      outputTokens: (text.length / 4).ceil(),
    ),
  );
}

// ─── Public: callLLM (non-streaming) ─────────────────────────────────────────

Future<LLMResult> callLLM(
  LLMConfig cfg,
  String systemPrompt, {
  String? model,
  double? temperature,
  int? seed,
}) async {
  if (cfg.isMock) throw LLMMockException('Offline mode: LLM unavailable');

  final providerKey = cfg.baseUrl;
  final now = DateTime.now().millisecondsSinceEpoch;
  final cooldownUntil = _cooldowns[providerKey] ?? 0;
  if (now < cooldownUntil) {
    final remainingSec = ((cooldownUntil - now) / 1000).ceil();
    throw LLMRateLimitException(429, 'LLM rate limit: cooldown active', remainingSec);
  }

  final temp = temperature ?? cfg.temperature;
  final useModel = model ?? cfg.model;

  if (cfg.isOllama) {
    return _callOllama(cfg, systemPrompt, temp, useModel);
  }

  final url = '${cfg.baseUrl}/chat/completions';
  final promptChars = systemPrompt.length;

  // Build candidate request bodies, most likely to succeed FIRST.
  //
  // Порядок важен для латентности: типичный успешный путь — один запрос с
  // `response_format: json_object`, а варианты ниже пробуются только если
  // предыдущие отвергнуты провайдером. Раньше стриминг пробовался первым, из-за
  // чего один логический вызов разворачивался в 4 тела × 2 режима = до 8
  // HTTP-запросов, каждый потенциально по `timeoutMs` (180 с) — на
  // таймаут-тяжёлом провайдере это и давало минуты на один вызов.
  final reasoningBlock = _reasoningBlockFor(cfg, useModel);

  /// Прогоняет список тел-кандидатов, возвращает результат или последнюю ошибку.
  Future<LLMResult> attemptAll(Map<String, dynamic> reasoning) async {
    final baseBody = <String, dynamic>{
      'model': useModel,
      'messages': [
        {'role': 'system', 'content': systemPrompt}
      ],
      'temperature': temp,
      'max_tokens': cfg.maxOutputTokens,
      if (reasoning.isNotEmpty) 'reasoning': reasoning,
    };
    final jsonBody = {...baseBody, 'response_format': {'type': 'json_object'}};
    final candidates = <Map<String, dynamic>>[
      if (seed != null) {...jsonBody, 'seed': seed},
      jsonBody,
      baseBody,
      {
        'model': useModel,
        'messages': [
          {'role': 'user', 'content': systemPrompt}
        ],
        'temperature': temp,
        'max_tokens': cfg.maxOutputTokens,
        if (reasoning.isNotEmpty) 'reasoning': reasoning,
      },
    ];

    // Try each candidate non-streaming first, then streaming; hard cap on the
    // total number of HTTP attempts so a broken provider cannot multiply
    // latency. Exhaustion throws the last error: the scheduler applies its own
    // retry/fallback-across-models policy on top.
    var streamRejected = false;
    var attempts = 0;
    Exception? lastError;
    outer:
    for (final body in candidates) {
      try {
        final result = await _chatCompletionsOnce(cfg, url, body, false, cfg.timeoutMs, promptChars);
        if (result != null) return result;
      } on LLMRateLimitException {
        rethrow;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        // Отказ именно из-за `reasoning` обрабатываем сразу: иначе остальные
        // кандидаты с тем же полем съедят лимит попыток и до отката дойдёт
        // только исчерпанный `_maxTransportAttempts`.
        if (body.containsKey('reasoning') && _isReasoningRejection(e)) rethrow;
        attempts++;
        if (attempts >= _maxTransportAttempts) break outer;
        continue;
      }
      attempts++;
      if (attempts >= _maxTransportAttempts) break outer;

      // Стрим — запасной путь для провайдеров, которые не отдают обычный ответ.
      if (!streamRejected) {
        try {
          final result = await _chatCompletionsOnce(cfg, url, body, true, cfg.timeoutMs, promptChars);
          if (result != null) return result;
        } on LLMRateLimitException {
          rethrow;
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          if (e.toString().contains('400') || e.toString().contains('stream')) {
            streamRejected = true;
          }
          attempts++;
          if (attempts >= _maxTransportAttempts) break outer;
        }
      }
    }
    throw lastError ?? Exception('Failed to get LLM response after all candidates');
  }

  try {
    return await attemptAll(reasoningBlock);
  } catch (e) {
    // Модель с обязательным thinking (glm-5.3*) отвергает объект `reasoning`.
    // Помечаем пару «провайдер+модель» и повторяем ровно один раз без него,
    // чтобы пользовательский сценарий не падал из-за необязательного параметра.
    if (reasoningBlock.isEmpty || !_isReasoningRejection(e)) rethrow;
    _reasoningUnsupported.add('${cfg.baseUrl}|$useModel');
    return attemptAll(const {});
  }
}

// ─── Public: callLLMStream (streaming for tutor) ──────────────────────────────

Stream<String> callLLMStream(
  LLMConfig cfg,
  String systemPrompt, {
  String? model,
  double? temperature,
}) async* {
  if (cfg.isMock) throw LLMMockException('Offline mode: LLM unavailable');
  if (cfg.isOllama) throw Exception('Streaming not supported for Ollama');

  final useModel = model ?? cfg.model;
  final temp = temperature ?? cfg.temperature;
  final url = '${cfg.baseUrl}/chat/completions';

  final body = <String, dynamic>{
    'model': useModel,
    'messages': [{'role': 'system', 'content': systemPrompt}],
    'temperature': temp,
    'stream': true,
  };

  final request = http.Request('POST', Uri.parse(url));
  request.headers['Content-Type'] = 'application/json';
  request.headers['Authorization'] = 'Bearer ${cfg.apiKey}';
  request.body = jsonEncode(body);

  final streamedResponse = await http.Client().send(request).timeout(
    Duration(milliseconds: cfg.timeoutMs),
    onTimeout: () => throw Exception('LLM API: request timeout'),
  );

  if (!streamedResponse.statusCode.toString().startsWith('2')) {
    final bodyText = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode == 429) {
      final retryAfter = _parseRetryAfter(streamedResponse.headers['retry-after']);
      _cooldowns[cfg.baseUrl] = DateTime.now().millisecondsSinceEpoch +
          (retryAfter ?? _defaultCooldownSec) * 1000;
      throw LLMRateLimitException(streamedResponse.statusCode, _compactErrorBody(bodyText), retryAfter);
    }
    throw Exception('LLM API error (${streamedResponse.statusCode}): ${_compactErrorBody(bodyText)}');
  }

  var emitted = 0;
  // Чтение стрима ограничено клиентским таймаутом (зеркально server client.ts:
  // setTimeout(() => controller.abort(), timeoutMs)) — зависший SSE-провайдер
  // не может держать запрос бесконечно.
  await for (final piece in _parseSseStream(streamedResponse.stream)
      .timeout(Duration(milliseconds: cfg.timeoutMs))) {
    emitted += piece.length;
    yield piece;
  }

  if (emitted == 0) throw Exception('LLM API returned empty stream');
}

// ─── Utilities ────────────────────────────────────────────────────────────────

int? _parseRetryAfter(String? value) {
  if (value == null || value.isEmpty) return null;
  final seconds = double.tryParse(value);
  if (seconds != null && seconds >= 0) return seconds.ceil();
  try {
    final date = DateTime.parse(value);
    return date.difference(DateTime.now()).inSeconds.clamp(0, 3600);
  } catch (_) {}
  return null;
}

String _compactErrorBody(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'<!DOCTYPE html|<html[\s>]', caseSensitive: false).hasMatch(flat)) {
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false).firstMatch(flat);
    if (titleMatch != null) return 'HTML page: "${titleMatch.group(1)?.trim()}"';
    final stripped = flat.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return (stripped.isEmpty ? 'HTML provider page' : stripped).substring(0, 200.clamp(0, stripped.length));
  }
  return flat.length > 300 ? '${flat.substring(0, 300)}…' : flat;
}
