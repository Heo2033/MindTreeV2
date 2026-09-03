import { describe, it, expect } from "vitest";
import { fallbackStructure, dedupeNodeIds } from "../KnowledgeGraphEngine.js";

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
});
