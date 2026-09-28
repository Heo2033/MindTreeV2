import { describe, it, expect } from "vitest";
import { fallbackQuestions } from "../DiagnosticEngine.js";
import { EventBus } from "../EventBus.js";

const LABELS = ["Производная", "Интеграл", "Предел", "Локальный экстремум"];

function nodes(n: number) {
  return Array.from({ length: n }, (_, i) => ({
    id: `n${i + 1}~abcdef0${i}`,
    label: LABELS[i] ?? `Узел ${i + 1}`,
    one_liner: `Это ${LABELS[i] ?? `Узел ${i + 1}`} в одном предложении.`,
  }));
}

describe("DiagnosticEngine fallback (без LLM)", () => {
  it("пустое дерево даёт пустой список, а не исключение", () => {
    expect(fallbackQuestions("Тема", [])).toEqual([]);
  });

  it("дерево из одного узла не даёт бессмысленный вопрос", () => {
    expect(fallbackQuestions("Тема", nodes(1))).toEqual([]);
  });

  it("строит вопрос на каждый узел с ≥2 вариантами", () => {
    const qs = fallbackQuestions("Тема", nodes(4));
    expect(qs).toHaveLength(4);
    for (const q of qs) {
      expect(q.options.length).toBeGreaterThanOrEqual(2);
      expect(q.correctIndex).toBeGreaterThanOrEqual(0);
      expect(q.correctIndex).toBeLessThan(q.options.length);
      expect(q.question).toMatch(/^Что означает понятие/);
      expect(q.explanation.length).toBeGreaterThan(0);
    }
  });

  it("correctIndex указывает на подпись своего узла", () => {
    const src = nodes(4);
    for (const q of fallbackQuestions("Тема", src)) {
      const node = src.find((n) => n.id === q.nodeId)!;
      expect(q.options[q.correctIndex]).toBe(node.label);
    }
  });

  it("детерминирован: два прогона дают одинаковые варианты и позиции", () => {
    const a = fallbackQuestions("Тема", nodes(4));
    const b = fallbackQuestions("Тема", nodes(4));
    for (let i = 0; i < a.length; i++) {
      expect(a[i]!.options).toEqual(b[i]!.options);
      expect(a[i]!.correctIndex).toBe(b[i]!.correctIndex);
      expect(a[i]!.nodeId).toBe(b[i]!.nodeId);
      expect(a[i]!.question).toBe(b[i]!.question);
    }
  });

  it("правильный вариант не всегда первый — позиция плавает", () => {
    const positions = new Set(fallbackQuestions("Тема", nodes(4)).map((q) => q.correctIndex));
    expect(positions.size).toBeGreaterThan(1);
  });

  it("id вопроса не «голый», а с префиксом d_", () => {
    for (const q of fallbackQuestions("Тема", nodes(3))) {
      expect(q.id).toMatch(/^d_/);
    }
  });

  it("без label берёт one_liner, чтобы вопрос не был пустым", () => {
    const qs = fallbackQuestions("Тема", [
      { id: "a~1", label: "  ", one_liner: "Первое понятие" },
      { id: "b~1", label: "Второе", one_liner: "Второе понятие" },
    ]);
    expect(qs).toHaveLength(2);
    expect(qs[0]!.question).toContain("Первое понятие");
  });

  it("одинаковые подписи не дают вопрос с единственным вариантом", () => {
    // Обе подписи совпадают → отличить варианты нечем → узлы пропускаются,
    // вместо того чтобы лепить вопрос с одним вариантом ответа.
    const qs = fallbackQuestions("Тема", [
      { id: "a~1", label: "Понятие", one_liner: "x" },
      { id: "b~1", label: "Понятие", one_liner: "y" },
    ]);
    expect(qs).toEqual([]);
  });

  it("в вариантах нет повторов, а correctOption — label узла", () => {
    const src = nodes(4);
    for (const q of fallbackQuestions("Тема", src)) {
      expect(new Set(q.options).size).toBe(q.options.length);
      const node = src.find((n) => n.id === q.nodeId)!;
      expect(q.options[q.correctIndex]).toBe(node.label);
    }
  });
});

describe("EventBus.markUnitStart / closeUnit", () => {
  it("без отметки closeUnit возвращает 0, а не падает", () => {
    expect(EventBus.closeUnit("s-never")).toBe(0);
  });

  it("после markUnitStart closeUnit возвращает положительное время", () => {
    EventBus.markUnitStart("s1");
    const spent = EventBus.closeUnit("s1");
    expect(spent).toBeGreaterThanOrEqual(0);
  });

  it("closeUnit снимает отметку — повторный вызов даёт 0", () => {
    EventBus.markUnitStart("s2");
    EventBus.closeUnit("s2");
    expect(EventBus.closeUnit("s2")).toBe(0);
  });

  it("отметки разных сессий изолированы", () => {
    EventBus.markUnitStart("s3");
    EventBus.markUnitStart("s4");
    EventBus.closeUnit("s3");
    // Закрытие s3 не тронуло отметку s4: повторное закрытие даёт 0.
    expect(EventBus.closeUnit("s4")).toBe(0);
  });
});
