// Рендер отчёта ревью: JSON (машино) и Markdown (для чтения агентом/человеком).
//
// Детерминизм: в JSON попадают только данные артефакта. Никаких таймстемпов
// генерации, никаких id провайдера — иначе два прогона одного файла дадут
// разные байты и отчёт перестанет быть сравнимым.

import 'dart:convert';
import 'dart:io';

import 'judge.dart';
import 'finding.dart';

/// Что именно ревьюили.
enum ReviewSubjectKind { tree, session }

/// Полный отчёт по одному артефакту.
class ReviewReport {
  final ReviewSubjectKind kind;

  /// Имя артефакта: путь к файлу темы или id сессии.
  final String subject;

  /// Тема (имя) — для шапки отчёта.
  final String topicName;

  /// Человекочитаемый подзаголовок: цель/уровень/бюджет или id сессии.
  final String subjectSummary;

  /// Метрики артефакта (числа): размер дерева, суммы времени, счётчики сессии.
  final Map<String, dynamic> metrics;

  final List<Finding> findings;
  final List<JudgeFinding> judgeFindings;

  /// Предупреждения загрузчика/судьи.
  final List<String> warnings;

  const ReviewReport({
    required this.kind,
    required this.subject,
    this.topicName = '',
    this.subjectSummary = '',
    this.metrics = const {},
    this.findings = const [],
    this.judgeFindings = const [],
    this.warnings = const [],
  });

  bool get isTree => kind == ReviewSubjectKind.tree;

  /// Сводка по детерминированным находкам.
  FindingSummary get summary => summarizeFindings(findings);

  /// Сводка по находкам судьи.
  FindingSummary get judgeSummary => summarizeFindings([
        for (final f in judgeFindings)
          Finding(
            code: 'judge_${f.dimension}',
            severity: f.severity,
            nodeId: f.nodeId,
            message: f.message,
          ),
      ]);

  /// Есть ли блокирующие находки — по ним CLI возвращает ненулевой код.
  bool get hasFailures => summary.hasFailures || judgeSummary.hasFailures;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'subject': subject,
        'topicName': topicName,
        'subjectSummary': subjectSummary,
        'metrics': metrics,
        'summary': summary.toJson(),
        'judgeSummary': judgeFindings.isEmpty ? null : judgeSummary.toJson(),
        'findings': [for (final f in sortedFindings(findings)) f.toJson()],
        'judgeFindings': [for (final f in judgeFindings) f.toJson()],
        'warnings': warnings,
      };

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Печатает [report] в stdout и раскладывает по [outDir].
///
/// Отчёты сортируются по (вид, объект) — и имя файла, и содержимое не зависят от
/// порядка аргументов CLI, поэтому два прогона по одному набору входов дают
/// побайтово одинаковые артефакты и diff между прогонами остаётся осмысленным.
void writeReports(List<ReviewReport> reports, String outDir) {
  final dir = Directory(outDir);
  dir.createSync(recursive: true);
  final ordered = [...reports]
    ..sort((a, b) {
      final byKind = a.kind.name.compareTo(b.kind.name);
      return byKind != 0 ? byKind : a.subject.compareTo(b.subject);
    });
  final stamp = _fileStamp(ordered);
  File('$outDir\\review-$stamp.json').writeAsStringSync(_jsonBundle(ordered));
  File('$outDir\\review-$stamp.md').writeAsStringSync(_markdownBundle(ordered));
}

/// Имя файла: детерминированное, из состава артефактов (без времени).
///
/// Смешанный набор (`--tree` и `--session` вместе) больше не называется по виду
/// первого отчёта — такой stamp вводил в заблуждение и зависел от порядка
/// аргументов.
String _fileStamp(List<ReviewReport> reports) {
  if (reports.isEmpty) return 'empty-0';
  final kinds = <ReviewSubjectKind>{
    for (final r in reports) r.kind,
  }.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final prefix = kinds.length == 1 ? kinds.single.name : 'mixed';
  return '$prefix-${reports.length}';
}

String _jsonBundle(List<ReviewReport> reports) => const JsonEncoder.withIndent('  ')
    .convert({
      'reports': [for (final r in reports) r.toJson()],
    });

String _markdownBundle(List<ReviewReport> reports) {
  final buf = StringBuffer('# Ревью MindTree\n\n');
  for (final r in reports) {
    buf.writeln(_markdownOne(r));
  }
  return buf.toString();
}

/// ─── Markdown ────────────────────────────────────────────────────────────────

String _markdownOne(ReviewReport r) {
  final buf = StringBuffer();
  final title = r.isTree ? 'Дерево знаний' : 'Учебная сессия';
  buf.writeln('## $title: ${_md(r.topicName.isEmpty ? r.subject : r.topicName)}\n');
  buf.writeln('- Артефакт: `${r.subject}`');
  if (r.subjectSummary.isNotEmpty) {
    buf.writeln('- Контекст: ${_md(r.subjectSummary)}');
  }
  for (final entry in r.metrics.entries) {
    buf.writeln('- ${_metricLabel(entry.key)}: ${entry.value}');
  }
  buf.writeln();

  final s = r.summary;
  final js = r.judgeSummary;
  final parts = <String>[
    if (s.total > 0) 'детерминированные проверки — fail: ${s.fail}, warn: ${s.warn}, info: ${s.info}',
    if (r.judgeFindings.isNotEmpty)
      'судья — fail: ${js.fail}, warn: ${js.warn}, info: ${js.info}',
  ];
  if (parts.isEmpty) {
    buf.writeln('Находок нет.\n');
  } else {
    buf.writeln('**Итог**: ${parts.join('; ')}.\n');
  }

  final findings = sortedFindings(r.findings);
  if (findings.isNotEmpty) {
    buf.writeln('### Детерминированные проверки\n');
    for (final f in findings) {
      final where = f.nodeId == null ? '' : ' — `${f.nodeId}`';
      buf.writeln('- **${f.severity.name}** `${f.code}`$where: ${_md(f.message)}');
    }
    buf.writeln();
  }

  if (r.judgeFindings.isNotEmpty) {
    buf.writeln('### LLM-судья\n');
    for (final f in r.judgeFindings) {
      final where = f.nodeId == null ? '' : ' — `${f.nodeId}`';
      buf.writeln('- **${f.severity.name}** ${f.dimension}$where: ${_md(f.message)}');
      if (f.suggestion != null && f.suggestion!.isNotEmpty) {
        buf.writeln('  - правка: ${_md(f.suggestion!)}');
      }
    }
    buf.writeln();
  }

  if (r.warnings.isNotEmpty) {
    buf.writeln('### Предупреждения инструмента\n');
    for (final w in r.warnings) {
      buf.writeln('- ${_md(w)}');
    }
    buf.writeln();
  }

  buf.writeln('---\n');
  return buf.toString();
}

/// Экранирует pipe и переводы строк, чтобы Markdown не разъезжался.
String _md(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ').trim();

/// Человекочитаемые подписи метрик.
String _metricLabel(String key) => switch (key) {
      'nodeCount' => 'узлов',
      'leafCount' => 'листьев',
      'leafMinutes' => 'минут по листьям',
      'rootMinutes' => 'оценка корня, мин',
      'timeBudgetMinutes' => 'бюджет, мин',
      'budgetRatio' => 'листов к бюджету',
      'analogyCoverage' => 'покрытие аналогиями',
      'relationCount' => 'всего связей',
      'resolvableRelationCount' => 'валидных связей',
      'danglingRelationCount' => 'висящих связей',
      'activityCount' => 'активностей',
      'stepCount' => 'шагов',
      'answeredSteps' => 'отвеченных шагов',
      'questionCount' => 'вопросов оценки',
      'eventCount' => 'событий',
      'masteryNodes' => 'узлов с mastery',
      'milestoneCount' => 'milestones',
      'judgedNodes' => 'узлов проверено судьёй',
      _ => key,
    };
