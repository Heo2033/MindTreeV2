import { afterEach, describe, expect, it, vi } from "vitest";
import { postSSE, type SSEEvent, type SSEStream } from "./client";

// Должно совпадать с CONNECT_TIMEOUT_MS в client.ts.
const CONNECT_TIMEOUT_MS = 15_000;

type FetchMock = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

function installFetch(mock: FetchMock) {
  const spy = vi.fn(mock);
  vi.stubGlobal("fetch", spy);
  return spy;
}

/**
 * Fetch, который зависает навсегда до abort(), а при отмене отклоняется
 * AbortError — как это делает реальный браузерный fetch с signal.
 */
function installAbortableFetch() {
  return installFetch(
    (_input, init) =>
      new Promise((_resolve, reject) => {
        const signal = init?.signal;
        if (!signal) return;
        if (signal.aborted) {
          reject(new DOMException("Aborted", "AbortError"));
          return;
        }
        signal.addEventListener("abort", () =>
          reject(new DOMException("Aborted", "AbortError")),
        );
      }),
  );
}

/** ReadableStream, который сразу отдаёт готовые SSE-фреймы и закрывается. */
function sseBody(...frames: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (const f of frames) controller.enqueue(encoder.encode(f));
      controller.close();
    },
  });
}

function okResponse(body: ReadableStream<Uint8Array> | unknown): Response {
  return { ok: true, status: 200, body } as unknown as Response;
}

function frame(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

/** Вычитывает все события потока: возвращает список и (если был) кинутый error. */
async function collect(stream: SSEStream): Promise<{ events: SSEEvent[]; error: unknown }> {
  const events: SSEEvent[] = [];
  let error: unknown = null;
  try {
    for await (const ev of stream.events) events.push(ev);
  } catch (e) {
    error = e;
  }
  return { events, error };
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("postSSE", () => {
  it("доставляет progress- и done-фреймы сервера и завершается без ошибки", async () => {
    installFetch(() =>
      Promise.resolve(
        okResponse(
          sseBody(
            frame("progress", { phase: "structure", message: "Структурирование…" }),
            frame("done", { nodes: [], warnings: [], persisted: 3 }),
          ),
        ),
      ),
    );

    const { events, error } = await collect(postSSE("/api/pipeline/generate", { topic_id: "t1" }));

    expect(error).toBeNull();
    expect(events.map((e) => e.event)).toEqual(["progress", "done"]);
    expect(events[1].data).toEqual({ nodes: [], warnings: [], persisted: 3 });
  });

  it("склеивает SSE-фреймы, пришедшие несколькими чанками", async () => {
    const encoder = new TextEncoder();
    const chunk1 = encoder.encode('event: progress\ndata: {"ph');
    const chunk2 = encoder.encode('ase":"structure"}\n\nevent: done\ndata: {"ok":true}\n\n');
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(chunk1);
        c.enqueue(chunk2);
        c.close();
      },
    });
    installFetch(() => Promise.resolve(okResponse(body)));

    const { events, error } = await collect(postSSE("/p", { query: "x" }));

    expect(error).toBeNull();
    expect(events).toEqual([
      { event: "progress", data: { phase: "structure" } },
      { event: "done", data: { ok: true } },
    ]);
  });

  it("доставляет error-фрейм сервера и завершает поток без исключения", async () => {
    installFetch(() =>
      Promise.resolve(
        okResponse(
          sseBody(
            frame("progress", { phase: "structure", message: "go" }),
            frame("error", { message: "LLM недоступен" }),
          ),
        ),
      ),
    );

    const { events, error } = await collect(postSSE("/p", { query: "x" }));

    expect(error).toBeNull();
    expect(events.map((e) => e.event)).toEqual(["progress", "error"]);
    expect(events[1].data).toEqual({ message: "LLM недоступен" });
  });

  it("для HTTP-ошибки доставляет error с сообщением из JSON-тела", async () => {
    installFetch(() =>
      Promise.resolve({
        ok: false,
        status: 400,
        body: null,
        text: () => Promise.resolve(JSON.stringify({ error: "query is required" })),
      } as unknown as Response),
    );

    const { events, error } = await collect(postSSE("/p", {}));

    expect(error).toBeNull();
    expect(events.map((e) => e.event)).toEqual(["error"]);
    expect(events[0].data).toEqual({ message: "query is required" });
  });

  it("для не-JSON тела HTTP-ошибки переиспользует HTTP-статус", async () => {
    installFetch(() =>
      Promise.resolve({
        ok: false,
        status: 502,
        body: null,
        text: () => Promise.resolve("Bad Gateway"),
      } as unknown as Response),
    );

    const { events } = await collect(postSSE("/p", {}));

    expect(events[0].data).toEqual({ message: "HTTP 502" });
  });

  it("транспортный обрыв при чтении даёт __error__ и исключение в итераторе", async () => {
    const networkError = new TypeError("Failed to fetch");
    const body = {
      getReader: () => ({ read: () => Promise.reject(networkError) }),
    } as unknown as ReadableStream<Uint8Array>;
    installFetch(() => Promise.resolve(okResponse(body)));

    const { events, error } = await collect(postSSE("/p", { query: "x" }));

    // Сначала событие __error__ (видно циклу событий в сторе)…
    expect(events.map((e) => e.event)).toEqual(["__error__"]);
    expect(events[0].data).toEqual({ message: "Failed to fetch" });
    // …затем итератор бросает ту же ошибку (если потребитель дойдёт до конца).
    expect(error).toBe(networkError);
  });

  it("EOF без done/error-фрейма трактуется как обрыв соединения (__error__)", async () => {
    installFetch(() =>
      Promise.resolve(
        okResponse(sseBody(frame("progress", { phase: "expand", message: "…" }))),
      ),
    );

    const { events, error } = await collect(postSSE("/p", { query: "x" }));

    expect(events.map((e) => e.event)).toEqual(["progress", "__error__"]);
    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toContain("Соединение закрыто");
  });

  it("хвост буфера без event: эмитится как message (и EOF даёт __error__)", async () => {
    installFetch(() => Promise.resolve(okResponse(sseBody('data: {"a":1}\n\n'))));

    const { events, error } = await collect(postSSE("/p", { query: "x" }));

    expect(events.map((e) => e.event)).toEqual(["message", "__error__"]);
    expect((events[0] as SSEEvent).data).toEqual({ a: 1 });
    expect(error).toBeDefined();
  });

  it("при таймауте ожидания заголовков доставляет __error__ о таймауте", async () => {
    vi.useFakeTimers();
    installAbortableFetch();

    const stream = postSSE("/p", { query: "x" });
    const collection = collect(stream);

    // Ответа от сервера нет — проходит только connect-таймаут.
    await vi.advanceTimersByTimeAsync(CONNECT_TIMEOUT_MS + 1);

    const { events, error } = await collection;
    expect(events.map((e) => e.event)).toEqual(["__error__"]);
    expect(events[0].data).toEqual({ message: "Таймаут соединения с сервером" });
    expect((error as Error).message).toContain("Таймаут");
  });

  it("явный abort() завершает поток без исключений и падений", async () => {
    installAbortableFetch();

    const stream = postSSE("/p", { query: "x" });
    const collection = collect(stream);

    // abort() синхронно отклоняет fetch AbortError'ом — таймеры не нужны.
    stream.abort();

    const { events, error } = await collection;
    expect(events).toEqual([]);
    expect(error).toBeNull();
  });
});