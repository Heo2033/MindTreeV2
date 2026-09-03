import { describe, it, expect } from "vitest";
import {
  fallbackStructure,
  dedupeNodeIds,
  parseNodeMetadata,
  consistencyCheckAgainstTree,
  mergeRepairs,
  type NodeDraft,
} from "../KnowledgeGraphEngine.js";
import { masteryLevelToKnowledgeLevel } from "../../prompts/structure.js";

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
});
