// LLM-судья ревью: оценивает то, что нельзя решить словарём.
//
// Детерминированные проверки (`tree_checks.dart`) ловят форму: висящие id,
// длины, дубли, бюджет. Судья ловит смысл: неверная формула, подмена понятий
// (ELBO ≠ VAE), выдуманная атрибуция, сложность не по уровню аудитории.
//
// Правила, общие для всех LLM-вызовов в проекте:
//  * вызов идёт через [TreeScheduler] с тиром `strong` (операция `judge`);
//  * результат парсится по JSON-контракту и валидируется;
//  * есть fallback: сбой LLM не роняет ревью — в отчёт уходит warning;
//  * секреты не печатаются.

import 'package:mindtree_flutter/data/llm/client.dart' show parseLLMJson;
import 'package:mindtree_flutter/data/llm/scheduler.dart';
import 'package:mindtree_flutter/data/io/topic_file.dart';
import 'package:mindtree_flutter/domain/models/knowledge_node.dart';

import 'finding.dart';

/// Находка судьи. `dimension` — по какой оси оценки.
class JudgeFinding {
  /// `factual` | `complexity` | `pedagogy` | `terminology` | `structure`.
  final String dimension;
  final FindingSeverity severity;
  final String? nodeId;
  final String message;

  /// Что делать: конкретная правка формулировки или структуры.
  final String? suggestion;

  const JudgeFinding({
    required this.dimension,
    required this.severity,
    required this.message,
    this.nodeId,
    this.suggestion,
  });

  Map<String, dynamic> toJson() => {
        'dimension': dimension,
        'severity': severity.name,
        if (nodeId != null) 'nodeId': nodeId,
        'message': message,
        if (suggestion != null) 'suggestion': suggestion,
      };
}

/// Итог судейства.
class JudgeResult {
  final List<JudgeFinding> findings;

  /// Сколько узлов реально прошло через модель.
  final int reviewedNodes;

  /// Проблемы самого судейства: сбой вызова, битый JSON, не разобрали ответ.
  final List<String> warnings;

  const JudgeResult({
    this.findings = const [],
    this.reviewedNodes = 0,
    this.warnings = const [],
  });

  bool get isEmpty => findings.isEmpty && warnings.isEmpty;

  Map<String, dynamic> toJson() => {
        'reviewedNodes': reviewedNodes,
        'findings': [for (final f in findings) f.toJson()],
        'warnings': warnings,
      };
}

/// Оси оценки — они же значения `dimension` в ответе модели.
const List<String> kJudgeDimensions = [
  'factual',
  'complexity',
  'pedagogy',
  'terminology',
  'structure',
];

/// Судит узлы дерева.
///
/// Узлы режутся на пачки [batchSize] (иначе запрос не влезет в контекст и
/// начнётся обрезка), всего не больше [maxBatches] пачек — иначе ревью
/// превращается в дорогую генерацию и упрётся в лимиты провайдера.
Future<JudgeResult> judgeTopicFile({
  required TopicFile file,
  required TreeScheduler scheduler,
  int batchSize = 4,
  int maxBatches = 20,
}) async {
  final warnings = <String>[];
  final findings = <JudgeFinding>[];

  final nodes = [for (final n in file.nodes) if (n.contentLoaded) n];
  if (nodes.isEmpty) {
    return const JudgeResult(
      warnings: ['Нет узлов с контентом — судить нечего'],
    );
  }

  var reviewed = 0;
  for (var i = 0; i < nodes.length && i ~/ batchSize < maxBatches; i += batchSize) {
    final batch = nodes.skip(i).take(batchSize).toList();
    final prompt = buildJudgePrompt(
      topicName: file.topic.name,
      goal: file.topic.goal.raw,
      targetLevel: file.topic.targetLevel.raw,
      nodes: batch,
    );
    Map<String, dynamic> parsed;
    try {
      final exec = await scheduler.execute<Map<String, dynamic>>(
        'judge',
        () => prompt,
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
        nodeIds: [for (final n in batch) n.id],
      );
      parsed = exec.result;
    } catch (e) {
      // Fallback: сбой LLM не должен ронять ревью — детерминированные
      // проверки уже отработали, семантика просто останется непроверенной.
      warnings.add('Судья недоступен на пачке $i: $e');
      break;
    }
    final batchFindings = _parseFindings(parsed, batch, warnings, i);
    findings.addAll(batchFindings);
    reviewed += batch.length;
  }

  if (nodes.length > batchSize * maxBatches) {
    warnings.add(
      'Проверено только ${batchSize * maxBatches} из ${nodes.length} узлов: '
      'лимит пачек (--judge-batches).',
    );
  }

  return JudgeResult(
    findings: findings,
    reviewedNodes: reviewed,
    warnings: warnings,
  );
}

/// Разбирает и валидирует ответ модели. Всё, чего нет в узлах пачки, —
/// отбрасывается: модель склонна «дорисовывать» id.
List<JudgeFinding> _parseFindings(
  Map<String, dynamic> parsed,
  List<KnowledgeNode> batch,
  List<String> warnings,
  int batchIndex,
) {
  final known = {for (final n in batch) n.id};
  final raw = parsed['findings'];
  if (raw is! List) {
    warnings.add('Судья вернул ответ без массива findings (пачка $batchIndex)');
    return const [];
  }
  final out = <JudgeFinding>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final message = '${item['message'] ?? ''}'.trim();
    if (message.isEmpty) continue;
    final nodeId = item['node_id'] is String ? item['node_id'] as String : null;
    if (nodeId != null && !known.contains(nodeId)) {
      warnings.add('Судья указал незнакомый node_id «$nodeId» — находка отброшена');
      continue;
    }
    final dimension = '${item['dimension'] ?? ''}'.trim();
    out.add(JudgeFinding(
      dimension: kJudgeDimensions.contains(dimension) ? dimension : 'structure',
      severity: _severity('${item['severity'] ?? 'warn'}'),
      nodeId: nodeId,
      message: message,
      suggestion: item['suggestion'] is String ? item['suggestion'] as String : null,
    ));
  }
  return out;
}

FindingSeverity _severity(String raw) => switch (raw.trim().toLowerCase()) {
      'fail' || 'critical' || 'error' => FindingSeverity.fail,
      'info' || 'note' => FindingSeverity.info,
      _ => FindingSeverity.warn,
    };

/// Промпт судьи. Русский, с явным контрактом ответа и рубрикой.
String buildJudgePrompt({
  required String topicName,
  required String goal,
  required String targetLevel,
  required List<KnowledgeNode> nodes,
}) {
  final block = [
    for (final n in nodes)
      [
        '### id: ${n.id}',
        'label: ${n.label}',
        'one_liner: ${n.oneLiner}',
        'details: ${n.details}',
        if (n.analogy != null && n.analogy!.isNotEmpty) 'analogy: ${n.analogy!}',
        if (n.sources.isNotEmpty) 'sources: ${n.sources.join('; ')}',
        'difficulty: ${n.difficulty}',
      ].join('\n'),
  ].join('\n\n');

  return '''
# Роль
Ты — строгий научный редактор учебных материалов. Проверяешь узлы дерева знаний,
которые показывает система адаптивного обучения пользователю.

# Контекст
Тема: «$topicName». Цель обучения: $goal. Уровень аудитории: $targetLevel.

# Что проверять (по каждому узлу)
1. factual — ФАКТИЧЕСКАЯ ТОЧНОСТЬ. Формулы, определения, названия методов,
   авторы и годы. Неверная формула или подмена понятия (например, ELBO ≠ VAE) —
   это severity fail. Если не уверен в факте — не выдумывай, а укажи
   severity warn с пометкой «требует проверки».
2. complexity — СЛОЖНОСТЬ ПО УРОВНЮ. Материал должен быть понятен целевой
   аудитории. Для уровней awareness/basic_understanding/solid_understanding:
   термины без объяснения, формулы без смыслового объяснения, плотная
   энциклопедическая выжимка — это нарушения.
3. pedagogy — ПОДАЧА. Есть ли интуиция «как это работает», есть ли связь с
   тем, что пользователь уже знает, не пересказывает ли родительский узел,
   не дублирует ли соседний узел.
4. terminology — ТЕРМИНОЛОГИЯ. Не расшифрованные аббревиатуры, несоответствие
   терминов между узлами, жаргон без пояснения.
5. structure — ЛОГИКА ДЕРЕВА. Порядок изучения, зависимости, дубли, пробелы в
   покрытии темы (например, нет применений или нет сравнения с альтернативой).

# Чего НЕ делать
- Не переписывать текст целиком: дай конкретное короткое `suggestion`.
- Не оценивать оформление (длина, регистр) — этим занимаются кодовые проверки.
- Не придумывать факты: твоя задача — сигнал, а не эссе.

# Контракт ответа
Только JSON:
{"findings":[{"node_id":"id узла из входа","dimension":"factual|complexity|pedagogy|terminology|structure","severity":"fail|warn|info","message":"что не так, 1 предложение","suggestion":"что сделать, 1 предложение"}]}

Если узел в порядке — не включай его в findings. Пустой массив — валидный ответ.

# Узлы
$block
''';
}
