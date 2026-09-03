import { describe, it, expect } from "vitest";
import { levelFromScore } from "../MasteryEngine.js";

describe("levelFromScore (маппинг score → уровень)", () => {
  it("низкий score → awareness", () => {
    expect(levelFromScore(0).label).toBe("awareness");
  });

  it("высокий score → expert", () => {
    expect(levelFromScore(1).label).toBe("expert");
  });

  it("монотонно не убывает с ростом score", () => {
    const labels: string[] = [];
    for (let i = 0; i <= 10; i++) {
      labels.push(levelFromScore(i / 10).label);
    }
    // нет «отката» в более низкий уровень при росте score
    const order = [
      "awareness",
      "basic_understanding",
      "solid_understanding",
      "practical_application",
      "advanced",
      "expert",
    ];
    for (let i = 1; i < labels.length; i++) {
      expect(order.indexOf(labels[i])).toBeGreaterThanOrEqual(order.indexOf(labels[i - 1]));
    }
  });
});
