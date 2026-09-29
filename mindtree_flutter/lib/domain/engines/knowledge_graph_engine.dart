import 'dart:async';

import '../../data/database/mindtree_repository.dart';
import '../../data/llm/client.dart';
import '../../data/llm/scheduler.dart';
import '../models/knowledge_node.dart';
import '../models/primitives.dart';
import 'scoped_ids.dart';

/// Options passed through to structure-generation prompts.
class StructurePromptOptions {
  final String? goal;
  final String? level;
  final int? timeBudgetMinutes;

  const StructurePromptOptions({this.goal, this.level, this.timeBudgetMinutes});
}

/// A minimal node reference used in prompt contexts.
class NodeRef {
  final String id;
  final String title;
  final String? canonicalDefinition;

  const NodeRef({required this.id, required this.title, this.canonicalDefinition});
}

class L1PromptContext {
  final String query;
  final StructurePromptOptions options;

  const L1PromptContext({required this.query, required this.options});
}

class L2PromptContext {
  final String userQuery;
  final NodeRef root;
  final StructurePromptOptions? options;

  const L2PromptContext({required this.userQuery, required this.root, this.options});
}

class ParentRef {
  final String id;
  final String title;
  final String? canonicalDefinition;
  final String? semanticAxis;

  const ParentRef({
    required this.id,
    required this.title,
    this.canonicalDefinition,
    this.semanticAxis,
  });
}

class L3PromptContext {
  final String userQuery;
  final String rootTitle;
  final ParentRef parent;
  final List<NodeRef> siblings;
  final StructurePromptOptions? options;

  const L3PromptContext({
    required this.userQuery,
    required this.rootTitle,
    required this.parent,
    required this.siblings,
    this.options,
  });
}

class ExpandTargetRef {
  final String id;
  final String title;
  final String path;

  const ExpandTargetRef({required this.id, required this.title, required this.path});
}

class ExistingNodeRef {
  final String id;
  final String title;
  final String? parentId;
  final int level;

  const ExistingNodeRef({
    required this.id,
    required this.title,
    this.parentId,
    required this.level,
  });
}

class ExpandPromptContext {
  final String rootTopic;
  final List<String> contextPaths;
  final List<ExpandTargetRef> nodesToExpand;
  final List<ExistingNodeRef> existingTree;
  final StructurePromptOptions? options;

  const ExpandPromptContext({
    required this.rootTopic,
    required this.contextPaths,
    required this.nodesToExpand,
    required this.existingTree,
    this.options,
  });
}

class ValidationNodeRef {
  final String id;
  final String? parentId;
  final int level;
  final String label;
  final String oneLiner;
  final String? details;
  final String? conceptType;
  final String? semanticAxis;
  final String? canonicalDefinition;
  final List<String> forbiddenInterpretations;

  const ValidationNodeRef({
    required this.id,
    required this.parentId,
    required this.level,
    required this.label,
    required this.oneLiner,
    this.details,
    this.conceptType,
    this.semanticAxis,
    this.canonicalDefinition,
    this.forbiddenInterpretations = const [],
  });
}

class ValidatePromptContext {
  final List<ValidationNodeRef> nodes;
  final List<String>? focusIds;

  const ValidatePromptContext({required this.nodes, this.focusIds});
}

/// A single validation issue reported by the validate pass.
class ValidationIssue {
  final String type;
  final String nodeId;
  final String reason;

  const ValidationIssue({required this.type, required this.nodeId, required this.reason});
}

class ProblemNodeRef {
  final String id;
  final String? parentId;
  final int level;
  final String label;
  final String oneLiner;
  final String? details;
  final String? conceptType;
  final String? semanticAxis;
  final String? canonicalDefinition;
  final List<String> forbiddenInterpretations;

  const ProblemNodeRef({
    required this.id,
    required this.parentId,
    required this.level,
    required this.label,
    required this.oneLiner,
    this.details,
    this.conceptType,
    this.semanticAxis,
    this.canonicalDefinition,
    this.forbiddenInterpretations = const [],
  });
}

class RepairPromptContext {
  final List<ProblemNodeRef> problemNodes;
  final List<ValidationIssue> issues;
  final String? level;

  const RepairPromptContext({
    required this.problemNodes,
    required this.issues,
    this.level,
  });
}

class ContentNodeRef {
  final String id;
  final String label;

  const ContentNodeRef({required this.id, required this.label});
}

class OntologyContext {
  final String? canonicalDefinition;
  final String? semanticAxis;
  final List<String>? forbiddenInterpretations;

  const OntologyContext({
    this.canonicalDefinition,
    this.semanticAxis,
    this.forbiddenInterpretations,
  });
}

class ContentPromptContext {
  final String rootTopic;
  final List<String> nodePath;
  final List<String> siblings;
  final String? knowledgeLevel;
  final String? goal;
  final int? nodeLevel;
  final bool isRoot;
  final bool isCriticalDomain;
  final OntologyContext ontologyContext;
  final ContentNodeRef node;

  const ContentPromptContext({
    required this.rootTopic,
    required this.nodePath,
    required this.siblings,
    this.knowledgeLevel,
    this.goal,
    this.nodeLevel,
    this.isRoot = false,
    required this.isCriticalDomain,
    required this.ontologyContext,
    required this.node,
  });
}

/// A prompt builder: given a typed context it returns the prompt string.
typedef GeneratorFn<TContext> = String Function(TContext context);

/// Progress callback for the generation pipeline.
class TreeStats {
  final int total;
  final int depth;
  final int leaves;

  const TreeStats({required this.total, required this.depth, required this.leaves});
}

typedef ProgressCallback = void Function(String phase, String message, [TreeStats? stats]);

/// Result of a full tree build.
class TreeBuildResult {
  final List<NodeDraft> nodes;
  final List<String> warnings;

  /// Id узлов, собранных по запасному (деградированному) пути: их структура
  /// ненастоящая и помечена в [warnings]. Пусто в нормальном прогоне.
  final List<String> degradedNodeIds;

  const TreeBuildResult({
    required this.nodes,
    this.warnings = const [],
    this.degradedNodeIds = const [],
  });
}

/// Generated content for a single node.
class NodeContentResult {
  final String oneLiner;
  final String details;
  final String? analogy;
  final List<Relation> relations;
  final List<String> sources;

  const NodeContentResult({
    required this.oneLiner,
    required this.details,
    this.analogy,
    this.relations = const [],
    this.sources = const [],
  });
}

/// Shared context for [KnowledgeGraphEngine.generateNodeContent].
class NodeContentContext {
  final List<String> nodePath;
  final List<String> siblings;
  final String? canonicalDefinition;
  final String? semanticAxis;
  final List<String>? forbiddenInterpretations;
  final String? knowledgeLevel;
  final String? goal;
  final int? nodeLevel;
  final bool? isRoot;

  const NodeContentContext({
    required this.nodePath,
    required this.siblings,
    this.canonicalDefinition,
    this.semanticAxis,
    this.forbiddenInterpretations,
    this.knowledgeLevel,
    this.goal,
    this.nodeLevel,
    this.isRoot,
  });
}

const int _maxDepth = 5;

/// Максимальная длина `one_liner` — инвариант AGENTS.md. Единственный источник
/// истины: лимит используется движком (переспрос/триммация), промптами
/// (`prompts.dart`) и проверкой качества probe (`jargon.dart`).
const int oneLinerMaxChars = 120;

/// Детерминированный кламп черновика `one_liner` до лимита (инвариант AGENTS.md).
///
/// Применяется на путях записи дерева, где LLM-переспрос нецелесообразен:
/// repair, драфты L1/L2/L3, мапперы `tree_mapper.dart`/`ui_stores.dart`. Триммация
/// по границе слова + фолбэк всегда возвращает результат <= лимита. Для контента
/// по-прежнему работает `_withinOneLinerLimit` (переспрос + этот же фолбэк).
String enforceOneLinerLimit(String? draft, {int maxChars = oneLinerMaxChars}) {
  final trimmed = (draft ?? '').trim();
  if (trimmed.isEmpty || trimmed.length <= maxChars) return trimmed;
  return truncateOneLiner(trimmed, maxChars: maxChars);
}

/// Детерминированная обрезка до лимита: режем по границе слова, не оставляя
/// хвостовой пунктуации. Результат всегда <= [maxChars].
String truncateOneLiner(String s, {int maxChars = oneLinerMaxChars}) {
  if (s.length <= maxChars) return s;
  var cut = s.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > maxChars * 0.6) {
    cut = cut.substring(0, lastSpace);
  }
  return cut.trimRight();
}

/// Сколько L3-ветвей движок держит «в полёте» одновременно.
///
/// Ветви независимы (каждый `structure-l3` смотрит только на свой L2-родитель и
/// соседей), поэтому их можно гнать конкурентно. Реальные лимиты (RPM/RPD/
/// `maxConcurrency`) держит `TreeScheduler` — он выстроит запросы в очередь
/// сам; эта константа нужна, чтобы не держать в памяти десятки pending-промптов
/// на больших деревьях. Значение 4 — заметно больше типичного
/// `maxConcurrency` приложения (2), поэтому очередь scheduler-а заполняется
/// сразу и не простаивает, но не «раздувает» шаг генерации.
const int _l3BranchConcurrency = 4;

/// Жёсткий бюджет вызовов `repair` на одну генерацию дерева.
///
/// Без него «валидация → ремонт» повторяется на каждой L3-ветке и при плохом
/// ответе валидатора превращается в каскад из дорогих вызовов. Исчерпание
/// бюджета — не ошибка: дерево принимается в best-effort виде, в `warnings`
/// попадает пометка, пайплайн не падает.
const int _maxRepairCallsPerTree = 2;

/// Бюджет ремонта на одну генерацию дерева.
///
/// Счётчик общий на всё дерево, а проверка и списание выполняются синхронно
/// (между ними нет `await`), поэтому конкурентные ветки не могут превысить
/// лимит: в одной зоне изоляции синхронный участок — критическая секция.
class _RepairBudget {
  _RepairBudget(this.limit) : _left = limit;

  /// Сколько вызовов `repair` разрешено на всё дерево.
  final int limit;

  int _left;

  /// Сколько попыток ремонта уже израсходовано.
  int get used => limit - _left;

  bool _warned = false;

  /// Резервирует одну попытку ремонта. Возвращает `false`, если бюджет исчерпан
  /// (и тогда же добавляет ровно одно предупреждение в [warnings]).
  bool tryConsume(List<String> warnings) {
    if (_left <= 0) {
      if (!_warned) {
        _warned = true;
        warnings.add('Ремонт исчерпан: $used попыток, часть узлов оставлена как есть.');
      }
      return false;
    }
    _left--;
    return true;
  }
}

/// Результат одной L3-ветки: либо дети, либо ошибка этой ветки.
typedef _L3Branch = ({NodeDraft parent, List<NodeDraft> children, Object? error});

/// Прогоняет [action] по [items] конкурентно, но не шире [limit] задач сразу.
///
/// Результаты собираются **по позиции** в [items], поэтому итоговый список не
/// зависит от того, в каком порядке отработали вызовы (детерминизм доменной
/// логики по AGENTS.md). [action] не должна бросать: сбой отдельной ветки
/// разбирает вызывающий.
Future<List<T>> _mapBounded<E, T>(
  int limit,
  List<E> items,
  Future<T> Function(E item) action,
) async {
  if (items.isEmpty) return <T>[];
  final width = limit < 1 ? 1 : (limit > items.length ? items.length : limit);
  final slots = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      // Синхронное резервирование индекса: гонок нет (одна зона изоляции).
      final i = next++;
      if (i >= items.length) return;
      slots[i] = await action(items[i]);
    }
  }
  await Future.wait([for (var w = 0; w < width; w++) worker()]);
  return [for (final slot in slots) slot as T];
}

/// Orchestrates knowledge-tree generation: structure -> expand ->
/// validate/repair -> content, backed by the repository for persistence and
/// the [TreeScheduler] for LLM calls. Prompt builders are injected as pure
/// Dart functions so the engine itself stays framework-free.
/// Maximum tree generation depth for a given user level.
/// Mirrors web: beginner→2, intermediate→3, advanced/expert→4.
int _maxGenerationLevel(String? level) {
  switch (level) {
    case 'beginner':
      return 2;
    case 'intermediate':
      return 3;
    case 'expert':
      return 4;
    default:
      return 3; // intermediate по умолчанию
  }
}

class KnowledgeGraphEngine {
  final MindtreeRepository repo;
  final TreeScheduler scheduler;
  final GeneratorFn<L1PromptContext> generateStructure;
  final GeneratorFn<L2PromptContext> generateL2;
  final GeneratorFn<L3PromptContext> generateL3;
  final GeneratorFn<ExpandPromptContext> generateExpand;
  final GeneratorFn<ValidatePromptContext> generateValidate;
  final GeneratorFn<RepairPromptContext> generateRepair;
  final GeneratorFn<ContentPromptContext> generateContent;

  /// Переспрос для слишком длинного `one_liner` (операция `oneline-rewrite`).
  final String Function({
    required String label,
    required String currentOneLiner,
  }) generateOnelineRewrite;
  final bool Function(String rootTopic, List<String> nodePath) isCriticalDomain;

  const KnowledgeGraphEngine({
    required this.repo,
    required this.scheduler,
    required this.generateStructure,
    required this.generateL2,
    required this.generateL3,
    required this.generateExpand,
    required this.generateValidate,
    required this.generateRepair,
    required this.generateContent,
    required this.generateOnelineRewrite,
    this.isCriticalDomain = _isCriticalDomainDefault,
  });

  /// Full pipeline: structure -> expand -> validate -> repair -> content.
  /// Content is generated lazily (just-in-time); this builds the skeleton with
  /// top-level content filled in.
  Future<TreeBuildResult> generate(
    String query, {
    String? goal,
    String? level,
    int? timeBudgetMinutes,
    ProgressCallback? onProgress,
    Future<void> Function(List<NodeDraft> batched)? onBatch,
  }) async {
    final warnings = <String>[];
    // Узлы, собранные по запасному пути: их структура ненастоящая, и об этом
    // должны знать и probe, и пользователь.
    final degraded = <String>[];
    // Бюджет ремонта на всё дерево (общий для всех валидаций, в т.ч. L3).
    final repairBudget = _RepairBudget(_maxRepairCallsPerTree);
    final opts = StructurePromptOptions(
      goal: goal,
      level: level,
      timeBudgetMinutes: timeBudgetMinutes,
    );
    // Ограничиваем максимальную глубину генерации по уровню пользователя.
    // beginner → L2, intermediate → L3, advanced/expert → L4.
    final maxGenLevel = _maxGenerationLevel(level);

    // Step 1: root (L1).
    onProgress?.call('structure', 'Определение корня темы...');
    List<NodeDraft> nodes;
    try {
      nodes = await _generateRoot(query, opts);
    } catch (err) {
      if (_isOffline(err)) {
        nodes = fallbackStructure(query);
        warnings.add('Офлайн-режим: построено демо-дерево знаний вместо LLM.');
      } else {
        throw Exception('Не удалось определить корень темы: $err');
      }
    }

    if (!nodes.any((n) => n.level == 1 && n.parentId == null)) {
      nodes = fallbackStructure(query);
      warnings.add('Корень темы не был определён; построено демо-дерево.');
    }

    // Incremental persist: the root becomes visible immediately while the
    // following levels are still being generated.
    if (onBatch != null) {
      nodes = dedupeNodeIds(nodes);
      final batch = nodes.where((n) => n.level == 1 && n.parentId == null).toList();
      try {
        await onBatch(batch);
      } catch (_) {
        // Not critical for generation; a final persist restores the tree.
      }
    }

    // Step 2: sections (L2) — генерируем всегда (уровень ≥ 2 для всех).
    onProgress?.call('structure', 'Генерация главных разделов (уровень 2)...');
    var l2 = <NodeDraft>[];
    if (maxGenLevel >= 2) {
      try {
        l2 = await _generateL2FromRoot(query, nodes, opts);
        nodes = [...nodes, ...l2];
      } catch (err) {
        // Сбой L2 не «съедает» уровень: без разделов тема остаётся с одним
        // корнем, а план обучения и проверки качества (`content_coverage`,
        // `goal_coverage`) вырождаются. Переключаемся на запасной путь.
        warnings.add('Генерация разделов не завершена: ${err.toString()}');
        l2 = await _recoverL2(query, nodes, opts, warnings);
        degraded.addAll(l2.map((n) => n.id));
        nodes = [...nodes, ...l2];
      }
    }

    if (onBatch != null && l2.isNotEmpty) {
      nodes = dedupeNodeIds(nodes);
      final l2Ids = nodes.where((n) => n.level == 2).map((n) => n.id).toSet();
      final batch = nodes.where((n) => l2Ids.contains(n.id)).toList();
      try {
        await onBatch(batch);
      } catch (_) {
        // Final persist restores the tree.
      }
    }

    // Validate L1+L2 (and repair if needed).
    nodes = await _validateAndRepair(
        nodes, opts, onProgress, warnings, repairBudget, 'validate');

    // Step 3: subsections (L3) — only for intermediate+ levels.
    if (maxGenLevel >= 3) {
      onProgress?.call('structure', 'Генерация подразделов (уровень 3)...');
      final l2Nodes = nodes.where((n) => n.level == 2).toList();
      if (l2Nodes.isNotEmpty) {
        // Ветви независимы, поэтому `structure-l3` идут конкурентно (см.
        // `_l3BranchConcurrency`), а `nodes` на этом шаге — замороженный
        // снимок: L3-узлы не влияют на контекст соседних ветвей (root и
        // siblings берутся с уровней 1–2), а значит порядок ответа не может
        // изменить результат.
        final branches = await _mapBounded(_l3BranchConcurrency, l2Nodes, (l2Node) =>
            _generateL3Branch(query, l2Node, nodes, opts));

        // Дальше — строго в порядке L2-узлов: так итоговый `nodes` совпадает
        // с последовательным прогоном, а validate/repair видят ровно ту же
        // окрестность, что и раньше (parentId детей уже в дереве — сирот нет).
        for (final branch in branches) {
          if (branch.error != null) {
            warnings.add('Подразделы для «${branch.parent.title}» не завершены: '
                '${branch.error.toString()}');
            continue;
          }
          if (branch.children.isEmpty) continue;
          nodes = [...nodes, ...branch.children];
          final focusIds = branch.children.map((n) => n.id).toList();
          nodes = await _validateAndRepair(
            nodes,
            opts,
            onProgress,
            warnings,
            repairBudget,
            'validate-l3-${branch.parent.id}',
            focusIds,
          );
          if (onBatch != null) {
            nodes = dedupeNodeIds(nodes);
            final kept = nodes
                .where((n) => n.parentId == branch.parent.id && n.level == 3)
                .toList();
            if (kept.isNotEmpty) {
              try {
                await onBatch(kept);
              } catch (_) {
                // Final persist restores the tree.
              }
            }
          }
        }
      }
    } else {
      onProgress?.call('structure', 'Для текущего уровня достаточно 2 разделов — углубление доступно по кнопке.');
    }

    onProgress?.call('content', 'Заполнение контента узлов...');
    try {
      nodes = _fillTopLevelContent(query, nodes);
    } catch (err) {
      warnings.add('Контент заполнен не полностью: ${err.toString()}');
    }

    // Final de-duplication across branches.
    nodes = dedupeNodeIds(nodes);

    final stats = TreeStats(
      total: nodes.length,
      depth: _maxLevelOf(nodes),
      leaves: nodes.where((n) => !nodes.any((c) => c.parentId == n.id)).length,
    );
    onProgress?.call('done', 'Дерево готово', stats);

    return TreeBuildResult(
      nodes: nodes,
      warnings: warnings,
      degradedNodeIds: degraded,
    );
  }

  /// Generates the root node (L1) with a dedicated request.
  Future<List<NodeDraft>> _generateRoot(String query, StructurePromptOptions opts) async {
    final prompt = generateStructure(L1PromptContext(query: query, options: opts));
    final exec = await scheduler.execute<List<dynamic>>(
      'structure',
      () => prompt,
      _nodesFromJson,
    );
    return _normalizeDrafts(exec.result)
        .where((n) => n.level == 1 && n.parentId == null)
        .toList();
  }

  /// Generates sections (L2) with the root for context.
  Future<List<NodeDraft>> _generateL2FromRoot(
    String query,
    List<NodeDraft> current,
    StructurePromptOptions opts,
  ) async {
    final root = _firstWhereOrNull(current, (n) => n.level == 1 && n.parentId == null);
    if (root == null) return [];
    final prompt = generateL2(L2PromptContext(
      userQuery: query,
      root: NodeRef(
        id: root.id,
        title: root.title,
        canonicalDefinition: root.canonicalDefinition,
      ),
      options: opts,
    ));
    final exec = await scheduler.execute<List<dynamic>>(
      'structure-l2',
      () => prompt,
      _nodesFromJson,
    );
    return _normalizeDrafts(exec.result)
        .where((n) => n.level == 2 && n.parentId != null)
        .toList();
  }

  /// Generates subsections (L3) for one L2 node with a dedicated request.
  Future<List<NodeDraft>> _generateL3ForNode(
    String query,
    NodeDraft parent,
    List<NodeDraft> current,
    StructurePromptOptions opts,
  ) async {
    final root = _firstWhereOrNull(current, (n) => n.level == 1 && n.parentId == null);
    final siblings = current
        .where((n) => n.level == 2 && n.parentId == root?.id && n.id != parent.id)
        .toList();
    final prompt = generateL3(L3PromptContext(
      userQuery: query,
      rootTitle: root?.title ?? parent.title,
      parent: ParentRef(
        id: parent.id,
        title: parent.title,
        canonicalDefinition: parent.canonicalDefinition,
        semanticAxis: parent.semanticAxis,
      ),
      siblings: siblings
          .map((s) => NodeRef(
                id: s.id,
                title: s.title,
                canonicalDefinition: s.canonicalDefinition,
              ))
          .toList(),
      options: opts,
    ));
    final exec = await scheduler.execute<List<dynamic>>(
      'structure-l3',
      () => prompt,
      _nodesFromJson,
    );
    return _normalizeDrafts(exec.result)
        .where((n) => n.level == 3 && n.parentId == parent.id)
        .toList();
  }

  /// Генерирует подразделы (L3) для одного L2-узла с отдельным запросом.
  ///
  /// Оборачивает сбой в [_L3Branch]: ошибка ветки не должна ронять остальные и
  /// не должна вылетать из конкурентного [_mapBounded] (иначе `Future.wait`
  /// потерял бы результаты уже завершившихся ветвей).
  Future<_L3Branch> _generateL3Branch(
    String query,
    NodeDraft parent,
    List<NodeDraft> current,
    StructurePromptOptions opts,
  ) async {
    try {
      final l3 = await _generateL3ForNode(query, parent, current, opts);
      return (parent: parent, children: l3, error: null);
    } catch (err) {
      return (parent: parent, children: const <NodeDraft>[], error: err);
    }
  }

  /// Запасной путь для уровня 2 после сбоя `structure-l2`.
  ///
  /// L2 — несущий уровень дерева: потеряв его, тема остаётся с одним корнем,
  /// а план обучения и проверки качества (`content_coverage`,
  /// `goal_coverage`) вырождаются. Поэтому сбой переключает генерацию на
  /// `expand` от корня: промпт `expand` — fast-тир, он дешевле и заметно
  /// устойчивее к JSON-трашену, чем `structure-l2`. Последний рубеж —
  /// детерминированный `fallbackStructure`.
  ///
  /// Инварианты дерева соблюдаются на обоих путях: корень уже есть в
  /// [current], все новые узлы — его дети (`parentId` = id корня, `level` = 2),
  /// циклов быть не может. `consistencyCheckAgainstTree` отсекает коллизии id и
  /// дубли заголовков, которые могли бы остаться от предыдущих попыток.
  ///
  /// Возвращает пустой список, если восстановить нечего (нет корня); вызывающий
  /// тогда работает с деревом из одного корня, и это видно в [warnings].
  Future<List<NodeDraft>> _recoverL2(
    String query,
    List<NodeDraft> current,
    StructurePromptOptions opts,
    List<String> warnings,
  ) async {
    final root =
        _firstWhereOrNull(current, (n) => n.level == 1 && n.parentId == null);
    if (root == null) {
      warnings.add('Разделы темы не восстановлены: нет корня для уровня 2.');
      return const [];
    }

    // 1. `expand` от корня: fast-тир, дешевле и устойчивее к битому JSON.
    var fromExpand = const <NodeDraft>[];
    try {
      fromExpand = consistencyCheckAgainstTree(
        current,
        (await _expandNodes(query, current, [root], options: opts))
            .where((n) => n.parentId == root.id && n.level == 2)
            .toList(),
      ).nodes;
    } catch (err) {
      warnings.add('Восстановление разделов через «expand» не удалось: '
          '${err.toString()}');
    }
    if (fromExpand.isNotEmpty) {
      warnings.add('Уровень 2 восстановлен через «expand»: '
          '${fromExpand.length} разделов (структура деградирована).');
      return fromExpand;
    }

    // 2. Детерминированный скелет — лучше демо-дерево, чем тема без разделов.
    final demo = consistencyCheckAgainstTree(
      current,
      fallbackStructure(query)
          .where((n) => n.level == 2 && n.parentId != null)
          .map((n) => n.copyWith(parentId: () => root.id, level: 2))
          .toList(),
    ).nodes;
    if (demo.isEmpty) {
      warnings.add('Разделы темы не восстановлены: структура уровня 2 отсутствует.');
    } else {
      warnings.add('Уровень 2 восстановлен демо-структурой: '
          '${demo.length} разделов (структура ненастоящая).');
    }
    return demo;
  }

  /// Validates (and repairs) the tree, focused on the given node ids.
  ///
  /// [repairBudget] общий на всё дерево: когда он исчерпан, дерево принимается
  /// в best-effort виде (с пометкой в [warnings]) — ремонт не превращается в
  /// каскад дорогих вызовов, а пайплайн не падает.
  Future<List<NodeDraft>> _validateAndRepair(
    List<NodeDraft> nodes,
    StructurePromptOptions opts,
    ProgressCallback? onProgress,
    List<String> warnings,
    _RepairBudget repairBudget,
    String phase, [
    List<String>? focusIds,
  ]) async {
    if (nodes.isEmpty) return nodes;
    onProgress?.call(phase, 'Проверка структуры на дубли и логические ошибки...');
    try {
      final validation = await _validate(nodes, focusIds);
      if (!validation.valid) {
        if (!repairBudget.tryConsume(warnings)) {
          return nodes;
        }
        onProgress?.call('repair', 'Исправление проблем дерева...');
        final repaired = await _repair(validation.issues, nodes, opts);
        if (repaired.repairedNodes.isNotEmpty) {
          nodes = mergeRepairs(nodes, repaired.repairedNodes);
        }
        if (repaired.warnings.isNotEmpty) {
          warnings.addAll(repaired.warnings);
        }
      }
    } catch (err) {
      warnings.add('Валидация не завершена: ${err.toString()}');
    }
    return nodes;
  }

  /// Expands the given nodes one level down in one LLM request.
  Future<List<NodeDraft>> _expandNodes(
    String query,
    List<NodeDraft> allNodes,
    List<NodeDraft> nodesToExpand, {
    StructurePromptOptions? options,
  }) async {
    final paths = <String, List<String>>{};
    final ctxPaths = <String>[];
    for (final target in nodesToExpand) {
      final path = buildPath(allNodes, target.id);
      paths[target.id] = path;
      ctxPaths.add('${target.title}: ${path.join(' → ')}');
    }

    final prompt = generateExpand(ExpandPromptContext(
      rootTopic: query,
      contextPaths: ctxPaths,
      nodesToExpand: nodesToExpand
          .map((n) => ExpandTargetRef(
                id: n.id,
                title: n.title,
                path: (paths[n.id] ?? []).join(' → '),
              ))
          .toList(),
      existingTree: allNodes
          .map((n) => ExistingNodeRef(
                id: n.id,
                title: n.title,
                parentId: n.parentId,
                level: n.level,
              ))
          .toList(),
      options: options,
    ));

    final exec = await scheduler.execute<List<dynamic>>(
      'expand',
      () => prompt,
      // Контракт промпта (и сервера): JSON-объект {"nodes": [...]}.
      (raw) {
        final data = parseLLMJson<Map<String, dynamic>>(raw);
        final nodes = data['nodes'];
        return nodes is List ? nodes : <dynamic>[];
      },
    );

    final added = <NodeDraft>[];
    for (final item in exec.result) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      if (id is! String) continue;
      final parentLevel =
          _firstWhereOrNull(allNodes, (n) => n.id == id)?.level ?? 0;
      final children = item['children'];
      if (children is! List) continue;
      for (final child in children) {
        if (child is! Map<String, dynamic>) continue;
        final childId = child['id'];
        if (childId is! String) continue;
        final level = parentLevel + 1;
        if (level > _maxDepth) continue;
        added.add(NodeDraft(
          id: childId,
          title: '${child['title'] ?? child['label'] ?? ''}',
          parentId: id,
          level: level,
          canonicalDefinition: _stringOrNull(child['canonical_definition']),
          semanticAxis: _stringOrNull(child['semantic_axis']),
          conceptType: _stringOrNull(child['conceptType']),
          forbiddenInterpretations: _stringList(child['forbidden_interpretations']),
          relations: _relationsOf(child),
          importance: _clamp01Num(child['importance']),
          difficulty: _clamp01Num(child['difficulty']),
          estimatedMinutes: _estimatedMinutes(child['estimated_time_minutes']),
          prerequisites: _stringList(child['prerequisites']),
        ));
      }
    }
    return added;
  }

  Future<({bool valid, List<ValidationIssue> issues})> _validate(
    List<NodeDraft> nodes, [
    List<String>? focusIds,
  ]) async {
    final validationNodes = nodes
        .map((n) => ValidationNodeRef(
              id: n.id,
              parentId: n.parentId,
              level: n.level,
              label: n.title,
              oneLiner: '',
              semanticAxis: n.semanticAxis,
              canonicalDefinition: n.canonicalDefinition,
              conceptType: n.conceptType,
              forbiddenInterpretations: n.forbiddenInterpretations,
            ))
        .toList();

    final focus = (focusIds != null && focusIds.isNotEmpty);
    final prompt = generateValidate(ValidatePromptContext(
      nodes: validationNodes,
      focusIds: focus ? focusIds : null,
    ));
    final exec = await scheduler.execute<Map<String, dynamic>>(
      'validate',
      () => prompt,
      (raw) => parseLLMJson<Map<String, dynamic>>(raw),
    );

    final data = exec.result;
    return (
      valid: data['valid'] == true,
      issues: _parseValidationIssues(data['issues']),
    );
  }

  Future<({List<NodeDraft> repairedNodes, List<String> warnings})> _repair(
    List<ValidationIssue> issues,
    List<NodeDraft> nodes,
    StructurePromptOptions? opts,
  ) async {
    final warnings = <String>[];
    final byId = {for (final n in nodes) n.id: n};
    final issuesByNode = <String, List<ValidationIssue>>{};
    for (final issue in issues) {
      if (issue.nodeId.isEmpty) continue;
      issuesByNode.putIfAbsent(issue.nodeId, () => []).add(issue);
    }

    final problemNodes = <ProblemNodeRef>[];
    for (final id in issuesByNode.keys) {
      final node = byId[id];
      if (node == null) continue;
      problemNodes.add(ProblemNodeRef(
        id: node.id,
        parentId: node.parentId,
        level: node.level,
        label: node.title,
        oneLiner: '',
        conceptType: node.conceptType,
        semanticAxis: node.semanticAxis,
        canonicalDefinition: node.canonicalDefinition,
        forbiddenInterpretations: node.forbiddenInterpretations,
      ));
    }

    final prompt = generateRepair(RepairPromptContext(
      problemNodes: problemNodes,
      issues: issues,
      level: opts?.level,
    ));

    try {
      final exec = await scheduler.execute<List<dynamic>>(
        'repair',
        () => prompt,
        (raw) => parseLLMJson<List<dynamic>>(raw),
      );
      final repaired = <NodeDraft>[];
      for (final r in exec.result) {
        if (r is! Map<String, dynamic>) continue;
        repaired.add(NodeDraft(
          id: '${r['id']}',
          title: '${r['label'] ?? r['title'] ?? ''}',
          parentId: r['parentId'] != null ? '${r['parentId']}' : null,
          level: r['level'] is num ? (r['level'] as num).toInt() : 1,
          // Repair приходит от LLM и может вернуть сколь угодно длинный
          // черновик: клампим детерминированно, иначе нарушается инвариант
          // one_liner <= 120 (регрессия live-прогона: 7 узлов по 247–458).
          canonicalDefinition: enforceOneLinerLimit(_stringOrNull(r['canonical_definition'])),
          semanticAxis: _stringOrNull(r['semantic_axis']),
          conceptType: _stringOrNull(r['conceptType']),
          forbiddenInterpretations: _stringList(r['forbidden_interpretations']),
        ));
      }
      return (repairedNodes: repaired, warnings: warnings);
    } catch (err) {
      warnings.add('Ремонт не завершён: ${err.toString()}');
      return (repairedNodes: <NodeDraft>[], warnings: warnings);
    }
  }

  /// Minimal content fill for top-level nodes so they are immediately usable.
  /// Deep content is filled lazily via background fill.
  List<NodeDraft> _fillTopLevelContent(String query, List<NodeDraft> nodes) {
    return nodes.map((n) {
      if (n.canonicalDefinition != null && n.canonicalDefinition!.isNotEmpty) return n;
      // Fallback one_liner from title — at least something is better than nothing.
      final depthHint = n.level <= 2 ? ' (основное понятие)' : '';
      return n.copyWith(
        canonicalDefinition: () => '${n.title} — ключевой элемент темы «$query».$depthHint',
      );
    }).toList();
  }

  /// Generates content (one_liner/details/analogy) for a single node.
  Future<NodeContentResult> generateNodeContent(
    String query,
    NodeDraft node,
    NodeContentContext context,
  ) async {
    final prompt = generateContent(ContentPromptContext(
      rootTopic: query,
      nodePath: context.nodePath,
      siblings: context.siblings,
      knowledgeLevel: context.knowledgeLevel,
      goal: context.goal,
      nodeLevel: context.nodeLevel,
      isRoot: context.isRoot ?? false,
      isCriticalDomain: isCriticalDomain(query, context.nodePath),
      ontologyContext: OntologyContext(
        canonicalDefinition: context.canonicalDefinition,
        semanticAxis: context.semanticAxis,
        forbiddenInterpretations: context.forbiddenInterpretations,
      ),
      node: ContentNodeRef(id: node.id, label: node.title),
    ));

    final exec = await scheduler.execute<Map<String, dynamic>>(
      'content',
      () => prompt,
      (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      nodeIds: [node.id],
    );
    final result = exec.result;

    final oneLiner = await _withinOneLinerLimit(
      label: node.title,
      draft: '${result['one_liner'] ?? node.title}',
    );

    return NodeContentResult(
      oneLiner: oneLiner,
      details: '${result['details'] ?? ''}',
      analogy: result['analogy'] is String && (result['analogy'] as String).isNotEmpty
          ? result['analogy'] as String
          : null,
      relations: _contentRelations(result['relations'], node.id),
      sources: _stringList(result['sources']),
    );
  }

  /// Гарантирует инвариант `one_liner <= 120` (AGENTS.md).
  ///
  /// Если черновик длиннее лимита — переспрашиваем модель (fast-тир): просим
  /// сократить без потери смысла. Если переспрос не дал короткий вариант,
  /// применяем детерминированную триммацию (fallback обязателен, «удача модели»
  /// не должна влиять на инвариант).
  Future<String> _withinOneLinerLimit({
    required String label,
    required String draft,
  }) async {
    final trimmed = draft.trim();
    if (trimmed.isEmpty || trimmed.length <= oneLinerMaxChars) return draft;
    try {
      final exec = await scheduler.execute<Map<String, dynamic>>(
        'oneline-rewrite',
        () => generateOnelineRewrite(label: label, currentOneLiner: trimmed),
        (raw) => parseLLMJson<Map<String, dynamic>>(raw),
      );
      final candidate = '${exec.result['one_liner'] ?? ''}'.trim();
      if (candidate.isNotEmpty && candidate.length <= oneLinerMaxChars) {
        return candidate;
      }
    } catch (_) {
      // Сбой переспроса не роняет сценарий — ниже детерминированный fallback.
    }
    return truncateOneLiner(trimmed);
  }

  /// Deepens the branch of a node from the DB: reads the node and its
  /// neighbors, generates children and persists them.
  Future<List<NodeDraft>> expandNodeFromDb(String topicId, String nodeId) async {
    final node = await repo.getNode(nodeId);
    if (node == null) throw Exception('Узел не найден');

    final nodeLevel = node.level;
    if (nodeLevel >= _maxDepth) {
      throw Exception('Достигнута максимальная глубина ($_maxDepth)');
    }

    final topic = await repo.getTopic(topicId);
    final rootTopic = topic?.name ?? 'Тема';
    final expandOptions = StructurePromptOptions(
      goal: topic?.goal.raw,
      level: topic?.targetLevel.raw,
    );

    final allRows = await repo.listNodes(topicId);
    final allNodes = allRows
        .where((r) => r.id.isNotEmpty)
        .map((r) => NodeDraft(
              id: r.id,
              title: r.label,
              parentId: r.parentId,
              level: r.level,
              conceptType: r.conceptType?.raw,
            ))
        .toList();

    final target = _firstWhereOrNull(allNodes, (n) => n.id == nodeId);
    if (target == null) throw Exception('Узел не найден');

    // The node already has children (incl. hidden) — no re-generation.
    final hasChildren = allNodes.any((n) => n.parentId == nodeId);
    if (hasChildren) return [];

    final added = await _expandNodes(
      rootTopic,
      allNodes,
      [target],
      options: expandOptions,
    );

    // Reconcile with the full tree: drop duplicates of existing concepts and
    // id collisions so no contradictions are introduced.
    final consistent = consistencyCheckAgainstTree(allNodes, added);

    // Make ids globally unique by suffixing the topic id.
    final scoped = scopeNodeIds(consistent.nodes, topicId);

    final childLevel = nodeLevel + 1;
    final leaf = childLevel >= _maxDepth;
    final nodesToInsert = <KnowledgeNode>[];
    for (final c in scoped) {
      final oneLinerDraft = c.canonicalDefinition ?? '';
      nodesToInsert.add(KnowledgeNode(
        id: c.id,
        topicId: topicId,
        parentId: nodeId,
        level: childLevel,
        label: c.title.trim(),
        // canonical_definition используется как черновик one_liner: инвариант
        // 120 символов обеспечиваем здесь, а не в репозитории.
        oneLiner: await _withinOneLinerLimit(
          label: c.title,
          draft: oneLinerDraft,
        ),
        details: '',
        conceptType: ConceptType.fromString(c.conceptType),
        importance: c.importance ?? 0.5,
        difficulty: c.difficulty ?? 0.5,
        estimatedTimeMinutes: c.estimatedMinutes ?? 5,
        relations: (c.relations ?? [])
            .map((r) => Relation(
                  from: r.from,
                  to: r.to,
                  type: RelationType.fromString(r.type),
                  label: r.label,
                ))
            .toList(),
        state: NodeState.structureGenerated,
        contentLoaded: false,
        leaf: leaf,
      ));
    }

    await repo.insertOrReplaceNodes(nodesToInsert);

    // If no children appeared the node is a natural (terminal) leaf.
    final gotChildren = scoped.isNotEmpty;
    await repo.updateNode(node.copyWith(
      state: NodeState.expanded,
      leaf: !gotChildren,
    ));

    return scoped;
  }

  /// Lazy content generation for a DB node: produces one_liner/details/analogy,
  /// persists them and marks content_loaded.
  Future<NodeContentResult> generateNodeContentFromDb(
    String topicId,
    String nodeId,
  ) async {
    final node = await repo.getNode(nodeId);
    if (node == null) throw Exception('Узел не найден');

    final topic = await repo.getTopic(topicId);
    final rootTopic = topic?.name ?? 'Тема';
    final knowledgeLevel = masteryLevelToKnowledgeLevel(topic?.targetLevel.raw);

    final allRows = await repo.listNodes(topicId);
    final path = _nodePathFromRows(allRows, nodeId);
    final parentId = node.parentId;
    final siblings = parentId != null
        ? allRows
            .where((r) => r.parentId == parentId && r.id != nodeId)
            .map((r) => r.label)
            .take(8)
            .toList()
        : <String>[];

    final content = await generateNodeContent(
      rootTopic,
      NodeDraft(
        id: nodeId,
        title: node.label,
        parentId: parentId,
        level: node.level,
      ),
      NodeContentContext(
        nodePath: path,
        siblings: siblings,
        canonicalDefinition: node.oneLiner.isNotEmpty ? node.oneLiner : null,
        semanticAxis: node.conceptType?.raw,
        knowledgeLevel: knowledgeLevel,
        goal: topic?.goal.raw,
        nodeLevel: node.level,
        isRoot: node.level <= 1 && node.parentId == null,
      ),
    );

    await repo.updateNode(node.copyWith(
      oneLiner: content.oneLiner,
      details: content.details,
      analogy: () => content.analogy,
      relations: content.relations,
      sources: content.sources,
      state: NodeState.contentGenerated,
      contentLoaded: true,
    ));

    return content;
  }

  List<String> _nodePathFromRows(List<KnowledgeNode> rows, String nodeId) {
    final byId = {for (final r in rows) r.id: r};
    final path = <String>[];
    KnowledgeNode? current = byId[nodeId];
    var guard = 0;
    while (current != null && guard < 50) {
      path.insert(0, current.label);
      final parentId = current.parentId;
      current = parentId != null ? byId[parentId] : null;
      guard++;
    }
    return path;
  }
}

// ─── Prompt defaults ──────────────────────────────────────────────────────────

/// Maps a MasteryLevel wire value to a KnowledgeLevel hint key.
String? masteryLevelToKnowledgeLevel(String? level) {
  switch (level) {
    case 'awareness':
    case 'basic_understanding':
      return 'beginner';
    case 'solid_understanding':
    case 'practical_application':
      return 'intermediate';
    case 'advanced':
    case 'expert':
      return 'expert';
    default:
      return null;
  }
}

const List<String> _criticalDomainKeywords = [
  'медицина', 'медицин', 'фармаколог', 'фармац', 'терапи', 'хирург',
  'патолог', 'анатом', 'физиолог', 'клини', 'диагност',
  'law', 'право', 'юрис', 'уголовн', 'гражданск',
  'finance', 'финанс', 'экономик', 'бухгалт', 'налог',
  'medicine', 'medical', 'pharmacolog', 'clinical', 'surgery',
  'legal', 'jurisprud',
  'exam', 'экзамен', 'сертиф', ' licens',
  'наук', 'scientific', 'исследован',
];

bool _isCriticalDomainDefault(String topicName, List<String> nodePath) {
  final text = [topicName, ...nodePath].join(' ').toLowerCase();
  return _criticalDomainKeywords.any(text.contains);
}

// ─── Draft normalization ──────────────────────────────────────────────────────

List<dynamic> _nodesFromJson(String raw) {
  final data = parseLLMJson<Map<String, dynamic>>(raw);
  final nodes = data['nodes'];
  return nodes is List ? nodes : <dynamic>[];
}

List<NodeDraft> _normalizeDrafts(List<dynamic> raw) {
  final drafts = <NodeDraft>[];
  for (final r in raw) {
    if (r is! Map<String, dynamic>) continue;
    final rec = r;
    drafts.add(NodeDraft(
      id: '${rec['id'] ?? ''}',
      title: '${rec['title'] ?? rec['label'] ?? ''}',
      parentId: _stringOrNull(rec['parentId']),
      level: rec['level'] is num ? (rec['level'] as num).toInt() : _guessLevel(rec),
      canonicalDefinition: _stringOrNull(rec['canonical_definition']),
      semanticAxis: _stringOrNull(rec['semantic_axis']),
      conceptType: _stringOrNull(rec['conceptType']),
      forbiddenInterpretations: _stringList(rec['forbidden_interpretations']),
      relations: _relationsOf(rec),
      importance: _clamp01Num(rec['importance']),
      difficulty: _clamp01Num(rec['difficulty']),
      estimatedMinutes: _estimatedMinutes(rec['estimated_time_minutes']),
      prerequisites: _stringList(rec['prerequisites']),
    ));
  }

  // Fix levels via DFS from root.
  final roots = drafts.where((d) => d.parentId == null).toList();
  final result = <NodeDraft>[];
  final visited = <String>{};

  void visit(NodeDraft d, int level) {
    if (visited.contains(d.id)) return;
    visited.add(d.id);
    result.add(d.copyWith(level: d.level != 0 ? d.level : level));
    final children = drafts.where((c) => c.parentId == d.id).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    for (final child in children) {
      visit(child, level + 1);
    }
  }

  for (final root in roots) {
    visit(root, 1);
  }

  // Orphans: nodes whose parentId points to a node outside this batch.
  for (final d in drafts) {
    if (!visited.contains(d.id)) {
      result.add(d.copyWith(level: d.level != 0 ? d.level : _guessLevelFromDraft(d)));
    }
  }

  return result;
}

int _guessLevel(Map<String, dynamic> rec) => rec['parentId'] == null ? 1 : 2;

int _guessLevelFromDraft(NodeDraft d) => d.parentId == null ? 1 : 2;

const Set<String> _validRelationTypes = {
  'related', 'depends_on', 'requires', 'example_of', 'similar_to',
  'contrasts_with', 'causes', 'enables', 'used_for', 'alternative_to',
};

/// Parses relation metadata emitted by structure prompts. Invalid records are
/// skipped; returns null when absent or empty.
List<RawRelation>? _relationsOf(Map<String, dynamic> rec) {
  final rels = rec['relations'];
  if (rels is! List) return null;
  final out = <RawRelation>[];
  for (final rel in rels) {
    if (rel is! Map<String, dynamic>) continue;
    final to = rel['to'];
    if (to is! String || to.isEmpty) continue;
    final type = rel['type'] is String ? rel['type'] as String : 'related';
    out.add((
      from: '${rec['id'] ?? ''}',
      to: to,
      type: _validRelationTypes.contains(type) ? type : 'related',
      label: rel['label'] is String && (rel['label'] as String).isNotEmpty
          ? rel['label'] as String
          : null,
    ));
  }
  return out.isEmpty ? null : out;
}

List<Relation> _contentRelations(dynamic raw, String fromId) {
  final out = <Relation>[];
  if (raw is! List) return out;
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final to = item['to'];
    if (to is! String || to.isEmpty) continue;
    final from = item['from'];
    out.add(Relation(
      from: from is String && from.isNotEmpty ? from : fromId,
      to: to,
      type: RelationType.fromString(item['type'] is String ? item['type'] as String : 'related'),
      label: item['label'] is String ? item['label'] as String : null,
    ));
  }
  return out;
}

List<ValidationIssue> _parseValidationIssues(dynamic raw) {
  final out = <ValidationIssue>[];
  if (raw is! List) return out;
  for (final i in raw) {
    if (i is! Map<String, dynamic>) continue;
    out.add(ValidationIssue(
      type: i['type'] is String ? i['type'] as String : 'DUPLICATE',
      nodeId: i['node_id'] is String ? i['node_id'] as String : '',
      reason: i['reason'] is String ? i['reason'] as String : '',
    ));
  }
  return out;
}

bool _isOffline(Object err) {
  if (err is LLMMockException) return true;
  if (err is LLMRetriesExhaustedException) return err.lastError is LLMMockException;
  return false;
}

// ─── Tree helpers ─────────────────────────────────────────────────────────────

int _maxLevelOf(List<NodeDraft> nodes) =>
    nodes.fold(0, (max, n) => n.level > max ? n.level : max);

List<String> buildPath(List<NodeDraft> nodes, String nodeId) {
  final byId = {for (final n in nodes) n.id: n};
  final path = <String>[];
  NodeDraft? current = byId[nodeId];
  var guard = 0;
  while (current != null && guard < 50) {
    path.insert(0, current.title);
    final parentId = current.parentId;
    current = parentId != null ? byId[parentId] : null;
    guard++;
  }
  return path;
}

/// Reconciles incoming children against an existing tree: drops concepts
/// already present (by normalized title), id collisions, and title duplicates
/// among siblings.
({List<NodeDraft> nodes, int skipped}) consistencyCheckAgainstTree(
  List<NodeDraft> existing,
  List<NodeDraft> incoming,
) {
  final existingTitles = <String>{};
  for (final n in existing) {
    final t = _normalizeTitle(n.title);
    if (t.isNotEmpty) existingTitles.add(t);
  }
  final existingIds = existing.map((n) => n.id).toSet();

  final seenTitles = <String, String>{};
  final seenIds = <String>{};
  final nodes = <NodeDraft>[];

  for (final n in incoming) {
    final t = _normalizeTitle(n.title);
    if (t.isEmpty) continue;
    if (existingTitles.contains(t)) continue;
    if (n.id.isNotEmpty && existingIds.contains(n.id)) continue;
    if (seenTitles.containsKey(t)) continue;
    final id = n.id.isEmpty ? 'c_${nodes.length + 1}' : n.id;
    if (seenIds.contains(id)) continue;
    seenIds.add(id);
    seenTitles[t] = id;
    nodes.add(n.copyWith(id: id));
  }

  return (nodes: nodes, skipped: incoming.length - nodes.length);
}

String _normalizeTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Applies repair results to the tree. A problematic node is replaced only if
/// the repair returned a node with the same id; newly-created nodes are added.
List<NodeDraft> mergeRepairs(List<NodeDraft> nodes, List<NodeDraft> repaired) {
  final byId = {for (final r in repaired) r.id: r};
  final out = nodes.map((n) => byId[n.id] ?? n).toList();
  final existingIds = {for (final o in out) o.id};
  for (final r in repaired) {
    if (!existingIds.contains(r.id)) out.add(r);
  }
  return out;
}

/// Collapses exact duplicates and renames remaining id collisions, updating
/// parentId references so the tree stays internally consistent.
List<NodeDraft> dedupeNodeIds(List<NodeDraft> nodes) {
  final seen = <String>{};
  final out = <NodeDraft>[];
  // original id -> new unique id (for all, including unchanged ids).
  final idMap = <String, String>{};

  for (final n in nodes) {
    if (n.id.isEmpty) continue;
    final existing = _firstWhereOrNull(out, (o) => o.id == n.id);
    final isExactDup = existing != null &&
        existing.title == n.title &&
        existing.level == n.level &&
        existing.parentId == n.parentId;
    if (isExactDup) {
      idMap[n.id] = n.id;
      continue;
    }

    var newId = n.id;
    if (seen.contains(n.id)) {
      final base = n.id.replaceFirst(RegExp(r'-\d+$'), '');
      var i = 1;
      do {
        newId = '$base-$i';
        i++;
      } while (seen.contains(newId));
    }
    seen.add(newId);
    if (!idMap.containsKey(n.id)) {
      idMap[n.id] = newId;
    }
    out.add(n.copyWith(id: newId));
  }

  // Rewrite parentId references according to the renames.
  return out
      .map((n) {
        final parentId = n.parentId;
        if (parentId != null &&
            parentId != n.id &&
            idMap.containsKey(parentId)) {
          final mapped = idMap[parentId]!;
          if (mapped != parentId) {
            return n.copyWith(parentId: () => mapped);
          }
        }
        return n;
      })
      .toList();
}

/// Deterministic demo tree for offline mode (LLM mock). Skeleton of levels
/// 1-2 with guaranteed-unique ids.
List<NodeDraft> fallbackStructure(String query) {
  final firstLine = query.split(RegExp(r'\r?\n')).first.trim();
  var topic = firstLine;
  if (topic.length > 80) topic = topic.substring(0, 80);
  final title = topic.isEmpty ? 'Тема' : topic;
  return [
    NodeDraft(
      id: 'n1',
      title: title,
      canonicalDefinition: 'Общий обзор темы «$title» и её ключевых разделов.',
      semanticAxis: 'theory',
      conceptType: 'topic',
    ),
    NodeDraft(
      id: 'n2_1',
      title: 'Основы',
      parentId: 'n1',
      level: 2,
      canonicalDefinition:
          'Базовые понятия и определения, с которых начинается изучение темы.',
      semanticAxis: 'theory',
      conceptType: 'concept',
    ),
    NodeDraft(
      id: 'n2_2',
      title: 'Ключевые направления',
      parentId: 'n1',
      level: 2,
      canonicalDefinition:
          'Главные подтемы и принципы, составляющие ядро предмета.',
      semanticAxis: 'architecture',
      conceptType: 'concept',
    ),
    NodeDraft(
      id: 'n2_3',
      title: 'Применение',
      parentId: 'n1',
      level: 2,
      canonicalDefinition:
          'Практические области использования знаний по теме.',
      semanticAxis: 'application',
      conceptType: 'example',
    ),
  ];
}

// ─── Small utilities ──────────────────────────────────────────────────────────

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

String? _stringOrNull(dynamic v) => v is String ? v : null;

List<String> _stringList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<String>().toList();
}

double? _clamp01Num(dynamic v) {
  if (v is! num) return null;
  return v.toDouble().clamp(0.0, 1.0).toDouble();
}

int? _estimatedMinutes(dynamic v) {
  if (v is num && v > 0) return v.round();
  if (v is String) {
    final n = num.tryParse(v);
    if (n != null && n > 0) return n.round();
  }
  return null;
}