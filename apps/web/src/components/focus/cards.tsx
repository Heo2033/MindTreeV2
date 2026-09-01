import type { KnowledgeNode } from "@mindtree/types";

function dotClass(node: KnowledgeNode): string {
  if (node.contentLoaded || node.state === "content_generated") return "bg-ok";
  if (node.oneLiner) return "bg-ink-4";
  return "border border-warn";
}

export function CurrentNodeCard({ node }: { node: KnowledgeNode }) {
  return (
    <div className="flex max-w-[260px] flex-col items-center rounded-xl border-2 border-accent/70 bg-surface px-4 py-2 shadow-lg">
      <div className="flex items-center gap-1.5">
        <span className={`inline-block h-2 w-2 shrink-0 rounded-full ${dotClass(node)}`} />
        <span className="truncate text-sm font-semibold text-ink">
          {node.label || "Без названия"}
        </span>
      </div>
      {node.oneLiner && (
        <p className="mt-1 line-clamp-2 text-center text-[11px] leading-snug text-ink-4">
          {node.oneLiner}
        </p>
      )}
    </div>
  );
}

function ChevronDownTiny() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}

export interface ChildCardProps {
  node: KnowledgeNode;
  grandkids: number;
  selected?: boolean;
  onSelect: (id: string) => void;
}

export function ChildCard({ node, grandkids, selected = false, onSelect }: ChildCardProps) {
  const drillable = grandkids > 0;
  return (
    <button
      type="button"
      onClick={() => onSelect(node.id)}
      title={drillable ? `Открыть поддерево «${node.label || "Без названия"}»` : "Раздел без подуровней"}
      className={`group w-full rounded-lg border bg-surface p-2 text-left shadow transition-all ${
        selected
          ? "border-accent ring-2 ring-accent"
          : drillable
            ? "border-border-strong hover:-translate-y-0.5 hover:border-accent hover:shadow-md"
            : "border-dashed border-border-strong hover:border-border-strong"
      }`}
    >
      <div className="flex items-center gap-1.5">
        <span className={`inline-block h-1.5 w-1.5 shrink-0 rounded-full ${dotClass(node)}`} />
        <span className="truncate text-xs font-medium text-ink-2">
          {node.label || "Без названия"}
        </span>
      </div>
      {node.oneLiner && (
        <p className="mt-1 line-clamp-2 text-[10px] leading-snug text-ink-4">{node.oneLiner}</p>
      )}
      <div className="mt-1.5 flex min-h-[14px] items-center justify-between">
        {drillable ? (
          <span className="rounded-full bg-surface-2 px-1.5 py-0.5 font-mono text-[9px] font-bold text-ink-4">
            +{grandkids}
          </span>
        ) : (
          <span className="rounded bg-surface-2 px-1 py-px text-[9px] text-ink-4">лист</span>
        )}
        {drillable && (
          <span className="text-ink-4 transition-colors group-hover:text-accent-ink">
            <ChevronDownTiny />
          </span>
        )}
      </div>
    </button>
  );
}

export interface LeafHintProps {
  canDeepen: boolean;
  isDeepening: boolean;
  onDeepen: () => void;
}

export function LeafHint({ canDeepen, isDeepening, onDeepen }: LeafHintProps) {
  return (
    <div className="rounded-lg border border-dashed border-border-strong px-5 py-3 text-center">
      <p className="text-xs text-ink-4">Это лист дерева.</p>
      {canDeepen ? (
        <button
          type="button"
          disabled={isDeepening}
          className="mt-2 rounded-md bg-accent px-3 py-1 text-xs font-medium text-ink transition-colors hover:bg-accent-hover disabled:cursor-not-allowed disabled:opacity-50"
          onClick={onDeepen}
        >
          {isDeepening ? "Углубляем…" : "Углубить ветку"}
        </button>
      ) : (
        <p className="mt-1 text-[11px] text-ink-4">Максимальная детализация достигнута</p>
      )}
    </div>
  );
}
