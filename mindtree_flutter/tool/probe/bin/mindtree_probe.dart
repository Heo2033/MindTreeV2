// Headless-прогон доменных движков MindTree.
//
// Probe собирает ровно те же движки, что и приложение (`buildEngines`), но
// без Flutter и Riverpod, и прогоняет полный цикл обучения на настоящем LLM
// (или на детерминированном fake в режиме `--mock`).
//
// Запуск:
//   dart run tool/probe/bin/mindtree_probe.dart --mock
//   dart run tool/probe/bin/mindtree_probe.dart \
//     --query "теорема остановки" --level 2 --out build/probe
//
// Отчёты:
//   <out>/report.json     — детерминированный (побайтово сравнимый)
//   <out>/report.md       — детерминированный
//   <out>/run-stats.json  — время и ретраи (НЕ детерминированные)
//
// Секреты: probe НИКОГДА не печатает и не пишет `apiKey`/`baseUrl`.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:mindtree_flutter/data/database/mindtree_db.dart';
import 'package:mindtree_flutter/data/database/mindtree_repository.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/domain/engines/engine_factory.dart';

import '../fake_llm.dart';
import '../pipeline.dart';
import '../probe_result.dart';
import '../report.dart';

const String _configPath = 'provider-config.json';

const String _usage = '''
MindTree probe — headless прогон доменных движков.

Опции:
  --query <текст>      Тема для прогона. Можно указать несколько раз
                       (каждый запрос — отдельная тема). По умолчанию:
                       один демонстрационный запрос.
  --goal <цель>        Цель обучения (например overview, exam). По умолчанию overview.
  --level <1..5>       Целевой уровень. По умолчанию 1.
  --minutes <N>        Бюджет времени, минут. По умолчанию 30.
  --out <каталог>      Куда положить отчёты. По умолчанию build/probe.
  --mock               Детерминированный прогон без сети (fake LLM).
  --concurrency <N>    maxConcurrency scheduler для живого прогона.
                       По умолчанию 2; для замера ускорения можно поднять
                       до 4–5 (RPM=10 это допускает).
  --max-nodes <N>      Ограничить число узлов дерева. 0 — без лимита.
  --skip-content       Не генерировать контент узлов.
  --skip-session       Не проходить учебную сессию и всё, что после неё.
  --keep-db            Сохранить Drift-БД в файл рядом с отчётами.
  --verbose            Печатать прогресс по шагам.
  --help               Эта справка.
''';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts == null) {
    stdout.write(_usage);
    exit(64); // EX_USAGE
  }

  final sw = Stopwatch()..start();

  // Режим без сети: fake LLM + щедрые лимиты scheduler, иначе десятки
  // вызовов уперлись бы в rate limit.
  final mock = opts.mock;
  final llmConfig = mock
      ? const llm_client.LLMConfig(
          isMock: true,
          temperature: 0,
          numCtx: 16384,
        )
      : _readRealConfig();

  if (llmConfig == null) {
    stderr.writeln('Не удалось прочитать $_configPath.');
    stderr.writeln('Сгенерируйте конфиг: & tool\\gen_config.ps1');
    stderr.writeln('Либо используйте --mock, чтобы обойтись без ключа.');
    exit(78); // EX_CONFIG
  }

  final dbFile = opts.keepDb ? File(_joinPath(opts.out, 'probe.db')) : null;
  if (dbFile != null) {
    dbFile.parent.createSync(recursive: true);
  }
  final db = MindtreeDb(
    dbFile == null
        ? NativeDatabase.memory()
        : NativeDatabase(dbFile),
  );

  // В mock-режиме подменяем транспорт: scheduler сохраняет rate-limit, retry
  // и телеметрию, а ответы приходят из детерминированного fake.
  final fake = mock ? FakeLlm() : null;
  final engines = buildEngines(
    repo: MindtreeRepository(db),
    configProvider: () => llmConfig,
    schedulerConfig: mock
        ? const SchedulerConfig(
            maxRPM: 100000,
            maxRPD: 100000,
            maxConcurrency: 1,
          )
        : SchedulerConfig(
            maxRPM: 10,
            maxRPD: 500,
            // Живой прогон: параллельность можно поднять флагом --concurrency
            // (RPM=10 это допускает; контент-пул и L3-ветви уже конкурентные).
            maxConcurrency: opts.concurrency > 0 ? opts.concurrency : 2,
            maxRetries: 2,
            opDeadlineMs: 300000,
          ),
    llmCall: fake == null
        ? null
        : (cfg, prompt, {model, temperature, seed}) async =>
            fake.invoke(cfg, prompt, model: model, temperature: temperature),
  );

  ProbeResult result;
  try {
    result = await runPipeline(
      engines,
      PipelineOptions(
        queries: opts.queries,
        goal: opts.goal,
        level: opts.level,
        minutes: opts.minutes,
        skipContent: opts.skipContent,
        skipSession: opts.skipSession,
        maxNodes: opts.maxNodes,
        mock: mock,
        onProgress:
            opts.verbose ? (m) => stdout.writeln('  $m') : null,
      ),
    );
  } finally {
    await db.close();
  }
  sw.stop();

  final outDir = Directory(opts.out)..createSync(recursive: true);
  final reportJson = File(_joinPath(outDir.path, 'report.json'));
  final reportMd = File(_joinPath(outDir.path, 'report.md'));
  final runStats = File(_joinPath(outDir.path, 'run-stats.json'));

  reportJson.writeAsStringSync(renderJson(result));
  reportMd.writeAsStringSync(renderMarkdown(result));
  runStats.writeAsStringSync(renderRunStats(RunStats(
    totalCalls: fake?.calls.length ?? result.llm.calls,
    wallClockMs: sw.elapsedMilliseconds,
    // Длительности транспортных попыток из телеметрии scheduler: в том числе
    // проваленных — без них не видно, сколько времени съели повторы.
    callDurationsMs: [
      for (final t in engines.scheduler.telemetry.callTimings()) t.durationMs,
    ],
    // Счётчики попыток: успешных вызовов меньше, чем попыток, когда
    // провайдер отвечает битым JSON / пустым телом.
    transportAttempts: engines.scheduler.stats()['transportAttempts'] as int,
    failedAttempts: engines.scheduler.stats()['failedAttempts'] as int,
  )));

  final summary = result.summary;
  stdout.writeln('Отчёты: ${outDir.path}');
  stdout.writeln('  report.json / report.md — детерминированные');
  stdout.writeln('  run-stats.json — время прогона (не детерминировано)');
  stdout.writeln('Запросов: ${result.outcomes.length}, '
      'узлов: ${result.outcomes.fold(0, (s, o) => s + o.nodes.length)}, '
      'LLM-вызовов: ${result.llm.calls}');
  stdout.writeln('Quality: ${summary.total} проверок '
      '(fail=${summary.fail}, warn=${summary.warn}, info=${summary.info})');
  stdout.writeln('Время: ${sw.elapsedMilliseconds} мс');

  // Fail-код при нарушениях уровня fail: удобно для CI.
  if (summary.hasFailures) {
    stderr.writeln('Есть quality-нарушения уровня fail — см. отчёт.');
    exit(1);
  }
}

/// Разобранные аргументы CLI.
class _Args {
  final List<String> queries;
  final String goal;
  final int level;
  final int minutes;
  final String out;
  final bool mock;
  final int concurrency;
  final int maxNodes;
  final bool skipContent;
  final bool skipSession;
  final bool keepDb;
  final bool verbose;

  const _Args({
    required this.queries,
    required this.goal,
    required this.level,
    required this.minutes,
    required this.out,
    required this.mock,
    required this.concurrency,
    required this.maxNodes,
    required this.skipContent,
    required this.skipSession,
    required this.keepDb,
    required this.verbose,
  });
}

_Args? _parseArgs(List<String> argv) {
  final queries = <String>[];
  var goal = 'overview';
  var level = 1;
  var minutes = 30;
  var out = 'build/probe';
  var mock = false;
  var concurrency = 0;
  var maxNodes = 0;
  var skipContent = false;
  var skipSession = false;
  var keepDb = false;
  var verbose = false;

  String? valueFor(String flag) {
    final i = argv.indexOf(flag);
    if (i < 0 || i + 1 >= argv.length) {
      stderr.writeln('Флаг $flag требует значение.');
      return null;
    }
    return argv[i + 1];
  }

  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    switch (a) {
      case '--help':
      case '-h':
        return null;
      case '--query':
        final v = valueFor('--query');
        if (v == null) return null;
        queries.add(v);
        i++;
      case '--goal':
        final v = valueFor('--goal');
        if (v == null) return null;
        goal = v;
        i++;
      case '--level':
        final v = valueFor('--level');
        if (v == null || int.tryParse(v) == null) {
          stderr.writeln('--level должен быть числом.');
          return null;
        }
        level = int.parse(v);
        i++;
      case '--minutes':
        final v = valueFor('--minutes');
        if (v == null || int.tryParse(v) == null) {
          stderr.writeln('--minutes должно быть числом.');
          return null;
        }
        minutes = int.parse(v);
        i++;
      case '--out':
        final v = valueFor('--out');
        if (v == null) return null;
        out = v;
        i++;
      case '--max-nodes':
        final v = valueFor('--max-nodes');
        if (v == null || int.tryParse(v) == null) {
          stderr.writeln('--max-nodes должно быть числом.');
          return null;
        }
        maxNodes = int.parse(v);
        i++;
      case '--mock':
        mock = true;
      case '--concurrency':
        final v = valueFor('--concurrency');
        if (v == null || int.tryParse(v) == null) {
          stderr.writeln('--concurrency должно быть числом.');
          return null;
        }
        concurrency = int.parse(v);
        i++;
      case '--skip-content':
        skipContent = true;
      case '--skip-session':
        skipSession = true;
      case '--keep-db':
        keepDb = true;
      case '--verbose':
        verbose = true;
      default:
        stderr.writeln('Неизвестный флаг: $a');
        return null;
    }
  }

  if (queries.isEmpty) {
    queries.add('доказательство теоремы остановки');
  }

  return _Args(
    queries: queries,
    goal: goal,
    level: level,
    minutes: minutes,
    out: out,
    mock: mock,
    concurrency: concurrency,
    maxNodes: maxNodes,
    skipContent: skipContent,
    skipSession: skipSession,
    keepDb: keepDb,
    verbose: verbose,
  );
}

/// Читает реальный провайдерский конфиг.
///
/// Возвращает `null`, если файла нет или он нечитаем. API-ключ НЕ логируется.
llm_client.LLMConfig? _readRealConfig() {
  final file = File(_configPath);
  if (!file.existsSync()) return null;
  try {
    final raw = file.readAsStringSync();
    // Разбираем вручную через Map, чтобы не тянуть dart:convert ради двух
    // полей и не выводить содержимое в лог.
    final apiKey = _jsonString(raw, 'LLM_API_KEY');
    final baseUrl = _jsonString(raw, 'LLM_BASE_URL');
    if (apiKey == null || apiKey.isEmpty || baseUrl == null) return null;
    return llm_client.LLMConfig(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: _jsonString(raw, 'LLM_MODEL') ?? 'gpt-4o',
      modelStrong: _jsonString(raw, 'LLM_MODEL_STRONG') ?? '',
      modelStrongFallback: _jsonString(raw, 'LLM_MODEL_STRONG_FALLBACK') ?? '',
      modelFast: _jsonString(raw, 'LLM_MODEL_FAST') ?? '',
      temperature: 0.4,
      numCtx: 8192,
      timeoutMs: 180000,
    );
  } catch (_) {
    return null;
  }
}

/// Достаёт строковое значение ключа верхнего уровня из плоского JSON.
///
/// Экстрагирован, чтобы не печатать содержимое конфига в лог и не тянуть
/// полноценный парсер там, где файла три поля.
String? _jsonString(String raw, String key) {
  final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
  final m = pattern.firstMatch(raw);
  return m?.group(1);
}

/// Склейка пути с учётом Windows-разделителя.
String _joinPath(String dir, String name) =>
    dir.endsWith(Platform.pathSeparator) || dir.endsWith('/')
        ? '$dir$name'
        : '$dir${Platform.pathSeparator}$name';
