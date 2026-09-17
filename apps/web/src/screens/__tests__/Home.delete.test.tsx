// @vitest-environment happy-dom
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { HomeScreen } from "../Home";

const { removeTopic, loadTopics } = vi.hoisted(() => ({
  removeTopic: vi.fn(() => Promise.resolve()),
  loadTopics: vi.fn(() => Promise.resolve()),
}));

vi.mock("../../stores", () => ({
  useTopicStore: () => ({
    topics: [
      {
        id: "topic-1",
        name: "Квантовая физика",
        goal: "Разобраться в основах",
        time_budget_minutes: 90,
        target_level: "basic",
      },
    ],
    loading: false,
    error: null,
    loadTopics,
    removeTopic,
  }),
}));

beforeEach(() => {
  removeTopic.mockClear();
  loadTopics.mockClear();
});

afterEach(() => {
  cleanup();
});

function renderHome() {
  return render(
    <MemoryRouter>
      <HomeScreen />
    </MemoryRouter>,
  );
}

describe("HomeScreen удаление темы", () => {
  it("подтверждение появляется через Modal; «Отмена» не удаляет", async () => {
    const user = userEvent.setup();
    renderHome();

    await screen.findByText("Квантовая физика");

    await user.click(screen.getByRole("button", { name: "Удалить" }));
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(screen.getByText(/Удалить тему «Квантовая физика»\?/)).toBeTruthy();

    await user.click(screen.getByRole("button", { name: "Отмена" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByText(/Удалить тему «Квантовая физика»\?/)).toBeNull();
    expect(removeTopic).not.toHaveBeenCalled();
  });

  it("подтверждение в Modal вызывает removeTopic с id темы", async () => {
    const user = userEvent.setup();
    renderHome();

    await screen.findByText("Квантовая физика");

    await user.click(screen.getByRole("button", { name: "Удалить" }));
    // Рядок и модалка содержат одинаковую кнопку «Удалить»: модальная — вторая.
    const [, modalConfirm] = screen.getAllByRole("button", { name: "Удалить" });
    await user.click(modalConfirm);

    expect(removeTopic).toHaveBeenCalledTimes(1);
    expect(removeTopic).toHaveBeenCalledWith("topic-1");
  });

  it("Escape закрывает модалку без удаления", async () => {
    const user = userEvent.setup();
    renderHome();

    await screen.findByText("Квантовая физика");
    await user.click(screen.getByRole("button", { name: "Удалить" }));

    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(removeTopic).not.toHaveBeenCalled();
  });
});