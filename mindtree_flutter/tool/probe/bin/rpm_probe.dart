// Замер реального потолка RPM провайдера.
//
// Зачем: TreeScheduler по умолчанию ограничен `maxRPM = 10` (1 вызов в 6 секунд)
// и `maxConcurrency = 2`. На живом прогоне дерева из 20 узлов это давало ~234 с
// чистого ожидания лимита из 320 с wall clock — то есть ограничение ритма, а не
// работа модели, задаёт скорость. Прежде чем поднимать лимиты, нужно знать,
// сколько вызовов в минуту провайдер действительно держит.
//
// Инструмент шлёт N запросов максимально плотным потоком через тот же
// LLM-клиент (общий код с приложением), печатает фактический темп и все ответы
// 429. Ключ не выводится.
//
// Запуск:
//   dart run tool/probe/bin/rpm_probe.dart --burst 12 --concurrency 12
//   dart run tool/probe/bin/rpm_probe.dart --burst 12 --fast
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mindtree_flutter/data/llm/client.dart';

/// Минимальная задача: ответ нужен крошечный, поэтому замеряет именно ритм
/// запросов, а не скорость генерации.
const _prompt = 'Ответь ровно одним словом: да';

String? _str(String raw, String key) {
  final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(raw);
  return m?.group(1);
}

LLMConfig _readConfig(String path, {bool strong = false}) {
  final raw = File(path).readAsStringSync();
  final apiKey = _str(raw, 'LLM_API_KEY') ?? '';
  final baseUrl = _str(raw, 'LLM_BASE_URL') ?? '';
  // Основная работа пайплайна идёт на strong-модели, поэтому её потолок важнее.
  final fast = _str(raw, 'LLM_MODEL_FAST') ?? '';
  final strongModel = _str(raw, 'LLM_MODEL_STRONG') ?? '';
  final model = strong && strongModel.isNotEmpty ? strongModel : fast;
  return LLMConfig(
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model.isEmpty ? (_str(raw, 'LLM_MODEL') ?? 'gpt-4o') : model,
    temperature: 0,
    numCtx: 8192,
    timeoutMs: 120000,
    reasoningEffort: _str(raw, 'LLM_REASONING_EFFORT'),
  );
}

Future<void> main(List<String> args) async {
  var burst = 12;
  var concurrency = 12;
  var configPath = 'provider-config.json';
  var strong = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--burst':
        burst = int.parse(args[++i]);
      case '--concurrency':
        concurrency = int.parse(args[++i]);
      case '--config':
        configPath = args[++i];
      case '--strong':
        strong = true;
    }
  }

  if (!File(configPath).existsSync()) {
    stderr.writeln('Нет конфига $configPath — замер невозможен.');
    exit(2);
  }
  final cfg = _readConfig(configPath, strong: strong);
  if (cfg.apiKey.isEmpty) {
    stderr.writeln('В конфиге нет ключа.');
    exit(2);
  }

  stdout.writeln('Модель: ${cfg.model}');
  stdout.writeln('Бурст: $burst запросов, одновременно до $concurrency, '
      'потолок RPM не ограничиваем');

  final started = DateTime.now();
  final stamps = <DateTime>[];
  final errors = <String>[];

  // Плотный поток: каждая волна стартует одновременно, ограничение только
  // размером волны (эмулируем «хочу максимум» и смотрим, что ответит провайдер).
  Future<void> one() async {
    try {
      await callLLM(cfg, _prompt);
      stamps.add(DateTime.now());
    } catch (e) {
      final text = e.toString();
      errors.add(text.contains('429') ? '429' : text.split('\n').first);
    }
  }

  var sent = 0;
  while (sent < burst) {
    final wave = <Future<void>>[];
    for (var i = sent; i < burst && i < sent + concurrency; i++) {
      wave.add(one());
    }
    sent += wave.length;
    await Future.wait(wave);
  }

  final elapsedMs = DateTime.now().difference(started).inMilliseconds;
  stamps.sort();

  stdout.writeln('Успешно: ${stamps.length} из $burst');
  if (errors.isNotEmpty) {
    final counts = <String, int>{};
    for (final e in errors) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    for (final e in counts.entries) {
      stdout.writeln('  ошибок «${e.key}»: ${e.value}');
    }
  }

  stdout.writeln('');
  stdout.writeln('Wall clock: ${(elapsedMs / 1000).toStringAsFixed(1)} с');
  if (elapsedMs > 0) {
    stdout.writeln('Достигнутый темп: ${(stamps.length * 60000 / elapsedMs).toStringAsFixed(1)} вызовов/мин');
  }
  if (stamps.length >= 2) {
    stdout.writeln('Первый ответ: +${stamps.first.difference(started).inMilliseconds} мс');    stdout.writeln('Последний ответ: +${stamps.last.difference(started).inMilliseconds} мс');
    // Размах между ответами показывает, был ли темп сглажен сервером.
    final gaps = <int>[];
    for (var i = 1; i < stamps.length; i++) {
      gaps.add(stamps[i].difference(stamps[i - 1]).inMilliseconds);
    }
    if (gaps.isNotEmpty) {
      final minGap = gaps.reduce((a, b) => a < b ? a : b);
      stdout.writeln('Минимальный интервал между ответами: $minGap мс');
    }
  }

  if (errors.any((e) => e == '429')) {
    stdout.writeln('');
    stdout.writeln('Провайдер отклонил часть бурста — это и есть потолок.');
  }
  // Не печатаем тело ответа: ключ и содержимое в лог не попадают.
  jsonEncode(const <String>[]);
}
