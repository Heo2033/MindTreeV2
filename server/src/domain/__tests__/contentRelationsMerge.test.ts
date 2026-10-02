// Зеркало test/domain/content_relations_merge_test.dart (flutter).
// Контентная стадия не затирает структурные связи и не добавляет выдуманные цели.

import { describe, it, expect } from "vitest";
import type { Relation } from "@mindtree/types";
import { mergeContentRelations } from "../KnowledgeGraphEngine.js";

const SELF = "n2_a~1a2b3c4d";
const KNOWN = new Set(["n1_root~1a2b3c4d", SELF, "n2_b~1a2b3c4d"]);

const rel = (to: string, type = "related", from = SELF): Relation =>
  ({ from, to, type }) as Relation;

const merge = (existing: Relation[] = [], fromContent: unknown[] = []) =>
  mergeContentRelations({ existing, fromContent, nodeId: SELF, knownIds: KNOWN });

describe("mergeContentRelations", () => {
  it("структурные связи сохраняются, даже если контент вернул свои", () => {
    const structural = [
      rel("n1_root~1a2b3c4d", "requires"),
      rel("n2_b~1a2b3c4d", "contrasts_with"),
    ];
    const result = merge(structural, [rel("n9_ghost~deadbeef")]);
    expect(result).toHaveLength(2);
    expect(result.map((r) => r.to)).toEqual(["n1_root~1a2b3c4d", "n2_b~1a2b3c4d"]);
  });

  it("цель вне дерева отбрасывается", () => {
    const result = merge([], [rel("n9_ghost~deadbeef"), rel("n2_b~1a2b3c4d")]);
    expect(result).toHaveLength(1);
    expect(result[0].to).toBe("n2_b~1a2b3c4d");
  });

  it("from принудительно ведёт с текущего узла", () => {
    const result = merge([], [rel("n2_b~1a2b3c4d", "related", "n1_root~1a2b3c4d")]);
    expect(result[0].from).toBe(SELF);
  });

  it("дубликат по (from,to,type) не добавляется дважды", () => {
    const result = merge([rel("n2_b~1a2b3c4d")], [rel("n2_b~1a2b3c4d")]);
    expect(result).toHaveLength(1);
  });

  it("одинаковые цели с разным типом связи сохраняются", () => {
    const result = merge([], [
      rel("n2_b~1a2b3c4d", "related"),
      rel("n2_b~1a2b3c4d", "contrasts_with"),
    ]);
    expect(result).toHaveLength(2);
  });

  it("битый fromContent не роняет слияние", () => {
    const result = merge([rel("n2_b~1a2b3c4d")], [null, {}, { to: 42 }] as unknown[]);
    expect(result).toHaveLength(1);
  });
});
