// Находка ревью + детерминированная сортировка и сводка.
//
// Общий формат для всех проверок CLI-ревью (`tree_checks.dart`,
// `session_checks.dart`). Файл не знает ни про дерево, ни про сессию: это
// только контейнер результата, который потом печатает репортер.
//
// ДЕЙЕРМИНИЗМ. Порядок находок в отчёте задаётся ТОЛЬКО [sortedFindings]:
// код, затем узел, затем порядок появления. Никаких `Set`-порядков и
// `Map`-порядков в вывод — иначе два прогона одного файла дали бы разные
// байты и отчёт перестал бы быть сравнимым.

/// Серьёзность находки.
enum FindingSeverity {
  info,
  warn,
  fail;

  /// Для сортировки и сводки: чем выше, тем хуже.
  int get rank => switch (this) {
        FindingSeverity.info => 0,
        FindingSeverity.warn => 1,
        FindingSeverity.fail => 2,
      };
}

/// Одна находка проверки качества.
class Finding {
  /// Стабильный код проверки (значение — часть контракта отчёта).
  final String code;

  final FindingSeverity severity;

  /// Узел-виновник, если находка относится к конкретному узлу.
  final String? nodeId;

  final String message;

  /// Произвольные числа проверки для отчёта (метрики, пороги, списки id).
  final Map<String, dynamic>? data;

  const Finding({
    required this.code,
    required this.severity,
    required this.message,
    this.nodeId,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'severity': severity.name,
        if (nodeId != null) 'nodeId': nodeId,
        'message': message,
        if (data != null) 'data': data,
      };

  @override
  String toString() =>
      '[${severity.name}] $code${nodeId == null ? '' : ' ($nodeId)'}: $message';
}

/// Стабильная сортировка находок: код, затем узел, затем порядок входа.
///
/// Третий ключ (порядок входа) делает сортировку стабильной: две находки с
/// одинаковыми кодом и узлом не переставляются местами между прогонами.
List<Finding> sortedFindings(Iterable<Finding> findings) {
  final list = findings.toList(growable: false);
  final indexed = [
    for (var i = 0; i < list.length; i++) (i, list[i]),
  ]..sort((a, b) {
      final byCode = a.$2.code.compareTo(b.$2.code);
      if (byCode != 0) return byCode;
      // Узел без значения сортируется раньше: удобнее читать общие находы
      // проверки перед помесячными.
      final byNode = (a.$2.nodeId ?? '').compareTo(b.$2.nodeId ?? '');
      if (byNode != 0) return byNode;
      return a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Сводка по находкам.
class FindingSummary {
  final int info;
  final int warn;
  final int fail;

  const FindingSummary({
    this.info = 0,
    this.warn = 0,
    this.fail = 0,
  });

  int get total => info + warn + fail;

  /// Есть ли нарушения, требующие внимания.
  bool get hasProblems => warn > 0 || fail > 0;

  /// Есть ли блокирующие нарушения — по ним CLI возвращает ненулевой код.
  bool get hasFailures => fail > 0;

  /// Наивысшая серьёзность среди находок (rank: info=0, warn=1, fail=2).
  ///
  /// CLI сравнивает это число с порогом `--fail-on`: warn=1, fail=2.
  int get rankMax => fail > 0
      ? FindingSeverity.fail.rank
      : warn > 0
          ? FindingSeverity.warn.rank
          : FindingSeverity.info.rank;

  Map<String, dynamic> toJson() => {
        'info': info,
        'warn': warn,
        'fail': fail,
        'total': total,
      };

  @override
  String toString() =>
      'findings: $total (fail=$fail, warn=$warn, info=$info)';
}

/// Считает сводку по списку находок.
FindingSummary summarizeFindings(List<Finding> findings) {
  var info = 0, warn = 0, fail = 0;
  for (final f in findings) {
    switch (f.severity) {
      case FindingSeverity.info:
        info++;
      case FindingSeverity.warn:
        warn++;
      case FindingSeverity.fail:
        fail++;
    }
  }
  return FindingSummary(info: info, warn: warn, fail: fail);
}