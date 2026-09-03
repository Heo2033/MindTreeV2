import { describe, it, expect } from "vitest";
import {
  scopeId,
  scopeNodeIds,
  scopedSuffix,
  type NodeDraft,
} from "../scopedIds.js";

describe("scopedIds", () => {
  describe("scopedSuffix", () => {
    it("returns consistent 8-hex-digit suffix with ~", () => {
      const s = scopedSuffix("topic_abc123");
      expect(s).toMatch(/^~[0-9a-f]{8}$/);
      expect(scopedSuffix("topic_abc123")).toBe(s);
    });
    it("different topicId → different suffix", () => {
      expect(scopedSuffix("topic_111")).not.toBe(scopedSuffix("topic_222"));
    });
  });

  describe("scopeId", () => {
    it("appends suffix to raw id", () => {
      const scoped = scopeId("n1_root", "topic_x");
      expect(scoped).toMatch(/^n1_root~[0-9a-f]{8}$/);
    });
    it("is idempotent", () => {
      const first = scopeId("n1_root", "topic_x");
      expect(scopeId(first, "topic_x")).toBe(first);
    });
  });

  describe("scopeNodeIds", () => {
    const topicA = "topic_aaaa1111";
    const topicB = "topic_bbbb2222";
    const suffixA = scopedSuffix(topicA);
    const suffixB = scopedSuffix(topicB);

    const makeTree = (): NodeDraft[] => [
      { id: "n1_root", title: "Тема", parentId: null, level: 1 },
      { id: "n2_child", title: "Раздел", parentId: "n1_root", level: 2 },
      { id: "n2_leaf", title: "Лист", parentId: "n1_root", level: 2 },
    ];

    it("scopes ids, parentId, and relations for a topic", () => {
      const nodes: NodeDraft[] = [
        { id: "n1_root", title: "Тема", parentId: null, level: 1 },
        {
          id: "n2_a",
          title: "A",
          parentId: "n1_root",
          level: 2,
          relations: [
            { from: "n2_a", to: "n2_b", type: "related" },
          ],
        },
        { id: "n2_b", title: "B", parentId: "n1_root", level: 2 },
      ];
      const scoped = scopeNodeIds(nodes, topicA);

      // ids are scoped
      expect(scoped[0].id).toBe(`n1_root${suffixA}`);
      expect(scoped[1].id).toBe(`n2_a${suffixA}`);
      expect(scoped[2].id).toBe(`n2_b${suffixA}`);

      // parentId remapped
      expect(scoped[1].parentId).toBe(`n1_root${suffixA}`);

      // relations remapped (from/to)
      const rel = scoped[1].relations![0] as { from: string; to: string };
      expect(rel.from).toBe(`n2_a${suffixA}`);
      expect(rel.to).toBe(`n2_b${suffixA}`);
    });

    it("produces different scoped ids for different topics", () => {
      const nodes = makeTree();
      const scopedA = scopeNodeIds(nodes, topicA);
      const scopedB = scopeNodeIds(nodes, topicB);

      // Different roots
      expect(scopedA[0].id).not.toBe(scopedB[0].id);
      expect(scopedA[0].id).toContain(suffixA);
      expect(scopedB[0].id).toContain(suffixB);

      // Same-topic coexistence: two topics with same raw ids don't collide
      const allIds = [...scopedA, ...scopedB].map((n) => n.id);
      expect(new Set(allIds).size).toBe(allIds.length);
    });

    it("handles trees with no children (root only)", () => {
      const nodes: NodeDraft[] = [
        { id: "n1_root", title: "Solo", parentId: null, level: 1 },
      ];
      const scoped = scopeNodeIds(nodes, topicA);
      expect(scoped.length).toBe(1);
      expect(scoped[0].id).toBe(`n1_root${suffixA}`);
      expect(scoped[0].parentId).toBeNull();
    });

    it("skips nodes with empty id", () => {
      const nodes: NodeDraft[] = [
        { id: "", title: "Empty", parentId: null, level: 1 },
        { id: "n2_x", title: "X", parentId: "n1_root", level: 2 },
      ];
      const scoped = scopeNodeIds(nodes, topicA);
      expect(scoped.length).toBe(1);
      expect(scoped[0].id).toBe(`n2_x${suffixA}`);
    });

    it("does not remap parentId pointing outside the tree", () => {
      const nodes: NodeDraft[] = [
        { id: "n1_root", title: "Тема", parentId: null, level: 1 },
        { id: "n2_a", title: "A", parentId: "n1_root", level: 2 },
        {
          id: "n2_b",
          title: "B",
          parentId: "external_orphan_id",
          level: 2,
        },
      ];
      const scoped = scopeNodeIds(nodes, topicA);
      // n2_b parentId stays as-is (external, not in node set)
      expect(scoped[2].parentId).toBe("external_orphan_id");
    });

    it("relations to nodes outside tree are left unchanged", () => {
      const nodes: NodeDraft[] = [
        { id: "n1_root", title: "Тема", parentId: null, level: 1 },
        {
          id: "n2_a",
          title: "A",
          parentId: "n1_root",
          level: 2,
          relations: [
            { from: "n2_a", to: "external_id", type: "depends_on" },
          ],
        },
      ];
      const scoped = scopeNodeIds(nodes, topicA);
      const rel = scoped[1].relations![0] as { from: string; to: string };
      expect(rel.from).toBe(`n2_a${suffixA}`);
      expect(rel.to).toBe("external_id");
    });

    it("20 topics with identical raw ids all get unique scoped ids", () => {
      const topics = Array.from({ length: 20 }, (_, i) => `topic_${i}`);
      const allIds = new Set<string>();
      for (const t of topics) {
        const scoped = scopeNodeIds(makeTree(), t);
        for (const n of scoped) {
          expect(allIds.has(n.id)).toBe(false);
          allIds.add(n.id);
        }
      }
    });
  });
});
