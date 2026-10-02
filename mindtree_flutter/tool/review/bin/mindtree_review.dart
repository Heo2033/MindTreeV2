// CLI ревью MindTree: оценивает экспортированное дерево темы или учебную
// сессию в базе приложения.
//
// Два режима:
//   --tree <mindtree-*.json>   разбор файла темы + детерминированные проверки
//   --db <mindtree.db>         чтение сессии из базы + проверки сессии
//
// Опционально `--judge` — вызов LLM-судьи (нужен `provider-config.json`).
// Без сети и без ключа ревью полностью детерминировано.

import 'dart:io';

import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/data/llm/client.dart' as llm_client;
import 'package:mindtree_flutter/data/llm/scheduler.dart';

import '../judge.dart';
import '../report.dart';
import '../session_checks.dart';
import '../session_loader.dart';
import '../tree_checks.dart';

/// Конфиг провайдера читается, но никогда не печатается.
const String kDefaultConfigPath = 'provider-config.json';

const String _usage = '''
Ревью артефактов MindTree (дерево темы или учебная сессия).

Использование:
  dart run tool/review/bin/mindtree_review.dart --tree <mindtree-*.json> [опции]
  dart run tool/review/bin/mindtree_review.dart --db <mindtree.db> [--session <id>] [опции]

Опции:
  --tree <путь>        файл экспорта темы (можно указать несколько раз)
  --db <путь>          файл базы приложения mindtree.db (только чтение)
  --session <id>       конкретная сессия; без флага берётся последняя
  --limit <N>          сколько последних сессий разбирать (по умолчанию 20)
  --judge              прогнать LLM-судью (нужен провайдерский конфиг)
  --judge-batches <N>  максимум пачек узлов судьи (по умолчанию 20)
  --config <путь>      конфиг провайдера (по умолчанию provider-config.json)
  --out <каталог>      куда положить отчёты (по умолчанию build/review)
  --fail-on <fail|warn>  код возврата 1 начиная с этого уровня (по умолчанию fail)
  --help               эта справка

Коды возврата: 0 — ок, 1 — есть находки, 64 — ошибка аргументов,
78 — нет конфига для режима --judge.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    exit(args.isEmpty ? 64 : 0);
  }

  final treePaths = _multiArg(args, '--tree');
  final dbPath = _arg(args, '--db');
  final sessionId = _arg(args, '--session');
  final judge = args.contains('--judge');
  final outDir = _arg(args, '--out') ?? 'build/review';
  final failOn = _arg(args, '--fail-on') ?? 'fail';
  final limit = int.tryParse(_arg(args, '--limit') ?? '') ?? 20;
  final judgeBatches = int.tryParse(_arg(args, '--judge-batches') ?? '') ?? 20;

  if (treePaths.isEmpty && dbPath == null) {
    stderr.writeln('Укажите --tree <файл> или --db <mindtree.db>.\n\n$_usage');
    exit(64);
  }
  if (failOn != 'fail' && failOn != 'warn') {
    stderr.writeln('--fail-on принимает только fail или warn.');
    exit(64);
  }

  TreeScheduler? judgeScheduler;
  if (judge) {
    final config = _readConfig(_arg(args, '--config') ?? kDefaultConfigPath);
    if (config == null) {
      stderr.writeln(
        'Не найден конфиг провайдера. Создайте его: '
        '& tool\\gen_config.ps1 (нужны ключи, они не выводятся в отчёт).',
      );
      exit(78);
    }
    judgeScheduler = TreeScheduler(configProvider: () => config);
  }

  final reports = <ReviewReport>[];

  for (final path in treePaths) {
    reports.add(await _reviewTree(path, judgeScheduler, judgeBatches));
  }

  if (dbPath != null) {
    try {
      final sessions = await loadSessions(
        dbPath: dbPath,
        sessionId: sessionId,
        limit: limit,
      );
      for (final s in sessions) {
        reports.add(_reviewSession(s));
      }
    } on SessionLoadException catch (e) {
      stderr.writeln('$e');
      exit(78);
    }
  }

  if (reports.isEmpty) {
    stderr.writeln('Нечего ревьюить: ни одного артефакта.');
    exit(64);
  }

  writeReports(reports, outDir);
  for (final r in reports) {
    stdout.writeln(_stdoutLine(r));
  }

  final limitSeverity = failOn == 'warn' ? 1 : 2; // rank: info=0, warn=1, fail=2
  final worst = reports.fold<int>(0, (acc, r) {
    final a = r.summary.rankMax;
    final b = r.judgeSummary.rankMax;
    return [acc, a, b].reduce((x, y) => x > y ? x : y);
  });
  final dir = Directory(outDir);
  stdout.writeln('Отчёты: ${dir.path}');
  exit(worst >= limitSeverity ? 1 : 0);
}

// ─── Дерево ───────────────────────────────────────────────────────────────────

Future<ReviewReport> _reviewTree(
  String path,
  TreeScheduler? scheduler,
  int judgeBatches,
) async {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Файл темы не найден: $path');
    exit(78);
  }
  final TopicFile topicFile;
  try {
    topicFile = TopicFile.fromJsonString(file.readAsStringSync());
  } on TopicFileFormatException catch (e) {
    stderr.writeln('Файл не читается как тема MindTree: ${e.message}');
    exit(64);
  }

  final findings = runTreeChecks(topicFile);
  final warnings = <String>[
    if (!topicFile.isValid)
      'Файл формально некорректен: ${topicFile.errors.join('; ')}',
    ...topicFile.warnings,
  ];

  var judgeFindings = const <JudgeFinding>[];
  var judgeWarnings = const <String>[];
  var judgedNodes = 0;
  if (scheduler != null) {
    final result = await judgeTopicFile(
      file: topicFile,
      scheduler: scheduler,
      maxBatches: judgeBatches,
    );
    judgeFindings = result.findings;
    judgeWarnings = result.warnings;
    judgedNodes = result.reviewedNodes;
  }

  final ids = {for (final n in topicFile.nodes) n.id};
  final relations = [for (final n in topicFile.nodes) ...n.relations];
  final resolvable = relations.where((r) => ids.contains(r.to) && ids.contains(r.from)).length;
  final parents = {for (final n in topicFile.nodes) if (n.parentId != null) n.parentId!};
  final leaves = [for (final n in topicFile.nodes) if (!parents.contains(n.id)) n];
  final leafMinutes = leaves.fold<int>(0, (sum, n) => sum + n.estimatedTimeMinutes);
  final root = topicFile.roots.isEmpty ? null : topicFile.roots.first;
  final analogies = topicFile.nodes.where((n) => (n.analogy ?? '').trim().isNotEmpty).length;

  final metrics = <String, dynamic>{
    'nodeCount': topicFile.nodes.length,
    'leafCount': leaves.length,
    'leafMinutes': leafMinutes,
    'rootMinutes': root?.estimatedTimeMinutes ?? 0,
    'timeBudgetMinutes': topicFile.topic.timeBudgetMinutes,
    'budgetRatio': topicFile.topic.timeBudgetMinutes > 0
        ? double.parse((leafMinutes / topicFile.topic.timeBudgetMinutes).toStringAsFixed(2))
        : 0.0,
    'analogyCoverage': topicFile.nodes.isEmpty
        ? '0.0'
        : (analogies / topicFile.nodes.length).toStringAsFixed(2),
    'relationCount': relations.length,
    'resolvableRelationCount': resolvable,
    'danglingRelationCount': relations.length - resolvable,
    if (judgedNodes > 0) 'judgedNodes': judgedNodes,
  };

  return ReviewReport(
    kind: ReviewSubjectKind.tree,
    subject: path,
    topicName: topicFile.topic.name,
    subjectSummary: 'цель ${topicFile.topic.goal.raw}, '
        'уровень ${topicFile.topic.targetLevel.raw}, '
        'бюджет ${topicFile.topic.timeBudgetMinutes} мин',
    metrics: metrics,
    findings: findings,
    judgeFindings: judgeFindings,
    warnings: [...warnings, ...judgeWarnings],
  );
}

// ─── Сессия ───────────────────────────────────────────────────────────────────

ReviewReport _reviewSession(LoadedSession loaded) {
  final view = loaded.view;
  final answered = view.answeredSteps.length;
  final questionsAnswered =
      view.questions.where((q) => q.userAnswer != null).length;
  final correct =
      view.questions.where((q) => q.correct == true).length;

  final metrics = <String, dynamic>{
    'activityCount': view.activities.length,
    'stepCount': view.allSteps.length,
    'answeredSteps': answered,
    'questionCount': view.questions.length,
    'questionsAnswered': questionsAnswered,
    'questionsCorrect': correct,
    'eventCount': view.events.length,
    'masteryNodes': view.masteryAfter.length,
    'milestoneCount': loaded.milestones.length,
    'nodeCount': loaded.nodes.length,
    'timeBudgetMinutes': view.timeBudgetMinutes,
    'status': view.status,
  };

  return ReviewReport(
    kind: ReviewSubjectKind.session,
    subject: loaded.sessionId,
    topicName: loaded.topicName,
    subjectSummary: 'цель ${view.goal}, уровень ${view.targetLevel}, '
        'бюджет ${view.timeBudgetMinutes} мин, статус ${view.status}',
    metrics: metrics,
    findings: runSessionChecks(view),
    warnings: loaded.warnings,
  );
}

// ─── Вспомогательное ─────────────────────────────────────────────────────────

/// Одна строка отчёта в stdout: видно без открытия файла.
String _stdoutLine(ReviewReport r) {
  final s = r.summary;
  final js = r.judgeSummary;
  final buf = StringBuffer();
  buf.write('${r.isTree ? 'tree' : 'session'} ${r.topicName.isEmpty ? r.subject : r.topicName}: ');
  buf.write('checks fail=${s.fail} warn=${s.warn} info=${s.info}');
  if (r.judgeFindings.isNotEmpty) {
    buf.write('; judge fail=${js.fail} warn=${js.warn} info=${js.info}');
  }
  return buf.toString();
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  final v = args[i + 1];
  if (v.startsWith('--')) return null;
  return v;
}

List<String> _multiArg(List<String> args, String name) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] != name) continue;
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out.add(args[i + 1]);
      i++;
    }
  }
  return out;
}

/// Читает провайдерский конфиг. Значения секретов наружу не отдаются.
llm_client.LLMConfig? _readConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final raw = file.readAsStringSync();
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
      temperature: _jsonDouble(raw, 'LLM_TEMPERATURE') ?? 0.2,
      numCtx: 8192,
      timeoutMs: 180000,
      maxOutputTokens: _jsonInt(raw, 'LLM_MAX_OUTPUT_TOKENS') ?? 8192,
    );
  } catch (_) {
    return null;
  }
}

String? _jsonString(String raw, String key) {
  final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(raw);
  final v = m?.group(1);
  return (v == null || v.isEmpty) ? null : v;
}

double? _jsonDouble(String raw, String key) {
  final m = RegExp('"$key"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?)').firstMatch(raw);
  return m == null ? null : double.tryParse(m.group(1)!);
}

int? _jsonInt(String raw, String key) => _jsonDouble(raw, key)?.round();
