import { describe, it, expect } from "vitest";
import { buildContentPrompt } from "../content.js";

const base = {
  rootTopic: "Диффузионные модели",
  nodePath: ["Диффузионные модели"],
  siblings: [],
  node: { id: "n1", label: "Диффузионные модели" },
};

describe("buildContentPrompt (тон контента от уровня цели)", () => {
  it("без knowledgeLevel — блок «Аудитория» отсутствует (регрессия, когда слали числовой уровень)", () => {
    const prompt = buildContentPrompt(base);
    expect(prompt).not.toContain("# Аудитория");
  });

  it("для beginner — доступный тон без жаргона", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "beginner" });
    expect(prompt).toContain("# Аудитория");
    expect(prompt).toContain("максимально доступно для новичка");
    expect(prompt).toContain("# Антижаргон");
  });

  it("для intermediate — интуиция: «как работает», затем термин", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "intermediate" });
    expect(prompt).toContain("знакомого с основами");
    expect(prompt).toContain("сначала «как работает», затем термин");
    expect(prompt).toContain("# Антижаргон");
  });

  it("для expert — точная терминология и без антижаргона", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "expert" });
    expect(prompt).toContain("точную терминологию");
    expect(prompt).not.toContain("# Антижаргон");
  });

  it("для неизвестного значения — без блока тона (не ломаем)", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "solid_understanding" });
    expect(prompt).not.toContain("# Аудитория");
  });

  it("корневой узел получает блок обзора с интуицией и roadmap", () => {
    const prompt = buildContentPrompt({ ...base, isRoot: true, goal: "deep" });
    expect(prompt).toContain("# Корневой узел");
    expect(prompt).toContain("интуиция");
    expect(prompt).toContain("roadmap");
  });

  it("некорневой узел не получает блок обзора", () => {
    const prompt = buildContentPrompt({ ...base, nodeLevel: 3 });
    expect(prompt).not.toContain("# Корневой узел");
  });

  it("goal=deep добавляет блок цели", () => {
    const prompt = buildContentPrompt({ ...base, goal: "deep" });
    expect(prompt).toContain("# Цель");
    expect(prompt).toContain("глубокое изучение");
  });

  it("intermediate + deep — двухчастная структура «Интуиция + Механика»", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "intermediate", goal: "deep" });
    expect(prompt).toContain("# Структура подробностей");
    expect(prompt).toContain("«Интуиция:»");
    expect(prompt).toContain("«Механика:»");
  });

  it("beginner + deep — тоже двухчастная структура", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "beginner", goal: "deep" });
    expect(prompt).toContain("# Структура подробностей");
  });

  it("expert + deep — без двухчастной структуры (точная терминология)", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "expert", goal: "deep" });
    expect(prompt).not.toContain("# Структура подробностей");
    expect(prompt).not.toContain("# Антижаргон");
  });

  it("deep + intermediate без goal — без двухчастной структуры", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "intermediate", goal: "overview" });
    expect(prompt).not.toContain("# Структура подробностей");
  });

  it("корневой узел получает запрет голых формул", () => {
    const prompt = buildContentPrompt({ ...base, isRoot: true });
    expect(prompt).toContain("# Формулы на корневом узле");
  });

  it("некорневой узел не получает запрет формул", () => {
    const prompt = buildContentPrompt({ ...base, nodeLevel: 3 });
    expect(prompt).not.toContain("# Формулы на корневом узле");
  });

  it("hard-антижаргон требует объяснять термин в том же предложении", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "intermediate" });
    expect(prompt).toContain("КАЖДЫЙ специальный термин");
    expect(prompt).toContain("ЗАПРЕЩЕНО использовать термин");
  });
});

describe("buildContentPrompt (контракт ответа от 02.10.2026)", () => {
  it("не просит генерировать relations: id других узлов модели неизвестны", () => {
    const prompt = buildContentPrompt({ ...base, knowledgeLevel: "intermediate" });
    expect(prompt).toContain('"relations": []');
    expect(prompt).not.toContain("id_другого_узла");
    expect(prompt).not.toContain("id_этого_узла");
  });

  it("non-expert получает блок сложности, expert — нет", () => {
    const beginner = buildContentPrompt({ ...base, knowledgeLevel: "beginner" });
    expect(beginner).toContain("# Сложность");
    expect(beginner).toContain("расшифруй");

    const expert = buildContentPrompt({ ...base, knowledgeLevel: "expert" });
    expect(expert).not.toContain("# Сложность");
  });

  it("фактическая дисциплина есть на любом уровне", () => {
    for (const level of ["beginner", "intermediate", "expert"]) {
      const prompt = buildContentPrompt({ ...base, knowledgeLevel: level });
      expect(prompt).toContain("# Фактическая дисциплина");
    }
  });
});
