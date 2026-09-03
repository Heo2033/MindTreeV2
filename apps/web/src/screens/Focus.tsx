import { useCallback, useEffect, useMemo, useState } from "react";
import { useLocation } from "react-router-dom";
import type { KnowledgeNode } from "@mindtree/types";
import { useGraphStore } from "../stores";
import { treeApi } from "../api";
import { FormattedText } from "../components/FormattedText";
import { CurrentNodeCard, ChildCard, LeafHint } from "../components/focus/cards";
import { buildChildrenMap, readingOrder, nodePath, canDeepen } from "../lib/tree";
import { ErrorBanner, Spinner, Button } from "@mindtree/ui";

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

function Toc({ nodes, selectedId, onSelect, onClose }: {
  nodes: KnowledgeNode[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onClose: () => void;
}) {
  const childrenMap = useMemo(() => buildChildrenMap(nodes), [nodes]);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const roots = nodes.filter((n) => !n.parentId);

  useEffect(() => {
    if (selectedId) {
      const path = nodePath(nodes, selectedId);
      setOpen((prev) => new Set([...prev, ...path.map((l) => l)]));
    }
  }, [selectedId, nodes]);

  const renderRows = (list: KnowledgeNode[], depth: number) => (
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
                  selectedId === n.id ? "text-accent-ink" : "text-ink-3"
                }`}
              >
                <span
                  className={`h-1.5 w-1.5 shrink-0 rounded-full ${
                    n.contentLoaded ? "bg-ok" : "bg-warn"
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
    <div className="flex h-full w-64 shrink-0 flex-col border-r border-border bg-surface">
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

function Subtree({ nodes, selected, onSelect, onDeepen, deepening, onCollapse }: {
  nodes: KnowledgeNode[];
  selected: KnowledgeNode;
  onSelect: (id: string) => void;
  onDeepen: (id: string) => void;
  deepening: boolean;
  onCollapse: () => void;
}) {
  const childrenMap = useMemo(() => buildChildrenMap(nodes), [nodes]);
  const kids = childrenMap.get(selected.id) ?? [];
  const parent = selected.parentId ? nodes.find((n) => n.id === selected.parentId) || null : null;
  const path = useMemo(() => nodePath(nodes, selected.id), [nodes, selected.id]);

  return (
    <section className="flex h-full min-w-0 flex-1 flex-col border-r border-border bg-surface-2">
      <div className="flex items-center gap-2 border-b border-border px-2 py-2">
        <button onClick={onCollapse} className="rounded p-1 text-ink-4 hover:text-ink-2" title="Скрыть">
          <Chevron rotate={180} />
        </button>
        {parent && (
          <button
            onClick={() => onSelect(parent.id)}
            className="rounded p-1 text-ink-4 hover:text-ink-2"
            title="Наверх"
          >
            ↑
          </button>
        )}
        <div className="flex min-w-0 flex-1 flex-wrap items-center text-xs text-ink-4">
          {path.map((p, i) => (
            <span key={i} className="min-w-0 truncate">
              {i > 0 && <span className="mx-0.5">/</span>}
              {p}
            </span>
          ))}
        </div>
      </div>
      <div className="flex min-h-0 flex-1 flex-col items-center overflow-auto p-4">
        <CurrentNodeCard node={selected} />
        {kids.length > 0 ? (
          <div className="mt-3 w-full">
            <div className="grid grid-cols-2 gap-3">
              {kids.map((child) => (
                <div key={child.id} className="min-w-0">
                  <ChildCard
                    node={child}
                    grandkids={(childrenMap.get(child.id) ?? []).length}
                    selected={false}
                    onSelect={onSelect}
                  />
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="mt-8">
            <LeafHint canDeepen={canDeepen(selected)} isDeepening={deepening} onDeepen={() => onDeepen(selected.id)} />
          </div>
        )}
      </div>
    </section>
  );
}

export function FocusScreen() {
  const location = useLocation();
  const { nodes, error, generateContent, expandNode } = useGraphStore();

  const firstId = useMemo(() => readingOrder(nodes)[0]?.id ?? null, [nodes]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loadingNodeId, setLoadingNodeId] = useState<string | null>(null);
  const [tocOpen, setTocOpen] = useState(true);
  const [treeOpen, setTreeOpen] = useState(true);
  const [explain, setExplain] = useState<{ term: string; explanation?: string; loading: boolean } | null>(null);
  // Узлы, для которых автогенерация контента уже запрошена (успех или ошибка),
  // чтобы при сбое не уйти в бесконечный цикл повторных запросов контента.
  const [attemptedContent, setAttemptedContent] = useState<Set<string>>(new Set());

  useEffect(() => {
    const fromState = (location.state as { nodeId?: string } | null)?.nodeId;
    setSelectedId(fromState ?? firstId);
  }, [firstId, location.state]);

  const selected = selectedId ? nodes.find((n) => n.id === selectedId) || null : null;
  const order = useMemo(() => readingOrder(nodes), [nodes]);
  const currentIndex = selectedId ? order.findIndex((n) => n.id === selectedId) : -1;

  useEffect(() => {
    if (
      selected &&
      !selected.details &&
      selectedId &&
      loadingNodeId !== selectedId &&
      !attemptedContent.has(selectedId)
    ) {
      setLoadingNodeId(selectedId);
      generateContent(selectedId)
        .catch(() => {})
        .finally(() => {
          setLoadingNodeId(null);
          setAttemptedContent((prev) => new Set(prev).add(selectedId));
        });
    }
  }, [selected, selectedId, generateContent, loadingNodeId, attemptedContent]);

  const go = useCallback(
    (delta: number) => {
      const next = currentIndex + delta;
      if (next >= 0 && next < order.length) setSelectedId(order[next].id);
    },
    [currentIndex, order],
  );

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName)) return;
      if (e.key === "ArrowRight") go(1);
      else if (e.key === "ArrowLeft") go(-1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go]);

  async function handleExplain(term: string) {
    if (!selected) return;
    setExplain({ term, loading: true });
    try {
      const res = await treeApi.explainTerm(selected.topicId, term);
      setExplain({ term, explanation: res.explanation, loading: false });
    } catch {
      setExplain({ term, loading: false, explanation: "Не удалось объяснить термин." });
    }
  }

  if (nodes.length === 0) {
    return (
      <div className="flex h-full items-center justify-center p-8 text-ink-4">
        Постройте дерево, чтобы изучать тему по веткам.
      </div>
    );
  }
  if (error) return <div className="p-8"><ErrorBanner message={error} /></div>;

  return (
    <div className="relative flex h-full min-h-0">
      {tocOpen && <Toc nodes={nodes} selectedId={selectedId} onSelect={setSelectedId} onClose={() => setTocOpen(false)} />}
      {!tocOpen && (
        <button onClick={() => setTocOpen(true)} className="w-9 shrink-0 border-r border-border bg-surface text-[11px] text-ink-4 hover:text-ink-2" style={{ writingMode: "vertical-rl" }}>
          Оглавление
        </button>
      )}
      {treeOpen && selected && (
        <Subtree
          nodes={nodes}
          selected={selected}
          onSelect={setSelectedId}
          onDeepen={(id) => { setLoadingNodeId(id); expandNode(id).finally(() => setLoadingNodeId(null)); }}
          deepening={loadingNodeId === selected.id}
          onCollapse={() => setTreeOpen(false)}
        />
      )}
      {!treeOpen && (
        <button onClick={() => setTreeOpen(true)} className="w-9 shrink-0 border-r border-border bg-surface text-[11px] text-ink-4 hover:text-ink-2" style={{ writingMode: "vertical-rl" }}>
          Структура ветки
        </button>
      )}

      <article className="relative flex min-w-0 flex-1 flex-col border-l border-border">
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="px-6 py-8">
            {currentIndex >= 0 && (
              <p className="mb-1 text-xs font-medium uppercase tracking-wide text-ink-4">
                Раздел {currentIndex + 1} из {order.length}
              </p>
            )}
            <h1 className="text-2xl font-bold tracking-tight text-ink">
              {selected?.label || "Тема"}
            </h1>
{loadingNodeId === selectedId && !selected?.details ? (
              <div className="mt-8 flex flex-col items-center gap-3 py-10">
                <Spinner />
                <span className="text-sm text-ink-3">Контент подгружается…</span>
              </div>
            ) : selected ? (
              <>
                {selected.oneLiner && (
                  <p className="mt-2 text-base leading-relaxed text-ink-3">{selected.oneLiner}</p>
                )}
                <div
                  className="mt-6 whitespace-pre-wrap text-[15px] leading-relaxed text-ink-2"
                  onMouseUp={() => {
                    const sel = window.getSelection();
                    const text = sel?.toString().trim() ?? "";
                    if (text.length >= 2 && text.length <= 200 && sel?.getRangeAt(0)) {
                      handleExplain(text);
                      sel?.removeAllRanges();
                    }
                  }}
                >
                  <FormattedText
                    text={selected.details}
                    fallback="Контент раздела ещё не сгенерирован…"
                  />
                </div>
                {selected.analogy && (
                  <div className="mt-6 rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm leading-relaxed text-warn">
                    <span className="font-semibold">Простыми словами: </span>
                    {selected.analogy}
                  </div>
                )}
                {selected.sources && selected.sources.length > 0 && (
                  <div className="mt-6 rounded-lg border border-border bg-surface px-4 py-3 text-sm">
                    <span className="font-semibold text-ink-2">Источники:</span>
                    <ul className="mt-1.5 list-disc space-y-1 pl-5 text-ink-3">
                      {selected.sources.map((src, i) => (
                        <li key={i}>{src}</li>
                      ))}
                    </ul>
                    <p className="mt-2 text-xs text-ink-4">
                      Контент сгенерирован ИИ и не считается автоматически достоверным — сверяйте с приведёнными источниками.
                    </p>
                  </div>
                )}
                {selected.details && selected.details.length > 400 && (
                  <div className="mt-6">
                    <Button variant="secondary" size="sm" onClick={() => generateContent(selected.id)}>
                      Обновить контент
                    </Button>
                  </div>
                )}
              </>
            ) : null}
          </div>
        </div>

        {explain && (
          <div className="absolute bottom-24 left-1/2 z-20 w-[28rem] max-w-[90vw] -translate-x-1/2 rounded-xl border border-accent bg-surface p-4 shadow-2xl">
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold text-accent-ink">«{explain.term}»</span>
              <button onClick={() => setExplain(null)} className="text-ink-4 hover:text-ink">✕</button>
            </div>
            <p className="mt-2 text-sm text-ink-2">
              {explain.loading ? <Spinner size="sm" /> : explain.explanation ?? ""}
            </p>
          </div>
        )}

        <div className="border-t border-border px-6 py-3">
          <div className="mx-auto flex max-w-2xl items-center justify-between gap-3">
            <Button variant="secondary" size="sm" disabled={currentIndex <= 0} onClick={() => go(-1)}>
              ← Предыдущий
            </Button>
            <span className="text-xs text-ink-4">
              {order.length > 0 ? `${currentIndex + 1} / ${order.length}` : ""}
            </span>
            <Button variant="secondary" size="sm" disabled={currentIndex < 0 || currentIndex >= order.length - 1} onClick={() => go(1)}>
              Следующий →
            </Button>
          </div>
        </div>
      </article>
    </div>
  );
}
