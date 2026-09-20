import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/provider_config_service.dart';

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
  const LLMUsage({this.inputTokens = 0, this.outputTokens = 0});
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
    this.provider = 'auto',
    this.isMock = false,
  });

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
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

typedef ModelTier = String;
const tierStrong = 'strong';
const tierFast = 'fast';

const _strongOps = {
  'structure', 'structure-l2', 'structure-l3', 'validate', 'repair',
  'quiz', 'curriculum', 'diagnostic', 'assessment', 'mastery',
  'tutor', 'milestone',
};

ModelTier tierForOperation(String op) => _strongOps.contains(op) ? tierStrong : tierFast;

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

  String get content {
    final c = delta?.content ?? message?.content ?? '';
    if (c.isNotEmpty) return c;
    return delta?.reasoningContent ?? message?.reasoningContent ?? '';
  }
}

class _Delta {
  final String content;
  final String reasoningContent;
  _Delta({this.content = '', this.reasoningContent = ''});

  factory _Delta.fromJson(Map<String, dynamic> j) => _Delta(
        content: j['content']?.toString() ?? '',
        reasoningContent: j['reasoning_content']?.toString() ?? '',
      );
}

class _Usage {
  final int promptTokens;
  final int completionTokens;
  _Usage({this.promptTokens = 0, this.completionTokens = 0});

  factory _Usage.fromJson(Map<String, dynamic> j) => _Usage(
        promptTokens: (j['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (j['completion_tokens'] as num?)?.toInt() ?? 0,
      );
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

  throw Exception('AI returned invalid JSON');
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

  // Build candidate request bodies.
  final baseBody = <String, dynamic>{
    'model': useModel,
    'messages': [{'role': 'system', 'content': systemPrompt}],
    'temperature': temp,
  };
  final candidates = <Map<String, dynamic>>[];
  if (seed != null) {
    candidates.add({...baseBody, 'seed': seed, 'response_format': {'type': 'json_object'}});
  }
  candidates.add({...baseBody, 'response_format': {'type': 'json_object'}});
  candidates.add({...baseBody});
  candidates.add({
    'model': useModel,
    'messages': [{'role': 'user', 'content': systemPrompt}],
    'temperature': temp,
  });

  // Try streaming first, then non-streaming, for each candidate.
  var streamRejected = false;
  Exception? lastError;
  for (final body in candidates) {
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
        } else {
          continue;
        }
      }
    }

    try {
      final result = await _chatCompletionsOnce(cfg, url, body, false, cfg.timeoutMs, promptChars);
      if (result != null) return result;
    } on LLMRateLimitException {
      rethrow;
    } catch (e) {
      lastError = e is Exception ? e : Exception(e.toString());
    }
  }

  throw lastError ?? Exception('Failed to get LLM response after all candidates');
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
