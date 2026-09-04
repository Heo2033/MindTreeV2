import { describe, it, expect } from "vitest";
import { buildL2Prompt } from "../generateL2.js";
import { buildL3Prompt } from "../generateL3.js";
import { buildExpandPrompt } from "../expand.js";
import { buildL1Prompt as buildL1 } from "../structure.js";

describe("Step-by-step generation prompts", () => {
  describe("buildL1Prompt", () => {
    it("строит промпт для генерации только корня", () => {
      const p = buildL1("Таро", { goal: "overview", level: "solid_understanding" });
      expect(p).toContain("КОРНЕВОЙ узел");
      expect(p).toContain("Таро");
      expect(p).toContain("semantic_axis");
      expect(p).not.toContain("уровень 2");
    });

    it("включает audience_block и depth_hint", () => {
      const p = buildL1("Х", { goal: "deep", level: "expert" });
      expect(p).toContain("Аудитория");
      expect(p).toContain("Глубина скелета");
    });
  });

  describe("buildL2Prompt", () => {
    it("подставляет корень и требует parentId = root_id", () => {
      const p = buildL2Prompt({
        userQuery: "Таро",
        root: { id: "n1_root", title: "Таро", canonical_definition: "Гадальная система" },
        options: { goal: "overview", level: "beginner" },
      });
      expect(p).toContain("Таро");
      expect(p).toContain("n1_root");
      expect(p).toContain("3–5 узлов");
    });
  });

  describe("buildL3Prompt", () => {
    it("передаёт родителя, сиблингов и критическое правило о дублях", () => {
      const p = buildL3Prompt({
        userQuery: "Таро",
        rootTitle: "Таро",
        parent: { id: "n2_ras", title: "Расклады", canonical_definition: "Способы раскладывания карт" },
        siblings: [
          { id: "n2_hist", title: "История", canonical_definition: "История таро" },
        ],
        options: { goal: "overview" },
      });
      expect(p).toContain("Расклады");
      expect(p).toContain("История");
      expect(p).toContain("Критическое правило о дублях");
      expect(p).toContain("n2_ras");
    });
  });

  describe("buildExpandPrompt", () => {
    it("передаёт полное дерево и настройки аудитории", () => {
      const p = buildExpandPrompt({
        rootTopic: "Таро",
        contextPaths: ["Расклады: Таро → Расклады"],
        nodesToExpand: [{ id: "n2_ras", title: "Расклады", path: "Таро → Расклады" }],
        existingTree: [
          { id: "n1", title: "Таро", parentId: null, level: 1 },
          { id: "n2_ras", title: "Расклады", parentId: "n1", level: 2 },
        ],
        options: { goal: "deep", level: "expert" },
      });
      expect(p).toContain("Уже существующее дерево");
      expect(p).toContain("n2_ras");
      expect(p).toContain("reparent_to");
      expect(p).toContain("Аудитория");
    });
  });
});
