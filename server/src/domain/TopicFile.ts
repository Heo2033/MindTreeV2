import type {
  ConceptType,
  KnowledgeNode,
  LearningGoal,
  MasteryLevel,
  NodeState,
  Relation,
  Sequence,
  SequenceStep,
} from "@mindtree/types";
import { truncateOneLiner } from "./KnowledgeGraphEngine.js";
import { scopedSuffix } from "./scopedIds.js";

/**
 * Формат файла темы (экспорт/импорт графа знаний).
 *
 * Зеркало `mindtree_flutter/lib/data/io/topic_file.dart` — 1:1, включая тексты
 * сообщений (они показываются пользователю, паритет важен).
 *
 * Конверт:
 * ```json
 * {
 *   "format": "mindtree.topic",
 *   "version": 1,
 *   "exportedAt": "2026-09-27T12:00:00.000Z",
 *   "source": { "topicId": "<id темы-источника>" },
 *   "topic": { "name": "...", "goal": "...", "targetLevel": "...", "timeBudgetMinutes": 60 },
 *   "tree": { "nodes": [ <вложенный узел> ] }
 * }
 * ```
 *
 * Дерево в файле ВЛОЖЕННОЕ (ключ `children`). Внутри кода nodes — плоский
 * список, как в БД (`parentId`/`level`). `parentId` и `level` в файл сознательно
 * НЕ пишутся: они выводятся из вложенности при импорте, поэтому в файле не
 * может быть рассинхрона между структурой и ссылками.
 */
export const TOPIC_FILE_FORMAT = "mindtree.topic";
export const TOPIC_FILE_VERSION = 1;

/** Инвариант `AGENTS.md`: `one_liner` не длиннее 120 символов. */
export const ONE_LINER_MAX_LENGTH = 120;

const NODE_STATES: readonly NodeState[] = [
  "new",
  "structure_generated",
  "expanded",
  "validating",
  "valid",
  "invalid",
  "repairing",
  "content_pending",
  "content_generated",
  "needs_review",
  "failed",
];

const CONCEPT_TYPES: readonly ConceptType[] = [
  "topic",
  "concept",
  "component",
  "mechanism",
  "process",
  "property",
  "rule",
  "method",
  "example",
];

const LEARNING_GOALS: readonly LearningGoal[] = ["overview", "exam", "deep"];

const MASTERY_LEVELS: readonly MasteryLevel[] = [
  "awareness",
  "basic_understanding",
  "solid_understanding",
  "practical_application",
  "advanced",
  "expert",
];

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

/** Файл нечитаем: чужой формат, будущая версия, нет обязательных полей. */
export class TopicFileFormatException extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TopicFileFormatException";
  }
  override toString(): string {
    return `TopicFileFormatException: ${this.message}`;
  }
}

/**
 * Метаданные темы в файле. `id`/`createdAt` не переносятся — при импорте тема
 * получает собственный id, иначе она бы перезаписала исходную.
 */
export interface TopicFileMeta {
  name: string;
  goal: LearningGoal;
  targetLevel: MasteryLevel;
  timeBudgetMinutes: number;
}

export function topicFileMetaFromJson(json: unknown): TopicFileMeta {
  const raw = isPlainObject(json) ? json : {};
  return {
    name: asString(raw.name),
    goal: oneOf<LearningGoal>(raw.goal, LEARNING_GOALS, "overview"),
    targetLevel: oneOf<MasteryLevel>(raw.targetLevel, MASTERY_LEVELS, "awareness"),
    timeBudgetMinutes: asNumber(raw.timeBudgetMinutes, 60),
  };
}

export function topicFileMetaToJson(meta: TopicFileMeta): Record<string, unknown> {
  return {
    name: meta.name,
    goal: meta.goal,
    targetLevel: meta.targetLevel,
    timeBudgetMinutes: meta.timeBudgetMinutes,
  };
}

export interface TopicFileInit {
  sourceTopicId: string;
  topic: TopicFileMeta;
  nodes: KnowledgeNode[];
  version?: number;
  exportedAt?: string;
  errors?: string[];
  warnings?: string[];
}

/**
 * Разобранный файл темы: плоский список узлов + метаданные + результат
 * семантической проверки (ошибки блокируют импорт, предупреждения — нет).
 */
export class TopicFile {
  readonly version: number;
  readonly exportedAt: string;
  readonly sourceTopicId: string;
  readonly topic: TopicFileMeta;
  readonly nodes: KnowledgeNode[];
  readonly errors: string[];
  readonly warnings: string[];

  constructor(init: TopicFileInit) {
    this.version = init.version ?? TOPIC_FILE_VERSION;
    this.exportedAt = init.exportedAt ?? "";
    this.sourceTopicId = init.sourceTopicId;
    this.topic = init.topic;
    this.nodes = init.nodes;
    this.errors = init.errors ?? [];
    this.warnings = init.warnings ?? [];
  }

  get isValid(): boolean {
    return this.errors.length === 0;
  }

  /** Корневые узлы (их должен быть ровно один, иначе `errors` непуст). */
  get roots(): KnowledgeNode[] {
    return this.nodes.filter((n) => n.parentId === null);
  }

  toJson(): Record<string, unknown> {
    return {
      format: TOPIC_FILE_FORMAT,
      version: this.version,
      exportedAt: this.exportedAt,
      source: { topicId: this.sourceTopicId },
      topic: topicFileMetaToJson(this.topic),
      tree: { nodes: nestNodes(this.nodes) },
    };
  }

  toJsonString(): string {
    return JSON.stringify(this.toJson(), null, 2);
  }

  /** Зеркало `TopicFile.fromJson`: бросает [TopicFileFormatException]. */
  static fromJson(json: unknown): TopicFile {
    if (!isPlainObject(json)) {
      throw new TopicFileFormatException('Файл не является JSON-объектом');
    }

    const format = json.format;
    if (format !== TOPIC_FILE_FORMAT) {
      throw new TopicFileFormatException(
        `Ожидался формат "${TOPIC_FILE_FORMAT}", получено: ${format ?? "—"}`,
      );
    }

    const version = typeof json.version === "number" ? Math.trunc(json.version) : 0;
    if (version > TOPIC_FILE_VERSION) {
      throw new TopicFileFormatException(
        `Версия файла ${version} новее поддерживаемой (${TOPIC_FILE_VERSION}). Обновите приложение.`,
      );
    }
    if (version < 1) {
      throw new TopicFileFormatException(`Некорректная версия файла: ${version}`);
    }

    const source = isPlainObject(json.source) ? json.source : undefined;
    const sourceTopicId = typeof source?.topicId === "string" ? source.topicId : "";

    if (!isPlainObject(json.topic)) {
      throw new TopicFileFormatException('Отсутствует раздел "topic"');
    }
    const meta = topicFileMetaFromJson(json.topic);
    if (meta.name.trim().length === 0) {
      throw new TopicFileFormatException('В разделе "topic" пустое имя темы');
    }

    const tree = isPlainObject(json.tree) ? json.tree : undefined;
    const nested = tree ? tree.nodes : undefined;
    if (!Array.isArray(nested) || nested.length === 0) {
      throw new TopicFileFormatException(
        'Раздел "tree.nodes" пуст — нечего импортировать',
      );
    }

    const warnings: string[] = [];
    const nodes = flattenNodes(
      nested.filter(isPlainObject),
      (message) => warnings.push(message),
    );

    const file = new TopicFile({
      version,
      exportedAt: typeof json.exportedAt === "string" ? json.exportedAt : "",
      sourceTopicId,
      topic: meta,
      nodes,
      warnings,
    });
    return file.with({ errors: validateImport(file) });
  }

  static fromJsonString(raw: string): TopicFile {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      throw new TopicFileFormatException(`Файл не является корректным JSON: ${String(e)}`);
    }
    return TopicFile.fromJson(parsed);
  }

  with(patch: { errors?: string[]; warnings?: string[]; nodes?: KnowledgeNode[] }): TopicFile {
    return new TopicFile({
      version: this.version,
      exportedAt: this.exportedAt,
      sourceTopicId: this.sourceTopicId,
      topic: this.topic,
      nodes: patch.nodes ?? this.nodes,
      errors: patch.errors ?? this.errors,
      warnings: patch.warnings ?? this.warnings,
    });
  }
}

/**
 * Плоский список → вложенный JSON-дерево.
 *
 * Узлы группируются по `parentId`; корень — узел без родителя. Если корней
 * несколько (файл мог быть собран вручную), остальные подвешиваются к
 * первому — семантическую проверку отдаёт `validateImport`.
 */
export function nestNodes(flat: KnowledgeNode[]): Record<string, unknown>[] {
  if (flat.length === 0) return [];

  const byId = new Map<string, KnowledgeNode>();
  for (const n of flat) byId.set(n.id, n);
  const childrenOf = new Map<string, KnowledgeNode[]>();
  const roots: KnowledgeNode[] = [];

  for (const n of flat) {
    const parent = n.parentId;
    if (parent === null || parent === undefined || !byId.has(parent)) {
      roots.push(n);
    } else {
      const bucket = childrenOf.get(parent);
      if (bucket) bucket.push(n);
      else childrenOf.set(parent, [n]);
    }
  }
  if (roots.length === 0) roots.push(flat[0]!);

  // Порядок детей — как в плоском списке (стабильно, детерминированно).
  const emitted = new Set<string>();
  const build = (node: KnowledgeNode): Record<string, unknown> => {
    emitted.add(node.id);
    const kids = childrenOf.get(node.id) ?? [];
    return nodeToFileJson(node, kids.map(build));
  };

  const result: Record<string, unknown>[] = [];
  for (const r of roots) {
    if (emitted.has(r.id)) continue;
    result.push(build(r));
  }
  // «Острова» — узлы, не достигнутые от корня (висячие ссылки). Пишем их
  // отдельными деревьями, чтобы файл не потерял данные молча.
  for (const n of flat) {
    if (emitted.has(n.id)) continue;
    result.push(build(n));
  }
  return result;
}

function nodeToFileJson(
  n: KnowledgeNode,
  children: Record<string, unknown>[],
): Record<string, unknown> {
  // Порядок ключей совпадает с Dart-оригиналом: опциональные `analogy` и
  // `conceptType` стоят между `details`/`sources` и `importance`, а не в
  // конце. Иначе два стека давали бы семантически одинаковый, но разный по
  // байтам JSON, и экспортированные файлы нельзя было бы diff-ить.
  return {
    id: n.id,
    label: n.label,
    oneLiner: n.oneLiner,
    details: n.details,
    ...(n.analogy !== undefined && n.analogy !== null ? { analogy: n.analogy } : {}),
    sources: n.sources ?? [],
    ...(n.conceptType !== undefined && n.conceptType !== null ? { conceptType: n.conceptType } : {}),
    importance: n.importance,
    difficulty: n.difficulty,
    estimatedTimeMinutes: n.estimatedTimeMinutes,
    state: n.state,
    contentLoaded: n.contentLoaded,
    // `leaf` в файле — для читаемости; при разборе он НЕ доверяется и
    // пересчитывается из наличия `children` (вложенность первична).
    leaf: children.length === 0,
    relations: n.relations.map(relationToJson),
    sequences: n.sequences.map(sequenceToJson),
    children,
  };
}

function relationToJson(r: Relation): Record<string, unknown> {
  const json: Record<string, unknown> = { from: r.from, to: r.to, type: r.type };
  if (r.label !== undefined && r.label !== null) json.label = r.label;
  return json;
}

function sequenceToJson(s: Sequence): Record<string, unknown> {
  const json: Record<string, unknown> = {
    id: s.id,
    label: s.label,
    steps: s.steps.map((st) => {
      const step: Record<string, unknown> = { conceptId: st.conceptId, order: st.order };
      if (st.label !== undefined && st.label !== null) step.label = st.label;
      if (st.description !== undefined && st.description !== null) step.description = st.description;
      return step;
    }),
  };
  if (s.description !== undefined && s.description !== null) json.description = s.description;
  return json;
}

/**
 * Вложенный JSON → плоский список. `parentId` и `level` выводятся из
 * вложенности, `topicId` остаётся пустым (проставится при импорте).
 *
 * Обход — DFS в порядке массива.
 */
export function flattenNodes(
  nested: Record<string, unknown>[],
  onWarning?: (message: string) => void,
): KnowledgeNode[] {
  const out: KnowledgeNode[] = [];

  const walk = (items: Record<string, unknown>[], parentId: string | null, level: number): void => {
    for (const raw of items) {
      const id = raw.id;
      if (typeof id !== "string" || id.length === 0) {
        onWarning?.(`Пропущен узел без id на уровне ${level}`);
        continue;
      }
      const oneLiner = truncateOneLinerForFile(asString(raw.oneLiner), onWarning);
      const children = Array.isArray(raw.children)
        ? raw.children.filter(isPlainObject)
        : [];

      out.push({
        id,
        topicId: "",
        parentId,
        level,
        label: asString(raw.label),
        oneLiner,
        details: asString(raw.details),
        analogy: typeof raw.analogy === "string" ? raw.analogy : undefined,
        sources: Array.isArray(raw.sources) ? raw.sources.filter((s): s is string => typeof s === "string") : [],
        conceptType: (CONCEPT_TYPES as readonly string[]).includes(asString(raw.conceptType))
          ? (raw.conceptType as ConceptType)
          : undefined,
        importance: asNumber(raw.importance, 0.5),
        difficulty: asNumber(raw.difficulty, 0.5),
        estimatedTimeMinutes: Math.trunc(asNumber(raw.estimatedTimeMinutes, 5)),
        state: oneOf<NodeState>(raw.state, NODE_STATES, "new"),
        contentLoaded: raw.contentLoaded === true,
        // leaf пересчитывается: вложенность первична.
        leaf: children.length === 0,
        relations: (Array.isArray(raw.relations) ? raw.relations : [])
          .filter(isPlainObject)
          .map(relationFromJson),
        sequences: (Array.isArray(raw.sequences) ? raw.sequences : [])
          .filter(isPlainObject)
          .map(sequenceFromJson),
      });
      walk(children, id, level + 1);
    }
  };

  walk(nested, null, 1);
  return out;
}

/** Импорт/экспорт: кламп лимита `one_liner`.
 *
 * Зеркало Dart `_truncateOneLiner`. Используется доменный безопасный кламп
 * (граница предложения/клаузы/слова + снятие висящих служебных слов): сырой
 * `slice` обрывал фразы посреди слова прямо в экспорте.
 */
function truncateOneLinerForFile(value: string, onWarning?: (message: string) => void): string {
  if (value.length <= ONE_LINER_MAX_LENGTH) return value;
  onWarning?.(`one_liner длиннее ${ONE_LINER_MAX_LENGTH} символов — обрезан`);
  return truncateOneLiner(value, ONE_LINER_MAX_LENGTH);
}

function relationFromJson(json: Record<string, unknown>): Relation {
  return {
    from: asString(json.from),
    to: asString(json.to),
    type: asString(json.type) as Relation["type"],
    label: typeof json.label === "string" ? json.label : undefined,
  };
}

function sequenceFromJson(json: Record<string, unknown>): Sequence {
  return {
    id: asString(json.id),
    label: asString(json.label),
    steps: (Array.isArray(json.steps) ? json.steps : [])
      .filter(isPlainObject)
      .map((st) => {
        const step: SequenceStep = {
          conceptId: asString(st.conceptId),
          order: Math.trunc(asNumber(st.order, 0)),
        };
        if (typeof st.label === "string") step.label = st.label;
        if (typeof st.description === "string") step.description = st.description;
        return step;
      }),
    description: typeof json.description === "string" ? json.description : undefined,
  };
}

/**
 * Валидирует форму дерева: ровно один корень, все родители существуют, нет
 * циклов. Зеркало `lib/domain/lib/tree_validation.dart` (в TS-стеке отдельной
 * функции не было, поэтому живёт здесь приватно).
 */
function validateTreeShape(nodes: KnowledgeNode[]): boolean {
  if (nodes.length === 0) return false;
  const ids = new Set(nodes.map((n) => n.id));
  const roots = nodes.filter((n) => n.parentId === null);
  if (roots.length !== 1) return false;

  for (const n of nodes) {
    if (n.parentId !== null && !ids.has(n.parentId)) return false;
  }

  const visited = new Set<string>();
  const inStack = new Set<string>();
  const byId = new Map<string, KnowledgeNode>();
  for (const n of nodes) byId.set(n.id, n);

  const dfs = (id: string): boolean => {
    if (inStack.has(id)) return false;
    if (visited.has(id)) return true;
    inStack.add(id);
    visited.add(id);
    const node = byId.get(id);
    if (node?.parentId != null && !dfs(node.parentId)) return false;
    inStack.delete(id);
    return true;
  };

  for (const n of nodes) {
    if (!dfs(n.id)) return false;
  }
  return true;
}

/** Семантическая проверка импорта. Непустой результат блокирует импорт. */
export function validateImport(file: TopicFile): string[] {
  const errors: string[] = [];
  const nodes = file.nodes;

  // Дубликаты id: проверка формы их не ловит, а БД уронит на PK.
  const seen = new Set<string>();
  const dups = new Set<string>();
  for (const n of nodes) {
    if (seen.has(n.id)) dups.add(n.id);
    else seen.add(n.id);
  }
  if (dups.size > 0) {
    errors.push(`Дублирующиеся id узлов: ${[...dups].join(", ")}`);
  }

  // Пустые подписи — узел нельзя показать в дереве.
  const noLabel = nodes.filter((n) => n.label.trim().length === 0).map((n) => n.id);
  if (noLabel.length > 0) {
    errors.push(`Узлы с пустым названием: ${noLabel.join(", ")}`);
  }

  if (!validateTreeShape(nodes)) {
    const roots = file.roots.length;
    if (roots !== 1) {
      errors.push(`В дереве корней: ${roots}, ожидается ровно один`);
    }
    // Родители/циклы: даём более конкретную причину, если она одна.
    const ids = new Set(nodes.map((n) => n.id));
    const dangling = nodes
      .filter((n) => n.parentId !== null && !ids.has(n.parentId!))
      .map((n) => `${n.id} → ${n.parentId}`);
    if (dangling.length > 0) {
      errors.push(`Ссылки на несуществующих родителей: ${dangling.join(", ")}`);
    } else if (roots === 1) {
      errors.push("В дереве есть цикл");
    }
  }

  return errors;
}

/**
 * Пере-скоупинг id узлов под новую тему.
 *
 * `knowledge_nodes.id` — глобальный первичный ключ, а id узлов несут
 * `~`-суффикс, производный от id темы (`scopedIds.ts`). При импорте в новую
 * тему старые id уедут в конфликт с уже существующими узлами, поэтому все id
 * переезжают под id новой темы, а вместе с ними — все ссылки: `parentId`,
 * `relations[].from/to` и `sequences[].steps[].conceptId`.
 *
 * Ссылка, для которой в карте нет соответствия, остаётся как есть: лучше
 * висячая ссылка (её починит repair-проход при чтении), чем молчаливая потеря
 * связи.
 */
export function rescopeNodes(
  nodes: KnowledgeNode[],
  sourceTopicId: string,
  newTopicId: string,
): KnowledgeNode[] {
  if (nodes.length === 0) return [];
  const oldSuffix = scopedSuffix(sourceTopicId);
  const newSuffix = scopedSuffix(newTopicId);

  const stripOld = (id: string): string =>
    id.endsWith(oldSuffix) ? id.slice(0, id.length - oldSuffix.length) : id;

  const remap = new Map<string, string>();
  for (const n of nodes) {
    const base = stripOld(n.id);
    remap.set(base, `${base}${newSuffix}`);
  }

  const mapRef = (ref: string | null | undefined): string | null | undefined => {
    if (ref === null || ref === undefined || ref.length === 0) return ref;
    return remap.get(stripOld(ref)) ?? ref;
  };

  return nodes.map((n) => {
    const base = stripOld(n.id);
    return {
      ...n,
      id: `${base}${newSuffix}`,
      topicId: newTopicId,
      parentId: mapRef(n.parentId) ?? null,
      relations: n.relations.map((r) => ({
        ...r,
        from: mapRef(r.from) ?? r.from,
        to: mapRef(r.to) ?? r.to,
      })),
      sequences: n.sequences.map((s) => ({
        ...s,
        steps: s.steps.map((st) => ({
          ...st,
          conceptId: mapRef(st.conceptId) ?? st.conceptId,
        })),
      })),
    };
  });
}
