const API_BASE = import.meta.env.VITE_API_URL || "";

// Глобальный переключатель точки входа для десктопной обвязки: в Tauri порт
// встроенного сервера известен только в рантайме, поэтому клиент читает его
// из window.__MINDTREE_API_BASE__ (задаётся обёрткой) раньше, чем env-префикс.
function apiBase(): string {
  return (
    (typeof window !== "undefined"
      && (window as { __MINDTREE_API_BASE__?: string }).__MINDTREE_API_BASE__)
    || API_BASE
  );
}

export function setApiBase(base: string): void {
  if (typeof window !== "undefined") {
    (window as { __MINDTREE_API_BASE__?: string }).__MINDTREE_API_BASE__ = base;
  }
}

// Токен доступа к встроенному серверу десктопной обвязки. Задаётся один раз
// после invoke("get_server_info") и добавляется ко всем запросам и SSE-каналам.
let authToken: string | null = null;

export function setAuthToken(token: string | null): void {
  authToken = token ?? null;
}

function getAuthorizationHeader(): Record<string, string> {
  return authToken ? { Authorization: `Bearer ${authToken}` } : {};
}

/**
 * Лимит ожидания HTTP-заголовков SSE-рукопожатия. 0 — без лимита.
 * Это НЕ лимит на весь стриминг: после установки соединения фазы LLM могут
 * легитимно идти десятки секунд, поэтому обрывать читающий поток нельзя.
 */
const CONNECT_TIMEOUT_MS = 15_000;

export interface RequestOptions extends RequestInit {
  json?: unknown;
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { json, ...fetchOptions } = options;
  const headers: Record<string, string> = {
    ...getAuthorizationHeader(),
    ...(fetchOptions.headers as Record<string, string>),
  };

  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    fetchOptions.body = JSON.stringify(json);
  }

  const res = await fetch(`${apiBase()}${path}`, { ...fetchOptions, headers });

  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(error.error || `HTTP ${res.status}`);
  }

  return res.json();
}

export function buildUrl(path: string): string {
  return `${apiBase()}${path}`;
}

export interface SSEEvent {
  event: string;
  data: unknown;
}

export interface SSEStream {
  events: AsyncIterable<SSEEvent>;
  abort: () => void;
}

/**
 * POST with SSE response. Correctly parses `event:\ndata:{...}\n\n` frames.
 * Frames without an explicit `event:` line are emitted with event "message".
 */
export function postSSE(path: string, body: unknown): SSEStream {
  const controller = new AbortController();
  let connectTimedOut = false;

  const events: SSEEvent[] = [];
  const listeners = new Set<(e: SSEEvent) => void>();
  let done = false;
  let streamError: Error | null = null;

  function emit(e: SSEEvent) {
    events.push(e);
    for (const fn of listeners) fn(e);
  }

  // Разбудить ожидающие итераторы/потребителей НЕ добавляя событие в буфер
  // (используется для закрывающего сигнала после уже доставленного терминала).
  function notify(e: SSEEvent) {
    for (const fn of listeners) fn(e);
  }

  // Единая точка закрытия потока с ошибкой: ставим streamError (итератор бросит)
  // и доставляем событие __error__ потребителю, чтобы цикл событий увидел его.
  function fail(error: Error, message: string) {
    streamError = error;
    done = true;
    emit({ event: "__error__", data: { message } });
  }

  const iteratorPromise = (async function* () {
    let cursor = 0;
    while (true) {
      while (cursor < events.length) {
        yield events[cursor++];
      }
      if (streamError) throw streamError;
      if (done) return;
      await new Promise<void>((res) => {
        const wake = () => res();
        const check = () => {
          if (cursor < events.length || done || streamError) {
            listeners.delete(check);
            wake();
          }
        };
        if (!listeners.has(check)) listeners.add(check);
        check();
      });
    }
  })();

  (async () => {
    const connectTimer = setTimeout(() => {
      connectTimedOut = true;
      controller.abort();
    }, CONNECT_TIMEOUT_MS);

    try {
      const res = await fetch(`${apiBase()}${path}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...getAuthorizationHeader(),
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(connectTimer);

      if (!res.ok || !res.body) {
        let detail = `HTTP ${res.status}`;
        try {
          const text = await res.text();
          const parsed = JSON.parse(text);
          const msg = (parsed as { error?: unknown; message?: unknown })?.error
            ?? (parsed as { message?: unknown })?.message;
          if (typeof msg === "string" && msg.trim()) detail = msg;
        } catch {
          // не JSON — оставляем HTTP-статус
        }
        emit({ event: "error", data: { message: detail } });
        done = true;
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      // Сервер по контракту всегда шлёт терминальный done/error-фрейм.
      let sawTerminal = false;

      while (true) {
        const { done: readerDone, value } = await reader.read();
        if (readerDone) break;

        buffer += decoder.decode(value, { stream: true });

        const frames = buffer.split("\n\n");
        buffer = frames.pop() ?? "";

        for (const frame of frames) {
          if (frame.trim() === "") continue;
          let event = "message";
          const dataLines: string[] = [];
          for (const line of frame.split("\n")) {
            if (line.startsWith("event:")) {
              event = line.slice(6).trim();
            } else if (line.startsWith("data:")) {
              dataLines.push(line.slice(5).trim());
            }
          }
          if (event === "done" || event === "error") sawTerminal = true;
          const raw = dataLines.join("\n");
          let parsed: unknown = raw;
          try {
            parsed = JSON.parse(raw);
          } catch {
            // keep raw string
          }
          emit({ event, data: parsed });
        }
      }

      if (buffer.trim() !== "") {
        // Хвост без завершающего \n\n — извлекаем data:-строки (event не указан).
        const raw = buffer.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).join("\n");
        if (raw.trim() !== "") {
          let parsed: unknown = raw;
          try {
            parsed = JSON.parse(raw);
          } catch {
            // keep raw
          }
          emit({ event: "message", data: parsed });
        }
      }

      // Сервер закрыл поток без явного терминального done/error-фрейма.
      // Это обрыв соединения/пропажа сети — сигнализируем как ошибку, а не
      // фальсифицируем успешное «done» (иначе оверлей зависнет или скроет неполноту).
      if (!sawTerminal) {
        fail(new Error("Соединение закрыто без завершения генерации"), "Соединение прервано: дерево не было завершено");
        return;
      }

      // Закрывающий сигнал для ожидающих итераторов без дублирования события:
      // терминальный протокольный фрейм (done/error) уже доставлен выше.
      done = true;
      notify({ event: "done", data: null });
    } catch (err) {
      clearTimeout(connectTimer);
      if (controller.signal.aborted) {
        if (connectTimedOut) {
          fail(new Error("Таймаут соединения с сервером"), "Таймаут соединения с сервером");
        } else {
          // Сознательная отмена: завершаем поток, чтобы ожидающий итератор
          // не завис навечно, и не выдаём ошибку.
          done = true;
          notify({ event: "done", data: null });
        }
        return;
      }
      // Транспортная ошибка во время чтения (сеть) — поверх уже открытого потока.
      const error = err instanceof Error ? err : new Error(String(err));
      fail(error, error.message);
    } finally {
      for (const fn of listeners) listeners.delete(fn);
    }
  })();

  return {
    events: iteratorPromise,
    abort: () => controller.abort(),
  };
}
