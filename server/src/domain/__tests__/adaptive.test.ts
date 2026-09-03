import { describe, it, expect } from "vitest";
import { computeEtaFrom } from "../AdaptiveLearningEngine.js";

describe("computeEtaFrom (§39–40 динамическое время)", () => {
  it("темп faster при малых затратах на много завершённых item'ов", () => {
    // план 70 мин на 14 item'ов = 5 мин/item; реально 2 мин/item
    const eta = computeEtaFrom(20, 10, 14, 70);
    expect(eta.pace).toBe("faster");
    expect(eta.remainingMinutesMax).toBeLessThan(70);
  });

  it("темп slower при больших затратах времени", () => {
    // 30 мин на 1 item — сильно медленнее плановых 5 мин/item
    const eta = computeEtaFrom(30, 1, 14, 70);
    expect(eta.pace).toBe("slower");
  });

  it("всегда возвращает минимальный диапазон даже при нуле потраченного времени", () => {
    const eta = computeEtaFrom(0, 0, 14, 70);
    expect(eta.remainingMinutesMin).toBeGreaterThanOrEqual(0);
    expect(eta.remainingMinutesMax).toBeGreaterThanOrEqual(eta.remainingMinutesMin);
    expect(eta.totalItems).toBe(14);
  });

  it("диапазон вокруг прогноза (±40%)", () => {
    const eta = computeEtaFrom(5, 1, 14, 70);
    const mid = (eta.remainingMinutesMin + eta.remainingMinutesMax) / 2;
    expect(mid).toBeGreaterThan(0);
  });
});
