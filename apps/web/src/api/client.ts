const API_BASE = import.meta.env.VITE_API_URL || "";

export interface RequestOptions extends RequestInit {
  json?: unknown;
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { json, ...fetchOptions } = options;
  const headers: Record<string, string> = {
    ...(fetchOptions.headers as Record<string, string>),
  };

  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    fetchOptions.body = JSON.stringify(json);
  }

  const res = await fetch(`${API_BASE}${path}`, { ...fetchOptions, headers });

  if (!res.ok) {
    const error = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(error.error || `HTTP ${res.status}`);
  }

  return res.json();
}

export function buildUrl(path: string): string {
  return `${API_BASE}${path}`;
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

  const events: SSEEvent[] = [];
  const listeners = new Set<(e: SSEEvent) => void>();
  let done = false;
  let streamError: Error | null = null;

  function emit(e: SSEEvent) {
    events.push(e);
    for (const fn of listeners) fn(e);
  }

  const iteratorPromise = (async function* () {
    let cursor = 0;
    while (true) {
      while (cursor < events.length) {
        yield events[cursor++];
      }
      if (done) return;
      if (streamError) throw streamError;
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
    try {
      const res = await fetch(`${API_BASE}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!res.ok || !res.body) {
        streamError = new Error(`SSE HTTP ${res.status}`);
        done = true;
        for (const fn of listeners) fn({ event: "error", data: { message: `HTTP ${res.status}` } });
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

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
        const trimmed = buffer.trim().startsWith("event:") || buffer.trim().startsWith("data:")
          ? buffer
          : buffer;
        const raw = trimmed.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).join("\n");
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

      done = true;
      for (const fn of listeners) fn({ event: "done", data: null });
    } catch (err) {
      if (controller.signal.aborted) {
        done = true;
        return;
      }
      streamError = err instanceof Error ? err : new Error(String(err));
      done = true;
      for (const fn of listeners) fn({ event: "__error__", data: streamError });
    } finally {
      for (const fn of listeners) listeners.delete(fn);
    }
  })();

  return {
    events: iteratorPromise,
    abort: () => controller.abort(),
  };
}
