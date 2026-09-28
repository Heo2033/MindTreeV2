import { describe, it, expect } from "vitest";
import type { KnowledgeNode, Relation, Sequence } from "@mindtree/types";
import {
  ONE_LINER_MAX_LENGTH,
  TOPIC_FILE_FORMAT,
  TOPIC_FILE_VERSION,
  TopicFile,
  TopicFileFormatException,
  flattenNodes,
  nestNodes,
  rescopeNodes,
  validateImport,
  type TopicFileMeta,
} from "../TopicFile.js";
import { scopedSuffix } from "../scopedIds.js";

const SRC_TOPIC = "topic_src_aaaa";

const META: TopicFileMeta = {
  name: "Тема",
  goal: "overview",
  targetLevel: "basic_understanding",
  timeBudgetMinutes: 60,
};

function node(
  id: string,
  parentId: string | null,
  level: number,
  label: string,
  oneLiner = "Краткое определение.",
  relations: Relation[] = [],
  sequences: Sequence[] = [],
): KnowledgeNode {
  return {
    id,
    topicId: "",
    parentId,
    level,
    label,
    oneLiner,
    details: `Подробное описание ${label}.`,
    sources: [],
    importance: 0.5,
    difficulty: 0.5,
    estimatedTimeMinutes: 5,
    state: "new",
    contentLoaded: false,
    leaf: level >= 3,
    relations,
    sequences,
  };
}

/** Дерево из 3 уровней: root -> a -> a1, root -> b. */
function tree3(): KnowledgeNode[] {
  const s = scopedSuffix(SRC_TOPIC);
  return [
    node("n1_root" + s, null, 1, "Корень", "Обзор темы.", [
      { from: "n1_root" + s, to: "n2_a" + s, type: "related", label: "часть" },
    ], [
      {
        id: "seq1",
        label: "Путь",
        steps: [
          { conceptId: "n2_a" + s, order: 0, label: "первый" },
          { conceptId: "n4_b" + s, order: 1, label: "второй" },
        ],
      },
    ]),
    node("n2_a" + s, "n1_root" + s, 2, "Ветка А"),
    node("n3_a1" + s, "n2_a" + s, 3, "Лист А1"),
    node("n4_b" + s, "n1_root" + s, 2, "Ветка Б"),
  ];
}

function fileOf(nodes: KnowledgeNode[], meta: TopicFileMeta = META): TopicFile {
  return new TopicFile({ sourceTopicId: SRC_TOPIC, topic: meta, nodes });
}

/** плоский → JSON → плоский */
function roundTrip(flat: KnowledgeNode[]): KnowledgeNode[] {
  return TopicFile.fromJson(fileOf(flat).toJson()).nodes;
}

describe("TopicFile — round-trip", () => {
  it("плоский → JSON → плоский сохраняет все поля узлов", () => {
    const original = tree3();
    const result = roundTrip(original);

    expect(result).toHaveLength(original.length);
    for (let i = 0; i < original.length; i++) {
      const a = original[i]!;
      const b = result[i]!;
      expect(b.id).toBe(a.id);
      expect(b.parentId).toBe(a.parentId);
      expect(b.level).toBe(a.level);
      expect(b.label).toBe(a.label);
      expect(b.oneLiner).toBe(a.oneLiner);
      expect(b.details).toBe(a.details);
      expect(b.relations).toHaveLength(a.relations.length);
      expect(b.sequences).toHaveLength(a.sequences.length);
    }
  });

  it("relations и sequences переживают round-trip без потерь", () => {
    const result = roundTrip(tree3());
    const root = result[0]!;

    expect(root.relations[0]!.from).toBe(root.id);
    expect(root.relations[0]!.to).toBe(result[1]!.id);
    expect(root.relations[0]!.label).toBe("часть");
    expect(root.sequences[0]!.steps).toHaveLength(2);
    expect(root.sequences[0]!.steps[0]!.conceptId).toBe(result[1]!.id);
    expect(root.sequences[0]!.steps[1]!.conceptId).toBe(result[3]!.id);
  });

  it("в файле дерево вложенное: у корня есть children, у листа пусто", () => {
    const json = fileOf(tree3()).toJson();
    const root = (json.tree as { nodes: Record<string, unknown>[] }).nodes[0]!;
    const children = root.children as Record<string, unknown>[];
    expect(children).toHaveLength(2);

    const leafChild = (children[0]!.children as Record<string, unknown>[])[0]!;
    expect(leafChild.children).toEqual([]);
    expect(leafChild.leaf).toBe(true);
  });

  it("в узлах файла нет topicId / parentId / level — они из вложенности", () => {
    const json = fileOf(tree3()).toJson();
    const root = (json.tree as { nodes: Record<string, unknown>[] }).nodes[0]!;
    expect(root).not.toHaveProperty("topicId");
    expect(root).not.toHaveProperty("parentId");
    expect(root).not.toHaveProperty("level");
  });

  it("конверт несёт format/version/source/topic", () => {
    const json = fileOf(tree3(), { ...META, name: "Математический анализ", timeBudgetMinutes: 90 })
      .toJson();
    expect(json.format).toBe(TOPIC_FILE_FORMAT);
    expect(json.version).toBe(TOPIC_FILE_VERSION);
    expect((json.source as { topicId: string }).topicId).toBe(SRC_TOPIC);
    expect((json.topic as { name: string }).name).toBe("Математический анализ");
    expect((json.topic as { timeBudgetMinutes: number }).timeBudgetMinutes).toBe(90);
  });

  it("toJsonString даёт валидный JSON, читаемый обратно", () => {
    const parsed = TopicFile.fromJsonString(fileOf(tree3()).toJsonString());
    expect(parsed.isValid).toBe(true);
    expect(parsed.nodes).toHaveLength(4);
  });
});

describe("TopicFile — отказ на некорректном файле", () => {
  const wrap = (body: string): string =>
    `{"format":"mindtree.topic","version":1,"source":{"topicId":"t"},"topic":{"name":"X"},${body}}`;

  it("чужой format", () => {
    expect(() => TopicFile.fromJsonString('{"format":"other","version":1}')).toThrow(
      TopicFileFormatException,
    );
  });

  it("версия из будущего", () => {
    expect(() =>
      TopicFile.fromJsonString(
        '{"format":"mindtree.topic","version":999,"topic":{"name":"X"},"tree":{"nodes":[{"id":"a"}]}}',
      ),
    ).toThrow(/999/);
  });

  it("пустое дерево", () => {
    expect(() => TopicFile.fromJsonString(wrap('"tree":{"nodes":[]}'))).toThrow(/tree\.nodes/);
  });

  it("пустое имя темы", () => {
    expect(() =>
      TopicFile.fromJsonString(
        '{"format":"mindtree.topic","version":1,"topic":{"name":"  "},"tree":{"nodes":[{"id":"a"}]}}',
      ),
    ).toThrow(TopicFileFormatException);
  });

  it("не JSON", () => {
    expect(() => TopicFile.fromJsonString("не json вовсе")).toThrow(TopicFileFormatException);
  });
});

describe("validateImport", () => {
  it("корректное дерево — без ошибок", () => {
    expect(validateImport(fileOf(tree3()))).toEqual([]);
  });

  it("два корня — ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const errors = validateImport(fileOf([
      node("a" + s, null, 1, "Первый корень"),
      node("b" + s, null, 1, "Второй корень"),
    ]));
    expect(errors.join(" ")).toContain("корней");
  });

  it("висячий parentId — ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const errors = validateImport(fileOf([
      node("a" + s, null, 1, "Корень"),
      node("b" + s, "нет_такого" + s, 2, "Сирота"),
    ]));
    expect(errors.join(" ")).toContain("родител");
  });

  it("цикл — ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const errors = validateImport(fileOf([
      node("a" + s, "b" + s, 2, "A"),
      node("b" + s, "a" + s, 2, "B"),
    ]));
    expect(errors.length).toBeGreaterThan(0);
  });

  it("дубликаты id — ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const errors = validateImport(fileOf([
      node("a" + s, null, 1, "Корень"),
      node("a" + s, "a" + s, 2, "Дубль"),
    ]));
    expect(errors.join(" ")).toContain("Дублирующиеся id");
  });

  it("пустой label — ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const errors = validateImport(fileOf([
      node("a" + s, null, 1, "Корень"),
      node("b" + s, "a" + s, 2, "   "),
    ]));
    expect(errors.join(" ")).toContain("пустым названием");
  });

  it("one_liner > 120 символов — обрезка и предупреждение, не ошибка", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const parsed = TopicFile.fromJson(fileOf([
      node("a" + s, null, 1, "Корень"),
      node("b" + s, "a" + s, 2, "Ветка", "я".repeat(200)),
    ]).toJson());

    expect(parsed.isValid).toBe(true);
    expect(parsed.warnings.join(" ")).toContain("one_liner");
    expect(parsed.nodes[1]!.oneLiner).toHaveLength(ONE_LINER_MAX_LENGTH);
  });
});

describe("rescopeNodes", () => {
  it("id, parentId, relations и sequences переезжают под новую тему", () => {
    const NEW_TOPIC = "topic_new_bbbb";
    const s = scopedSuffix(SRC_TOPIC);
    const n = scopedSuffix(NEW_TOPIC);
    const result = rescopeNodes(tree3(), SRC_TOPIC, NEW_TOPIC);

    const ids = new Set(result.map((e) => e.id));
    expect([...ids].every((id) => id.endsWith(n))).toBe(true);
    expect(ids.has("n1_root" + n)).toBe(true);
    expect(ids.has("n1_root" + s)).toBe(false);

    // parentId указывает на пере-скоупленный id
    const branch = result.find((e) => e.label === "Ветка А")!;
    expect(ids.has(branch.parentId!)).toBe(true);

    // relations переписаны
    const root = result.find((e) => e.label === "Корень")!;
    expect(ids.has(root.relations[0]!.from)).toBe(true);
    expect(ids.has(root.relations[0]!.to)).toBe(true);

    // sequences.steps[].conceptId переписаны
    for (const st of root.sequences[0]!.steps) {
      expect(ids.has(st.conceptId)).toBe(true);
    }

    // topicId проставлен, уровни сохранены
    expect(result.every((e) => e.topicId === NEW_TOPIC)).toBe(true);
    expect(result.map((e) => e.level)).toEqual([1, 2, 3, 2]);
  });

  it("ссылка на неизвестный узел не роняет и не теряется", () => {
    const s = scopedSuffix(SRC_TOPIC);
    const result = rescopeNodes(
      [node("a" + s, null, 1, "Корень", "Краткое определение.", [
        { from: "a" + s, to: "чужак" + s, type: "related" },
      ])],
      SRC_TOPIC,
      "topic_new_cccc",
    );
    expect(result[0]!.relations[0]!.to).toBe("чужак" + s);
  });

  it("пустой список — пустой результат", () => {
    expect(rescopeNodes([], SRC_TOPIC, "topic_x")).toEqual([]);
  });
});

describe("вложенность как единственный источник правды", () => {
  it("nestNodes группирует детей по parentId, flattenNodes восстанавливает уровни", () => {
    const nested = nestNodes(tree3());
    expect(nested).toHaveLength(1);
    const flat = flattenNodes(nested);
    expect(flat.map((n) => n.level)).toEqual([1, 2, 3, 2]);
    expect(flat[0]!.parentId).toBeNull();
    expect(flat[2]!.parentId).toBe(flat[1]!.id);
  });

  it("узел без id пропускается с предупреждением", () => {
    const warnings: string[] = [];
    const flat = flattenNodes([{ label: "Без id" }], (m) => warnings.push(m));
    expect(flat).toHaveLength(0);
    expect(warnings.join(" ")).toContain("Пропущен узел без id");
  });

  it("неизвестный conceptType не ломает разбор", () => {
    const flat = flattenNodes([{ id: "a", label: "A", conceptType: "выдумка" }]);
    expect(flat[0]!.conceptType).toBeUndefined();
  });
});
