import type {
  Relation,
  RelationType,
} from "@mindtree/types";
import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson, LLMMockError, LLMRetriesExhaustedError } from "../llm/client.js";
import { scopeNodeIds } from "./scopedIds.js";
import {
  buildL1Prompt,
  type IStructurePromptOptions,
} from "../prompts/structure.js";
import { buildL2Prompt } from "../prompts/generateL2.js";
import { buildL3Prompt } from "../prompts/generateL3.js";
import { buildExpandPrompt } from "../prompts/expand.js";
import {
  buildValidatePrompt,
  parseValidationResult,
  VALIDATION_BLOCKING_ISSUE_TYPES,
  type ValidationNode,
  type ValidationIssueType,
} from "../prompts/validate.js";
import {
  buildRepairPrompt,
  type ProblemNode,
} from "../prompts/repair.js";
import { ONELINER_MAX_CHARS } from "../prompts/oneline.js";

export interface NodeDraft {
  id: string;
  title: string;
  parentId: string | null;
  level: number;
  canonical_definition?: string;
  semantic_axis?: string;
  conceptType?: string;
  forbidden_interpretations?: string[];
  /** §20/§52: метаданные для приоритизации и curriculum engine. */
  importance?: number;
  difficulty?: number;
  estimatedMinutes?: number;
  prerequisites?: string[];
  relations?: Relation[];
}

export interface TreeBuildResult {
  nodes: NodeDraft[];
  warnings: string[];
  /**
   * Id узлов, собранных по запасному (деградированному) пути: их структура
   * ненастоящая и помечена в `warnings`. Пусто в нормальном прогоне.
   * Зеркалит mindtree_flutter/lib/domain/engines/knowledge_graph_engine.dart.
   */
  degradedNodeIds: string[];
}

export interface ProgressCallback {
  (phase: string, message: string, stats?: { total: number; depth: number; leaves: number }): void;
}

const MAX_DEPTH = 5;

/**
 * Максимальная глубина генерации дерева для уровня пользователя.
 * Зеркалит mindtree_flutter/lib/domain/engines/knowledge_graph_engine.dart
 * (_maxGenerationLevel): beginner → 2, intermediate → 3, advanced/expert → 4.
 */
function maxGenerationLevel(level?: string): number {
  switch (level) {
    case "beginner":
      return 2;
    case "intermediate":
      return 3;
    case "expert":
      return 4;
    default:
      return 3; // intermediate по умолчанию
  }
}

/**
 * Сколько L3-ветвей движок держит «в полёте» одновременно.
 *
 * Ветви независимы (каждый `structure-l3` смотрит только на свой L2-родитель и
 * соседей), поэтому их можно гнать конкурентно. Реальные лимиты (RPM/RPD/
 * `maxConcurrency`) держит scheduler — он выстроит запросы в очередь сам; эта
 * константа нужна, чтобы не держать в памяти десятки pending-промптов.
 * Зеркалит `_l3BranchConcurrency` в knowledge_graph_engine.dart.
 */
const L3_BRANCH_CONCURRENCY = 4;

/**
 * Жёсткий бюджет вызовов `repair` на одну генерацию дерева.
 *
 * Без него «валидация → ремонт» повторяется на каждой L3-ветке и при плохом
 * ответе валидатора превращается в каскад из дорогих вызовов. Исчерпание
 * бюджета — не ошибка: дерево принимается в best-effort виде, в `warnings`
 * попадает пометка, пайплайн не падает.
 * Зеркалит `_maxRepairCallsPerTree` в knowledge_graph_engine.dart.
 */
const MAX_REPAIR_CALLS_PER_TREE = 2;

/**
 * Бюджет ремонта на одну генерацию дерева.
 *
 * Счётчик общий на всё дерево, а проверка и списание выполняются синхронно
 * (между ними нет `await`), поэтому конкурентные ветки не могут превысить
 * лимит: JS-рантайм однопоточный, синхронный участок — критическая секция.
 */
class RepairBudget {
  private left: number;
  private warned = false;

  constructor(private readonly limit: number) {
    this.left = limit;
  }

  /** Сколько попыток ремонта уже израсходовано. */
  get used(): number {
    return this.limit - this.left;
  }

  /** Резервирует одну попытку; при исчерпании добавляет ровно один warning. */
  tryConsume(warnings: string[]): boolean {
    if (this.left <= 0) {
      if (!this.warned) {
        this.warned = true;
        warnings.push(`Ремонт исчерпан: ${this.used} попыток, часть узлов оставлена как есть.`);
      }
      return false;
    }
    this.left--;
    return true;
  }
}

/** Результат одной L3-ветки: либо дети, либо ошибка этой ветки. */
type L3Branch = { parent: NodeDraft; children: NodeDraft[]; error?: unknown };

/**
 * Прогоняет `action` по `items` конкурентно, но не шире `limit` задач сразу.
 *
 * Результаты собираются **по позиции** в `items`, поэтому итоговый список не
 * зависит от того, в каком порядке отработали вызовы (детерминизм доменной
 * логики). `action` не должна бросать: сбой ветки разбирает вызывающий.
 * Зеркалит `_mapBounded` в knowledge_graph_engine.dart.
 */
async function mapBounded<E, T>(
  limit: number,
  items: E[],
  action: (item: E) => Promise<T>,
): Promise<T[]> {
  if (items.length === 0) return [];
  const width = Math.max(1, Math.min(limit, items.length));
  const slots: (T | undefined)[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    for (;;) {
      // Синхронное резервирование индекса: гонок нет.
      const i = next++;
      if (i >= items.length) return;
      slots[i] = await action(items[i]);
    }
  };
  await Promise.all(Array.from({ length: width }, () => worker()));
  return slots as T[];
}

export class KnowledgeGraphEngine {
  /**
   * Полный конвейер: structure → expand → validate → repair → content.
   * content генерируется лениво (just-in-time), здесь строится скелет с контентом верхних уровней.
   */
  async generate(
    query: string,
    options: { goal?: string; level?: string; timeBudgetMinutes?: number } = {},
    onProgress?: ProgressCallback,
    onBatch?: (added: NodeDraft[]) => Promise<void>,
  ): Promise<TreeBuildResult> {
    const warnings: string[] = [];
    // Узлы, собранные по запасному пути: их структура ненастоящая, и об этом
    // должны знать и probe, и пользователь.
    const degraded: string[] = [];
    // Бюджет ремонта на всё дерево (общий для всех валидаций, в т.ч. L3).
    const repairBudget = new RepairBudget(MAX_REPAIR_CALLS_PER_TREE);
    const opts: IStructurePromptOptions = {
      goal: options.goal as IStructurePromptOptions["goal"],
      level: options.level as IStructurePromptOptions["level"],
      timeBudgetMinutes: options.timeBudgetMinutes,
    };
    // Ограничиваем максимальную глубину генерации по уровню пользователя.
    // beginner → L2, intermediate → L3, advanced/expert → L4.
    const maxGenLevel = maxGenerationLevel(options.level);

    // Пошаговый конвейер: L1 (корень) → L2 (разделы) → L3 (подразделы).
    // Каждый шаг — отдельный LLM-запрос с полным семантическим контекстом,
    // что гарантирует логическую согласованность (нет «Виды раскладов» как
    // L2 рядом с L2 «Расклады»). Валидация и ремонт выполняются на каждом этапе.
    let nodes: NodeDraft[] = [];

    // Шаг 1: корень (L1)
    onProgress?.("structure", "Определение корня темы...");
    try {
      const root = await this.generateRoot(query, opts);
      nodes = root;
    } catch (err) {
      const isOffline = err instanceof LLMMockError
        || (err instanceof LLMRetriesExhaustedError && err.lastError instanceof LLMMockError);
      if (isOffline) {
        nodes = fallbackStructure(query);
        warnings.push("Офлайн-режим: построено демо-дерево знаний вместо LLM.");
      } else {
        throw new Error(
          `Не удалось определить корень темы: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    if (!nodes.some((n) => n.level === 1 && !n.parentId)) {
      // Корня нет — без него дерево не построить.
      nodes = fallbackStructure(query);
      warnings.push("Корень темы не был определён; построено демо-дерево.");
    }

    // Инкрементальный персист: корень виден пользователю сразу, пока генерируются
    // следующие уровни. При сбое (закрытие вкладки и т.п.) в БД остаётся
    // сохранённая часть дерева, а не пустота.
    // Важно: dedupeNodeIds вызывается ДО onBatch, чтобы ID были стабильны
    // и reconcileTree в pipeline.ts не удалял инкрементально сохранённые узлы.
    if (onBatch) {
      nodes = dedupeNodeIds(nodes);
      const batch = nodes.filter((n) => n.level === 1 && !n.parentId);
      console.log(`[engine] onBatch L1: ${batch.length} узлов`);
      try {
        await onBatch(batch);
      } catch {
        // Не критично для генерации: финальный persist в route восстановит дерево.
      }
    }

    // Шаг 2: разделы (L2) — один запрос, полный контекст корня.
    onProgress?.("structure", "Генерация главных разделов (уровень 2)...");
    let l2: NodeDraft[] = [];
    try {
      l2 = await this.generateL2FromRoot(query, nodes, opts);
      nodes = nodes.concat(l2);
    } catch (err) {
      // Сбой L2 не «съедает» уровень: без разделов тема остаётся с одним
      // корнем, а план обучения и проверки качества (`content_coverage`,
      // `goal_coverage`) вырождаются. Переключаемся на запасной путь.
      warnings.push(`Генерация разделов не завершена: ${err instanceof Error ? err.message : String(err)}`);
      l2 = await this.recoverL2(query, nodes, opts, warnings);
      degraded.push(...l2.map((n) => n.id));
      nodes = nodes.concat(l2);
    }

    if (onBatch && l2.length > 0) {
      nodes = dedupeNodeIds(nodes);
      const l2Ids = new Set(nodes.filter((n) => n.level === 2).map((n) => n.id));
      const batch = nodes.filter((n) => l2Ids.has(n.id));
      console.log(`[engine] onBatch L2: ${batch.length} узлов`);
      try {
        await onBatch(batch);
      } catch {
        // финальный persist в route восстановит дерево
      }
    }

    // Валидация L1+L2 (и ремонт при необходимости).
    nodes = await this.validateAndRepair(nodes, opts, onProgress, warnings, repairBudget, "validate");

    // Шаг 3: подразделы (L3) — отдельный запрос на каждый L2-раздел,
    // чтобы LLM видел контекст конкретной ветви и не создавал противоречий.
    // Раздел генерируем только для intermediate+ уровней (как во flutter).
    if (maxGenLevel >= 3) {
      onProgress?.("structure", "Генерация подразделов (уровень 3)...");
      const l2Nodes = nodes.filter((n) => n.level === 2);
      if (l2Nodes.length > 0) {
        // Ветви независимы, поэтому `structure-l3` идут конкурентно (см.
        // L3_BRANCH_CONCURRENCY), а `nodes` на этом шаге — замороженный
        // снимок: L3-узлы не влияют на контекст соседних ветвей (root и
        // siblings берутся с уровней 1–2), а значит порядок ответа не может
        // изменить результат.
        const branches = await mapBounded(
          L3_BRANCH_CONCURRENCY,
          l2Nodes,
          (l2Node) => this.generateL3Branch(query, l2Node, nodes, opts),
        );

        // Дальше — строго в порядке L2-узлов: порядок итогового `nodes` совпадает
        // с последовательным прогоном (parentId детей уже в дереве — сирот нет).
        // Инкрементальный персист L3-ветви: ветка появляется у пользователя
        // по мере завершения, а не только в конце всей генерации.
        const l3Nodes: NodeDraft[] = [];
        for (const branch of branches) {
          if (branch.error !== undefined) {
            warnings.push(
              `Подразделы для «${branch.parent.title}» не завершены: ${branch.error instanceof Error ? branch.error.message : String(branch.error)}`,
            );
            continue;
          }
          if (branch.children.length === 0) continue;
          nodes = nodes.concat(branch.children);
          l3Nodes.push(...branch.children);
          if (onBatch) {
            nodes = dedupeNodeIds(nodes);
            const kept = nodes.filter((n) => n.parentId === branch.parent.id && n.level === 3);
            if (kept.length > 0) {
              console.log(`[engine] onBatch L3 (ветка «${branch.parent.title}»): ${kept.length} узлов`);
              await onBatch(kept);
            }
          }
        }
        // Батч-валидация всех L3-ветвей одним вызовом вместо N per-branch:
        // модель видит все ветки разом (лучше ловит OVERLAP между ветвями),
        // а число вызовов сильной модели не растёт с числом разделов.
        if (l3Nodes.length > 0) {
          const focusIds = l3Nodes.map((n) => n.id);
          nodes = await this.validateAndRepair(
            nodes,
            opts,
            onProgress,
            warnings,
            repairBudget,
            "validate-l3",
            focusIds,
          );
        }
      }
    } else {
      onProgress?.("structure", "Для текущего уровня достаточно 2 разделов — углубление доступно по кнопке.");
    }

    onProgress?.("content", "Заполнение контента узлов...");
    try {
      const withContent = await this.fillTopLevelContent(query, nodes);
      nodes = withContent;
    } catch (err) {
      warnings.push(`Контент заполнен не полностью: ${err instanceof Error ? err.message : String(err)}`);
    }

    // Финальная дедупликация (на случай, если предыдущие вызовы dedupeNodeIds
    // не покрыли все коллизии — например, между L3-ветками разных L2).
    nodes = dedupeNodeIds(nodes);

    const stats = {
      total: nodes.length,
      depth: maxLevelOf(nodes),
      leaves: nodes.filter((n) => !nodes.some((c) => c.parentId === n.id)).length,
    };
    onProgress?.("done", "Дерево готово", stats);

    return { nodes, warnings, degradedNodeIds: degraded };
  }

  /** Генерирует корневой узел (L1) отдельным запросом. */
  private async generateRoot(
    query: string,
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const scheduler = getScheduler();
    const prompt = buildL1Prompt(query, opts);
    const { result } = await scheduler.execute(
      "structure",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 1 && !n.parentId);
  }

  /** Генерирует разделы (L2) с контекстом корня. */
  private async generateL2FromRoot(
    query: string,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const root = current.find((n) => n.level === 1 && !n.parentId);
    if (!root) return [];
    const scheduler = getScheduler();
    const prompt = buildL2Prompt({
      userQuery: query,
      root: {
        id: root.id,
        title: root.title,
        canonical_definition: root.canonical_definition,
      },
      options: opts,
    });
    const { result } = await scheduler.execute(
      "structure-l2",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 2 && n.parentId);
  }

  /** Генерирует подразделы (L3) для одного L2-узла отдельным запросом. */
  private async generateL3ForNode(
    query: string,
    parent: NodeDraft,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const root = current.find((n) => n.level === 1 && !n.parentId);
    const siblings = current
      .filter((n) => n.level === 2 && n.parentId === root?.id && n.id !== parent.id);
    const scheduler = getScheduler();
    const prompt = buildL3Prompt({
      userQuery: query,
      rootTitle: root?.title ?? parent.title,
      parent: {
        id: parent.id,
        title: parent.title,
        canonical_definition: parent.canonical_definition,
        semantic_axis: parent.semantic_axis,
      },
      siblings: siblings.map((s) => ({
        id: s.id,
        title: s.title,
        canonical_definition: s.canonical_definition,
      })),
      options: opts,
    });
    const { result } = await scheduler.execute(
      "structure-l3",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );
    return normalizeDrafts(result).filter((n) => n.level === 3 && n.parentId === parent.id);
  }

  /**
   * Генерирует подразделы (L3) для одного L2-узла, не бросая наружу.
   *
   * Ошибка ветки не должна ронять остальные и не должна вылетать из
   * конкурентного `mapBounded` (иначе Promise.all потерял бы результаты уже
   * завершившихся ветвей).
   */
  private async generateL3Branch(
    query: string,
    parent: NodeDraft,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
  ): Promise<L3Branch> {
    try {
      const children = await this.generateL3ForNode(query, parent, current, opts);
      return { parent, children };
    } catch (err) {
      return { parent, children: [], error: err };
    }
  }

  /**
   * Запасной путь для уровня 2 после сбоя `structure-l2`.
   *
   * L2 — несущий уровень дерева: потеряв его, тема остаётся с одним корнем,
   * а план обучения и проверки качества вырождаются. Поэтому сбой
   * переключает генерацию на `expand` от корня: промпт `expand` — fast-тир,
   * он дешевле и заметно устойчивее к JSON-трашену, чем `structure-l2`.
   * Последний рубеж — детерминированный `fallbackStructure`.
   *
   * Инварианты дерева соблюдаются на обоих путях: корень уже есть в
   * `current`, все новые узлы — его дети (`parentId` = id корня, `level` = 2),
   * циклов быть не может. `consistencyCheckAgainstTree` отсекает коллизии id и
   * дубли заголовков, которые могли бы остаться от предыдущих попыток.
   */
  private async recoverL2(
    query: string,
    current: NodeDraft[],
    opts: IStructurePromptOptions,
    warnings: string[],
  ): Promise<NodeDraft[]> {
    const root = current.find((n) => n.level === 1 && !n.parentId);
    if (!root) {
      warnings.push("Разделы темы не восстановлены: нет корня для уровня 2.");
      return [];
    }

    // 1. `expand` от корня: fast-тир, дешевле и устойчивее к битому JSON.
    let fromExpand: NodeDraft[] = [];
    try {
      const expanded = await this.expandNodes(query, current, [root], undefined, opts);
      fromExpand = consistencyCheckAgainstTree(
        current,
        expanded.filter((n) => n.parentId === root.id && n.level === 2),
      ).nodes;
    } catch (err) {
      warnings.push(
        `Восстановление разделов через «expand» не удалось: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    if (fromExpand.length > 0) {
      warnings.push(
        `Уровень 2 восстановлен через «expand»: ${fromExpand.length} разделов (структура деградирована).`,
      );
      return fromExpand;
    }

    // 2. Детерминированный скелет — лучше демо-дерево, чем тема без разделов.
    const demo = consistencyCheckAgainstTree(
      current,
      fallbackStructure(query)
        .filter((n) => n.level === 2 && n.parentId)
        .map((n) => ({ ...n, parentId: root.id, level: 2 })),
    ).nodes;
    if (demo.length === 0) {
      warnings.push("Разделы темы не восстановлены: структура уровня 2 отсутствует.");
    } else {
      warnings.push(
        `Уровень 2 восстановлен демо-структурой: ${demo.length} разделов (структура ненастоящая).`,
      );
    }
    return demo;
  }

  /**
   * Валидирует (и ремонтирует) дерево, фокусно — на указанных узлах.
   *
   * Сначала отрабатывает детерминированный пре-пасс ([deterministicValidate]):
   * формальные дефекты (exact-дубликаты подписей) считаются кодом и не требуют
   * вызова сильной модели. Его `hardIssues` добавляются к issues LLM-валидации —
   * `repair` этот тип правила умеет. Информационные находки пре-пасса (типы
   * 14–16, которые LLM по контракту проверять не может) уходят в `warnings`
   * без повторов.
   *
   * `repairBudget` общий на всё дерево: когда он исчерпан, дерево принимается
   * в best-effort виде (с пометкой в `warnings`) — ремонт не превращается в
   * каскад дорогих вызовов, а пайплайн не падает.
   */
  private async validateAndRepair(
    nodes: NodeDraft[],
    opts: IStructurePromptOptions,
    onProgress: ProgressCallback | undefined,
    warnings: string[],
    repairBudget: RepairBudget,
    phase: string,
    focusIds?: string[],
  ): Promise<NodeDraft[]> {
    if (nodes.length === 0) return nodes;
    onProgress?.(phase, "Проверка структуры на дубли и логические ошибки...");
    try {
      // Циклы в графе зависимостей разрываются кодом ДО обращения к модели:
      // участники цикла обычно не дефектны, а repair всё равно не умеет
      // чинить связи. Заодно снимается причина ложных находок — в промпте
      // тип CIRCULAR_DEPENDENCY объявлен критичным, но `relations` в
      // ValidationNodeRef не передаются, то есть проверить его модель не
      // может и выдумывает его вместо того, чтобы смотреть на другие узлы.
      const broken = breakDependencyCycles(nodes);
      if (broken.nodes !== nodes) {
        nodes = broken.nodes;
        for (const note of broken.notes) {
          if (!warnings.includes(note)) warnings.push(note);
        }
      }
      const deterministic = deterministicValidate(nodes);
      for (const note of deterministic.notes) {
        // Пре-пасс прогоняется на каждой точке пайплайна, поэтому один и тот же
        // дефект всплывает повторно — в warnings кладём по одному вхождению.
        if (!warnings.includes(note)) warnings.push(note);
      }
      const validation = await this.validate(nodes, focusIds);
      // Решение о ремонте принимается по ТИПУ находок, а не по флагу `valid`
      // модели. Раньше правило «valid=false при любой находке» в промпте
      // приводило к тому, что валидатор отвергал здоровое дерево и запускал
      // полный repair-проход впустую (≈2.6 руб на прогон, замерено).
      const blocking = validation.issues.filter((i) =>
        VALIDATION_BLOCKING_ISSUE_TYPES.has(i.type),
      );
      const advisory = validation.issues.filter(
        (i) => !VALIDATION_BLOCKING_ISSUE_TYPES.has(i.type),
      );
      // Сводка нужна для разбора прогонов: без неё неизвестно, что именно
      // валидатор счёл проблемой и почему дерево чинили.
      const blockingTypes = [...new Set(blocking.map((i) => i.type))];
      const advisoryTypes = [...new Set(advisory.map((i) => i.type))];
      const verdictNote =
        `Валидация (${nodes.length} узл.): вердикт valid=${validation.valid}, ` +
        `блокирующих=${blocking.length}, некритичных=${advisory.length}` +
        (blockingTypes.length ? ` [${blockingTypes.join(", ")}]` : "") +
        (advisoryTypes.length ? `; рекомендации: ${advisoryTypes.join(", ")}` : "");
      if (!warnings.includes(verdictNote)) warnings.push(verdictNote);
      // Модель может ошибиться в `valid`; верим типизированным находкам.
      const needsRepair = blocking.length > 0 || deterministic.hardIssues.length > 0;
      if (needsRepair) {
        const allIssues = [...deterministic.hardIssues, ...blocking];
        if (!repairBudget.tryConsume(warnings)) {
          return nodes;
        }
        onProgress?.("repair", "Исправление проблем дерева...");
        const repaired = await this.repair(allIssues, nodes, opts);
        if (repaired.repairedNodes.length > 0) {
          nodes = mergeRepairs(nodes, repaired.repairedNodes);
        }
        if (repaired.warnings.length > 0) warnings.push(...repaired.warnings);
      }
    } catch (err) {
      warnings.push(`Валидация не завершена: ${err instanceof Error ? err.message : String(err)}`);
    }
    return nodes;
  }

  private async expandNodes(
    query: string,
    allNodes: NodeDraft[],
    nodesToExpand: NodeDraft[],
    onProgress?: ProgressCallback,
    options?: IStructurePromptOptions,
  ): Promise<NodeDraft[]> {
    const scheduler = getScheduler();
    const paths = new Map<string, string[]>();
    const ctxPaths: string[] = [];

    for (const target of nodesToExpand) {
      const path = buildPath(allNodes, target.id);
      paths.set(target.id, path);
      ctxPaths.push(`${target.title}: ${path.join(" → ")}`);
    }

    const prompt = buildExpandPrompt({
      rootTopic: query,
      contextPaths: ctxPaths,
      nodesToExpand: nodesToExpand.map((n) => ({
        id: n.id,
        title: n.title,
        path: (paths.get(n.id) ?? []).join(" → "),
      })),
      existingTree: allNodes.map((n) => ({
        id: n.id,
        title: n.title,
        parentId: n.parentId,
        level: n.level,
      })),
      options,
    });

    const { result } = await scheduler.execute(
      "expand",
      () => prompt,
      (raw) => {
        const data = parseLLMJson<{ nodes?: unknown[] }>(raw);
        return Array.isArray(data?.nodes) ? data.nodes : [];
      },
    );

    const added: NodeDraft[] = [];
    for (const item of result as unknown[]) {
      const rec = item as Record<string, unknown>;
      if (!rec || typeof rec.id !== "string") continue;
      const parentLevel = allNodes.find((n) => n.id === rec.id)?.level ?? 0;
      const children = Array.isArray(rec.children) ? rec.children : [];
      for (const child of children as unknown[]) {
        const c = child as Record<string, unknown>;
        if (!c || typeof c.id !== "string") continue;
        const level = parentLevel + 1;
        if (level > MAX_DEPTH) continue;
        added.push({
          id: String(c.id),
          title: String(c.title ?? c.label ?? ""),
          parentId: String(rec.id),
          level,
          canonical_definition:
            typeof c.canonical_definition === "string" ? c.canonical_definition : undefined,
          semantic_axis: typeof c.semantic_axis === "string" ? c.semantic_axis : undefined,
          conceptType: typeof c.conceptType === "string" ? c.conceptType : undefined,
          forbidden_interpretations: Array.isArray(c.forbidden_interpretations)
            ? (c.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
            : undefined,
          ...parseNodeMetadata(c),
        });
      }
    }
    return added;
  }

  private async validate(
    nodes: NodeDraft[],
    focusIds?: string[],
  ): Promise<{
    valid: boolean;
    issues: Array<{ type: ValidationIssueType; node_id: string; reason: string }>;
  }> {
    const scheduler = getScheduler();
    const validationNodes: ValidationNode[] = nodes.map((n) => ({
      id: n.id,
      parentId: n.parentId,
      level: n.level,
      label: n.title,
      one_liner: "",
      semantic_axis: n.semantic_axis,
      canonical_definition: n.canonical_definition,
      conceptType: n.conceptType,
      forbidden_interpretations: n.forbidden_interpretations,
    }));

    const prompt = buildValidatePrompt(validationNodes, focusIds ? { focusIds } : undefined);
    const { result } = await scheduler.execute(
      "validate",
      () => prompt,
      (raw) => parseValidationResult(parseLLMJson(raw)),
    );

    return {
      valid: result.valid,
      issues: result.issues.map((i) => ({
        type: i.type as ValidationIssueType,
        node_id: i.node_id,
        reason: i.reason,
      })),
    };
  }

  private async repair(
    issues: Array<{ type: ValidationIssueType; node_id: string; reason: string }>,
    nodes: NodeDraft[],
    opts?: IStructurePromptOptions,
  ): Promise<{ repairedNodes: NodeDraft[]; warnings: string[] }> {
    const scheduler = getScheduler();
    const warnings: string[] = [];
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const issuesByNode = new Map<string, typeof issues>();

    for (const issue of issues) {
      if (!issue.node_id) continue;
      const arr = issuesByNode.get(issue.node_id) ?? [];
      arr.push(issue);
      issuesByNode.set(issue.node_id, arr);
    }

    const problemIds = [...issuesByNode.keys()];
    const problemNodes: ProblemNode[] = [];
    for (const id of problemIds) {
      const node = byId.get(id);
      if (!node) continue;
      problemNodes.push({
        id: node.id,
        parentId: node.parentId,
        level: node.level,
        label: node.title,
        one_liner: "",
        details: "",
        conceptType: node.conceptType,
        semantic_axis: node.semantic_axis,
        canonical_definition: node.canonical_definition,
        forbidden_interpretations: node.forbidden_interpretations,
      });
    }

    const prompt = buildRepairPrompt({
      problemNodes,
      issues: issues.map((i) => ({
        type: i.type,
        node_id: i.node_id,
        reason: i.reason,
      })),
      level: opts?.level,
    });

    try {
      const { result } = await scheduler.execute(
        "repair",
        () => prompt,
        (raw) => parseLLMJson<unknown[]>(raw),
      );

      const repaired: NodeDraft[] = (result as unknown[]).map((r) => {
        const rec = r as Record<string, unknown>;
        return {
          id: String(rec.id),
          title: String(rec.label ?? rec.title ?? ""),
          parentId: rec.parentId !== null && rec.parentId !== undefined ? String(rec.parentId) : null,
          level: typeof rec.level === "number" ? rec.level : 1,
          canonical_definition:
            typeof rec.canonical_definition === "string"
              ? enforceOneLinerLimit(rec.canonical_definition)
              : undefined,
          semantic_axis: typeof rec.semantic_axis === "string" ? rec.semantic_axis : undefined,
          conceptType: typeof rec.conceptType === "string" ? rec.conceptType : undefined,
          forbidden_interpretations: Array.isArray(rec.forbidden_interpretations)
            ? (rec.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
            : undefined,
        };
      });
      return { repairedNodes: repaired, warnings };
    } catch (err) {
      warnings.push(`Ремонт не завершён: ${err instanceof Error ? err.message : String(err)}`);
      return { repairedNodes: [], warnings };
    }
  }

  private async fillTopLevelContent(
    query: string,
    nodes: NodeDraft[],
  ): Promise<NodeDraft[]> {
    // For MVP, top-level nodes get one_liner content; deep content is lazy/just-in-time.
    // Content generation is handled by generateNodeContent on demand.
    return nodes;
  }

  async generateNodeContent(
    query: string,
    node: NodeDraft,
    context: {
      nodePath: string[];
      siblings: string[];
      canonical_definition?: string;
      semantic_axis?: string;
      forbidden_interpretations?: string[];
      knowledgeLevel?: string;
      goal?: string;
      nodeLevel?: number;
      isRoot?: boolean;
    },
  ): Promise<{ one_liner: string; details: string; analogy?: string; relations: unknown[]; sources?: string[] }> {
    const scheduler = getScheduler();
    const { buildContentPrompt, isCriticalDomain } = await import("../prompts/content.js");

    const prompt = buildContentPrompt({
      rootTopic: query,
      nodePath: context.nodePath,
      siblings: context.siblings,
      knowledgeLevel: context.knowledgeLevel,
      goal: context.goal,
      nodeLevel: context.nodeLevel,
      isRoot: context.isRoot,
      isCriticalDomain: isCriticalDomain(query, context.nodePath),
      ontologyContext: {
        canonical_definition: context.canonical_definition,
        semantic_axis: context.semantic_axis,
        forbidden_interpretations: context.forbidden_interpretations,
      },
      node: { id: node.id, label: node.title },
    });

    const { result } = await scheduler.execute(
      "content",
      () => prompt,
      (raw) =>
        parseLLMJson<{ one_liner?: string; details?: string; analogy?: string; relations?: unknown[]; sources?: string[] }>(
          raw,
        ),
    );

    return {
      one_liner: await this._withinOneLinerLimit(
        node.title,
        String(result.one_liner ?? node.title),
      ),
      details: String(result.details ?? ""),
      analogy: typeof result.analogy === "string" && result.analogy !== "" ? result.analogy : undefined,
      relations: Array.isArray(result.relations) ? result.relations : [],
      sources: Array.isArray(result.sources) ? result.sources.map(String) : [],
    };
  }

  /**
   * Гарантирует инвариант `one_liner <= 120` (AGENTS.md).
   *
   * Если черновик длиннее лимита — переспрашиваем модель (fast-тир,
   * операция `oneline-rewrite`): просим сократить без потери смысла.
   * Если переспрос не дал короткий вариант — детерминированная триммация
   * (fallback обязателен; «удача модели» не должна влиять на инвариант).
   * Зеркало: `_withinOneLinerLimit` в Flutter-движке.
   */
  private async _withinOneLinerLimit(label: string, draft: string): Promise<string> {
    const trimmed = draft.trim();
    if (trimmed === "" || trimmed.length <= ONELINER_MAX_CHARS) return draft;
    try {
      const scheduler = getScheduler();
      const { buildOnelineRewritePrompt } = await import("../prompts/oneline.js");
      const { result } = await scheduler.execute(
        "oneline-rewrite",
        () => buildOnelineRewritePrompt({ label, currentOneLiner: trimmed }),
        (raw) => parseLLMJson<{ one_liner?: string }>(raw),
      );
      const candidate = String(result?.one_liner ?? "").trim();
      if (candidate !== "" && candidate.length <= ONELINER_MAX_CHARS) {
        return candidate;
      }
    } catch {
      // Сбой переспроса не роняет сценарий — ниже детерминированный fallback.
    }
    return this._truncateOneLiner(trimmed);
  }

  /** Детерминированная обрезка до лимита по границе слова (результат <= 120). */
  private _truncateOneLiner(s: string): string {
    return truncateOneLiner(s);
  }

  /**
   * Углубление ветки для узла, хранящегося в БД: читает узел и соседей,
   * генерирует детей и персистит их в knowledge_nodes.
   */
  async expandNodeFromDb(topicId: string, nodeId: string): Promise<NodeDraft[]> {
    const { getDb } = await import("../db/connection.js");
    const db = getDb();

    const nodeRow = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    const nodeLevel = Number(nodeRow.level);
    if (nodeLevel >= MAX_DEPTH) {
      throw new Error(`Достигнута максимальная глубина (${MAX_DEPTH})`);
    }

    const topicRow = db.prepare(`SELECT name, goal, target_level FROM topics WHERE id = ?`).get(topicId) as
      | { name: string; goal?: string | null; target_level?: string | null }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";
    const expandOptions: IStructurePromptOptions = {
      goal: typeof topicRow?.goal === "string" ? topicRow.goal : undefined,
      level: typeof topicRow?.target_level === "string" ? topicRow.target_level : undefined,
    };

    const allRows = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<Record<string, unknown>>;

    const allNodes: NodeDraft[] = allRows
      .map((r) => ({
        id: String(r.id),
        title: String(r.label),
        parentId: r.parent_id ? String(r.parent_id) : null,
        level: Number(r.level),
        conceptType: r.concept_type ? String(r.concept_type) : undefined,
      }))
      .filter((n) => n.id !== "");

    const target = allNodes.find((n) => n.id === nodeId);
    if (!target) throw new Error("Узел не найден");

    // У узла уже есть дети (в т.ч. скрытые) — не запускаем повторную генерацию.
    // «Углубить» в этом случае раскрывает существующих детей, а не зовёт LLM.
    const hasChildren = allNodes.some((n) => n.parentId === nodeId);
    if (hasChildren) {
      return [];
    }

    const added = await this.expandNodes(
      rootTopic,
      allNodes,
      [target],
      undefined,
      expandOptions,
    );

    // Согласование с полным деревом (§63): отбрасываем дубли уже существующих
    // понятий и коллизии id, чтобы не вносить противоречия.
    const consistent = consistencyCheckAgainstTree(allNodes, added);

    // Уникализация id: LLM может вернуть те же id что и в другой теме.
    // Суффикс topicId делает id глобально уникальными.
    const scoped = scopeNodeIds(consistent.nodes, topicId);

    const insert = db.prepare(
      `INSERT OR IGNORE INTO knowledge_nodes
         (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
          estimated_time_minutes, relations_json, state, content_loaded, leaf, level, created_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    );

    const relationByTo = new Map<string, Relation[]>();
    for (const c of scoped) {
      if (c.relations && c.relations.length > 0) {
        relationByTo.set(c.id, c.relations);
      }
    }

    // Инвариант one_liner <= 120: переспрашиваем ДО транзакции (внутри sync
    // транзакции LLM-вызов невозможен).
    const oneLinerEntries = await Promise.all(
      scoped.map(async (c) => [
        c.id,
        await this._withinOneLinerLimit(c.title, c.canonical_definition ?? ""),
      ] as const),
    );
    const oneLinerByChildId = new Map<string, string>(oneLinerEntries);

    const tx = db.transaction((items: NodeDraft[]) => {
      for (const c of items) {
        const childLevel = nodeLevel + 1;
        const leaf = childLevel >= MAX_DEPTH ? 1 : 0;
        const relations = relationByTo.get(c.id) ?? [];
        insert.run(
          c.id,
          topicId,
          nodeId,
          c.title.trim(),
          // canonical_definition используется как черновик one_liner: инвариант
          // 120 символов обеспечиваем здесь, а не на уровне SQL.
          oneLinerByChildId.get(c.id) ?? "",
          c.conceptType ? String(c.conceptType) : null,
          c.importance ?? 0.5,
          c.difficulty ?? 0.5,
          c.estimatedMinutes ?? 5,
          JSON.stringify(relations),
          "structure_generated",
          0,
          leaf,
          childLevel,
          new Date().toISOString(),
        );
      }
      // update parent state; если детей не появилось — узел оказался естественным
      // листом (терминальным), помечаем его как leaf=1
      const gotChildren = items.length > 0;
      db.prepare("UPDATE knowledge_nodes SET state = 'expanded', leaf = ? WHERE id = ?").run(
        gotChildren ? 0 : 1,
        nodeId,
      );
    });

    tx(scoped);
    return scoped;
  }

  /**
   * Ленивая генерация контента для узла в БД: генерирует one_liner/details/analogy
   * и персистит их, помечая content_loaded.
   */
  async generateNodeContentFromDb(topicId: string, nodeId: string): Promise<{
    one_liner: string;
    details: string;
    analogy?: string;
    relations: unknown[];
    sources?: string[];
  }> {
    const { getDb } = await import("../db/connection.js");
    const db = getDb();

    const nodeRow = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
      .get(nodeId, topicId) as Record<string, unknown> | undefined;
    if (!nodeRow) throw new Error("Узел не найден");

    const topicRow = db.prepare(`SELECT name, goal, target_level FROM topics WHERE id = ?`).get(topicId) as
      | { name: string; goal?: string | null; target_level?: string | null }
      | undefined;
    const rootTopic = topicRow?.name ?? "Тема";
    const { masteryLevelToKnowledgeLevel } = await import("../prompts/structure.js");
    const knowledgeLevel =
      typeof topicRow?.target_level === "string"
        ? masteryLevelToKnowledgeLevel(topicRow.target_level)
        : undefined;

    const allRows = db
      .prepare(`SELECT * FROM knowledge_nodes WHERE topic_id = ?`)
      .all(topicId) as Array<Record<string, unknown>>;

    const path = this.nodePathFromRows(allRows, nodeId);
    const parentId = nodeRow.parent_id ? String(nodeRow.parent_id) : null;
    const siblings = parentId
      ? allRows
          .filter((r) => String(r.parent_id ?? "") === parentId && String(r.id) !== nodeId)
          .map((r) => String(r.label))
          .slice(0, 8)
      : [];

    const content = await this.generateNodeContent(rootTopic, {
      id: nodeId,
      title: String(nodeRow.label),
      parentId,
      level: Number(nodeRow.level),
    }, {
      nodePath: path,
      siblings,
      canonical_definition:
        typeof nodeRow.one_liner === "string" && nodeRow.one_liner !== ""
          ? String(nodeRow.one_liner)
          : undefined,
      semantic_axis: nodeRow.concept_type ? String(nodeRow.concept_type) : undefined,
      knowledgeLevel,
      goal: topicRow?.goal ?? undefined,
      nodeLevel: Number(nodeRow.level),
      isRoot: Number(nodeRow.level) <= 1 && !nodeRow.parent_id,
    });

    db.prepare(
      `UPDATE knowledge_nodes SET one_liner = ?, details = ?, analogy = ?, relations_json = ?, sources_json = ?,
         state = 'content_generated', content_loaded = 1
       WHERE id = ?`,
    ).run(
      content.one_liner,
      content.details,
      content.analogy ?? null,
      JSON.stringify(
        mergeContentRelations({
          existing: parseNodeRelations(nodeRow.relations_json),
          fromContent: content.relations,
          nodeId,
          knownIds: new Set(allRows.map((r) => String(r.id))),
        }),
      ),
      JSON.stringify(content.sources ?? []),
      nodeId,
    );

    return content;
  }

  private nodePathFromRows(rows: Array<Record<string, unknown>>, nodeId: string): string[] {
    const byId = new Map(rows.map((r) => [String(r.id), r]));
    const path: string[] = [];
    let current = byId.get(nodeId);
    let guard = 0;
    while (current && guard < 50) {
      path.unshift(String(current.label));
      current = current.parent_id ? byId.get(String(current.parent_id)) : undefined;
      guard++;
    }
    return path;
  }
}

/** Детерминированный кламп черновика one_liner до лимита (инвариант AGENTS.md).
 *
 * Зеркало: `enforceOneLinerLimit` в Flutter-движке. Применяется на путях записи
 * дерева, где LLM-переспрос нецелесообразен (repair, драфты L1/L2/L3);
 * для контента по-прежнему работает `_withinOneLinerLimit` (переспрос + кламп).
 */
export function enforceOneLinerLimit(draft: string | undefined, maxChars: number = ONELINER_MAX_CHARS): string {
  const trimmed = (draft ?? "").trim();
  if (trimmed === "" || trimmed.length <= maxChars) return trimmed;
  return truncateOneLiner(trimmed, maxChars);
}

/** Служебные слова, после которых обрыв читается как незаконченная мысль.
 *
 * Зеркало: `_danglingTailWords` в Flutter-движке. Резать строку по границе слова
 * мало: «процессов как» — слово целое, но фраза оборвана на предлоге. На живом
 * прогоне это давало именно такие хвосты в `one_liner`.
 */
const DANGLING_TAIL_WORDS = new Set<string>([
  // предлоги
  "в", "во", "на", "по", "за", "из", "от", "до", "об", "о", "обо", "у", "к",
  "ко", "с", "со", "для", "при", "через", "между", "над", "под",
  "перед", "после", "вокруг", "вдоль", "без", "близ", "вблизи", "наравне",
  "против", "вопреки", "согласно", "вследствие", "ввиду", "вслед",
  // союзы
  "и", "или", "но", "а", "же", "бы", "то", "ли", "что", "чтобы", "как",
  "так", "тоже", "также", "зато", "причем", "причём", "потому", "поэтому",
  "хотя", "если", "когда", "пока", "чем", "раз", "не", "ни", "да",
  "однако",
  // вводные обороты-кандидаты на обрыв
  "например", "включая", "таким", "следовательно", "иными", "особенно",
  "главным", "основным", "прежде", "затем", "далее", "точнее", "условно",
  "формально", "фактически", "концептуально", "структурно", "математически",
  // относительные и связки
  "который", "которая", "которое", "которые", "которых", "которым",
  "тем", "где", "куда", "откуда", "путем", "путём",
]);

/** Убирает хвостовую пунктуацию и висящие служебные слова, пока фраза
 * остаётся осмысленной.
 */
function stripDanglingTail(cut: string): string {
  let out = cut;
  let changed = true;
  while (changed) {
    changed = false;
    const trimmedPunct = out.replace(/[\s,;:.!?’"`»)\]—–-]+$/u, "");
    if (trimmedPunct !== out) {
      out = trimmedPunct;
      changed = true;
      continue;
    }
    const lastSpace = out.lastIndexOf(" ");
    if (lastSpace <= 0) break;
    const lastWord = out.slice(lastSpace + 1).toLowerCase();
    if (DANGLING_TAIL_WORDS.has(lastWord)) {
      out = out.slice(0, lastSpace);
      changed = true;
    }
  }
  return out.trimEnd();
}

/** Индекс последнего вхождения любой из подстрок, либо -1. */
function lastIndexOfAny(haystack: string, needles: string[]): number {
  let best = -1;
  for (const n of needles) {
    const at = haystack.lastIndexOf(n);
    if (at > best) best = at;
  }
  return best;
}

/** Детерминированная обрезка `one_liner` до лимита так, чтобы видимый текст
 * оставался связным куском, а не хвостом фразы.
 *
 * Зеркало: `truncateOneLiner` в Flutter-движке. Порядок попыток: граница
 * предложения -> граница клаузы -> граница слова -> жёсткий срез.
 */
export function truncateOneLiner(s: string, maxChars: number = ONELINER_MAX_CHARS): string {
  if (s.length <= maxChars) return s;
  const cut = s.slice(0, maxChars);

  // 1. Предпочитаем целое предложение. Знак конца предложения входит в
  // результат: обрезанное по точке предложение должно выглядеть как
  // законченная мысль, а не как фрагмент без точки.
  const sentenceEnd = lastIndexOfAny(cut, [". ", "! ", "? ", ".", "!", "?"]);
  if (sentenceEnd > maxChars * 0.6) {
    const mark = [".", "!", "?"].find((m) => cut[sentenceEnd] === m) ?? "";
    return finalizeTruncation(cut.slice(0, sentenceEnd), maxChars, mark);
  }
  // 2. Иначе — клауза: запятая и подобное.
  const clauseEnd = lastIndexOfAny(cut, [", ", "; ", ": ", " — ", " – ", ","]);
  if (clauseEnd > maxChars * 0.6) {
    return finalizeTruncation(cut.slice(0, clauseEnd), maxChars);
  }
  // 3. Иначе — слово.
  const lastSpace = cut.lastIndexOf(" ");
  if (lastSpace > maxChars * 0.6) {
    return finalizeTruncation(cut.slice(0, lastSpace), maxChars);
  }
  // 4. Внутри лимита нет ни одной границы — жёсткий срез. Пунктуацию здесь
  // не снимаем: это единственный шанс не вернуть пустую строку.
  return finalizeTruncation(cut, maxChars, "", false);
}

/** Финальная чистка куска после выбора границы.
 *
 * Гарантирует непустой результат: если чистка съела всё (строка состояла
 * только из пунктуации), возвращается необработанный кусок — пустой
 * `one_liner` в дереве хуже, чем неидеально обрезанный текст.
 */
function finalizeTruncation(
  body: string,
  maxChars: number,
  terminalMark = "",
  stripPunctuation = true,
): string {
  let out = stripPunctuation ? stripDanglingTail(body.trimEnd()) : body.trimEnd();
  if (out === "") out = body.trimEnd();
  if (out === "") return out;
  if (terminalMark !== "" && out.length + terminalMark.length <= maxChars) {
    out = out + terminalMark;
  }
  return out;
}

function normalizeDrafts(raw: unknown[]): NodeDraft[] {
  const drafts: NodeDraft[] = raw.map((r) => {
    const rec = r as Record<string, unknown>;
    return {
      id: String(rec.id ?? ""),
      title: String(rec.title ?? rec.label ?? ""),
      parentId: rec.parentId !== null && rec.parentId !== undefined ? String(rec.parentId) : null,
      level: typeof rec.level === "number" ? rec.level : guessLevel(rec),
      // Инвариант one_liner <= 120: черновики структуры/repair клампим
      // детерминированно (LLM может вернуть сколь угодно длинный текст).
      canonical_definition:
        typeof rec.canonical_definition === "string"
          ? enforceOneLinerLimit(rec.canonical_definition)
          : undefined,
      semantic_axis: typeof rec.semantic_axis === "string" ? rec.semantic_axis : undefined,
      conceptType: typeof rec.conceptType === "string" ? rec.conceptType : undefined,
      forbidden_interpretations: Array.isArray(rec.forbidden_interpretations)
        ? (rec.forbidden_interpretations as unknown[]).filter((f): f is string => typeof f === "string")
        : undefined,
      ...parseNodeMetadata(rec),
    };
  });

  // fix levels via DFS from root
  const roots = drafts.filter((d) => !d.parentId);
  const result: NodeDraft[] = [];
  const visited = new Set<string>();

  const visit = (d: NodeDraft, level: number) => {
    if (visited.has(d.id)) return;
    visited.add(d.id);
    const fixed = { ...d, level: d.level || level };
    result.push(fixed);
    const children = drafts
      .filter((c) => c.parentId === d.id)
      .sort((a, b) => a.title.localeCompare(b.title));
    for (const child of children) visit(child, level + 1);
  };

  for (const root of roots) visit(root, 1);

  // Сироты: узлы, чей parentId указывает на узел не из этой партии
  // (например, L2-узлы в ответе, где корень генерировался отдельным запросом).
  for (const d of drafts) {
    if (!visited.has(d.id)) {
      result.push({ ...d, level: d.level || guessLevel(d as unknown as Record<string, unknown>) });
    }
  }

  return result;
}

function guessLevel(rec: Record<string, unknown>): number {
  if (rec.parentId === null || rec.parentId === undefined) return 1;
  return 2;
}

/**
 * Извлекает метаданные узла (importance/difficulty/estimated_time/prerequisites/relations)
 * из ответа LLM. Возвращает undefined-поля, если значения отсутствуют или невалидны.
 * relations — массив объектов { to, type, label? }, при невалидной записи пропускается.
 */
export function parseNodeMetadata(rec: Record<string, unknown>): Partial<NodeDraft> {
  const importance = typeof rec.importance === "number" ? clamp01(rec.importance) : undefined;
  const difficulty = typeof rec.difficulty === "number" ? clamp01(rec.difficulty) : undefined;
  const estimatedMinutes =
    typeof rec.estimated_time_minutes === "number" && rec.estimated_time_minutes > 0
      ? Math.round(rec.estimated_time_minutes)
      : typeof rec.estimated_time_minutes === "string" &&
        Number(rec.estimated_time_minutes) > 0
        ? Math.round(Number(rec.estimated_time_minutes))
        : undefined;

  const prerequisites = Array.isArray(rec.prerequisites)
    ? (rec.prerequisites as unknown[]).filter((p): p is string => typeof p === "string")
    : undefined;

  const relations = Array.isArray(rec.relations)
    ? (rec.relations as unknown[]).flatMap((rel) => {
        const r = rel as Record<string, unknown>;
        if (!r || typeof r.to !== "string" || !r.to) return [];
        const type = String(r.type ?? "related");
        return [
          {
            from: String(rec.id ?? ""),
            to: r.to,
            type: (VALID_RELATION_TYPES.has(type) ? type : "related") as RelationType,
            label: typeof r.label === "string" && r.label !== "" ? r.label : undefined,
          } satisfies Relation,
        ];
      })
    : undefined;

  return {
    ...(importance !== undefined ? { importance } : {}),
    ...(difficulty !== undefined ? { difficulty } : {}),
    ...(estimatedMinutes !== undefined ? { estimatedMinutes } : {}),
    ...(prerequisites !== undefined && prerequisites.length > 0 ? { prerequisites } : {}),
    ...(relations !== undefined && relations.length > 0 ? { relations } : {}),
  };
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}

const VALID_RELATION_TYPES = new Set<string>([
  "related",
  "depends_on",
  "requires",
  "example_of",
  "similar_to",
  "contrasts_with",
  "causes",
  "enables",
  "used_for",
  "alternative_to",
]);

/** Разбирает `relations_json` узла; битое значение — пустой список. */
function parseNodeRelations(raw: unknown): Relation[] {
  if (typeof raw !== "string" || raw === "") return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (r): r is Relation =>
        !!r && typeof r === "object" && typeof (r as { to?: unknown }).to === "string",
    );
  } catch {
    return [];
  }
}

/**
 * Связи принадлежат структурной стадии: там модель видит настоящие id.
 *
 * Контентная стадия таких id не знает, поэтому её связи не должны ни затирать
 * структурные, ни попадать в дерево выдуманными целями (`AGENTS.md`: связи
 * ссылаются на существующие узлы). Берём структурные как есть и добавляем только
 * разрешимые контентные. Зеркало `_mergeContentRelations` в knowledge_graph_engine.dart.
 */
export function mergeContentRelations({
  existing,
  fromContent,
  nodeId,
  knownIds,
}: {
  existing: Relation[];
  fromContent: unknown;
  nodeId: string;
  knownIds: Set<string>;
}): Relation[] {
  const out: Relation[] = [...existing];
  const seen = new Set(existing.map((r) => `${r.from}|${r.to}|${r.type}`));
  const list = Array.isArray(fromContent) ? fromContent : [];
  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const rec = item as { to?: unknown; type?: unknown; label?: unknown };
    if (typeof rec.to !== "string" || rec.to === "") continue;
    // `from` принудительно ведёт с узла: иначе связь повисает в воздухе.
    if (!knownIds.has(nodeId) || !knownIds.has(rec.to)) continue;
    const type = typeof rec.type === "string" ? rec.type : "related";
    const key = `${nodeId}|${rec.to}|${type}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      from: nodeId,
      to: rec.to,
      type: type as RelationType,
      label: typeof rec.label === "string" ? rec.label : undefined,
    } as Relation);
  }
  return out;
}


function maxLevelOf(nodes: NodeDraft[]): number {
  return nodes.reduce((max, n) => Math.max(max, n.level), 0);
}

function buildPath(nodes: NodeDraft[], nodeId: string): string[] {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const path: string[] = [];
  let current = byId.get(nodeId);
  let guard = 0;
  while (current && guard < 50) {
    path.unshift(current.title);
    current = current.parentId ? byId.get(current.parentId) : undefined;
    guard++;
  }
  return path;
}

/**
 * Согласует новые узлы (дети при расширении) с уже существующим деревом:
 * - отбрасывает узлы, чьё понятие уже присутствует в дереве (по нормализованному title);
 * - отбрасывает коллизии id с существующими узлами;
 * - отбрасывает детей, дублирующих title среди своих же сиблингов.
 * Возвращает согласованный список и число отброшенных узлов.
 */
export function consistencyCheckAgainstTree(
  existing: NodeDraft[],
  incoming: NodeDraft[],
): { nodes: NodeDraft[]; skipped: number } {
  const existingTitles = new Set<string>();
  for (const n of existing) {
    const t = normalizeTitle(n.title);
    if (t) existingTitles.add(t);
  }
  const existingIds = new Set(existing.map((n) => n.id));

  const seenTitles = new Map<string, string>(); // нормализованный title -> id в этой партии
  const seenIds = new Set<string>();
  const nodes: NodeDraft[] = [];

  for (const n of incoming) {
    const t = normalizeTitle(n.title);
    if (!t) continue;
    if (existingTitles.has(t)) continue; // дубль с существующим понятием
    if (n.id && existingIds.has(n.id)) continue; // коллизия id
    if (seenTitles.has(t)) continue; // дубль title среди сиблингов
    const id = n.id || `c_${nodes.length + 1}`;
    if (seenIds.has(id)) continue; // коллизия id внутри партии
    seenIds.add(id);
    seenTitles.set(t, id);
    nodes.push({ ...n, id });
  }

  return { nodes, skipped: incoming.length - nodes.length };
}

function normalizeTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, " ");
}

// ─── Детерминированный пре-пасс валидации ─────────────────────────────────────
// Зеркалит mindtree_flutter/lib/domain/engines/knowledge_graph_engine.dart
// (deterministicValidate): три типа промпта `validate` модель проверить
// физически не может (в ValidationNode нет relations/prerequisites/
// estimatedMinutes) — их считает код, а exact-дубликаты подписей надёжнее
// ловить детерминированно, чем «на глаз» сильной моделью.

/** Типы `relations`, образующие граф зависимостей (CIRCULAR_DEPENDENCY). */
const DEPENDENCY_RELATION_TYPES = new Set(["requires", "depends_on", "enables"]);

/** Порог `UNREALISTIC_TIMING`: минуты ОДНОГО узла. */
const MAX_MINUTES_PER_NODE = 120;

export interface DeterministicValidationResult {
  /** Только `DUPLICATE`: инвалидирует дерево и чинится repair'ом. */
  hardIssues: Array<{ type: ValidationIssueType; node_id: string; reason: string }>;
  /** Информационные находки: дерево не инвалидируют. */
  notes: string[];
}

export function deterministicValidate(nodes: NodeDraft[]): DeterministicValidationResult {
  const hardIssues: DeterministicValidationResult["hardIssues"] = [];
  const notes: string[] = [];
  if (nodes.length === 0) return { hardIssues, notes };

  const ids = new Set(nodes.map((n) => n.id));

  // 1. exact-DUPLICATE (инвалидирует): совпадает нормализованная
  //    подпись. Порядок — по узлам; проблемой помечается второй узел пары.
  const firstIdByTitle = new Map<string, string>();
  for (const n of nodes) {
    const title = normalizeTitle(n.title);
    // У пустой подписи не с чем сравнивать: выдумывать проблему нельзя.
    if (!title) continue;
    const firstId = firstIdByTitle.get(title);
    if (firstId === undefined) {
      firstIdByTitle.set(title, n.id);
      continue;
    }
    hardIssues.push({
      type: "DUPLICATE",
      node_id: n.id,
      reason: `Дубликат узла «${n.title.trim()}» (совпадает с ${firstId})`,
    });
  }

  // 2. MISSING_PREREQUISITE (note): ссылки в relations.to и в
  //    prerequisites на узлы, которых в дереве нет. Повторы пары «узел→цель»
  //    схлопываются, порядок — по узлам и по relations.
  const missingSeen = new Set<string>();
  for (const n of nodes) {
    const refs = [
      ...(n.relations ?? []).map((r) => r.to),
      ...(n.prerequisites ?? []),
    ];
    for (const to of refs) {
      if (!to || ids.has(to)) continue;
      const key = `${n.id}|${to}`;
      if (missingSeen.has(key)) continue;
      missingSeen.add(key);
      notes.push(`MISSING_PREREQUISITE узел ${n.id}: ссылка на отсутствующий узел ${to}`);
    }
  }

  // 3. CIRCULAR_DEPENDENCY (note): циклы в графе зависимостей. К моменту
  //    доезжают до пре-пасса уже разорванными — см. breakDependencyCycles.
  notes.push(...circularDependencyNotes(nodes, ids));

  // 4. UNREALISTIC_TIMING (note): оценка времени самого узла.
  for (const n of nodes) {
    const minutes = n.estimatedMinutes;
    if (minutes === undefined || minutes <= MAX_MINUTES_PER_NODE) continue;
    notes.push(
      `UNREALISTIC_TIMING узел ${n.id}: оценка ${minutes} мин выходит за разумный предел ${MAX_MINUTES_PER_NODE} мин на узел`,
    );
  }

  return { hardIssues, notes };
}

/**
 * Циклы в графе зависимостей (`requires`/`depends_on`/`enables`).
 * DFS с тремя цветами (0 — не посещён, 1 — в стеке, 2 — обработан). Корни
 * обхода идут в порядке входного списка, цели рёбер — в порядке `relations`,
 * поэтому порядок находок стабилен между прогонами. Рёбра на несуществующие
 * узлы пропускаются: их уже поймал `MISSING_PREREQUISITE`.
 */
function circularDependencyNotes(nodes: NodeDraft[], ids: Set<string>): string[] {
  const edges = new Map<string, string[]>();
  for (const n of nodes) {
    for (const r of n.relations ?? []) {
      if (!DEPENDENCY_RELATION_TYPES.has(r.type)) continue;
      if (!ids.has(r.from) || !ids.has(r.to)) continue;
      const targets = edges.get(r.from) ?? [];
      if (!targets.includes(r.to)) targets.push(r.to);
      edges.set(r.from, targets);
    }
  }
  if (edges.size === 0) return [];

  const notes: string[] = [];
  const reportedCycles = new Set<string>();
  const color = new Map<string, number>();
  for (const id of ids) color.set(id, 0);
  const stack: string[] = [];

  const dfs = (id: string): void => {
    color.set(id, 1);
    stack.push(id);
    for (const to of edges.get(id) ?? []) {
      const state = color.get(to) ?? 0;
      if (state === 0) {
        dfs(to);
      } else if (state === 1) {
        // `to` ещё в стеке — ребро замыкает цикл `to … id → to`.
        const cycle = [...stack.slice(stack.indexOf(to)), to];
        const key = cycle.join(">");
        if (!reportedCycles.has(key)) {
          reportedCycles.add(key);
          notes.push(`CIRCULAR_DEPENDENCY: цикл зависимостей ${cycle.join(" → ")}`);
        }
      }
    }
    stack.pop();
    color.set(id, 2);
  };

  for (const n of nodes) {
    if ((color.get(n.id) ?? 0) === 0) dfs(n.id);
  }
  return notes;
}

/**
 * Разрывает циклы в графе зависимостей детерминированно.
 *
 * Обход — тот же DFS с тремя цветами и по тем же правилам, что и
 * circularDependencyNotes: корни в порядке входного списка, цели рёбер в
 * порядке relations, рёбра на несуществующие узлы пропускаются (их ловит
 * MISSING_PREREQUISITE). Удаляется только «обратное» ребро — то, чья цель ещё
 * лежит в стеке обхода, — потому что именно оно замыкает цикл, а остальные
 * рёбра цикла несут смысл и остаются. Набор обратных рёбер DFS-леса даёт
 * ациклический граф, поэтому одного прохода достаточно.
 *
 * Почему без вызова модели. Цикл в requires/depends_on делает порядок изучения
 * противоречивым («A требует B» и «B требует A»), но чинить его repair-ом
 * бессмысленно: узлы-участники как правило вовсе не дефектны, ложна связь между
 * ними. Удаление одного ребра — точное минимальное исправление, детерминированное
 * и бесплатное.
 *
 * Раньше циклы попадали только в notes пре-пасса и доходили до пользователя
 * вместе с готовым деревом (замерено на живом прогоне: циклы n2_1 → n2_2 → n2_1
 * и n2_2 → n2_3 → n2_2, repair при этом не запускался вовсе).
 *
 * Зеркало lib/domain/engines/knowledge_graph_engine.dart (breakDependencyCycles).
 */
export function breakDependencyCycles(
  nodes: NodeDraft[],
): { nodes: NodeDraft[]; notes: string[] } {
  const ids = new Set(nodes.map((n) => n.id));
  if (nodes.length === 0 || ids.size === 0) return { nodes, notes: [] };

  const edges = new Map<string, string[]>();
  for (const n of nodes) {
    for (const r of n.relations ?? []) {
      if (!DEPENDENCY_RELATION_TYPES.has(r.type)) continue;
      if (!ids.has(r.from) || !ids.has(r.to)) continue;
      const targets = edges.get(r.from) ?? [];
      if (!targets.includes(r.to)) targets.push(r.to);
      edges.set(r.from, targets);
    }
  }
  if (edges.size === 0) return { nodes, notes: [] };

  // Узел-источник -> цели рёбер, которые удаляем.
  const dropped = new Map<string, Set<string>>();
  const notes: string[] = [];
  const reported = new Set<string>();
  const color = new Map<string, number>();
  for (const id of ids) color.set(id, 0);
  const stack: string[] = [];

  const dfs = (id: string): void => {
    color.set(id, 1);
    stack.push(id);
    for (const to of edges.get(id) ?? []) {
      const state = color.get(to) ?? 0;
      if (state === 0) {
        dfs(to);
      } else if (state === 1) {
        // `to` ещё в стеке — ребро `id → to` замыкает цикл и удаляется.
        // Сюда же попадают петли `id → id`.
        const dead = dropped.get(id) ?? new Set<string>();
        dead.add(to);
        dropped.set(id, dead);
        const cycle = [...stack.slice(stack.indexOf(to)), to];
        const key = cycle.join(">");
        if (!reported.has(key)) {
          reported.add(key);
          notes.push(
            `CIRCULAR_DEPENDENCY разорван: ${cycle.join(" → ")} `
            + `(удалена связь ${id} → ${to})`,
          );
        }
      }
    }
    stack.pop();
    color.set(id, 2);
  };

  for (const n of nodes) {
    if ((color.get(n.id) ?? 0) === 0) dfs(n.id);
  }
  if (dropped.size === 0) return { nodes, notes: [] };

  const out = nodes.map((n) => {
    const dead = dropped.get(n.id);
    if (!dead || !n.relations) return n;
    return {
      ...n,
      relations: n.relations.filter(
        (r) => !(DEPENDENCY_RELATION_TYPES.has(r.type) && dead.has(r.to)),
      ),
    };
  });
  return { nodes: out, notes };
}

/**
 * Применяет результаты repair-шага к дереву.
 * Проблемный узел заменяется исправленной версией ТОЛЬКО если repair вернул
 * узел с тем же id; в противном случае исходный узел сохраняется, чтобы
 * repair, опустивший часть узлов (в т.ч. корень), не удалял их из дерева
 * (иначе дети становились сиротами без родителя).
 * Новые узлы, которых не было в исходном дереве, добавляются.
 */
export function mergeRepairs(nodes: NodeDraft[], repaired: NodeDraft[]): NodeDraft[] {
  const byId = new Map(repaired.map((r) => [r.id, r]));
  const out: NodeDraft[] = nodes.map((n) => {
    const rep = byId.get(n.id);
    return rep ? { ...rep } : n;
  });
  const existingIds = new Set(out.map((o) => o.id));
  for (const r of repaired) {
    if (!existingIds.has(r.id)) out.push(r);
  }
  return out;
}

/**
 * Детерминированное демо-дерево для офлайн-режима (LLM_MOCK=1).
 * Возвращает скелет уровня 1–2 с гарантированно уникальными id,
 * чтобы persistNodes не падал на UNIQUE constraint.
 */
export function fallbackStructure(query: string): NodeDraft[] {
  const topic = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";
  return [
    {
      id: "n1",
      title: topic,
      parentId: null,
      level: 1,
      canonical_definition: `Общий обзор темы «${topic}» и её ключевых разделов.`,
      semantic_axis: "theory",
      conceptType: "topic",
    },
    {
      id: "n2_1",
      title: "Основы",
      parentId: "n1",
      level: 2,
      canonical_definition: "Базовые понятия и определения, с которых начинается изучение темы.",
      semantic_axis: "theory",
      conceptType: "concept",
    },
    {
      id: "n2_2",
      title: "Ключевые направления",
      parentId: "n1",
      level: 2,
      canonical_definition: "Главные подтемы и принципы, составляющие ядро предмета.",
      semantic_axis: "architecture",
      conceptType: "concept",
    },
    {
      id: "n2_3",
      title: "Применение",
      parentId: "n1",
      level: 2,
      canonical_definition: "Практические области использования знаний по теме.",
      semantic_axis: "application",
      conceptType: "example",
    },
  ];
}

/**
 * Схлопывает точные дубли узлов и переименовывает оставшиеся коллизии id,
 * обновляя ссылки parentId, чтобы дерево было внутренне согласованным и
 * персистентность не падала на UNIQUE constraint.
 */
export function dedupeNodeIds(nodes: NodeDraft[]): NodeDraft[] {
  const seen = new Set<string>();
  const out: NodeDraft[] = [];
  // исходный id -> новый уникальный id (для всех, включая неизменённые)
  const idMap = new Map<string, string>();
  // ключ сиблингов -> id выжившего узла с такой же подписью
  const survivorByLabel = new Map<string, string>();

  for (const n of nodes) {
    if (!n.id) continue;

    // Дубль подписи среди сиблингов: узел поглощается выжившим. Ключ сравнения
    // — тот же normalizeTitle, что и у детектора в deterministicValidate: иначе
    // флаг DUPLICATE поднимался на «Регуляризация» против «  регуляризация  »,
    // а схлопнуть их было нечем, и находка оставалась неустранимой без repair.
    // Слияние допускается только среди сиблингов (один parentId и один level):
    // узлы из разных ветвей объединять нельзя — сломалась бы структура.
    const label = normalizeTitle(n.title);
    const labelKey = `${n.parentId ?? ""}|${n.level}|${label}`;
    if (label) {
      const survivorId = survivorByLabel.get(labelKey);
      if (survivorId !== undefined && survivorId !== n.id) {
        idMap.set(n.id, survivorId);
        continue;
      }
    }

    // Точный дубль (тот же id и тот же контент) — пропускаем.
    const existing = out.find((o) => o.id === n.id);
    const isExactDup = existing !== undefined
      && existing.title === n.title
      && existing.level === n.level
      && existing.parentId === n.parentId;
    if (isExactDup) {
      idMap.set(n.id, n.id);
      continue;
    }

    let newId = n.id;
    if (seen.has(n.id)) {
      const base = n.id.replace(/-\d+$/, "");
      let i = 1;
      do {
        newId = `${base}-${i}`;
        i++;
      } while (seen.has(newId));
    }
    seen.add(newId);
    // parentId-ссылки должны указывать на первый (канонический) узел с данным id,
    // поэтому маппинг исходного id сохраняем только при первом вхождении.
    if (!idMap.has(n.id)) {
      idMap.set(n.id, newId);
    }
    if (label) {
      survivorByLabel.set(labelKey, newId);
    }
    out.push({ ...n, id: newId });
  }

  // Поглощённый узел не исчезает бесследно: его id попал в idMap, поэтому все
  // ссылки на него — parentId детей, relations и prerequisites — переписываются
  // на выживший узел. Иначе дети стали бы сиротами, а связи повисли бы в
  // воздухе. Ссылка на саму себя после слияния бессмысленна — выкидываем.
  const mapRef = (id: string): string => idMap.get(id) ?? id;

  return out.map((n) => {
    if (n.parentId && n.parentId !== n.id) {
      n.parentId = mapRef(n.parentId);
    }
    if (n.relations) {
      n.relations = n.relations
        .map((r) => ({ ...r, to: mapRef(r.to) }))
        .filter((r) => r.to !== n.id);
    }
    if (n.prerequisites) {
      n.prerequisites = n.prerequisites.map(mapRef).filter((p) => p !== n.id);
    }
    return n;
  });
}

