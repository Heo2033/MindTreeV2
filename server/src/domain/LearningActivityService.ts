import { getScheduler } from "../llm/scheduler.js";
import { parseLLMJson } from "../llm/client.js";
import {
  buildActivityPrompt,
  type ActivityNodeContext,
} from "../prompts/activity.js";
import { LearningSessionEngine } from "./LearningSessionEngine.js";
import { FeedbackEngine } from "./FeedbackEngine.js";
import { EventBus } from "./EventBus.js";
import { getDb } from "../db/connection.js";

export type ActivityStepType = "explain" | "example" | "recall" | "apply";

export interface ActivityStep {
  type: ActivityStepType;
  title: string;
  body?: string;
  instruction?: string;
  options?: string[];
  correctIndex?: number;
  bestAnswer?: string;
  placeholder?: string;
  status: "pending" | "current" | "answered";
  userAnswer?: string;
  correct?: boolean;
  feedback?: string;
}

export interface Activity {
  sessionId: string;
  itemId: string;
  nodeId: string;
  nodeLabel: string;
  goal: string;
  steps: ActivityStep[];
  currentStep: number;
  isComplete: boolean;
}

export class LearningActivityService {
  constructor(
    private engine = new LearningSessionEngine(),
    private feedback = new FeedbackEngine(),
  ) {}

  getActivity(sessionId: string): Activity | null {
    const session = this.engine.getSession(sessionId);
    if (!session) return null;
    const row = getDb()
      .prepare(`SELECT activity_json FROM learning_sessions WHERE id = ?`)
      .get(sessionId) as { activity_json: string } | undefined;
    if (!row) return null;
    const { itemId: storedItemId, steps } = parseActivityBlob(row.activity_json);
    if (steps.length === 0) return null;

    const current = this.engine.getCurrentItem(sessionId)?.item;
    if (!current) return null;

    // Сохранённая активность должна принадлежать текущему концепту плана.
    // Иначе (после перехода к следующему концепту или правок учебного плана)
    // считаем её устаревшей и заставляем ensureActivity перестроить шаги для нового узла.
    if (storedItemId && storedItemId !== current.id) return null;

    const nodeLabel = current?.nodeId ? nodeRow(current.nodeId)?.label ?? "" : "";
    const goal = session.goal;
    const currentStep = nextPendingIndex(steps);
    return {
      sessionId,
      itemId: current?.id ?? "",
      nodeId: current?.nodeId ?? "",
      nodeLabel,
      goal,
      steps,
      currentStep,
      isComplete: currentStep === -1,
    };
  }

  async ensureActivity(sessionId: string): Promise<Activity> {
    const existing = this.getActivity(sessionId);
    if (existing) return existing;

    const current = this.engine.getCurrentItem(sessionId);
    if (!current) throw new Error("В сессии нет текущего шага учебного плана");
    const session = this.engine.getSession(sessionId);
    if (!session) throw new Error("Сессия не найдена");

    const node = nodeRow(current.item.nodeId);
    if (!node) throw new Error("Узел не найден");

    const steps = await this.buildSteps(session, node, current.item.order);

    getDb()
      .prepare(
        `UPDATE learning_sessions SET activity_json = ?, current_activity_step = 0 WHERE id = ?`,
      )
      .run(JSON.stringify({ itemId: current.item.id, steps }), sessionId);

    // Маркер старта шага: длительность 0, открываем границу единицы работы.
    EventBus.markUnitStart(sessionId);
    EventBus.emit({
      sessionId,
      topicId: session.topicId,
      kind: "activity_started",
      nodeId: node.id,
      payload: { itemId: current.item.id, steps: steps.map((s) => s.type) },
    });

    return this.getActivity(sessionId)!;
  }

  async answer(sessionId: string, stepIndex: number, answer: string): Promise<Activity> {
    const session = this.engine.getSession(sessionId);
    if (!session) throw new Error("Сессия не найдена");
    const activity = this.getActivity(sessionId);
    if (!activity) throw new Error("Активность не найдена. Начните с GET /activity");
    const step = activity.steps[stepIndex];
    if (!step) throw new Error("Неверный индекс шага");
    if (step.status === "answered") throw new Error("Шаг уже отвечен");

    const node = nodeRow(activity.nodeId);
    const nodeLabel = node?.label ?? activity.nodeLabel;
    const nodeOneLiner = node?.one_liner ?? "";

    if (step.type === "recall") {
      const chosenIndex = Math.max(0, Math.min(Number(answer) || 0, (step.options?.length ?? 1) - 1));
      const res = this.feedback.evaluateRecall(
        session.topicId,
        session.goal,
        activity.nodeId,
        nodeLabel,
        step,
        chosenIndex,
      );
      step.status = "answered";
      step.userAnswer = answer;
      step.correct = res.correct;
      step.feedback = res.feedback;
      // Закрываем шаг: несём длительность и сразу открываем следующий.
      const recallMs = EventBus.closeUnit(sessionId);
      EventBus.emit({
        sessionId,
        topicId: session.topicId,
        kind: "activity_answer",
        nodeId: activity.nodeId,
        payload: { step: "recall", correct: res.correct, score: res.score },
        durationMs: recallMs,
      });
      EventBus.markUnitStart(sessionId);
    } else if (step.type === "apply") {
      const res = await this.feedback.evaluateApply(
        session.topicId,
        topicName(session.topicId),
        activity.nodeId,
        nodeLabel,
        nodeOneLiner,
        step.instruction ?? "",
        step.bestAnswer ?? "",
        answer,
      );
      step.status = "answered";
      step.userAnswer = answer;
      step.correct = res.correct;
      step.feedback = res.feedback;
      const applyMs = EventBus.closeUnit(sessionId);
      EventBus.emit({
        sessionId,
        topicId: session.topicId,
        kind: "activity_answer",
        nodeId: activity.nodeId,
        payload: { step: "apply", correct: res.correct, score: res.score },
        durationMs: applyMs,
      });
      EventBus.markUnitStart(sessionId);
    } else {
      // explain / example — не требуют ответа ученика
      step.status = "answered";
      step.userAnswer = answer || "";
      const readMs = EventBus.closeUnit(sessionId);
      EventBus.emit({
        sessionId,
        topicId: session.topicId,
        kind: "activity_step_done",
        nodeId: activity.nodeId,
        payload: { step: step.type },
        durationMs: readMs,
      });
      EventBus.markUnitStart(sessionId);
    }

    this.persistSteps(sessionId, activity.itemId, activity.steps);
    return this.getActivity(sessionId)!;
  }

  private async buildSteps(
    session: NonNullable<ReturnType<LearningSessionEngine["getSession"]>>,
    node: KnowledgeNodeRow,
    order: number,
  ): Promise<ActivityStep[]> {
    const topicLabel = topicName(session.topicId);
    const targetLevel = this.targetLevel(session.topicId);

    const actCtx: ActivityNodeContext = {
      id: node.id,
      label: node.label,
      one_liner: node.one_liner,
      details: node.details,
      concept_type: node.concept_type ?? undefined,
      difficulty: node.difficulty,
    };

    let generated: { example?: string; recall?: { question: string; options: string[]; correct_index: number }; apply?: { instruction: string; reference_answer: string } } = {};
    try {
      const res = await getScheduler().execute(
        "curriculum",
        () => buildActivityPrompt({ topic: topicLabel, goal: session.goal, targetLevel, ...actCtx }),
        (raw) =>
          parseLLMJson<{
            example?: string;
            recall?: { question: string; options: string[]; correct_index: number };
            apply?: { instruction: string; reference_answer: string };
          }>(raw),
        { cacheKey: `activity:${node.id}:${session.goal}:${targetLevel}` },
      );
      generated = res.result;
    } catch (err) {
      console.warn(
        `[activity] генерация не удалась, использую фолбэк: ${err instanceof Error ? err.message.slice(0, 120) : "unknown"}`,
      );
    }

    const siblingLabels = siblingOneLiners(node);
    const explainBodyText = node.details || explainBody(node, siblingLabels);
    const rawExample = generated.example?.trim()
      ? generated.example
      : fallbackExample(node);
    const exampleBody = ensureDistinctExample(node, explainBodyText, rawExample);
    const recall = generated.recall && generated.recall.options.length >= 2
      ? { question: generated.recall.question, options: generated.recall.options, correct_index: generated.recall.correct_index }
      : fallbackRecall(node, siblingLabels);
    const rotation = order % recall.options.length;
    const rotated = rotateOptions(recall.options, rotation);
    const correctIndex = rotateIndex(recall.correct_index, rotation, recall.options.length);

    const apply = generated.apply && generated.apply.instruction.trim()
      ? { instruction: generated.apply.instruction, reference_answer: generated.apply.reference_answer }
      : fallbackApply(node);

    const steps: ActivityStep[] = [
      {
        type: "explain",
        title: "Изучаем понятие",
        body: explainBodyText,
        status: "pending",
      },
      {
        type: "example",
        title: "Разбираем пример",
        body: exampleBody,
        status: "pending",
      },
      {
        type: "recall",
        title: "Проверяем запоминание",
        instruction: recall.question,
        options: rotated,
        correctIndex,
        placeholder: "Выберите вариант ответа",
        status: "pending",
      },
      {
        type: "apply",
        title: "Применяем на практике",
        instruction: apply.instruction,
        bestAnswer: apply.reference_answer,
        placeholder: "Введите ответ своими словами…",
        status: "pending",
      },
    ];
    return steps.map((s, i) => ({ ...s, status: i === 0 ? ("current" as const) : s.status }));
  }

  private persistSteps(sessionId: string, itemId: string, steps: ActivityStep[]) {
    getDb()
      .prepare(
        `UPDATE learning_sessions SET activity_json = ?, current_activity_step = ? WHERE id = ?`,
      )
      .run(JSON.stringify({ itemId, steps }), nextPendingIndex(steps), sessionId);
  }

  private targetLevel(topicId: string): string {
    const row = getDb().prepare(`SELECT target_level FROM topics WHERE id = ?`).get(topicId) as
      | { target_level: string }
      | undefined;
    return row?.target_level ?? "basic_understanding";
  }
}

export function nextPendingIndex(steps: ActivityStep[]): number {
  const idx = steps.findIndex((s) => s.status === "pending" || s.status === "current");
  return idx;
}

export function parseSteps(raw: string): ActivityStep[] {
  try {
    const parsed = JSON.parse(raw || "[]") as ActivityStep[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/**
 * Разбирает блоб активности, который хранится как { itemId, steps }.
 * Старые/внешние форматы (простой массив шагов) обрабатываются как steps без itemId.
 */
export function parseActivityBlob(raw: string): { itemId?: string; steps: ActivityStep[] } {
  try {
    const parsed = JSON.parse(raw || "{}") as { itemId?: string; steps?: ActivityStep[] } | ActivityStep[];
    if (Array.isArray(parsed)) {
      return { steps: parsed };
    }
    if (parsed && Array.isArray(parsed.steps)) {
      return { itemId: parsed.itemId, steps: parsed.steps };
    }
    return { steps: [] };
  } catch {
    return { steps: [] };
  }
}

export function rotateOptions<T>(options: T[], shift: number): T[] {
  if (options.length === 0 || shift === 0) return options;
  const n = options.length;
  const shiftMod = ((shift % n) + n) % n;
  return options.map((_, i) => options[(i + shiftMod) % n]!);
}

export function rotateIndex(index: number, shift: number, length: number): number {
  if (length === 0) return 0;
  return ((index - ((shift % length) + length) % length) + length) % length;
}

export function fallbackExample(node: KnowledgeNodeRow): string {
  if (node.analogy) {
    return `Аналогия: ${node.analogy}`;
  }
  return `Рассмотрите, как понятие «${node.label}» проявляется вокруг: в жизни, работе или учёбе. Приведите один простой пример, где оно применимо, и разберите его.`;
}

/**
 * Текст шага «объяснение»: подробный details, либо связка
 * one_liner + связи — но не голый one_liner. Аналогия НЕ включается:
 * она отдаётся шагу «пример» (fallbackExample), иначе оба шага дублируются.
 * (зеркало _explainBody flutter).
 */
export function explainBody(node: KnowledgeNodeRow, relatedLabels: string[]): string {
  const parts = [node.one_liner];
  if (relatedLabels.length > 0) {
    parts.push(`Связанные понятия: ${relatedLabels.slice(0, 3).join(", ")}.`);
  }
  return parts.join("\n\n");
}

/**
 * Защита от дубля «пример повторяет объяснение»: если LLM/fallback вернул
 * для примера тот же текст, что в шаге «объяснение», подменяем его на
 * fallback-пример (аналогия либо нейтральная инструкция).
 * (зеркало _ensureDistinctExample flutter).
 */
export function ensureDistinctExample(
  node: KnowledgeNodeRow,
  explainBodyText: string,
  example: string,
): string {
  const a = example.trim();
  const b = explainBodyText.trim();
  if (!a) return fallbackExample(node);
  if (b && (a === b || a.includes(b) || b.includes(a))) {
    return fallbackExample(node);
  }
  return a;
}

/**
 * Осмысленные дистракторы: one_liner соседних понятий (siblings по тому же
 * родителю), дополненные generic-фразами (зеркало _fallbackRecall flutter).
 */
function fallbackRecall(
  node: KnowledgeNodeRow,
  relatedLabels: string[] = [],
): { question: string; options: string[]; correct_index: number } {
  const distractors: string[] = [];
  for (const label of relatedLabels) {
    if (!label || label === node.one_liner || distractors.includes(label)) continue;
    distractors.push(label);
    if (distractors.length >= 3) break;
  }
  const generic = [
    "Понятие, обратное изучаемому",
    "Термин из другого раздела темы",
    "Случайная комбинация тезисов",
  ];
  for (const label of generic) {
    if (distractors.includes(label)) continue;
    distractors.push(label);
    if (distractors.length >= 3) break;
  }
  return {
    question: `Что означает понятие «${node.label}»?`,
    options: [node.one_liner || "Верный ответ — в определении понятия", ...distractors.slice(0, 3)],
    correct_index: 0,
  };
}

/** one_liner соседних узлов (общий родитель), до 4 штук. */
function siblingOneLiners(node: KnowledgeNodeRow & { parent_id: string | null }): string[] {
  if (!node.parent_id) return [];
  const rows = getDb()
    .prepare(
      `SELECT one_liner FROM knowledge_nodes WHERE parent_id = ? AND id != ? AND one_liner != '' LIMIT 4`,
    )
    .all(node.parent_id, node.id) as { one_liner: string }[];
  return rows.map((r) => r.one_liner);
}

function fallbackApply(node: KnowledgeNodeRow): { instruction: string; reference_answer: string } {
  return {
    instruction: `Объясните своими словами, как понятие «${node.label}» применяется на практике. Приведите один собственный пример из реальной жизни или задачи.`,
    reference_answer: node.one_liner || node.details,
  };
}

interface KnowledgeNodeRow {
  id: string;
  label: string;
  one_liner: string;
  details: string;
  analogy?: string | null;
  concept_type?: string | null;
  difficulty: number;
  parent_id: string | null;
}

function nodeRow(nodeId: string): KnowledgeNodeRow | null {
  const row = getDb().prepare(`SELECT * FROM knowledge_nodes WHERE id = ?`).get(nodeId) as
    | Record<string, unknown>
    | undefined;
  if (!row) return null;
  return {
    id: String(row.id),
    label: String(row.label),
    one_liner: String(row.one_liner ?? ""),
    details: String(row.details ?? ""),
    analogy: row.analogy ? String(row.analogy) : null,
    concept_type: row.concept_type ? String(row.concept_type) : null,
    difficulty: Number(row.difficulty ?? 0.5),
    parent_id: row.parent_id ? String(row.parent_id) : null,
  };
}

function topicName(topicId: string): string {
  const row = getDb().prepare(`SELECT name FROM topics WHERE id = ?`).get(topicId) as
    | { name: string }
    | undefined;
  return row?.name ?? "";
}