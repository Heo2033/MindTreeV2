import { describe, it, expect } from "vitest";
import {
  buildOnelineRewritePrompt,
  ONELINER_MAX_CHARS,
  PROMPT_ONELINE_REWRITE,
} from "../oneline.js";

describe("buildOnelineRewritePrompt (зеркало prompts.dart)", () => {
  it("вставляет лимит, понятие и текущее длинное описание", () => {
    const prompt = buildOnelineRewritePrompt({
      label: "Диффузионные модели",
      currentOneLiner: "Очень длинное описание понятия, превышающее лимит символов.",
    });
    expect(prompt).toContain(String(ONELINER_MAX_CHARS));
    expect(prompt).toContain('Понятие: "Диффузионные модели"');
    expect(prompt).toContain("Очень длинное описание понятия");
  });

  it("контракт: JSON-объект one_liner, без markdown-ограждения", () => {
    const prompt = buildOnelineRewritePrompt({
      label: "Краткое понятие",
      currentOneLiner: "Длинное описание для сокращения.",
    });
    expect(prompt.startsWith("# Роль")).toBe(true);
    // Формат ответа — валидный JSON c полем one_liner; инструкция прямо
    // запрещает оборачивать ответ в ```json.
    expect(PROMPT_ONELINE_REWRITE).toContain('{"one_liner": "сокращённое описание"}');
    expect(PROMPT_ONELINE_REWRITE).toContain("Без ```json и без пояснений");
  });

  it("правила: сохранить смысл, не добавлять фактов, без жаргона", () => {
    const prompt = buildOnelineRewritePrompt({
      label: "Краткое понятие",
      currentOneLiner: "Длинное описание для сокращения.",
    });
    expect(prompt).toContain("Сохрани ключевую идею");
    expect(prompt).toContain("не добавляй новых фактов");
    expect(prompt).toContain("жаргон");
    expect(prompt).toContain("только на русском языке");
  });

  it("лимит константы совпадает с инвариантом AGENTS.md (120)", () => {
    expect(ONELINER_MAX_CHARS).toBe(120);
  });
});