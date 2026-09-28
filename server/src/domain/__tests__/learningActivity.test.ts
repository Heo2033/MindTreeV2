import { describe, it, expect } from "vitest";
import {
  rotateOptions,
  rotateIndex,
  nextPendingIndex,
  parseSteps,
  parseActivityBlob,
  fallbackExample,
  explainBody,
  ensureDistinctExample,
  isUsableReferenceAnswer,
  looksLikeLearnerTask,
  sanitizeExample,
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

  describe("fallbackExample / explainBody / ensureDistinctExample (зеркало flutter)", () => {
    const node = {
      id: "n1",
      label: "Понятие X",
      one_liner: "Определение понятия X",
      details: "Подробное объяснение",
      analogy: null,
      difficulty: 0.5,
      parent_id: null,
    };

    it("fallbackExample не повторяет определение и содержит пример", () => {
      const text = fallbackExample(node);
      expect(text).not.toContain("Определение понятия X");
      expect(text).toContain("Понятие X");
      expect(text).toContain("пример");
    });

    it("fallbackExample использует аналогию, если она есть", () => {
      expect(fallbackExample({ ...node, analogy: "Это как рецепт блюда" })).toContain(
        "Аналогия: Это как рецепт блюда",
      );
    });

    it("explainBody (fallback без details) НЕ содержит аналогию", () => {
      const text = explainBody(
        { ...node, details: "", analogy: "Это как рецепт блюда" },
        [],
      );
      expect(text).toContain("Определение понятия X");
      expect(text).not.toContain("Аналогия");
    });

    it("ensureDistinctExample подменяет дубль объяснения на fallback-пример", () => {
      const explain = "Объяснение с определениями";
      const distinct = ensureDistinctExample(node, explain, explain);
      expect(distinct).toContain("Понятие X");
      expect(distinct).not.toBe(explain);
    });

    it("ensureDistinctExample не трогает различный пример", () => {
      expect(ensureDistinctExample(node, "Объяснение", "Пример про жизнь")).toBe(
        "Пример про жизнь",
      );
    });
  });

  describe("sanitizeExample: шаг «пример» не отдаёт ученику задание (зеркало flutter)", () => {
    const node = {
      id: "n1",
      label: "Понятие X",
      one_liner: "Определение понятия X",
      details: "Подробное объяснение",
      analogy: "Это как рецепт блюда",
      difficulty: 0.5,
      parent_id: null,
    };

    it("императив из LLM заменяется на fallback-пример", () => {
      // Раньше такой текст уезжал в UI как есть: вместо примера — задача.
      const body = sanitizeExample(node, "Объяснение", "Приведите один простой пример.");
      expect(body).toContain("Аналогия: Это как рецепт блюда");
      expect(body).not.toContain("Приведите");
    });

    it("вопрос вместо примера заменяется на fallback", () => {
      const body = sanitizeExample({ ...node, analogy: null }, "Объяснение", "А как это работает?");
      expect(body.endsWith("?")).toBe(false);
    });

    it("нормальный пример от LLM сохраняется", () => {
      const example = "В фотографии кадры собирают постепенно, шум уходит.";
      expect(sanitizeExample(node, "Объяснение", example)).toBe(example);
    });

    it("fallback-пример никогда не выглядит как задание ученику", () => {
      for (const text of [fallbackExample(node), fallbackExample({ ...node, analogy: null })]) {
        expect(looksLikeLearnerTask(text)).toBe(false);
      }
    });
  });

  describe("apply.reference_answer отвечает на задание про применение (зеркало flutter)", () => {
    const node = {
      id: "n1",
      label: "Понятие X",
      one_liner: "Определение понятия X",
      details: "Подробное объяснение",
      analogy: null,
      difficulty: 0.5,
      parent_id: null,
    };

    it("пересказ определения не принимается за образец ответа", () => {
      expect(isUsableReferenceAnswer("Определение понятия X", node)).toBe(false);
      expect(
        isUsableReferenceAnswer(
          "В задаче о прогнозе погоды это понятие применяют так: сначала " +
            "собирают частные признаки, потом усредняют их в один вывод.",
          node,
        ),
      ).toBe(true);
    });

    it("короткий или пустой образец отбрасывается", () => {
      expect(isUsableReferenceAnswer("", node)).toBe(false);
      expect(isUsableReferenceAnswer("Применяется в жизни", node)).toBe(false);
    });

    it("образец, дословно повторяющий details, отбрасывается", () => {
      expect(isUsableReferenceAnswer("Подробное объяснение", node)).toBe(false);
      expect(
        isUsableReferenceAnswer(
          "Это нужно там, где решают задачи прогноза: сначала собирают " +
            "признаки по отдельности, потом сводят их в один вывод.",
          node,
        ),
      ).toBe(true);
    });
  });
});
