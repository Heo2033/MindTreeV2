import { describe, it, expect } from "vitest";
import {
  heuristicApplyFeedback,
} from "../FeedbackEngine.js";

describe("FeedbackEngine", () => {
  describe("heuristicApplyFeedback", () => {
    it("пустой ответ → короткий ответ", () => {
      expect(heuristicApplyFeedback("эталонный ответ", "  ")).toMatch(/пустой|короткий/i);
    });

    it("высокое пересечение токенов → частичное совпадение", () => {
      const ref = "нервная система передаёт сигналы через нейроны";
      const answer = "нервная система передаёт сигналы через нейроны и синапсы";
      expect(heuristicApplyFeedback(ref, answer)).toMatch(/совпадает/i);
    });

    it("совсем другой ответ → не совпадает", () => {
      const ref = "кровь переносит кислород";
      const answer = "обычно по утрам идёт дождь";
      expect(heuristicApplyFeedback(ref, answer)).toMatch(/не совпадает/i);
    });
  });
});
