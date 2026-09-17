// @vitest-environment happy-dom
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { NewTopicScreen } from "../NewTopic";

const { createTopic, generateTree, setState, getState } = vi.hoisted(() => ({
  createTopic: vi.fn(),
  generateTree: vi.fn(),
  setState: vi.fn(),
  getState: vi.fn(),
}));

vi.mock("../../stores", () => {
  function useGraphStore(selector: (s: { generateTree: unknown; pipeline: unknown }) => unknown) {
    return selector({
      generateTree,
      pipeline: { phase: "", message: "", stats: null, status: "error" },
    });
  }
  useGraphStore.setState = setState;
  useGraphStore.getState = getState;
  return {
    useGraphStore,
    useTopicStore: (selector: (s: { createTopic: unknown }) => unknown) => selector({ createTopic }),
  };
});

beforeEach(() => {
  createTopic.mockReset();
  generateTree.mockReset();
  setState.mockReset();
  getState.mockReset();
  createTopic.mockResolvedValue({ id: "t1", name: "Квантовая механика" });
});

afterEach(() => {
  cleanup();
});

function renderNewTopic() {
  return render(
    <MemoryRouter>
      <NewTopicScreen />
    </MemoryRouter>,
  );
}

describe("NewTopicScreen: ошибка генерации", () => {
  it("показывает реальное сообщение пайплайна, а не generic-фразу", async () => {
    generateTree.mockResolvedValue(false);
    getState.mockReturnValue({
      pipeline: { phase: "", message: "LLM_API_KEY (или OPENAI_API_KEY) не задан", stats: null, status: "error" },
    });
    const user = userEvent.setup();
    renderNewTopic();

    await user.type(screen.getByPlaceholderText("Например: Квантовая механика"), "Квантовая механика");
    await user.type(screen.getByPlaceholderText("Опишите, что должно охватывать дерево…"), "Основы квантовой механики");
    await user.click(screen.getByRole("button", { name: "Создать тему и построить дерево" }));

    expect(generateTree).toHaveBeenCalledTimes(1);
    expect(await screen.findByText(/LLM_API_KEY \(или OPENAI_API_KEY\) не задан/)).toBeTruthy();
    expect(screen.queryByText(/Не удалось построить дерево/)).toBeNull();
  });

  it("без сообщения пайплайна показывает generic-фразу", async () => {
    generateTree.mockResolvedValue(false);
    getState.mockReturnValue({
      pipeline: { phase: "", message: "", stats: null, status: "error" },
    });
    const user = userEvent.setup();
    renderNewTopic();

    await user.type(screen.getByPlaceholderText("Например: Квантовая механика"), "Квантовая механика");
    await user.type(screen.getByPlaceholderText("Опишите, что должно охватывать дерево…"), "Основы квантовой механики");
    await user.click(screen.getByRole("button", { name: "Создать тему и построить дерево" }));

    expect(await screen.findByText(/Не удалось построить дерево/)).toBeTruthy();
  });
});