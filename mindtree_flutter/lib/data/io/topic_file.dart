import 'dart:convert';

import 'package:mindtree_flutter/domain/engines/knowledge_graph_engine.dart';
import 'package:mindtree_flutter/domain/engines/scoped_ids.dart';
import 'package:mindtree_flutter/domain/lib/tree_validation.dart';
import 'package:mindtree_flutter/domain/models/models.dart';

/// Формат файла темы (экспорт/импорт графа знаний).
///
/// Конверт:
/// ```json
/// {
///   "format": "mindtree.topic",
///   "version": 1,
///   "exportedAt": "2026-09-27T12:00:00.000Z",
///   "source": { "topicId": "<id темы-источника>" },
///   "topic": { "name": "...", "goal": "...", "targetLevel": "...", "timeBudgetMinutes": 60 },
///   "tree": { "nodes": [ <вложенный узел> ] }
/// }
/// ```
///
/// Дерево в файле ВЛОЖЕННОЕ (ключ `children`), как в `docs/exam-prep-plan.md`
/// §1.2. Внутри кода nodes — плоский список, как в БД (`parentId`/`level`).
/// `parentId` и `level` в файл сознательно НЕ пишутся: они выводятся из
/// вложенности при импорте, поэтому в файле не может быть рассинхрона между
/// структурой и ссылками.
const String kTopicFileFormat = 'mindtree.topic';
const int kTopicFileVersion = 1;

/// Инвариант `AGENTS.md`: `one_liner` не длиннее 120 символов.
const int kOneLinerMaxLength = 120;

/// Файл нечитаем: чужой формат, будущая версия, нет обязательных полей.
class TopicFileFormatException implements Exception {
  final String message;
  const TopicFileFormatException(this.message);
  @override
  String toString() => 'TopicFileFormatException: $message';
}

/// Метаданные темы в файле. `id`/`createdAt` не переносятся — при импорте тема
/// получает собственный id, иначе она бы перезаписала исходную.
class TopicFileMeta {
  final String name;
  final LearningGoal goal;
  final MasteryLevel targetLevel;
  final int timeBudgetMinutes;

  const TopicFileMeta({
    required this.name,
    this.goal = LearningGoal.overview,
    this.targetLevel = MasteryLevel.basicUnderstanding,
    this.timeBudgetMinutes = 60,
  });

  factory TopicFileMeta.fromJson(Map<String, dynamic> json) => TopicFileMeta(
    name: json['name'] as String? ?? '',
    goal: LearningGoal.fromString(json['goal'] as String?),
    targetLevel: MasteryLevel.fromString(json['targetLevel'] as String?),
    timeBudgetMinutes: (json['timeBudgetMinutes'] as num? ?? 60).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'goal': goal.raw,
    'targetLevel': targetLevel.raw,
    'timeBudgetMinutes': timeBudgetMinutes,
  };
}

/// Разобранный файл темы: плоский список узлов + метаданные + результат
/// семантической проверки (ошибки блокируют импорт, предупреждения — нет).
class TopicFile {
  final int version;
  final String exportedAt;
  final String sourceTopicId;
  final TopicFileMeta topic;
  final List<KnowledgeNode> nodes;

  /// Ошибки формы/ссылок: не пустой список — импорт запрещён.
  final List<String> errors;

  /// Предупреждения (например, слишком длинный `one_liner`, обрезанный при разборе).
  final List<String> warnings;

  const TopicFile({
    required this.sourceTopicId,
    required this.topic,
    required this.nodes,
    this.version = kTopicFileVersion,
    this.exportedAt = '',
    this.errors = const [],
    this.warnings = const [],
  });

  bool get isValid => errors.isEmpty;

  /// Корневые узлы (их должен быть ровно один, иначе `errors` непуст).
  List<KnowledgeNode> get roots =>
      nodes.where((n) => n.parentId == null).toList();

  // ─── Сериализация ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'format': kTopicFileFormat,
    'version': version,
    'exportedAt': exportedAt,
    'source': {'topicId': sourceTopicId},
    'topic': topic.toJson(),
    'tree': {'nodes': nestNodes(nodes)},
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  // ─── Десериализация ───────────────────────────────────────────────────────

  static TopicFile fromJsonString(String raw) {
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on TopicFileFormatException {
      rethrow;
    } catch (e) {
      throw TopicFileFormatException('Файл не является корректным JSON: $e');
    }
  }

  static TopicFile fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != kTopicFileFormat) {
      throw TopicFileFormatException(
        'Ожидался формат "$kTopicFileFormat", получено: ${format ?? '—'}',
      );
    }

    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version > kTopicFileVersion) {
      throw TopicFileFormatException(
        'Версия файла $version новее поддерживаемой ($kTopicFileVersion). '
        'Обновите приложение.',
      );
    }
    if (version < 1) {
      throw TopicFileFormatException('Некорректная версия файла: $version');
    }

    final source = json['source'];
    final sourceTopicId = source is Map && source['topicId'] is String
        ? source['topicId'] as String
        : '';

    final topicJson = json['topic'];
    if (topicJson is! Map<String, dynamic>) {
      throw const TopicFileFormatException('Отсутствует раздел "topic"');
    }
    final meta = TopicFileMeta.fromJson(topicJson);
    if (meta.name.trim().isEmpty) {
      throw const TopicFileFormatException('В разделе "topic" пустое имя темы');
    }

    final tree = json['tree'];
    final nested = tree is Map ? tree['nodes'] : null;
    if (nested is! List || nested.isEmpty) {
      throw const TopicFileFormatException(
        'Раздел "tree.nodes" пуст — нечего импортировать',
      );
    }

    final warnings = <String>[];
    final nodes = flattenNodes(
      nested.whereType<Map<String, dynamic>>().toList(),
      onWarning: warnings.add,
    );

    final file = TopicFile(
      version: version,
      exportedAt: json['exportedAt'] as String? ?? '',
      sourceTopicId: sourceTopicId,
      topic: meta,
      nodes: nodes,
      warnings: warnings,
    );
    return file.copyWith(errors: validateImport(file));
  }

  TopicFile copyWith({
    List<String>? errors,
    List<String>? warnings,
    List<KnowledgeNode>? nodes,
  }) => TopicFile(
    version: version,
    exportedAt: exportedAt,
    sourceTopicId: sourceTopicId,
    topic: topic,
    nodes: nodes ?? this.nodes,
    errors: errors ?? this.errors,
    warnings: warnings ?? this.warnings,
  );
}

/// Плоский список → вложенный JSON-дерево.
///
/// Узлы группируются по `parentId`; корень — узел без родителя. Если корней
/// несколько (файл мог быть собран вручную), остальные подвешиваются к
/// первому — семантическую проверку отдаёт `validateImport`.
List<Map<String, dynamic>> nestNodes(List<KnowledgeNode> flat) {
  if (flat.isEmpty) return [];

  final byId = {for (final n in flat) n.id: n};
  final childrenOf = <String, List<KnowledgeNode>>{};
  final roots = <KnowledgeNode>[];

  for (final n in flat) {
    final parent = n.parentId;
    if (parent == null || !byId.containsKey(parent)) {
      roots.add(n);
    } else {
      (childrenOf[parent] ??= <KnowledgeNode>[]).add(n);
    }
  }
  if (roots.isEmpty) roots.add(flat.first);

  // Порядок детей — как в плоском списке (стабильно, детерминированно).
  final emitted = <String>{};
  Map<String, dynamic> build(KnowledgeNode node) {
    emitted.add(node.id);
    final kids = childrenOf[node.id] ?? const <KnowledgeNode>[];
    return _nodeToFileJson(node, [for (final k in kids) build(k)]);
  }

  final result = <Map<String, dynamic>>[];
  for (final r in roots) {
    if (emitted.contains(r.id)) continue;
    result.add(build(r));
  }
  // «Острова» — узлы, не достигнутые от корня (висячие ссылки). Пишем их
  // отдельными деревьями, чтобы файл не потерял данные молча.
  for (final n in flat) {
    if (emitted.contains(n.id)) continue;
    result.add(build(n));
  }
  return result;
}

Map<String, dynamic> _nodeToFileJson(
  KnowledgeNode n,
  List<Map<String, dynamic>> children,
) {
  return {
    'id': n.id,
    'label': n.label,
    'oneLiner': n.oneLiner,
    'details': n.details,
    if (n.analogy != null) 'analogy': n.analogy,
    'sources': n.sources,
    if (n.conceptType != null) 'conceptType': n.conceptType!.raw,
    'importance': n.importance,
    'difficulty': n.difficulty,
    'estimatedTimeMinutes': n.estimatedTimeMinutes,
    'state': n.state.wire,
    'contentLoaded': n.contentLoaded,
    // `leaf` в файле — для читаемости; при разборе он НЕ доверяется и
    // пересчитывается из наличия `children` (вложенность первична).
    'leaf': children.isEmpty,
    'relations': n.relations.map((e) => e.toJson()).toList(),
    'sequences': n.sequences.map((e) => e.toJson()).toList(),
    'children': children,
  };
}

/// Вложенный JSON → плоский список. `parentId` и `level` выводятся из
/// вложенности, `topicId` остаётся пустым (проставится при импорте).
///
/// Обход — DFS в порядке массива, как `lib/domain/lib/tree_reading.dart`.
List<KnowledgeNode> flattenNodes(
  List<Map<String, dynamic>> nested, {
  void Function(String message)? onWarning,
}) {
  final out = <KnowledgeNode>[];

  void walk(List<Map<String, dynamic>> items, String? parentId, int level) {
    for (final raw in items) {
      final id = raw['id'];
      if (id is! String || id.isEmpty) {
        onWarning?.call('Пропущен узел без id на уровне $level');
        continue;
      }
      final oneLiner = _truncateOneLiner(
        raw['oneLiner'] as String? ?? '',
        onWarning,
      );
      final children =
          (raw['children'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const <Map<String, dynamic>>[];

      out.add(
        KnowledgeNode(
          id: id,
          topicId: '',
          parentId: parentId,
          level: level,
          label: raw['label'] as String? ?? '',
          oneLiner: oneLiner,
          details: raw['details'] as String? ?? '',
          analogy: raw['analogy'] as String?,
          sources: (raw['sources'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
          conceptType: ConceptType.fromString(raw['conceptType'] as String?),
          importance: (raw['importance'] as num? ?? 0.5).toDouble(),
          difficulty: (raw['difficulty'] as num? ?? 0.5).toDouble(),
          estimatedTimeMinutes: (raw['estimatedTimeMinutes'] as num? ?? 5)
              .toInt(),
          state: NodeState.fromString(raw['state'] as String? ?? 'new'),
          contentLoaded: raw['contentLoaded'] as bool? ?? false,
          // leaf пересчитывается: вложенность первична.
          leaf: children.isEmpty,
          relations: (raw['relations'] as List<dynamic>? ?? const [])
              .map((e) => Relation.fromJson(e as Map<String, dynamic>))
              .toList(),
          sequences: (raw['sequences'] as List<dynamic>? ?? const [])
              .map((e) => Sequence.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      walk(children, id, level + 1);
    }
  }

  walk(nested, null, 1);
  return out;
}

/// Импорт/экспорт: кламп лимита `one_liner`.
///
/// Зеркало доменного `truncateOneLiner` — важно и синтаксически безопасно
/// (граница предложения/клаузы/слова + снятие висящих служебных слов), и
/// просто: сырой `substring` обрывал фразы посреди слова прямо в экспорте.
String _truncateOneLiner(String value, void Function(String)? onWarning) {
  if (value.length <= kOneLinerMaxLength) return value;
  onWarning?.call('one_liner длиннее $kOneLinerMaxLength символов — обрезан');
  return truncateOneLiner(value, maxChars: kOneLinerMaxLength);
}

/// Семантическая проверка импорта. Непустой результат блокирует импорт.
///
/// Форму дерева (корень/родители/циклы) делегирована существующей
/// `validateTreeShape`; здесь добавляется то, чего в ней нет.
List<String> validateImport(TopicFile file) {
  final errors = <String>[];
  final nodes = file.nodes;

  // Дубликаты id: `validateTreeShape` их не ловит, а БД уронит на PK.
  final seen = <String>{};
  final dups = <String>{};
  for (final n in nodes) {
    if (!seen.add(n.id)) dups.add(n.id);
  }
  if (dups.isNotEmpty) {
    errors.add('Дублирующиеся id узлов: ${dups.join(', ')}');
  }

  // Пустые подписи — узел нельзя показать в дереве.
  final noLabel = nodes
      .where((n) => n.label.trim().isEmpty)
      .map((n) => n.id)
      .toList();
  if (noLabel.isNotEmpty) {
    errors.add('Узлы с пустым названием: ${noLabel.join(', ')}');
  }

  if (!validateTreeShape(nodes)) {
    final roots = file.roots.length;
    if (roots != 1) {
      errors.add('В дереве корней: $roots, ожидается ровно один');
    }
    // Родители/циклы: даём более конкретную причину, если она одна.
    final ids = nodes.map((n) => n.id).toSet();
    final dangling = nodes
        .where((n) => n.parentId != null && !ids.contains(n.parentId))
        .map((n) => '${n.id} → ${n.parentId}')
        .toList();
    if (dangling.isNotEmpty) {
      errors.add('Ссылки на несуществующих родителей: ${dangling.join(', ')}');
    } else if (roots == 1) {
      errors.add('В дереве есть цикл');
    }
  }

  return errors;
}

/// Пере-скоупинг id узлов под новую тему.
///
/// `knowledge_nodes.id` — глобальный первичный ключ, а id узлов несут
/// `~`-суффикс, производный от id темы (`scoped_ids.dart`). При импорте в
/// новую тему старые id уедут в конфликт с уже существующими узлами, поэтому
/// все id переезжают под id новой темы, а вместе с ними — все ссылки:
/// `parentId`, `relations[].from/to` и `sequences[].steps[].conceptId`.
///
/// Ссылка, для которой в карте нет соответствия, остаётся как есть: лучше
/// висячая ссылка (её починит `repairDanglingParentIds` при чтении), чем
/// молчаливая потеря связи.
List<KnowledgeNode> rescopeNodes(
  List<KnowledgeNode> nodes,
  String sourceTopicId,
  String newTopicId,
) {
  if (nodes.isEmpty) return const [];
  final oldSuffix = scopedSuffix(sourceTopicId);
  final newSuffix = scopedSuffix(newTopicId);

  String stripOld(String id) => id.endsWith(oldSuffix)
      ? id.substring(0, id.length - oldSuffix.length)
      : id;

  final remap = <String, String>{};
  for (final n in nodes) {
    final base = stripOld(n.id);
    remap[base] = '$base$newSuffix';
  }

  String? mapRef(String? ref) {
    if (ref == null || ref.isEmpty) return ref;
    return remap[stripOld(ref)] ?? ref;
  }

  return nodes.map((n) {
    final base = stripOld(n.id);
    return n.copyWith(
      id: '$base$newSuffix',
      topicId: newTopicId,
      parentId: () => mapRef(n.parentId),
      relations: n.relations
          .map(
            (r) => Relation(
              from: mapRef(r.from) ?? r.from,
              to: mapRef(r.to) ?? r.to,
              type: r.type,
              label: r.label,
            ),
          )
          .toList(),
      sequences: n.sequences
          .map(
            (s) => Sequence(
              id: s.id,
              label: s.label,
              description: s.description,
              steps: s.steps
                  .map(
                    (st) => SequenceStep(
                      conceptId: mapRef(st.conceptId) ?? st.conceptId,
                      order: st.order,
                      label: st.label,
                      description: st.description,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }).toList();
}
