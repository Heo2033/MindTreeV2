import { describe, it, expect } from "vitest";
import {
  fallbackStructure,
  dedupeNodeIds,
  parseNodeMetadata,
  consistencyCheckAgainstTree,
  mergeRepairs,
  deterministicValidate,
  breakDependencyCycles,
  truncateOneLiner,
  type NodeDraft,
} from "../KnowledgeGraphEngine.js";
import { masteryLevelToKnowledgeLevel } from "../../prompts/structure.js";
import { ONELINER_MAX_CHARS } from "../../prompts/oneline.js";

describe("KnowledgeGraphEngine helpers", () => {
  describe("fallbackStructure", () => {
    it("строит офлайн-скелет с уникальными id и валидными parentId", () => {
      const nodes = fallbackStructure("Медицина");
      expect(nodes.length).toBeGreaterThan(0);
      expect(nodes[0].level).toBe(1);
      expect(nodes[0].parentId).toBeNull();
      expect(nodes[0].title).toBe("Медицина");

      const ids = nodes.map((n) => n.id);
      expect(new Set(ids).size).toBe(ids.length);

      const idsSet = new Set(ids);
      for (const n of nodes) {
        if (n.parentId !== null) {
          expect(idsSet.has(n.parentId)).toBe(true);
        }
      }
    });
  });

  describe("dedupeNodeIds", () => {
    it("схлопывает точные дубли и оставляет уникальные id", () => {
      const nodes = [
        { id: "n1", title: "A", parentId: null, level: 1 },
        { id: "n1", title: "A", parentId: null, level: 1 }, // точный дубль
        { id: "n2", title: "B", parentId: "n1", level: 2 },
      ];
      const out = dedupeNodeIds(nodes);
      const ids = out.map((n) => n.id);
      expect(ids).toEqual(["n1", "n2"]);
      expect(new Set(ids).size).toBe(ids.length);
    });

    it("переименовывает коллизии id и обновляет parentId", () => {
      const nodes = [
        { id: "a", title: "Root", parentId: null, level: 1 },
        { id: "a", title: "Другой узел", parentId: null, level: 2 }, // коллизия id, другой контент
        { id: "b", title: "Child A", parentId: "a", level: 2 },
      ];
      const out = dedupeNodeIds(nodes);
      const ids = out.map((n) => n.id);
      expect(new Set(ids).size).toBe(ids.length);

      const root = out.find((n) => n.title === "Root");
      const other = out.find((n) => n.title === "Другой узел");
      expect(root).toBeDefined();
      expect(other).toBeDefined();
      expect(root!.id).not.toBe(other!.id);

      const childA = out.find((n) => n.title === "Child A");
      expect(childA!.parentId).toBe(root!.id);
    });
  });

  describe("parseNodeMetadata", () => {
    it("извлекает валидные метаданные и relations", () => {
      const meta = parseNodeMetadata({
        id: "n2_a",
        importance: 0.8,
        difficulty: 0.3,
        estimated_time_minutes: "15",
        prerequisites: ["n1", "n2_b"],
        relations: [
          { to: "n1", type: "requires" },
          { to: "BAD", type: "invalid_type" },
        ],
      });
      expect(meta.importance).toBe(0.8);
      expect(meta.difficulty).toBe(0.3);
      expect(meta.estimatedMinutes).toBe(15);
      expect(meta.prerequisites).toEqual(["n1", "n2_b"]);
      // обе связи сохранены; невалидный тип нормализуется в "related"
      expect(meta.relations).toHaveLength(2);
      expect(meta.relations![0].to).toBe("n1");
      expect(meta.relations![0].type).toBe("requires");
      expect(meta.relations![1].to).toBe("BAD");
      expect(meta.relations![1].type).toBe("related");
    });

    it("пропускает невалидные/отсутствующие значения", () => {
      const meta = parseNodeMetadata({ id: "n1", importance: 2.5, difficulty: -1, estimated_time_minutes: 0 });
      expect(meta.importance).toBe(1); // clamp
      expect(meta.difficulty).toBe(0); // clamp
      expect(meta.estimatedMinutes).toBeUndefined();
      expect(meta.prerequisites).toBeUndefined();
      expect(meta.relations).toBeUndefined();
    });
  });

  describe("consistencyCheckAgainstTree", () => {
    const existing = [
      { id: "n1", title: "Тема", parentId: null, level: 1 },
      { id: "n2_a", title: "Основы", parentId: "n1", level: 2 },
    ];
    it("отбрасывает узлы, дублирующие понятия существующего дерева", () => {
      const incoming = [
        { id: "n3_1", title: "Основы", parentId: "n2_a", level: 3 }, // дубль с n2_a
        { id: "n3_2", title: "Детали", parentId: "n2_a", level: 3 },
      ];
      const { nodes, skipped } = consistencyCheckAgainstTree(existing, incoming);
      expect(nodes.map((n) => n.id)).toEqual(["n3_2"]);
      expect(skipped).toBe(1);
    });
    it("отбрасывает коллизии id с существующими узлами", () => {
      const incoming = [
        { id: "n1", title: "Другой", parentId: "n2_a", level: 3 }, // id конфликтует
        { id: "n3_2", title: "Детали", parentId: "n2_a", level: 3 },
      ];
      const { nodes } = consistencyCheckAgainstTree(existing, incoming);
      expect(nodes.map((n) => n.id)).toEqual(["n3_2"]);
    });
  });

  describe("masteryLevelToKnowledgeLevel", () => {
    it("маппит MasteryLevel → KnowledgeLevel", () => {
      expect(masteryLevelToKnowledgeLevel("awareness")).toBe("beginner");
      expect(masteryLevelToKnowledgeLevel("basic_understanding")).toBe("beginner");
      expect(masteryLevelToKnowledgeLevel("solid_understanding")).toBe("intermediate");
      expect(masteryLevelToKnowledgeLevel("advanced")).toBe("expert");
      expect(masteryLevelToKnowledgeLevel("unknown")).toBeUndefined();
    });
  });

  describe("mergeRepairs", () => {
    const draft = (id: string, title: string, parentId: string | null, level: number): NodeDraft => ({
      id,
      title,
      parentId,
      level,
    });

    it("сохраняет проблемный узел (корень), если repair не вернул замену", () => {
      // валидация пометила корень, repair вернул только исправленных детей
      const nodes = [
        draft("n1_root", "Тема", null, 1),
        draft("n2_a", "Раздел A", "n1_root", 2),
        draft("n2_b", "Раздел B", "n1_root", 2),
      ];
      const repaired = [
        draft("n2_a", "Раздел A (испр.)", "n1_root", 2),
        draft("n2_b", "Раздел B (испр.)", "n1_root", 2),
      ];
      const out = mergeRepairs(nodes, repaired);
      expect(out.map((n) => n.id)).toEqual(["n1_root", "n2_a", "n2_b"]);
      // корень сохранён
      const root = out.find((n) => n.id === "n1_root");
      expect(root).toBeDefined();
      expect(root!.title).toBe("Тема");
      // исправленные дети заменены
      expect(out.find((n) => n.id === "n2_a")!.title).toBe("Раздел A (испр.)");
    });

    it("не создаёт сирот: дети не остаются без родителя после merge", () => {
      const nodes = [
        draft("n1_root", "Тема", null, 1),
        draft("n2_a", "Раздел A", "n1_root", 2),
      ];
      const repaired = [draft("n2_a", "Раздел A (испр.)", "n1_root", 2)];
      const out = mergeRepairs(nodes, repaired);
      const child = out.find((n) => n.id === "n2_a")!;
      expect(child.parentId).toBe("n1_root");
      expect(out.some((n) => n.id === child.parentId)).toBe(true);
    });

    it("заменяет узел исправленной версией с тем же id и добавляет новые узлы", () => {
      const nodes = [
        draft("n1_root", "Тема", null, 1),
        draft("n2_a", "Раздел A", "n1_root", 2),
      ];
      const repaired = [
        draft("n1_root", "Тема (испр.)", null, 1),
        draft("n3_x", "Новый узел", "n1_root", 3),
      ];
      const out = mergeRepairs(nodes, repaired);
      expect(out.find((n) => n.id === "n1_root")!.title).toBe("Тема (испр.)");
      expect(out.map((n) => n.id)).toContain("n3_x");
      expect(out).toHaveLength(3);
    });
  });

  describe("deterministicValidate", () => {
    const node = (id: string, title: string, extra: Partial<NodeDraft> = {}): NodeDraft => ({
      id,
      title,
      parentId: null,
      level: 1,
      ...extra,
    });

    it("пустое и одноуровневое дерево — без находок", () => {
      expect(deterministicValidate([]).hardIssues).toEqual([]);
      expect(deterministicValidate([]).notes).toEqual([]);
      const one = deterministicValidate([node("n1", "Тема")]);
      expect(one.hardIssues).toEqual([]);
      expect(one.notes).toEqual([]);
    });

    it("ловит точный дубликат и помечает второй узел пары", () => {
      const nodes = [
        node("a", "Раздел A"),
        node("b", "Раздел B"),
        node("c", "Раздел A"),
      ];
      const { hardIssues, notes } = deterministicValidate(nodes);
      expect(notes).toEqual([]);
      expect(hardIssues).toHaveLength(1);
      expect(hardIssues[0].type).toBe("DUPLICATE");
      expect(hardIssues[0].node_id).toBe("c");
      expect(hardIssues[0].reason).toContain("совпадает с a");
    });

    it("нормализует регистр/пробелы при сравнении подписей", () => {
      const nodes = [
        node("a", "  Раздел   A "),
        node("b", "раздел a"),
      ];
      const { hardIssues } = deterministicValidate(nodes);
      expect(hardIssues).toHaveLength(1);
      expect(hardIssues[0].node_id).toBe("b");
    });

    it("«разные слова» дубликатом не считает (семантика — за LLM)", () => {
      const nodes = [
        node("a", "Транспорт"),
        node("b", "Логистика"),
      ];
      expect(deterministicValidate(nodes).hardIssues).toEqual([]);
    });

    it("MISSING_PREREQUISITE — note, а не hardIssue", () => {
      const nodes = [
        node("a", "Тема", {
          relations: [{ from: "a", to: "ghost", type: "requires" }],
        }),
        node("b", "Раздел", {
          prerequisites: ["ghost2"],
        }),
      ];
      const { hardIssues, notes } = deterministicValidate(nodes);
      expect(hardIssues).toEqual([]);
      expect(notes.some((n) => n.startsWith("MISSING_PREREQUISITE узел a"))).toBe(true);
      expect(notes.some((n) => n.startsWith("MISSING_PREREQUISITE узел b"))).toBe(true);
    });

    it("CIRCULAR_DEPENDENCY ловит цикл depends_on+enables, но не related/example_of", () => {
      const nodes = [
        node("a", "A", { relations: [{ from: "a", to: "b", type: "depends_on" }] }),
        node("b", "B", { relations: [{ from: "b", to: "a", type: "enables" }] }),
        node("c", "C", { relations: [{ from: "c", to: "a", type: "related" }] }),
      ];
      const { hardIssues, notes } = deterministicValidate(nodes);
      expect(hardIssues).toEqual([]);
      expect(notes.some((n) => n.startsWith("CIRCULAR_DEPENDENCY"))).toBe(true);
      expect(notes.some((n) => n.includes("c → a"))).toBe(false);
    });

    it("UNREALISTIC_TIMING: порог 120 минут (включительно)", () => {
      const ok = deterministicValidate([node("a", "A", { estimatedMinutes: 120 })]);
      expect(ok.notes).toEqual([]);
      const bad = deterministicValidate([node("b", "B", { estimatedMinutes: 121 })]);
      expect(bad.notes.some((n) => n.startsWith("UNREALISTIC_TIMING"))).toBe(true);
    });

    it("порядок находок стабилен между прогонами", () => {
      const nodes = [
        node("a", "Раздел", {
          relations: [{ from: "a", to: "b", type: "depends_on" }],
          estimatedMinutes: 200,
        }),
        node("b", "Раздел", {
          relations: [{ from: "b", to: "a", type: "enables" }],
        }),
        node("c", "Раздел"),
      ];
      const first = deterministicValidate(nodes);
      const second = deterministicValidate(nodes);
      expect(first.hardIssues).toEqual(second.hardIssues);
      expect(first.notes).toEqual(second.notes);
    });

    it("fallbackStructure не даёт находок", () => {
      const { hardIssues, notes } = deterministicValidate(fallbackStructure("Тема"));
      expect(hardIssues).toEqual([]);
      expect(notes).toEqual([]);
    });

    it("рёбра на несуществующие узлы не создают циклов (их ловит MISSING_PREREQUISITE)", () => {
      const nodes = [
        node("a", "A", { relations: [{ from: "a", to: "ghost", type: "requires" }] }),
      ];
      const { notes } = deterministicValidate(nodes);
      expect(notes.some((n) => n.startsWith("CIRCULAR_DEPENDENCY"))).toBe(false);
    });
  });
  // Регресс: deterministicValidate помечает совпадающие нормализованные подписи
  // как DUPLICATE, но автоматического фиксера у такой находки не было —
  // dedupeNodeIds искал «уже существующий» узел по id, а у дублей подписей id
  // разные. На живом прогоне «Алгоритмы адаптивной оптимизации» доезжали до
  // пользователя дважды.
  describe("dedupeNodeIds: схлопывание дублей подписей", () => {
    const node = (id: string, title: string, extra: Partial<NodeDraft> = {}): NodeDraft => ({
      id,
      title,
      parentId: null,
      level: 1,
      ...extra,
    });

    it("дубли среди сиблингов схлопываются по нормализованной подписи", () => {
      const out = dedupeNodeIds([
        node("n1", "Корень"),
        node("n2_1", "Основы", { parentId: "n1", level: 2 }),
        node("n2_2", "  основы  ", { parentId: "n1", level: 2 }),
        node("n2_3", "Применение", { parentId: "n1", level: 2 }),
      ]);
      expect(out.map((n) => n.id)).toEqual(["n1", "n2_1", "n2_3"]);
      expect(out[1].title).toBe("Основы");
    });

    it("ребёнок поглощённого узла переподчиняется, а не осиротевает", () => {
      const out = dedupeNodeIds([
        node("n1", "Корень"),
        node("n2_1", "Основы", { parentId: "n1", level: 2 }),
        node("n2_2", "основы", { parentId: "n1", level: 2 }),
        node("n3_1", "Часть", { parentId: "n2_2", level: 3 }),
      ]);
      expect(out.find((n) => n.id === "n3_1")?.parentId).toBe("n2_1");
      const ids = new Set(out.map((n) => n.id));
      for (const n of out) {
        if (n.parentId !== null) expect(ids.has(n.parentId)).toBe(true);
      }
    });

    it("relations и prerequisites на поглощённый узел перенаправляются", () => {
      const out = dedupeNodeIds([
        node("n1", "Корень"),
        node("n2_1", "Основы", { parentId: "n1", level: 2 }),
        node("n2_2", "основы", { parentId: "n1", level: 2 }),
        node("n2_3", "Применение", {
          parentId: "n1",
          level: 2,
          relations: [{ from: "n2_3", to: "n2_2", type: "related" }],
          prerequisites: ["n2_2"],
        }),
      ]);
      const n = out.find((x) => x.id === "n2_3")!;
      expect(n.relations?.[0].to).toBe("n2_1");
      expect(n.prerequisites).toEqual(["n2_1"]);
    });

    it("одинаковые подписи в РАЗНЫХ ветвях не сливаются", () => {
      const out = dedupeNodeIds([
        node("n1", "Корень"),
        node("n2_1", "Оптимизация", { parentId: "n1", level: 2 }),
        node("n3_1", "Оптимизация", { parentId: "n2_1", level: 3 }),
      ]);
      expect(out.map((n) => n.id)).toEqual(["n1", "n2_1", "n3_1"]);
    });

    it("пустая подпись и разный уровень дублем не считаются", () => {
      const out = dedupeNodeIds([
        node("n1", "Корень"),
        node("n2_1", "", { parentId: "n1", level: 2 }),
        node("n2_2", "", { parentId: "n1", level: 2 }),
        node("n2_3", "Основы", { parentId: "n1", level: 2 }),
        node("n2_4", "Основы", { parentId: "n1", level: 3 }),
      ]);
      expect(out.map((n) => n.id)).toEqual(["n1", "n2_1", "n2_2", "n2_3", "n2_4"]);
    });
  });

  // Регресс: циклы ловились только как note и доезжали до пользователя с
  // готовым деревом (на живом прогоне n2_1 → n2_2 → n2_1 и
  // n2_2 → n2_3 → n2_2), а repair не запускался вовсе — он не умеет чинить
  // связи, участники цикла обычно не дефектны.
  describe("breakDependencyCycles", () => {
    const node = (id: string, title: string, extra: Partial<NodeDraft> = {}): NodeDraft => ({
      id,
      title,
      parentId: null,
      level: 1,
      ...extra,
    });

    const dep = (from: string, to: string) =>
      ({ from, to, type: "depends_on" as const });

    it("обратное ребро удаляется, остальные связи цикла сохраняются", () => {
      const broken = breakDependencyCycles([
        node("n1", "Корень", { relations: [dep("n1", "n2_1")] }),
        node("n2_1", "A", {
          parentId: "n1", level: 2, relations: [dep("n2_1", "n2_2")],
        }),
        node("n2_2", "B", {
          parentId: "n1", level: 2, relations: [dep("n2_2", "n2_1")],
        }),
      ]);
      expect(broken.notes).toHaveLength(1);
      expect(broken.notes[0]).toContain("CIRCULAR_DEPENDENCY разорван");
      const a = broken.nodes.find((n) => n.id === "n2_1")!;
      const b = broken.nodes.find((n) => n.id === "n2_2")!;
      expect(a.relations).toHaveLength(1);
      expect(b.relations).toHaveLength(0);
      const stillCyclic = deterministicValidate(broken.nodes).notes
        .filter((n) => n.startsWith("CIRCULAR_DEPENDENCY"));
      expect(stillCyclic).toEqual([]);
    });

    it("петля узла на себя разрывается", () => {
      const broken = breakDependencyCycles([
        node("n1", "A", { relations: [dep("n1", "n1")] }),
      ]);
      expect(broken.nodes[0].relations).toHaveLength(0);
      expect(broken.notes[0]).toContain("n1 → n1");
    });

    it("цикл из related/contrasts_with не трогается", () => {
      const nodes = [
        node("n1", "A", { relations: [{ from: "n1", to: "n2", type: "related" }] }),
        node("n2", "B", { relations: [{ from: "n2", to: "n1", type: "related" }] }),
      ];
      const broken = breakDependencyCycles(nodes);
      expect(broken.notes).toEqual([]);
      expect(broken.nodes).toBe(nodes);
    });

    it("ациклический граф не меняется", () => {
      const nodes = [
        node("n1", "Корень"),
        node("n2_1", "A", {
          parentId: "n1", level: 2, relations: [dep("n2_1", "n2_2")],
        }),
        node("n2_2", "B", { parentId: "n1", level: 2 }),
      ];
      const broken = breakDependencyCycles(nodes);
      expect(broken.nodes).toBe(nodes);
      expect(broken.notes).toEqual([]);
    });

    it("ссылки на несуществующие узлы игнорируются (их ловит пре-пасс)", () => {
      const nodes = [
        node("n1", "A", { relations: [dep("n1", "нет_такого")] }),
      ];
      const broken = breakDependencyCycles(nodes);
      expect(broken.notes).toEqual([]);
      expect(broken.nodes[0].relations).toHaveLength(1);
    });
  });
});
// Регрессии безопасной обрезки `one_liner` (инвариант AGENTS.md: <= 120).
//
// Исходный дефект: обрезка по границе слова оставляла висящие служебные слова —
// «описание прямого и обратного процессов как», «сигнала x̂_0, предсказание».
// Слово целое, синтаксис разрушен; пользователь видел это в экспорте темы
// (`TopicFile.ts`).
//
// Этими же тестами были зафиксированы и два последующих дефекта (теперь
// исправлены в проде):
//  1. обрезка по границе предложения теряла завершающий знак — теперь `.`/`!`/`?`
//     входит в результат;
//  2. результат мог оказаться пустым (вход из одной пунктуации) — теперь
//     гарантированно непустой; НЕ покрыт случай, когда тело куска состоит
//     только из пробелов (см. тест с пробелами ниже);
//  3. жёсткий срез (внутри лимита нет ни одной границы) больше не снимает
//     пунктуацию с хвоста.
//
// Тесты детерминированные: LLM не участвует, вход → ожидаемый вывод. Логика
// обрезки в тесте НЕ дублируется — проверяется экспорт движка.
// Зеркало Dart-тестов: mindtree_flutter/test/domain/one_liner_truncation_test.dart.
// Таблица GOLDEN продублирована там 1:1 (x̂ записан escape-последовательностью
// из-за комбинирующего знака) — расхождение означает разъезд стеков.
//
// Асимметрия зеркала: `enforceOneLinerLimit` в TS не экспортируется, поэтому
// соответствующие два теста есть только в Dart-файле.
describe("truncateOneLiner: безопасная обрезка one_liner", () => {
  /** Порог пригодности границы: 60% лимита. Границы раньше порога игнорируются,
   * обрезка идёт дальше по тексту (иначе фраза стала бы нечитаемой). */
  const BOUNDARY_FLOOR = Math.floor(ONELINER_MAX_CHARS * 0.6);

  // --- Фикстуры ------------------------------------------------------------

  /** Описание, из которого на живом прогоне остался хвост «…процессов как». */
  const DANGLING_HEAD =
    "Ключевая идея состоит в описании прямого и обратного процессов преобразования сигнала во времени";

  /** Длинный «токен» после хвоста: внутри лимита нет ни границ, ни пробелов. */
  const LONG_TOKEN = "псевдослучайнойпоследовательности";

  /** Регресс из бага целиком: сразу после `как` идёт длинное слово, поэтому
   * граница слова съедает ровно «… как». */
  const DANGLING_TAIL_BUG = `${DANGLING_HEAD} как ${LONG_TOKEN} и применение в теории сигналов`;

  /** Регресс «сигнала x̂_0, предсказание»: запятая перед последним словом.
   * x̂ = x + U+0302 (x-hat), escape — чтобы литерал не зависел от NFC редактора. */
  const SIGNAL_BUG =
    "Практика показывает что средняя ошибка оценки сигнала x̂_0 зависит от длины выборки, предсказание достигается обучением на длинных последовательностях";

  /** Граница клаузы (запятая на позиции 95) важнее границы слова (пробел на 119). */
  const CLAUSE_BUG =
    "Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу, добавляя шум на каждом шаге обучения";

  /** Тот же текст без запятой: остаётся только граница слова. */
  const WORD_ONLY =
    "Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу добавляя шум на каждом шаге обучения";

  /** Полное предложение с точкой; после него — ещё текст без точек. */
  const SENTENCE_FIRST =
    "Теорема остановки говорит, что любая детерминированная программа рано или поздно остановится.";
  const SENTENCE_TAIL =
    " Применяется к автоматам, стековым машинам и всей теории вычислимости";
  const SENTENCE_BUG = `${SENTENCE_FIRST}${SENTENCE_TAIL}`;

  /** То же предложение без завершающего знака — тело для знаков `.`/`!`/`?`. */
  const SENTENCE_BODY = SENTENCE_FIRST.slice(0, SENTENCE_FIRST.length - 1);

  /** Хвост из служебного союза и приклеенного тире: «…остановится— и применяется». */
  const DASH_TAIL =
    "Теорема остановки это утверждение о том что любая детерминированная программа рано или поздно остановится— и применяется к автоматам";

  /** Ранняя точка (позиция 6 — ниже порога) игнорируется: режем по последнему
   * пробелу, а висящий предлог «на» с хвоста снимается. */
  const EARLY_SENTENCE =
    "Кратко. Диффузионная модель постепенно учится восстанавливать исходную картинку по зашумлённому сигналу и обучается на шуме";

  /** Основа для каскада: заканчивается точкой «… слово и как.». */
  const CASCADE_HEAD =
    "Базовое определение термина фиксирует минимальный набор требований к описанию предмета";
  const CASCADE_TAIL = " Далее идут уточнения и примеры применения в задачах";

  /** Каскад со знаком конца: снимаются оба служебных слова, знак сохраняется. */
  const CASCADE_DOT = `${CASCADE_HEAD} слово и как.${CASCADE_TAIL}`;

  /** Каскад с запятой: знак клаузы — висящая пунктуация, он снимается и НЕ
   * восстанавливается (в отличие от знака конца предложения). */
  const CASCADE_COMMA = `${CASCADE_HEAD} слово и как,${CASCADE_TAIL}`;

  /** Шапка жёсткого среза: последний пробел на позиции 71 — ниже порога
   * пригодности границы, поэтому внутри лимита не остаётся ни одной границы. */
  const HARD_CUT_HEAD =
    "Описание понятия задаёт базовый смысл темы и требует понимания причин и ";

  /** Токен без пробелов, дотягивающийся до последнего символа лимита. */
  const HARD_CUT_TOKEN =
    "псевдослучайнаяпоследовательностьсгенерированнаяскрытымсостоянием";

  const HARD_CUT_BUG = `${HARD_CUT_HEAD}${HARD_CUT_TOKEN} хвост`;

  /** Тот же жёсткий срез, у которого последний символ внутри лимита — [tailMark].
   * Знак стоит ровно на позиции 119: он уже не образует границу (следующего
   * пробела внутри лимита нет), но раньше снимался как хвостовая пунктуация. */
  function hardCutWith(tailMark: string): string {
    const tokenBase = "псевдослучайнаяпоследовательность_";
    const token = tokenBase.padEnd(ONELINER_MAX_CHARS - HARD_CUT_HEAD.length - 1, "я");
    return `${HARD_CUT_HEAD}${token}${tailMark} хвост`;
  }

  /** Знаки конца предложения: в отличие от клаузной пунктуации они входят
   * в результат. */
  const TERMINAL_MARKS = [".", "!", "?"];

  /** Пунктуация, которая не должна оставаться в хвосте никогда. */
  const DANGLING_PUNCT_CHARS = [
    ",", ";", ":", "—", "–", "-", " ", "»", ")", "]", "'", '"',
  ];

  /** Служебные слова, которые не должны оказываться перед знаком конца. */
  const SERVICE_TAIL_WORDS = [
    "как", "и", "в", "во", "на", "по", "за", "от", "до", "об", "о", "у", "к",
    "ко", "с", "со", "для", "при", "через", "а", "но", "же", "бы", "то", "ли",
    "что", "чтобы", "так", "тем", "где", "не", "ни", "да",
  ];

  /** Фикстуры для «свойственных» проверок (инварианты, а не конкретный текст). */
  const FIXTURES = [
    DANGLING_TAIL_BUG,
    SIGNAL_BUG,
    CLAUSE_BUG,
    WORD_ONLY,
    SENTENCE_BUG,
    CASCADE_DOT,
    CASCADE_COMMA,
    DASH_TAIL,
    EARLY_SENTENCE,
    HARD_CUT_BUG,
    "Короткое описание темы.",
  ];

  /** Строка ровно [length] символов из обычных слов: ни границ, ни служебных
   * хвостов — для чистой проверки инварианта длины. */
  function ofLength(length: number): string {
    let s = "тема";
    let i = 0;
    while (s.length < length) {
      s = `${s} часть${i}`;
      i++;
    }
    if (s.length > length) {
      const head = s.slice(0, length);
      const lastSpace = head.lastIndexOf(" ");
      s = lastSpace > 0 ? head.slice(0, lastSpace) : head;
    }
    while (s.length < length) {
      s = `${s}я`;
    }
    return s;
  }

  /** Золотая таблица: [вход, ожидаемый результат]. Продублирована в
   * mindtree_flutter/test/domain/one_liner_truncation_test.dart. */
  const GOLDEN: Array<[string, string]> = [
    [DANGLING_TAIL_BUG, DANGLING_HEAD],
    [
      SIGNAL_BUG,
      "Практика показывает что средняя ошибка оценки сигнала x̂_0 зависит от длины выборки",
    ],
    [
      CLAUSE_BUG,
      "Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу",
    ],
    [
      WORD_ONLY,
      "Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу добавляя шум на каждом",
    ],
    [SENTENCE_BUG, SENTENCE_FIRST],
    [CASCADE_DOT, `${CASCADE_HEAD} слово.`],
    [CASCADE_COMMA, `${CASCADE_HEAD} слово`],
    [
      DASH_TAIL,
      "Теорема остановки это утверждение о том что любая детерминированная программа рано или поздно остановится",
    ],
    [
      EARLY_SENTENCE,
      "Кратко. Диффузионная модель постепенно учится восстанавливать исходную картинку по зашумлённому сигналу и обучается",
    ],
    [HARD_CUT_BUG, HARD_CUT_BUG.slice(0, ONELINER_MAX_CHARS)],
    [",".repeat(ONELINER_MAX_CHARS + 1), ",".repeat(ONELINER_MAX_CHARS - 1)],
    [hardCutWith(";"), hardCutWith(";").slice(0, ONELINER_MAX_CHARS)],
    ["Короткое описание темы.", "Короткое описание темы."],
  ];

  describe("инвариант длины", () => {
    it("результат всегда <= ONELINER_MAX_CHARS на разной длине входа", () => {
      for (const length of [100, 119, 120, 121, 200, 500]) {
        expect(truncateOneLiner(ofLength(length)).length).toBeLessThanOrEqual(
          ONELINER_MAX_CHARS,
        );
      }
    });

    it("результат <= ONELINER_MAX_CHARS на каждой длине от 0 до 520", () => {
      for (let length = 0; length <= 520; length++) {
        expect(
          truncateOneLiner(ofLength(length)).length,
        ).toBeLessThanOrEqual(ONELINER_MAX_CHARS);
      }
    });

    it("результат — префикс входа и без хвостовых пробелов", () => {
      for (let length = 0; length <= 520; length++) {
        const input = ofLength(length);
        const out = truncateOneLiner(input);
        expect(input.startsWith(out)).toBe(true);
        expect(out).toBe(out.trimEnd());
      }
    });

    it("лимит соблюдается для любого переданного maxChars", () => {
      const input = ofLength(400);
      for (const maxChars of [0, 1, 10, 30, 60, 72, 100, 120, 200]) {
        expect(truncateOneLiner(input, maxChars).length).toBeLessThanOrEqual(
          maxChars,
        );
      }
    });

    it("знак конца не выводит результат за лимит", () => {
      // Гарантия `finalizeTruncation`: знак дописывается только при
      // out.length + 1 <= maxChars. Отрицательная ветка математически
      // недостижима (тело обрезки всегда короче лимита хотя бы на символ,
      // чистка только укорачивает), поэтому проверяем сам инвариант.
      for (const fixture of FIXTURES) {
        for (let maxChars = 0; maxChars <= 200; maxChars++) {
          const out = truncateOneLiner(fixture, maxChars);
          expect(out.length).toBeLessThanOrEqual(maxChars);
          if (out.length > 0 && TERMINAL_MARKS.includes(out[out.length - 1])) {
            expect(out.slice(0, -1).trim().length).toBeGreaterThan(0);
          }
        }
      }
    });

    it("повторный вызов ничего не меняет", () => {
      for (const fixture of FIXTURES) {
        const once = truncateOneLiner(fixture);
        expect(truncateOneLiner(once)).toBe(once);
      }
    });
  });

  describe("короткие входы не обрезаются", () => {
    it("предложение короче лимита возвращается без изменений", () => {
      const input = "Диффузионная модель восстанавливает картинку из шума шаг за шагом.";
      expect(input.length).toBeLessThan(ONELINER_MAX_CHARS);
      expect(truncateOneLiner(input)).toBe(input);
    });

    it("строка ровно в 120 символов не обрезается", () => {
      const input = ofLength(120);
      expect(input).toHaveLength(ONELINER_MAX_CHARS);
      expect(truncateOneLiner(input)).toBe(input);
    });

    it("строка в 120 символов с хвостом «как» тоже не трогается", () => {
      // Чистка хвоста — часть процесса усечения; без обрезки не вмешиваемся.
      const input = `${WORD_ONLY.slice(0, ONELINER_MAX_CHARS - 4)} как`;
      expect(input).toHaveLength(ONELINER_MAX_CHARS);
      expect(input.endsWith("как")).toBe(true);
      expect(truncateOneLiner(input)).toBe(input);
    });

    it("пустая строка и строка из пробелов не падают", () => {
      expect(truncateOneLiner("")).toBe("");
      expect(truncateOneLiner("   ")).toBe("   ");
    });
  });

  describe("выбор границы", () => {
    it("граница предложения важнее границы слова, знак конца входит в результат", () => {
      const out = truncateOneLiner(SENTENCE_BUG);
      expect(out).toBe(SENTENCE_FIRST);
      expect(out.endsWith("остановится.")).toBe(true);
      expect(out.length).toBeLessThan(ONELINER_MAX_CHARS);
    });

    for (const mark of TERMINAL_MARKS) {
      it(`обрезка по границе предложения сохраняет знак «${mark}»`, () => {
        const input = `${SENTENCE_BODY}${mark}${SENTENCE_TAIL}`;
        const out = truncateOneLiner(input);
        expect(out).toBe(`${SENTENCE_BODY}${mark}`);
        expect(out.endsWith(mark)).toBe(true);
        expect(out).toHaveLength(SENTENCE_BODY.length + 1);
        expect(out.length).toBeLessThanOrEqual(ONELINER_MAX_CHARS);
      });
    }

    it("граница предложения важнее границы клаузы", () => {
      const out = truncateOneLiner(SENTENCE_BUG);
      const commaInTail = SENTENCE_BUG.indexOf(",", SENTENCE_FIRST.length);
      expect(commaInTail).toBeGreaterThan(BOUNDARY_FLOOR);
      expect(out.length).toBeLessThan(commaInTail);
    });

    it("граница клаузы важнее границы слова", () => {
      const commaAt = CLAUSE_BUG.indexOf(",");
      expect(commaAt).toBeGreaterThan(BOUNDARY_FLOOR);
      expect(CLAUSE_BUG.slice(0, ONELINER_MAX_CHARS).lastIndexOf(" ")).toBe(119);
      const out = truncateOneLiner(CLAUSE_BUG);
      expect(out).toBe(CLAUSE_BUG.slice(0, commaAt));
      expect(out.endsWith("сигналу")).toBe(true);
      expect(out.length).toBeLessThan(119);
    });

    it("при отсутствии границ обрезка идёт по последнему пробелу", () => {
      const lastSpace = WORD_ONLY.slice(0, ONELINER_MAX_CHARS).lastIndexOf(" ");
      expect(lastSpace).toBeGreaterThan(BOUNDARY_FLOOR);
      expect(truncateOneLiner(WORD_ONLY)).toBe(
        "Диффузионная модель учится постепенно восстанавливать исходную картинку по зашумлённому сигналу добавляя шум на каждом",
      );
      expect(truncateOneLiner(WORD_ONLY)).toHaveLength(lastSpace);
    });

    it("ранняя точка (ниже порога) игнорируется", () => {
      expect(EARLY_SENTENCE.indexOf(".")).toBeLessThanOrEqual(BOUNDARY_FLOOR);
      const out = truncateOneLiner(EARLY_SENTENCE);
      expect(out).toBe(
        "Кратко. Диффузионная модель постепенно учится восстанавливать исходную картинку по зашумлённому сигналу и обучается",
      );
      // Точка внутри строки остаётся: граница предложения здесь не выбрана.
      expect(out.startsWith("Кратко. ")).toBe(true);
      // Хвост «…на шуме» срезан по пробелу, висящий предлог «на» снят.
      expect(out.endsWith(" на")).toBe(false);
    });

    it("жёсткий срез по лимиту, если после порога нет ни границ, ни пробелов", () => {
      expect(HARD_CUT_BUG.slice(0, ONELINER_MAX_CHARS).lastIndexOf(" ")).toBe(71);
      expect(BOUNDARY_FLOOR).toBeGreaterThan(71);
      const out = truncateOneLiner(HARD_CUT_BUG);
      expect(out).toHaveLength(ONELINER_MAX_CHARS);
      expect(out).toBe(HARD_CUT_BUG.slice(0, ONELINER_MAX_CHARS));
    });

    for (const mark of [";", ":", "»", ")", "—"]) {
      it(`жёсткий срез сохраняет знак «${mark}» на хвосте`, () => {
        const input = hardCutWith(mark);
        expect(input.slice(0, ONELINER_MAX_CHARS).lastIndexOf(" ")).toBe(71);
        const out = truncateOneLiner(input);
        expect(out).toBe(input.slice(0, ONELINER_MAX_CHARS));
        expect(out.endsWith(mark)).toBe(true);
        expect(out).toHaveLength(ONELINER_MAX_CHARS);
      });
    }
  });

  describe("висящие служебные слова и пунктуация", () => {
    it("регресс: «…процессов как» — хвост «как» снят", () => {
      const out = truncateOneLiner(DANGLING_TAIL_BUG);
      expect(out).toBe(DANGLING_HEAD);
      expect(out.endsWith("как")).toBe(false);
      expect(out.endsWith(" как")).toBe(false);
      expect(out.length).toBeLessThanOrEqual(ONELINER_MAX_CHARS);
    });

    it("регресс: «сигнала x̂_0, предсказание» — хвост снят по запятой", () => {
      const out = truncateOneLiner(SIGNAL_BUG);
      expect(out).toBe(SIGNAL_BUG.slice(0, SIGNAL_BUG.indexOf(",")));
      expect(out.endsWith("предсказание")).toBe(false);
      expect(out.endsWith("выборки")).toBe(true);
    });

    for (const punct of TERMINAL_MARKS) {
      it(`каскад «… слово и как${punct}»: оба слова сняты, знак сохранён`, () => {
        const input = `${CASCADE_HEAD} слово и как${punct}${CASCADE_TAIL}`;
        const out = truncateOneLiner(input);
        expect(out).toBe(`${CASCADE_HEAD} слово${punct}`);
        expect(out.endsWith("как")).toBe(false);
        expect(out.endsWith(" и")).toBe(false);
        expect(out.endsWith(punct)).toBe(true);
      });
    }

    it("знак клаузы после каскада не восстанавливается", () => {
      const out = truncateOneLiner(CASCADE_COMMA);
      expect(out).toBe(`${CASCADE_HEAD} слово`);
      expect(out.endsWith(",")).toBe(false);
    });

    it("регистр хвоста не важен: «КАК» тоже снимается", () => {
      const input = `${DANGLING_HEAD} КАК ${LONG_TOKEN} и применение`;
      expect(truncateOneLiner(input)).toBe(DANGLING_HEAD);
    });

    it("тире и союз на хвосте снимаются вместе", () => {
      const out = truncateOneLiner(DASH_TAIL);
      expect(out).toBe(
        "Теорема остановки это утверждение о том что любая детерминированная программа рано или поздно остановится",
      );
      expect(out.endsWith("—")).toBe(false);
      expect(out.endsWith(" и")).toBe(false);
    });

    it("обычное слово на хвосте не выбрасывается", () => {
      // Защита от обратной ошибки: чистка не должна съедать содержание.
      const out = truncateOneLiner(WORD_ONLY);
      expect(out.endsWith("каждом")).toBe(true);
      expect(out.length).toBe(118);
      expect(out.length).toBeGreaterThan(BOUNDARY_FLOOR);
    });

    it("хвост не заканчивается клаузной пунктуацией или пробелом", () => {
      // `.`/`!`/`?` — законные знаки конца предложения, их проверяет отдельный
      // тест; в клаузной позиции такая пунктуация снимается всегда.
      for (const fixture of FIXTURES) {
        if (fixture.length <= ONELINER_MAX_CHARS) continue;
        const out = truncateOneLiner(fixture);
        for (const ch of DANGLING_PUNCT_CHARS) {
          expect(out.endsWith(ch), `хвост «${ch}» в «${out}»`).toBe(false);
        }
      }
    });

    it("знак конца предложения не прячет висящее служебное слово", () => {
      const marked = FIXTURES.map((s) => truncateOneLiner(s)).filter(
        (s) => s.length > 0 && TERMINAL_MARKS.includes(s[s.length - 1]),
      );
      expect(marked.length).toBeGreaterThan(0);
      for (const out of marked) {
        const body = out.slice(0, -1);
        const lastSpace = body.lastIndexOf(" ");
        const lastWord = (lastSpace >= 0 ? body.slice(lastSpace + 1) : body).toLowerCase();
        expect(SERVICE_TAIL_WORDS.includes(lastWord), `перед знаком конца висящее слово «${lastWord}» в «${out}»`).toBe(false);
      }
    });
  });

  describe("дегенератные входы и детерминированность", () => {
    it("результат непустой для входа из одной пунктуации", () => {
      const cases: Array<[string, string]> = [
        ["запятые", ",".repeat(ONELINER_MAX_CHARS + 1)],
        ["точки", ".".repeat(ONELINER_MAX_CHARS + 10)],
        ["точки с запятой", ";".repeat(200)],
        ["тире", "—".repeat(200)],
      ];
      for (const [label, input] of cases) {
        const out = truncateOneLiner(input);
        expect(out.length, label).toBeGreaterThan(0);
        expect(out.length, label).toBeLessThanOrEqual(ONELINER_MAX_CHARS);
        expect(input.startsWith(out), label).toBe(true);
      }
      // Запятая — единственный случай, когда кусок короче лимита на символ:
      // граница клаузы съела последнюю запятую, чистка съела всё, и вернулся
      // необработанный кусок.
      expect(truncateOneLiner(",".repeat(ONELINER_MAX_CHARS + 1))).toBe(
        ",".repeat(ONELINER_MAX_CHARS - 1),
      );
      // Точки идут по ветке границы предложения: знак конца возвращается.
      expect(truncateOneLiner(".".repeat(ONELINER_MAX_CHARS + 10))).toBe(
        ".".repeat(ONELINER_MAX_CHARS),
      );
    });

    it("известный пробел: строка из одних пробелов остаётся пустой", () => {
      // Гарантия непустоты не покрывает тело, состоящее только из пробелов:
      // `trimEnd` даёт пустую строку, и fallback не срабатывает. Не-пустота
      // здесь — не инвариант, тест фиксирует фактическое поведение.
      expect(truncateOneLiner(" ".repeat(200))).toBe("");
      expect(truncateOneLiner("\t".repeat(300))).toBe("");
    });

    it("короткий остаток сохраняет смысл, а не выбрасывает текст", () => {
      expect(truncateOneLiner("описание процессов как тут длинный текст", 26)).toBe(
        "описание процессов",
      );
    });

    it("два вызова на одном входе дают идентичный результат", () => {
      for (const fixture of FIXTURES) {
        expect(truncateOneLiner(fixture)).toBe(truncateOneLiner(fixture));
      }
    });

    it("золотая таблица фикстур совпадает с ожиданиями", () => {
      expect(GOLDEN.map(([input]) => truncateOneLiner(input))).toEqual(
        GOLDEN.map(([, expected]) => expected),
      );
    });
  });
});