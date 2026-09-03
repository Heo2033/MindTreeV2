import { describe, it, expect } from "vitest";
import {
  rotateOptions,
  rotateIndex,
  nextPendingIndex,
  parseSteps,
  parseActivityBlob,
  type ActivityStep,
} from "../LearningActivityService.js";

describe("LearningActivityService helpers", () => {
  describe("rotateOptions / rotateIndex", () => {
    it("вращает варианты и сохраняет корректный индекс", () => {
      const options = ["A", "B", "C", "D"];
      const rotated = rotateOptions(options, 1);
      // сдвиг на 1 влево: каждый элемент переезжает на индекс-1
      expect(rotated).toEqual(["B", "C", "D", "A"]);
      expect(rotateIndex(0, 1, 4)).toBe(3); // правильный A теперь на позиции 3
      expect(rotated[3]).toBe("A");
    });

    it("не вращает при shift 0", () => {
      expect(rotateOptions(["A", "B"], 0)).toEqual(["A", "B"]);
    });

    it("обрабатывает пустой массив", () => {
      expect(rotateOptions([], 3)).toEqual([]);
      expect(rotateIndex(2, 1, 0)).toBe(0);
    });
  });

  describe("nextPendingIndex", () => {
    it("возвращает первый не-отвеченный шаг", () => {
      const steps = [
        { status: "answered" as const },
        { status: "current" as const },
        { status: "pending" as const },
      ] as ActivityStep[];
      expect(nextPendingIndex(steps)).toBe(1);
    });

    it("возвращает -1, если все отвечены", () => {
      const steps = [
        { status: "answered" as const },
        { status: "answered" as const },
      ] as ActivityStep[];
      expect(nextPendingIndex(steps)).toBe(-1);
    });
  });

  describe("parseSteps", () => {
    it("разбирает валидный JSON", () => {
      const parsed = parseSteps('[{"type":"recall","status":"current"}]');
      expect(parsed).toHaveLength(1);
      expect(parsed[0].type).toBe("recall");
    });

    it("возвращает [] на битый JSON", () => {
      expect(parseSteps("{oops")).toEqual([]);
      expect(parseSteps("")).toEqual([]);
    });
  });

  describe("parseActivityBlob", () => {
    it("разбирает новый формат { itemId, steps }", () => {
      const blob = JSON.stringify({
        itemId: "ci_2",
        steps: [{ type: "explain" as const, status: "current" as const }],
      });
      const { itemId, steps } = parseActivityBlob(blob);
      expect(itemId).toBe("ci_2");
      expect(steps).toHaveLength(1);
      expect(steps[0].type).toBe("explain");
    });

    it("обрабатывает старый формат (простой массив) как steps без itemId", () => {
      const blob = JSON.stringify([{ type: "recall" as const, status: "current" as const }]);
      const { itemId, steps } = parseActivityBlob(blob);
      expect(itemId).toBeUndefined();
      expect(steps).toHaveLength(1);
    });

    it("возвращает пустой результат на битый JSON или пустой steps", () => {
      expect(parseActivityBlob("{oops")).toEqual({ steps: [] });
      expect(parseActivityBlob("")).toEqual({ steps: [] });
      expect(parseActivityBlob('{"itemId":"ci_1","steps":{}}')).toEqual({ steps: [] });
    });
  });
});
