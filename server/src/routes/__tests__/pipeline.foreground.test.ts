import { describe, expect, it } from "vitest";
import {
  beginForegroundGeneration,
  endForegroundGeneration,
  isForegroundGenerationActive,
} from "../pipeline.js";

describe("показатель активной форграунд-генерации", () => {
  it("выключен по умолчанию", () => {
    expect(isForegroundGenerationActive()).toBe(false);
  });

  it("включается в begin и выключается в end", () => {
    beginForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(true);
    endForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(false);
  });

  it("поддерживает вложенное/параллельное использование", () => {
    beginForegroundGeneration();
    beginForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(true);
    endForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(true);
    endForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(false);
  });

  it("не уходит в минус при лишнем end", () => {
    beginForegroundGeneration();
    endForegroundGeneration();
    endForegroundGeneration();
    expect(isForegroundGenerationActive()).toBe(false);
  });
});