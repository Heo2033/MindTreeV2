import type { FastifyInstance } from "fastify";
import { KnowledgeGraphEngine, type NodeDraft } from "../domain/KnowledgeGraphEngine.js";
import { scopeNodeIds, scopeId } from "../domain/scopedIds.js";
import { getDb } from "../db/connection.js";
import { getScheduler } from "../llm/scheduler.js";

// Число активных форграунд-генераций (/api/pipeline/generate). Пока идёт хотя бы
// одна, фоновое заполнение контента приостанавливается: фоновые 429 только
// «разогревают» общий cooldown рейт-лимита и голодают основной поток.
let foregroundGenerations = 0;

export function beginForegroundGeneration(): void {
  foregroundGenerations++;
}

export function endForegroundGeneration(): void {
  foregroundGenerations = Math.max(0, foregroundGenerations - 1);
}

export function isForegroundGenerationActive(): boolean {
  return foregroundGenerations > 0;
}

export async function pipelineRoutes(app: FastifyInstance) {
  app.post("/generate", async (request, reply) => {
    const body = (request.body ?? {}) as {
      topic_id?: string;
      query?: string;
      goal?: string;
      level?: string;
      time_budget_minutes?: number;
    };
    const { topic_id, query, goal, level, time_budget_minutes } = body;

    if (!query) {
      return reply.status(400).send({ error: "query is required" });
    }

    // SSE headers
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    const sendEvent = (event: string, data: unknown) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    const engine = new KnowledgeGraphEngine();
    const scheduler = getScheduler();
    const prevBackoff = scheduler.onBackoff;
    beginForegroundGeneration();
    // Во время ожидания рейт-лимита сообщаем клиенту, что генерация продолжается,
    // а не «зависла» — UI держит спиннер с понятным сообщением.
    scheduler.onBackoff = (delayMs) => {
      const waitS = Math.max(1, Math.ceil(delayMs / 1000));
      sendEvent("progress", {
        phase: "structure",
        message: `Сервис ограничил частоту запросов — повторяю (ждать ~${waitS} с)…`,
      });
    };

    try {
      const { nodes, warnings } = await engine.generate(
        query,
        {
          goal,
          level,
          timeBudgetMinutes:
            typeof time_budget_minutes === "number" && time_budget_minutes > 0
              ? time_budget_minutes
              : undefined,
        },
        (phase, message, stats) => {
          sendEvent("progress", { phase, message, stats });
        },
        // Инкрементальный персист: по мере завершения каждого уровня уровень
        // сразу сохраняется в БД и виден пользователю (прогрессивная генерация).
        topic_id ? (added) => persistBatch(topic_id, query, added) : undefined,
      );

      console.log(`[pipeline] generate() завершён: ${nodes.length} узлов, ${warnings.length} предупреждений`);
      const byLevel = new Map<number, number>();
      for (const n of nodes) byLevel.set(n.level, (byLevel.get(n.level) ?? 0) + 1);
      console.log(`[pipeline] по уровням: ${[...byLevel.entries()].sort((a, b) => a[0] - b[0]).map(([l, c]) => `L${l}=${c}`).join(", ")}`);

      // Persist nodes to DB if a topic_id was provided
      let persistCount = 0;
      let skippedOrphans: string[] = [];
      try {
        // Финальный persist — страховка; сам insert идемпотентен (INSERT OR IGNORE),
        // т.к. уровни уже могли быть сохранены инкрементально (persistBatch).
        const result = await persistNodes(topic_id, query, nodes);
        skippedOrphans = result.skippedOrphans;
        console.log(`[pipeline] persistNodes: ${result.count} записано, сирот пропущено: ${skippedOrphans.length}`);
        // Финальное дерево — авторитетно: удаляем узлы, которые остались в БД
        // от инкрементального персиста, но были отброшены валидацией/дедупом
        // финального результата (INSERT OR IGNORE не удаляет уже вставленное).
        if (topic_id) {
          reconcileTree(topic_id, nodes);
        }
        // Считаем реальное число узлов в БД (а не только добавленных финальным
        // persist), чтобы фоновое заполнение контента запускалось корректно.
        persistCount = topic_id
          ? (getDb()
              .prepare(`SELECT COUNT(*) AS c FROM knowledge_nodes WHERE topic_id = ?`)
              .get(topic_id) as { c: number }).c
          : result.count;
        console.log(`[pipeline] итого в БД: ${persistCount} узлов`);
      } catch (err) {
        sendEvent("error", {
          message: `Не удалось сохранить дерево: ${err instanceof Error ? err.message : String(err)}`,
        });
        reply.raw.end();
        return;
      }

      // Фоновое, тихое заполнение контента листьев после успешного persist.
      // Не блокирует SSE-ответ: запускается fire-and-forget и не зависит от
      // того, останется ли клиент открытым.
      if (topic_id && persistCount > 0) {
        scheduleBackgroundFill(topic_id, engine);
      }

      sendEvent("done", { nodes, warnings, persisted: persistCount, skippedOrphans });
    } catch (err) {
      sendEvent("error", {
        message: err instanceof Error ? err.message : String(err),
      });
    } finally {
      scheduler.onBackoff = prevBackoff;
      endForegroundGeneration();
    }

    reply.raw.end();
  });
}

function persistNodes(
  topicId: string | undefined,
  query: string,
  nodes: NodeDraft[],
): { count: number; skippedOrphans: string[] } {
  const db = getDb();
  if (!topicId) return { count: 0, skippedOrphans: [] };

  const topic = db.prepare("SELECT id FROM topics WHERE id = ?").get(topicId) as
    | { id: string }
    | undefined;
  if (!topic) return { count: 0, skippedOrphans: [] };

  // Уникализация id: LLM возвращает статичные id (n1_root, n2_*) одинаковые
  // для каждой темы. Суффикс topicId обеспечивает глобальную уникальность в БД.
  const scoped = scopeNodeIds(nodes, topicId);

  // Derive root label from query if tree root is empty
  const rootLabel = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";

  const insert = db.prepare(
    `INSERT OR IGNORE INTO knowledge_nodes
       (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
        estimated_time_minutes, relations_json, state, content_loaded, leaf, level, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
  );

  // Защита от «сирот»: до персиста собираем все id партии (уже scoped);
  // узел с parentId, указывающим на id, которого нет в сохраняемом дереве,
  // НЕ записываем, чтобы в БД не появлялись дети без родителя.
  const persistedIds = new Set(scoped.map((n) => String(n.id)));
  const skippedOrphans: string[] = [];
  const validItems = scoped.filter((n) => {
    const id = String(n.id ?? "");
    if (!id) return false;
    const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
    if (parentId && !persistedIds.has(parentId)) {
      skippedOrphans.push(id);
      return false;
    }
    return true;
  });

  // Сортировка по level: корень (level=1) вставляется раньше детей (level=2+),
  // чтобы satisfy `parent_id` FK (foreign_keys=ON).
  validItems.sort((a, b) => a.level - b.level);

  const tx = db.transaction((items: NodeDraft[]) => {
    let count = 0;
    for (const n of items) {
      const id = String(n.id ?? "");
      if (!id) continue;
      const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
      // level-1 root node uses query as label if empty
      const label = n.level === 1
        ? (String((n as { title?: string }).title ?? "") || rootLabel)
        : String((n as { title?: string }).title ?? "");
      if (!label.trim()) continue;

      const existingChildren = items.filter((c) => c.parentId === id);
      const leaf = existingChildren.length === 0 ? 1 : Number((n as { leaf?: unknown }).leaf ?? 0);
      const relations = Array.isArray((n as { relations?: unknown[] }).relations)
        ? (n as { relations: unknown[] }).relations
        : [];

      insert.run(
        id,
        topicId,
        parentId,
        label.trim(),
        String(n.canonical_definition ?? ""),
        n.conceptType ? String(n.conceptType) : null,
        typeof n.importance === "number" ? n.importance : 0.5,
        typeof n.difficulty === "number" ? n.difficulty : 0.5,
        typeof n.estimatedMinutes === "number" ? n.estimatedMinutes : 5,
        JSON.stringify(relations),
        "skeleton",
        0,
        leaf,
        Number(n.level ?? 1),
        new Date().toISOString(),
      );
      count++;
    }
    return count;
  });

  return { count: tx(validItems), skippedOrphans };
}

/**
 * Инкрементальный персист одной партии узлов (уровня). В отличие от persistNodes,
 * проверяет родительские id против БАЗЫ (ранее сохранённых уровней), а не только
 * против текущей партии — иначе L3-ветвь родитель которой уже в БД была бы
 * ошибочно отброшена как «сирота». После вставки пересчитывает флаги leaf,
 * чтобы родитель, получивший позднее детей, не остался помеченным как лист.
 */
export function persistBatch(topicId: string, query: string, added: NodeDraft[]): Promise<void> {
  const db = getDb();
  if (added.length === 0) {
    console.log(`[persistBatch] пустая партия, пропуск`);
    return Promise.resolve();
  }

  const rootLabel = query.split(/\r?\n/)[0].trim().slice(0, 80) || "Тема";
  // scopeNodeIds заскапит id/внутренние ссылки текущей партии, но parentId,
  // указывающий на узел из ПРОШЛОЙ партии (уже в БД), вне этой партии останется
  // «сырым». Применяем scopeId к parentId: родители в дереве всегда той же темы.
  const scoped = scopeNodeIds(added, topicId).map((n) => ({
    ...n,
    parentId: n.parentId ? scopeId(n.parentId, topicId) : n.parentId,
  }));
  console.log(`[persistBatch] ${scoped.length} узлов: ${scoped.map(n => `${n.id}(L${n.level}, parent=${n.parentId})`).join(", ")}`);

  // Множество id, которые уже существуют в БД по этой теме.
  const dbIds = new Set(
    (db.prepare(`SELECT id FROM knowledge_nodes WHERE topic_id = ?`).all(topicId) as Array<{ id: string }>)
      .map((r) => String(r.id)),
  );
  // + id текущей партии (уже scoped), чтобы дети этой же партии не стали сиротами.
  const knownIds = new Set(dbIds);
  for (const n of scoped) knownIds.add(String(n.id));

  const insert = db.prepare(
    `INSERT OR IGNORE INTO knowledge_nodes
       (id, topic_id, parent_id, label, one_liner, concept_type, importance, difficulty,
        estimated_time_minutes, relations_json, state, content_loaded, leaf, level, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
  );

  const valid = scoped
    .filter((n) => {
      const id = String(n.id ?? "");
      if (!id) return false;
      const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
      // Сирота = родитель не существует ни в БД, ни в этой партии.
      return parentId ? knownIds.has(parentId) : true;
    })
    .sort((a, b) => a.level - b.level);

  const tx = db.transaction((items: NodeDraft[]) => {
    for (const n of items) {
      const id = String(n.id ?? "");
      if (!id) continue;
      const parentId = n.parentId && n.parentId !== id ? String(n.parentId) : null;
      const label = n.level === 1
        ? (String(n.title ?? "") || rootLabel)
        : String(n.title ?? "");
      if (!label.trim()) continue;
      const relations = Array.isArray(n.relations) ? n.relations : [];
      insert.run(
        id,
        topicId,
        parentId,
        label.trim(),
        String(n.canonical_definition ?? ""),
        n.conceptType ? String(n.conceptType) : null,
        typeof n.importance === "number" ? n.importance : 0.5,
        typeof n.difficulty === "number" ? n.difficulty : 0.5,
        typeof n.estimatedMinutes === "number" ? n.estimatedMinutes : 5,
        JSON.stringify(relations),
        "skeleton",
        0,
        0,
        Number(n.level ?? 1),
        new Date().toISOString(),
      );
    }
    // Пересчёт leaf: узел — лист, только если у него нет детей в БД.
    db.prepare(
      `UPDATE knowledge_nodes SET leaf =
         (CASE WHEN EXISTS(
            SELECT 1 FROM knowledge_nodes c
            WHERE c.topic_id = knowledge_nodes.topic_id
              AND c.parent_id = knowledge_nodes.id
          ) THEN 0 ELSE 1 END)
       WHERE topic_id = ?`,
    ).run(topicId);
  });

  tx(valid);
  return Promise.resolve();
}

/**
 * Приводит БД в соответствие с финальным (авторитетным) деревом. Инкрементальный
 * персист (persistBatch) мог сохранить узел, который финальная валидация/дедуп
 * отбросил; INSERT OR IGNORE не удаляет уже вставленное. Удаляем только «скелетные»
 * узлы без контента (content_loaded=0), которых нет в финальном дереве — узлы с
 * уже сгенерированным контентом и историей учёбы не трогаем.
 */
export function reconcileTree(topicId: string, nodes: NodeDraft[]): void {
  const db = getDb();
  const finalIds = new Set(scopeNodeIds(nodes, topicId).map((n) => String(n.id)));
  const existingCount = (db.prepare(
    `SELECT COUNT(*) AS c FROM knowledge_nodes WHERE topic_id = ? AND content_loaded = 0 AND state = 'skeleton'`,
  ).get(topicId) as { c: number }).c;
  const deleted = db.prepare(
    `DELETE FROM knowledge_nodes
     WHERE topic_id = ? AND content_loaded = 0 AND state = 'skeleton'
       AND id NOT IN (SELECT value FROM json_each(?))`,
  ).run(topicId, JSON.stringify([...finalIds]));
  if (deleted.changes > 0) {
    console.log(`[reconcileTree] удалено ${deleted.changes} из ${existingCount} skeleton-узлов (finalIds: ${finalIds.size})`);
  }
}

// Множество topicId, для которых фоновое заполнение уже запущено и не завершено.
// Предотвращает накопление нескольких фоновых циклов для одной темы.
const backgroundFillInFlight = new Set<string>();

/**
 * Запускает тихое фоновое заполнение контента всех узлов темы, у которых
 * content_loaded = 0 (листья L1–L2 после первой генерации). Выполняется
 * fire-and-forget: не блокирует ответ, не привязан к открытой вкладке.
 * Узлы, не заполнившиеся (ошибка LLM и т.п.), остаются для ленивой подгрузки.
 * Идемпотентен: повторный запуск дозаполняет только оставшиеся узлы.
 */
function scheduleBackgroundFill(topicId: string, engine: KnowledgeGraphEngine): void {
  if (backgroundFillInFlight.has(topicId)) return;
  backgroundFillInFlight.add(topicId);

  void (async () => {
    const db = getDb();
    const scheduler = getScheduler();
    const backgroundIntervalMs = readBackgroundIntervalMs();
    try {
      const rows = db
        .prepare(
          `SELECT id FROM knowledge_nodes
           WHERE topic_id = ? AND content_loaded = 0
           ORDER BY level ASC, created_at ASC`,
        )
        .all(topicId) as Array<{ id: string }>;

      for (const { id } of rows) {
        // Технический узел уже заполнен к моменту обработки (например,
        // пользователь сам подгрузил контент) — пропускаем.
        const stillPending = db
          .prepare(`SELECT content_loaded FROM knowledge_nodes WHERE id = ? AND topic_id = ?`)
          .get(id, topicId) as { content_loaded: number } | undefined;
        if (!stillPending || stillPending.content_loaded === 1) continue;

        // Пока идёт форграунд-генерация — фон не мешаем: фоновые 429 только
        // «разогревают» общий cooldown рейт-лимита и голодают основной поток.
        while (isForegroundGenerationActive()) {
          await sleep(500);
        }

        // Интерактивные запросы (тьютор и пр.) не должны голодать из-за фона:
        // резервируем минимум один слот планировщика. Если все слоты заняты,
        // ждём освобождения (с тем же глобальным дедлайном операции).
        while (
          scheduler.maxConcurrency > 1 &&
          scheduler.runningCount >= scheduler.maxConcurrency
        ) {
          await sleep(150);
        }

        // Пауза между фоновыми узлами: спокойный расход RPM/RPD, чтобы не
        // упираться в лимиты провайдера (и не кормить общий cooldown 429-ками).
        if (backgroundIntervalMs > 0) {
          await sleep(backgroundIntervalMs);
        }

        try {
          await engine.generateNodeContentFromDb(topicId, id);
        } catch {
          // Ошибка конкретного узла не останавливает фоновую заливку остальных.
        }
      }
    } finally {
      backgroundFillInFlight.delete(topicId);
    }
  })();
}

/**
 * Пауза между фоновыми узлами при дозаполнении контента. По умолчанию 3 с —
 * достаточно, чтобы не упираться в низкие RPM/RPD-лимиты провайдера и не
 * циклично получать 429 (каждый из которых обновляет глобальный cooldown).
 * 0 — отключить паузу.
 */
function readBackgroundIntervalMs(): number {
  const raw = process.env.LLM_BACKGROUND_INTERVAL_MS;
  if (raw === undefined || raw === "") return 3000;
  const num = Number(raw);
  return Number.isFinite(num) && num >= 0 ? Math.trunc(num) : 3000;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
