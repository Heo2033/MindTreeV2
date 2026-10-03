import { describe, expect, it } from "vitest";

import { parseLLMJson } from "../client.js";

/**
 * Тихая порча LaTeX при разборе JSON-ответа LLM.
 *
 * Модель возвращает в JSON-строках формулы с одиночным обратным слэшем
 * (`\rightarrow`, `\frac`, `\text`). JSON.parse считает `\r`, `\t`, `\b`, `\f`,
 * `\n` валидными escape-последовательностями, поэтому разбор ПРОХОДИТ УСПЕШНО,
 * а значение молча портится: `\rightarrow` → CR + `ightarrow`, `\text` → TAB +
 * `ext`, `\frac` → formfeed + `rac`.
 *
 * Воспроизведено на живом прогоне probe: в `report.md` формула выглядела как
 * `12NADPH  ightarrow`, причём дефект не был виден в `report.json`, потому что
 * json_encode перекодировал CR обратно в `\r`.
 *
 * Зеркало flutter-теста `test/data/llm/parse_json_salvage_test.dart`.
 */

type Details = { details: string };

/** Сырой ответ модели: одиночный обратный слэш внутри JSON-строки. */
function raw(body: string): string {
  return `{"details":"${body}"}`;
}

describe("parseLLMJson: LaTeX в строковых значениях", () => {
  it("сохраняет \\rightarrow (не превращает в CR + ightarrow)", () => {
    const parsed = parseLLMJson<Details>(
      raw("Формула: $6CO_2 + 18ATP  \\rightarrow C_6H_{12}O_6$"),
    );
    expect(parsed.details).toBe("Формула: $6CO_2 + 18ATP  \\rightarrow C_6H_{12}O_6$");
    expect([...parsed.details].some((c) => c.charCodeAt(0) === 13)).toBe(false);
  });

  it.each([
    ["\\text", "text"],
    ["\\frac{1}{2}", "frac"],
    ["\\beta", "beta"],
    ["\\theta", "theta"],
    ["\\times", "times"],
    ["\\neq", "neq"],
    ["\\begin{aligned}", "begin"],
  ])("сохраняет макрос %s", (macro, name) => {
    const parsed = parseLLMJson<Details>(raw(`$x^{${macro}}$`));
    expect(parsed.details).toContain(macro);
    expect(parsed.details).toContain(name);
  });

  it("сохраняет \\to с пробелом, а не превращает в TAB", () => {
    const parsed = parseLLMJson<Details>(raw("$a \\to b$"));
    expect(parsed.details).toBe("$a \\to b$");
  });

  it("не трогает настоящие control-escape", () => {
    expect(parseLLMJson<Details>(raw("a\\nb")).details).toBe("a\nb");
    expect(parseLLMJson<Details>(raw("a\\tb")).details).toBe("a\tb");
    expect(parseLLMJson<Details>(raw("a\\rb")).details).toBe("a\rb");
  });

  it("не трогает экранированные кавычки и обратный слэш", () => {
    expect(parseLLMJson<Details>(raw("кавычка \\\" внутри")).details).toBe(
      'кавычка " внутри',
    );
    expect(parseLLMJson<Details>(raw("a\\\\b")).details).toBe("a\\b");
  });

  it("не трогает \\uXXXX", () => {
    expect(parseLLMJson<Details>(raw("\\u00e9")).details).toBe("é");
  });

  it("не удваивает уже экранированный макрос", () => {
    const parsed = parseLLMJson<Details>(raw("\\\\to"));
    expect(parsed.details).toBe("\\to");
    expect(parsed.details).not.toContain("\\\\");
  });

  it("чинит тот же дефект в ответе в code fence", () => {
    const parsed = parseLLMJson<Details>(
      "```json\n" + raw("$a \\rightarrow b$") + "\n```",
    );
    expect(parsed.details).toContain("\\rightarrow");
  });

  it("чинит тот же дефект при обрезке ответа (bracket matching)", () => {
    const parsed = parseLLMJson<Details>(
      "Предыдущий текст\n" + raw("$a \\rightarrow b$"),
    );
    expect(parsed.details).toContain("\\rightarrow");
  });

  it("не меняет разбор валидного JSON без LaTeX", () => {
    const parsed = parseLLMJson<{ a: number; b: string }>(
      '{"a":1,"b":"текст"}',
    );
    expect(parsed).toEqual({ a: 1, b: "текст" });
  });
});