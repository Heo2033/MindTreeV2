import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { CurriculumEngine, scorePriority, fitPlanToBudget, type CurriculumRequest } from "../CurriculumEngine.js";
import type { CurriculumItem, KnowledgeNode } from "@mindtree/types";
import { parseCurriculumResult } from "../../prompts/curriculum.js";
import { LLMCache } from "../../llm/cache.js";
import { TreeScheduler } from "../../llm/scheduler.js";

// Сеть в тестах запрещена: callLLM мокаем (как в llm/__tests__/scheduler.test.ts),
// а parseLLMJson оставляем настоящим — разбор «сырых» ответов LLM сам по себе
// часть проверяемой регрессии (пустой items не должен ронять план).
vi.mock("../../llm/client.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../../llm/client.js")>();
  return { ...mod, callLLM: vi.fn() };
});
import { callLLM, LLMMockError } from "../../llm/client.js";

describe("scorePriority (§20: goal_relevance × prerequisite_value × importance ÷ time)", () => {
  it("растёт при большей важности и падает при большем времени", () => {
    const low = scorePriority(0.5, 0.5, 0.3, 20);
    const high = scorePriority(0.5, 0.5, 0.9, 5);
    expect(high).toBeGreaterThan(low);
  });

  it("приоритет выше у понятия, от которого зависят другие", () => {
    const withPrePrereq = scorePriority(0.5, 1, 0.5, 10);
    const withoutPrereq = scorePriority(0.5, 0, 0.5, 10);
    expect(withPrePrereq).toBeGreaterThan(withoutPrereq);
  });

  it("всегда >= 1 (не нулевой, чтобы никого не исключать случайно)", () => {
    expect(scorePriority(0, 0, 0, 200)).toBeGreaterThanOrEqual(1);
  });
});

describe("CurriculumEngine.validate (§63: prereq → dependent ordering)", () => {
  function node(id: string, label: string, rels: Array<{ type: string; from: string; to: string }>): KnowledgeNode {
    return {
      id,
      label,
      relations: rels,
    } as unknown as KnowledgeNode;
  }

  const nodes: KnowledgeNode[] = [
    node("a", "A", []),
    node("b", "B", [{ type: "depends_on", from: "b", to: "a" }]),
    node("c", "C", [{ type: "requires", from: "c", to: "b" }]),
  ];

  function item(nodeId: string, order: number): CurriculumItem {
    return {
      id: `ci_${nodeId}`,
      nodeId,
      order,
      type: "explain",
      estimatedMinutes: 5,
      priority: 1,
      status: "pending",
    } as CurriculumItem;
  }

  it("не находит проблем, когда порядок корректный (a → b → c)", () => {
    const engine = new CurriculumEngine({} as never);
    const issues = engine.validate(
      [item("a", 0), item("b", 1), item("c", 2)],
      nodes,
    );
    expect(issues).toEqual([]);
  });

  it("находит проблему, когда dependent идёт раньше prerequisite", () => {
    const engine = new CurriculumEngine({} as never);
    const issues = engine.validate(
      [item("c", 0), item("b", 1), item("a", 2)],
      nodes,
    );
    expect(issues.length).toBeGreaterThan(0);
  });
});

describe("fitPlanToBudget (§20: time budget cap)", () => {
  function item(id: string, order: number, estimatedMinutes: number): CurriculumItem {
    return {
      id: `ci_${id}`,
      nodeId: `node_${id}`,
      order,
      type: "explain",
      estimatedMinutes,
      priority: 1,
      status: "pending",
    } as CurriculumItem;
  }

  it("пустой план остаётся пустым", () => {
    expect(fitPlanToBudget([], 30)).toEqual([]);
  });

  it("суммарное время плана не превышает бюджет", () => {
    const items = [
      item("a", 0, 10),
      item("b", 1, 15),
      item("c", 2, 20),
      item("d", 3, 5),
    ];
    const fitted = fitPlanToBudget(items, 30);
    expect(fitted.map((i) => i.id)).toEqual(["ci_a", "ci_b"]);
    const total = fitted.reduce((acc, i) => acc + i.estimatedMinutes, 0);
    expect(total).toBeLessThanOrEqual(30);
  });

  it("первый пункт сохраняется, даже если сам длиннее бюджета", () => {
    const fitted = fitPlanToBudget([item("big", 0, 120)], 30);
    expect(fitted).toHaveLength(1);
    expect(fitted[0].id).toBe("ci_big");
  });
});

/*
 * Регрессия: CurriculumEngine.generate возвращал ПУСТОЙ curriculum.
 *
 * Симптом у пользователя: «нажал генерацию — ничего не создалось» (сессия с
 * 0 элементов, вечное «генерация…»).
 *
 * Причина (исправлено в src/domain/CurriculumEngine.ts):
 *   let llmItems = baseline;
 *   try { llmItems = await this.llmSelect(req); } catch { }
 * llmItems заменял детерминированный baseline ЛЮБЫМ результатом LLM, а
 * parseCurriculumResult не бросает исключение на {"items": []} (и на ответе
 * вовсе без поля items) — возвращает пустой список. Значит catch не
 * срабатывал, и пустой список заменял baseline. Вторая половина бага: модель
 * часто возвращает «сырые» id без ~-скоупа (n2_root_1 вместо n2_root_1~hash),
 * и такой план не соответствовал дереву.
 *
 * Фикс: LLM-результат фильтруется по knownIds; если после фильтра пусто —
 * остаётся baseline; плюс последний рубеж
 * fitted.length === 0 && baseline.length > 0.
 *
 * Тесты детерминированы: настоящий CurriculumEngine, настоящий TreeScheduler,
 * подменён только сетевой вызов callLLM.
 */

const SCOPE = "1a2b3c4d";
const ROOT_ID = `n1_topic~${SCOPE}`;
const mockedCallLLM = vi.mocked(callLLM);

const BUDGETS = [1, 5, 30, 60];
const SIZES = [1, 3, 20];
const GOALS = ["понимание", "практическое применение", "подготовка к экзамену"];

type GlobalStore = {
  __mindtree_scheduler__?: TreeScheduler;
  __mindtree_llm_cache__?: LLMCache;
};

beforeAll(() => {
  // Без ключа readLLMConfig() бросает «LLM_API_KEY не задан», а он вызывается из
  // getModelsForTier() на каждый execute без явной model. LLM_MOCK=1 — штатный
  // офлайн-режим: ключ не нужен, а сетевой вызов всё равно подменён моком ниже.
  vi.stubEnv("LLM_MOCK", "1");

  // CurriculumEngine ходит в глобальный scheduler (getScheduler()). У того лимиты
  // RPM/RPD (60/500 в минуту) и retry с backoff: на ~90 вызовах тест уперся бы в
  // rate-limit, а сценарий падения LLM ждал бы десятки секунд. Поэтому подменяем
  // синглтон на экземпляр с высокими лимитами и maxRetries: 0.
  const store = globalThis as unknown as GlobalStore;
  store.__mindtree_llm_cache__ = new LLMCache({ persistDir: null });
  store.__mindtree_scheduler__ = new TreeScheduler(
    {
      maxRPM: 100000,
      maxRPD: 1000000,
      maxConcurrency: 1,
      maxRetries: 0,
      opDeadlineMs: 0,
    },
    store.__mindtree_llm_cache__,
  );
});

afterAll(() => {
  const store = globalThis as unknown as GlobalStore;
  delete store.__mindtree_scheduler__;
  delete store.__mindtree_llm_cache__;
  vi.unstubAllEnvs();
});

beforeEach(() => {
  mockedCallLLM.mockReset();
  // Ответ по умолчанию — самый частый случай из бага: пустой список items.
  mockedCallLLM.mockResolvedValue({
    text: rawItems([]),
    usage: { input_tokens: 10, output_tokens: 10 },
  });
});

function rootNode(): KnowledgeNode {
  return {
    id: ROOT_ID,
    topicId: "t1",
    parentId: null,
    level: 1,
    label: "Теорема остановки",
    oneLiner: "Обзорная тема раздела.",
    details: "Подробности корня.",
    importance: 0.5,
    difficulty: 0.5,
    estimatedTimeMinutes: 5,
    state: "content_generated",
    contentLoaded: true,
    leaf: false,
    relations: [],
    sequences: [],
  };
}

// Узел уровня 2 — именно они попадают в учебный план (корень не учится).
// Важность и время намеренно различаются, чтобы baseline был неоднородным.
function childNode(i: number): KnowledgeNode {
  return {
    ...rootNode(),
    id: `n2_root_${i}~${SCOPE}`,
    parentId: ROOT_ID,
    level: 2,
    label: `Понятие ${i}`,
    oneLiner: `Суть понятия ${i} в одном предложении.`,
    details: `Подробности понятия ${i}.`,
    importance: 0.35 + 0.05 * (i % 6),
    estimatedTimeMinutes: 4 + (i % 5) * 3, // 4, 7, 10, 13, 16 минут
  };
}

// «Размер дерева» в тестах = число учимых понятий плюс корень.
function treeOf(learnable: number): KnowledgeNode[] {
  return [rootNode(), ...Array.from({ length: learnable }, (_, i) => childNode(i + 1))];
}

function request(
  nodes: KnowledgeNode[],
  opts: { budget?: number; goal?: string; known?: Set<string> } = {},
): CurriculumRequest {
  return {
    topicId: "t1",
    topicName: "Теорема остановки",
    goal: opts.goal ?? "понимание",
    targetLevel: "solid_understanding",
    currentLevel: "basic_understanding",
    timeBudgetMinutes: opts.budget ?? 60,
    nodes,
    knownNodeIds: opts.known,
  };
}

function llmItem(nodeId: string, order: number, minutes: number): Record<string, unknown> {
  return {
    node_id: nodeId,
    order,
    estimated_minutes: minutes,
    why: `потому что ${nodeId}`,
  };
}

// Ответ LLM в контракте parseCurriculumResult.
function rawItems(items: Array<Record<string, unknown>>, totalMinutes?: number): string {
  return JSON.stringify({
    items,
    total_estimated_minutes:
      totalMinutes ?? items.reduce((s, i) => s + (i.estimated_minutes as number), 0),
  });
}

function sumMinutes(items: CurriculumItem[]): number {
  return items.reduce((s, i) => s + i.estimatedMinutes, 0);
}

describe("parseCurriculumResult: почему одного catch не хватало", () => {
  it("пустой items не бросает исключение, а отдаёт пустой список", () => {
    // Именно этот дефект ломал fallback: catch не срабатывал.
    const parsed = parseCurriculumResult({ items: [], total_estimated_minutes: 0 });
    expect(parsed.items).toEqual([]);
  });

  it("ответ без поля items тоже не бросает исключение", () => {
    const parsed = parseCurriculumResult({ total_estimated_minutes: 0 });
    expect(parsed.items).toEqual([]);
  });

  it("битый JSON-тип (items не список) не бросает исключение", () => {
    const parsed = parseCurriculumResult({ items: "вместо списка" });
    expect(parsed.items).toEqual([]);
  });
});

describe("CurriculumEngine.generate: план непустой при любом ответе LLM", () => {
  it('LLM вернул {"items": []} → план из детерминированного baseline', async () => {
    const nodes = treeOf(3);
    const req = request(nodes);
    const engine = new CurriculumEngine();

    const result = await engine.generate(req);

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.length).toBeGreaterThan(0);
    const baseline = engine["deterministicSelect"](req);
    expect(result.curriculum.items.map((i) => i.nodeId)).toEqual(
      baseline.map((b) => b.node_id),
    );
    expect(result.curriculum.items.map((i) => i.estimatedMinutes)).toEqual(
      baseline.map((b) => b.estimated_minutes),
    );
  });

  it("LLM вернул ответ без поля items → тот же непустой план", async () => {
    const nodes = treeOf(3);
    const req = request(nodes);
    mockedCallLLM.mockResolvedValue({
      text: JSON.stringify({ total_estimated_minutes: 0, note: "не знаю что выбрать" }),
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const result = await new CurriculumEngine().generate(req);

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.length).toBeGreaterThan(0);
  });

  it("LLM вернул битый JSON → парсер/движок не роняют сценарий", async () => {
    const nodes = treeOf(3);
    mockedCallLLM.mockResolvedValue({
      text: "просто текст без JSON",
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const result = await new CurriculumEngine().generate(request(nodes));

    expect(mockedCallLLM).toHaveBeenCalled();
    expect(result.curriculum.items.length).toBeGreaterThan(0);
  });

  it("LLM вернул только сырые id без скоупа → всё отброшено, взят baseline", async () => {
    const nodes = treeOf(3);
    const req = request(nodes);
    // Модель «забыла» ~-суффикс: n2_root_1 вместо n2_root_1~1a2b3c4d.
    mockedCallLLM.mockResolvedValue({
      text: rawItems([
        llmItem("n2_root_1", 1, 7),
        llmItem("n2_root_2", 2, 9),
        llmItem("n2_root_3", 3, 11),
      ]),
      usage: { input_tokens: 10, output_tokens: 10 },
    });
    const engine = new CurriculumEngine();

    const result = await engine.generate(req);

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.length).toBeGreaterThan(0);
    const treeIds = new Set(nodes.map((n) => n.id));
    for (const item of result.curriculum.items) {
      expect(treeIds.has(item.nodeId)).toBe(true);
    }
    const baseline = engine["deterministicSelect"](req);
    expect(result.curriculum.items.map((i) => i.nodeId)).toEqual(
      baseline.map((b) => b.node_id),
    );
  });

  it("LLM вернул смешанный список → остались только валидные", async () => {
    const nodes = treeOf(4);
    const validA = `n2_root_2~${SCOPE}`;
    const validB = `n2_root_3~${SCOPE}`;
    mockedCallLLM.mockResolvedValue({
      text: rawItems([
        llmItem(validA, 1, 7),
        llmItem("n2_root_99", 2, 99), // мусор: нет такого узла
        llmItem(validB, 3, 3),
        llmItem("", 4, 5), // пустой id
      ]),
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const result = await new CurriculumEngine().generate(request(nodes));

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.map((i) => i.nodeId)).toEqual([validA, validB]);
    expect(result.curriculum.items.map((i) => i.estimatedMinutes)).toEqual([7, 3]);
    // Порядок возрастает: после отбрасывания мусора в order остаются пропуски —
    // fitPlanToBudget только сортирует, но не перенумеровывает.
    const orders = result.curriculum.items.map((i) => i.order);
    expect(orders).toEqual([...orders].sort((a, b) => a - b));
  });

  it("LLM упал исключением → детерминированный baseline (не сломали)", async () => {
    const nodes = treeOf(3);
    const req = request(nodes);
    // LLMMockError scheduler не ретраит (shouldRetry), поэтому тест не ждёт backoff.
    mockedCallLLM.mockRejectedValue(new LLMMockError("провайдер недоступен (тест)"));
    const engine = new CurriculumEngine();

    const result = await engine.generate(req);

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.length).toBeGreaterThan(0);
    const baseline = engine["deterministicSelect"](req);
    expect(result.curriculum.items.map((i) => i.nodeId)).toEqual(
      baseline.map((b) => b.node_id),
    );
  });

  it("валидный план LLM не вытесняется baseline-ом", async () => {
    // Обратная сторона фикса: осмысленный ответ LLM не должен теряться.
    const nodes = treeOf(4);
    mockedCallLLM.mockResolvedValue({
      text: rawItems([
        llmItem(`n2_root_4~${SCOPE}`, 1, 12),
        llmItem(`n2_root_1~${SCOPE}`, 2, 6),
      ]),
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const result = await new CurriculumEngine().generate(request(nodes));

    expect(mockedCallLLM).toHaveBeenCalledTimes(1);
    expect(result.curriculum.items.map((i) => i.nodeId)).toEqual([
      `n2_root_4~${SCOPE}`,
      `n2_root_1~${SCOPE}`,
    ]);
  });
});

describe("Инвариант: непустой план при непустом бюджете", () => {
  it("план непустой во всех комбинациях бюджет × размер × цель", async () => {
    const engine = new CurriculumEngine();
    const failures: string[] = [];
    for (const budget of BUDGETS) {
      for (const size of SIZES) {
        for (const goal of GOALS) {
          const nodes = treeOf(size);
          const treeIds = new Set(nodes.map((n) => n.id));
          // Ответ по умолчанию из beforeEach — тот самый, что раньше обнулял план.
          const result = await engine.generate(request(nodes, { budget, goal }));
          if (result.curriculum.items.length === 0) {
            failures.push(`budget=${budget} size=${size} goal="${goal}"`);
          }
          for (const item of result.curriculum.items) {
            if (!treeIds.has(item.nodeId)) failures.push(`visiting id ${item.nodeId}`);
          }
        }
      }
    }
    expect(failures).toEqual([]);
  });

  it("план непустой при LLM-ответе из одних сырых id", async () => {
    const engine = new CurriculumEngine();
    mockedCallLLM.mockResolvedValue({
      text: rawItems([llmItem("n2_root_1", 1, 5), llmItem("n2_root_2", 2, 5)]),
      usage: { input_tokens: 10, output_tokens: 10 },
    });
    const failures: string[] = [];
    for (const budget of BUDGETS) {
      for (const size of SIZES) {
        const result = await engine.generate(request(treeOf(size), { budget }));
        if (result.curriculum.items.length === 0) {
          failures.push(`budget=${budget} size=${size}`);
        }
      }
    }
    expect(failures).toEqual([]);
  });

  it("бюджет соблюдён: сумма минут ≤ бюджета (кроме одного длинного пункта)", async () => {
    const engine = new CurriculumEngine();
    const violations: string[] = [];
    for (const budget of BUDGETS) {
      for (const size of SIZES) {
        const result = await engine.generate(request(treeOf(size), { budget }));
        const items = result.curriculum.items;
        if (items.length === 0) {
          violations.push(`budget=${budget} size=${size}: пустой план`);
          continue;
        }
        const total = sumMinutes(items);
        // Допустимое исключение fitPlanToBudget: единственный пункт, который сам
        // по себе длиннее бюджета (иначе план был бы пустым).
        const singleTooLong = items.length === 1 && items[0]!.estimatedMinutes > budget;
        if (total > budget && !singleTooLong) {
          violations.push(`budget=${budget} size=${size}: ${total} мин в ${items.length} пунктах`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it("totalEstimatedMinutes совпадает с суммой пунктов", async () => {
    const engine = new CurriculumEngine();
    for (const budget of BUDGETS) {
      for (const size of SIZES) {
        const result = await engine.generate(request(treeOf(size), { budget }));
        expect(result.curriculum.totalEstimatedMinutes).toBe(
          sumMinutes(result.curriculum.items),
        );
      }
    }
  });

  it("детерминирован: два одинаковых входа дают одинаковый план", async () => {
    const engine = new CurriculumEngine();
    for (const budget of BUDGETS) {
      for (const size of SIZES) {
        const req = request(treeOf(size), { budget });
        const first = await engine.generate(req);
        const second = await engine.generate(req);
        expect(second.curriculum.items.map((i) => i.nodeId)).toEqual(
          first.curriculum.items.map((i) => i.nodeId),
        );
        expect(second.curriculum.items.map((i) => i.estimatedMinutes)).toEqual(
          first.curriculum.items.map((i) => i.estimatedMinutes),
        );
      }
    }
  });
});

describe("Границы: когда пустой план — это законно", () => {
  it("дерево только с корнем (level 1) → в план попадает корень", async () => {
    // Раньше deterministicSelect брал только level >= 2, и на дереве из
    // одного корня план выходил пустым — то самое «генерация не создалась».
    // Теперь корневая страховка: сессия всегда предлагает хоть что-то.
    const result = await new CurriculumEngine().generate(request([rootNode()]));
    expect(result.curriculum.items).toHaveLength(1);
    expect(result.curriculum.items[0].nodeId).toBe(rootNode().id);
  });

  it("пустое дерево → пустой план без исключения", async () => {
    const result = await new CurriculumEngine().generate(request([]));
    expect(result.curriculum.items).toEqual([]);
    expect(result.curriculum.totalEstimatedMinutes).toBe(0);
  });

  it("все узлы уже освоены → план пуст, но alreadyKnown заполнен", async () => {
    const nodes = treeOf(3);
    const known = new Set(nodes.map((n) => n.id));
    const result = await new CurriculumEngine().generate(request(nodes, { known }));
    expect(result.curriculum.items).toEqual([]);
    expect(result.alreadyKnown.length).toBeGreaterThan(0);
  });
});