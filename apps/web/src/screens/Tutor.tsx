import { useEffect, useMemo, useRef, useState } from "react";
import { useGraphStore, useTutorStore, useSessionStore } from "../stores";
import { buildChildrenMap, nodePath } from "../lib/tree";
import { Button, Spinner, ErrorBanner, Badge } from "@mindtree/ui";

function Chevron({ rotate = 0, className = "" }: { rotate?: number; className?: string }) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={`transition-transform ${className}`}
      style={{ transform: `rotate(${rotate}deg)` }}
    >
      <path d="m9 18 6-6-6-6" />
    </svg>
  );
}

function TutorToc({
  selectedId,
  onSelect,
  onClose,
}: {
  selectedId: string | null;
  onSelect: (id: string) => void;
  onClose: () => void;
}) {
  const nodes = useGraphStore((s) => s.nodes);
  const childrenMap = useMemo(() => buildChildrenMap(nodes), [nodes]);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const roots = nodes.filter((n) => !n.parentId);

  useEffect(() => {
    if (selectedId) {
      const path = nodePath(nodes, selectedId);
      setOpen((prev) => new Set([...prev, ...path.map((l) => l)]));
    }
  }, [selectedId, nodes]);

  const renderRows = (list: typeof nodes, depth: number) => (
    <ul>
      {list.map((n) => {
        const kids = childrenMap.get(n.id) ?? [];
        const isOpen = open.has(n.id);
        return (
          <li key={n.id}>
            <div className="group flex w-full items-center gap-1 rounded-md pr-2 text-left hover:bg-surface-2">
              <span style={{ paddingLeft: `${8 + depth * 12}px` }} className="flex items-center">
                {kids.length > 0 ? (
                  <button
                    onClick={() =>
                      setOpen((prev) => {
                        const next = new Set(prev);
                        if (isOpen) next.delete(n.id);
                        else next.add(n.id);
                        return next;
                      })
                    }
                    className="shrink-0 rounded p-0.5 text-ink-4 hover:text-ink-2"
                  >
                    <Chevron rotate={isOpen ? 90 : 0} />
                  </button>
                ) : (
                  <span className="w-[21px] shrink-0" />
                )}
              </span>
              <button
                onClick={() => onSelect(n.id)}
                className={`flex min-w-0 flex-1 items-center gap-2 py-1.5 text-left ${
                  selectedId === n.id ? "text-accent-ink" : "text-ink-3 hover:text-ink"
                }`}
              >
                <span
                  className={`h-1.5 w-1.5 shrink-0 rounded-full ${
                    n.contentLoaded || n.details ? "bg-ok" : "bg-warn"
                  }`}
                />
                <span className="min-w-0 truncate text-sm">{n.label || "Без названия"}</span>
              </button>
            </div>
            {kids.length > 0 && isOpen && renderRows(kids, depth + 1)}
          </li>
        );
      })}
    </ul>
  );

  return (
    <div className="flex h-full w-72 shrink-0 flex-col border-r border-border bg-surface">
      <div className="flex items-center justify-between border-b border-border px-4 py-3">
        <h3 className="text-sm font-semibold">Оглавление</h3>
        <button onClick={onClose} className="rounded p-1 text-ink-4 hover:text-ink-2">
          <Chevron rotate={-90} />
        </button>
      </div>
      <nav className="flex-1 overflow-y-auto p-2">{renderRows(roots, 0)}</nav>
    </div>
  );
}

export function TutorScreen() {
  const { topicId, topicName, nodes } = useGraphStore();
  const { messages, sending, error, send, reset, timeRemainingMinutes } = useTutorStore();
  const sessionId = useSessionStore((s) => s.session?.id);
  const [input, setInput] = useState("");
  const [tocOpen, setTocOpen] = useState(true);
  const [contextNodeId, setContextNodeId] = useState<string | null>(null);
  const [contextNodeLabel, setContextNodeLabel] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Пока идёт потоковая генерация, последним сообщением становится assistant
  // с накапливающимся текстом — в этом случае спиннер не показываем.
  const lastMsg = messages[messages.length - 1];
  const liveContent =
    sending && lastMsg?.role === "assistant" && lastMsg.content.length > 0;

  useEffect(() => {
    reset();
  }, [reset]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, sending]);

  useEffect(() => {
    if (!contextNodeId) return;
    const node = nodes.find((n) => n.id === contextNodeId);
    if (node && node.label !== contextNodeLabel) setContextNodeLabel(node.label);
  }, [nodes, contextNodeId, contextNodeLabel]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const msg = input.trim();
    if (!msg || !topicId || sending) return;
    setInput("");
    await send(topicId, msg, { sessionId, nodeId: contextNodeId ?? undefined });
  }

  return (
    <div className="flex h-full min-h-0">
      {tocOpen && (
        <TutorToc
          selectedId={contextNodeId}
          onSelect={(id) => {
            setContextNodeId(id);
            const node = nodes.find((n) => n.id === id);
            setContextNodeLabel(node?.label ?? null);
          }}
          onClose={() => setTocOpen(false)}
        />
      )}
      {!tocOpen && (
        <button
          onClick={() => setTocOpen(true)}
          className="w-9 shrink-0 border-r border-border bg-surface text-[11px] text-ink-4 hover:text-ink-2"
          style={{ writingMode: "vertical-rl" }}
        >
          Оглавление
        </button>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <div className="border-b border-border px-6 py-3">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold text-ink">
              Тьютор {topicName ? `· ${topicName}` : ""}
            </h2>
            {contextNodeLabel && (
              <Badge variant="info">{contextNodeLabel}</Badge>
            )}
            {timeRemainingMinutes !== null && (
              <Badge variant={timeRemainingMinutes <= 5 ? "warning" : "muted"}>
                Осталось ≈ {timeRemainingMinutes} мин
              </Badge>
            )}
          </div>
          <p className="text-xs text-ink-4">
            {contextNodeLabel
              ? `Вопрос будет по разделу «${contextNodeLabel}».`
              : "Задайте вопрос по теме, тьютор объяснит и подскажет."}
          </p>
        </div>

        <div className="flex-1 overflow-y-auto px-6 py-4">
          {error && <div className="mb-4"><ErrorBanner message={error} /></div>}
          {messages.length === 0 && (
            <div className="mx-auto max-w-lg py-16 text-center text-sm text-ink-4">
              {contextNodeLabel
                ? `Выберите раздел слева и спросите о «${contextNodeLabel}», либо задайте общий вопрос.`
                : "Здравствуйте! Я ваш персональный тьютор. Выберите раздел в оглавлении слева или спрашивайте в целом по теме."}
            </div>
          )}
          <div className="mx-auto flex max-w-2xl flex-col gap-3">
            {messages.map((m) => (
              <div
                key={m.id}
                className={`max-w-[85%] whitespace-pre-wrap rounded-xl px-4 py-3 text-sm leading-relaxed ${
                  m.role === "user"
                    ? "self-end bg-accent text-white"
                    : "self-start border border-border bg-surface text-ink-2"
                }`}
              >
                {m.content}
                {m.role === "assistant" && m.usedFallback && (
                  <div className="mt-2 text-[10px] uppercase tracking-wide text-ink-4">
                    Отвечено из сохранённого контента
                  </div>
                )}
              </div>
            ))}
            {sending && !liveContent && (
              <div className="self-start rounded-xl border border-border bg-surface p-3">
                <Spinner size="sm" />
              </div>
            )}
            <div ref={bottomRef} />
          </div>
        </div>

        <form onSubmit={submit} className="border-t border-border px-6 py-3">
          <div className="mx-auto flex max-w-2xl gap-2">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder={
                contextNodeLabel
                  ? `Спросите о разделе «${contextNodeLabel}»…`
                  : "Спросите тьютора…"
              }
              disabled={sending}
              className="flex-1 rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink-2 placeholder:text-ink-4 outline-none focus:border-accent"
            />
            <Button type="submit" disabled={sending || !input.trim()}>Отправить</Button>
          </div>
        </form>
      </div>
    </div>
  );
}