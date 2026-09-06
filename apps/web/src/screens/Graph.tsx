import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  Handle,
  Position,
  MarkerType,
  BaseEdge,
  EdgeLabelRenderer,
  getBezierPath,
  useReactFlow,
  useViewport,
  type Node,
  type Edge,
  type NodeProps,
  type EdgeProps,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import {
  convertTreeToGraphFlow,
  cardSize,
  type GraphFlowNode,
  type GraphFlowEdge,
} from "@mindtree/graph";
import { useGraphStore, isNodeVisible, nodeHasHiddenChildren } from "../stores";
import { Spinner, ErrorBanner, ProgressBar } from "@mindtree/ui";

const PHASE_LABELS: Record<string, string> = {
  structure: "Структурирование",
  "structure-l2": "Генерация разделов (L2)",
  "structure-l3": "Генерация подразделов (L3)",
  expand: "Построение дерева",
  validate: "Проверка",
  repair: "Исправление",
  content: "Генерация контента",
  done: "Готово",
};

function BuildOverlay() {
  const pipeline = useGraphStore((s) => s.pipeline);
  // Оверлей прогресса — только пока идёт активная генерация. В состоянии error
  // спиннер не показываем: поверх дерева рендерится сообщение об ошибке.
  if (pipeline.status !== "running") return null;
  const pct =
    pipeline.stats && pipeline.stats.total > 0
      ? Math.min(100, (pipeline.stats.depth / 5) * 100)
      : 0;
  return (
    <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center p-6">
      <div className="pointer-events-auto w-full max-w-sm rounded-xl border border-border-strong bg-surface-2 p-4 shadow-xl">
        <div className="flex items-center gap-3">
          <Spinner size="sm" />
          <span className="text-sm font-medium text-ink-2">
            {PHASE_LABELS[pipeline.phase] ?? "Построение дерева…"}
          </span>
        </div>
        <p className="mt-2 text-xs text-ink-4">{pipeline.message || ""}</p>
        {pipeline.stats && pipeline.stats.total > 0 && (
          <div className="mt-3">
            <ProgressBar
              value={pct}
              label={`Уровней: ${pipeline.stats.depth ?? 0} · Листьев: ${pipeline.stats.leaves ?? 0}`}
            />
          </div>
        )}
      </div>
    </div>
  );
}

type FlowNode = Node;
type FlowEdge = Edge;

function MindNode({ data }: NodeProps) {
  const node = (data as { node: KnowledgeNodeLike }).node;
  const branchColor = (data as { branchColor?: string }).branchColor;
  const revealNode = useGraphStore((s) => s.revealNode);
  const allNodes = useGraphStore((s) => s.nodes);
  const visibleLevel = useGraphStore((s) => s.visibleLevel);
  const revealedNodes = useGraphStore((s) => s.revealedNodes);
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [hovered, setHovered] = useState(false);

  // У узла есть дети в дереве (на любом уровне, включая скрытые) → «Углубить»
  // просто их раскроет. Если детей нет — это настоящий лист, генерируем уровень.
  const hasChildren = allNodes.some(
    (n) => (n as KnowledgeNodeLike).parentId === node.id,
  );
  const isMaxLevel = node.level >= 5;
  const isTerminal = isMaxLevel || (node.leaf && node.state === "expanded");
  const isExpandable = !isTerminal;
  // «Раскрыть» показываем только если есть реально скрытые потомки — иначе
  // клик был бы пустым (например на корне, чьё поддерево уже всё видно).
  const canReveal =
    isExpandable && hasChildren && nodeHasHiddenChildren(node, allNodes, visibleLevel, revealedNodes);
  const canDeepen = isExpandable && !hasChildren;
  // Компактные карточки для L3+ (только label; one-liner/кнопки при наведении).
  const isCompact = node.level >= 3;

  const handleStyle: React.CSSProperties = {
    opacity: 0,
    width: 8,
    height: 8,
    border: "none",
    background: "transparent",
    pointerEvents: "none",
  };

  const HANDLE_SIDES: Array<{ id: string; pos: Position }> = [
    { id: "top", pos: Position.Top },
    { id: "right", pos: Position.Right },
    { id: "bottom", pos: Position.Bottom },
    { id: "left", pos: Position.Left },
  ];

  const dotColor = node.contentLoaded
    ? "bg-ok"
    : node.oneLiner
      ? "bg-ink-4"
      : "bg-warn";

  // Динамическая ширина компактной карточки L3+ (синхронизирована с layout).
  const compactWidth = cardSize(node.level, node.label).w;

  return (
    <div
      className={`rounded-xl border bg-surface shadow-lg ${
        isCompact ? "group p-1.5" : "p-2.5 w-[200px]"
      } ${
        isExpandable
          ? "border-accent ring-2 ring-accent/30"
          : "border-dashed border-border-strong"
      }`}
      style={
        isCompact
          ? { borderColor: branchColor ?? undefined, width: compactWidth }
          : undefined
      }
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {HANDLE_SIDES.map((side) => (
        <Handle
          key={`src-${side.id}`}
          type="source"
          id={side.id}
          position={side.pos}
          style={handleStyle}
        />
      ))}
      {HANDLE_SIDES.map((side) => (
        <Handle
          key={`tgt-${side.id}`}
          type="target"
          id={side.id}
          position={side.pos}
          style={handleStyle}
        />
      ))}
      <div className="flex items-center gap-2">
        <span
          className={`h-2 w-2 shrink-0 rounded-full ${
            branchColor ? "" : dotColor
          }`}
          style={branchColor ? { background: branchColor } : undefined}
        />
        <span
          className={`min-w-0 flex-1 truncate font-semibold text-ink ${
            isCompact ? "text-[12px]" : "text-[13px]"
          }`}
        >
          {node.label || "Без названия"}
        </span>
      </div>
      {!(isCompact && !hovered) && node.oneLiner && (
        <p className="mt-1 line-clamp-2 text-[11px] leading-snug text-ink-4">
          {node.oneLiner}
        </p>
      )}
      {!(isCompact && !hovered) &&
        (canReveal ? (
          <span className="mt-1 inline-block rounded bg-accent/15 px-1.5 py-0.5 text-[10px] font-semibold text-accent-ink">
            есть подразделы
          </span>
        ) : canDeepen ? (
          <span className="mt-1 inline-block rounded bg-accent/15 px-1.5 py-0.5 text-[10px] font-semibold text-accent-ink">
            + можно расширить
          </span>
        ) : !isExpandable ? (
          <span className="mt-1 inline-block rounded bg-surface-2 px-1.5 py-0.5 text-[10px] font-semibold text-ink-4">
            {isMaxLevel ? "максимальная глубина" : "конечный лист"}
          </span>
        ) : null)}
      {!(isCompact && !hovered) && (
        <div className="mt-2 flex items-center gap-2">
          <button
            onClick={() => navigate("../focus", { state: { nodeId: node.id } })}
            className="rounded-md bg-surface-2 px-2 py-0.5 text-xs text-ink-3 hover:bg-surface-3"
          >
            Изучить
          </button>
          {canReveal || canDeepen ? (
            <button
              onClick={async () => {
                setBusy(true);
                await revealNode(node.id);
                setBusy(false);
              }}
              disabled={busy}
              className="rounded-md border border-accent px-2 py-0.5 text-xs text-accent-ink hover:bg-accent disabled:opacity-40"
              title={
                canReveal
                  ? "Раскрыть уже сгенерированные подразделы"
                  : "Сгенерировать подразделы следующего уровня"
              }
            >
              {busy ? (
                <span className="flex items-center gap-1">
                  <Spinner size="sm" />
                  Генерирую…
                </span>
              ) : canReveal ? (
                "Раскрыть"
              ) : (
                "Углубить"
              )}
            </button>
          ) : null}
        </div>
      )}
    </div>
  );
}

interface KnowledgeNodeLike {
  id: string;
  label: string;
  oneLiner: string;
  leaf: boolean;
  level: number;
  parentId?: string | null;
  contentLoaded: boolean;
  state?: string;
}

const nodeTypes = { mindNode: MindNode };

const REL_LABEL_MIN_ZOOM = 0.4;

function RelationEdge(props: EdgeProps) {
  const {
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    markerEnd,
    style,
    label,
    data,
  } = props;
  const { zoom } = useViewport();
  const [path, labelX, labelY] = getBezierPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
  });
  const color = (style as { stroke?: string } | undefined)?.stroke ?? "#64748b";
  const text = typeof label === "string" ? label : "";
  const index = (data as { index?: number } | undefined)?.index ?? 0;
  const groupSize = (data as { groupSize?: number } | undefined)?.groupSize ?? 1;
  const highlighted = (data as { highlighted?: boolean } | undefined)?.highlighted ?? false;
  const stack = (index - (groupSize - 1) / 2) * 18;
  const showLabel = highlighted && zoom >= REL_LABEL_MIN_ZOOM && text.length > 0;

  return (
    <>
      <BaseEdge
        path={path}
        markerEnd={markerEnd}
        style={highlighted ? { ...style, strokeWidth: 3, opacity: 1 } : style}
      />
      {showLabel && (
        <EdgeLabelRenderer>
          <div
            className="pointer-events-none absolute whitespace-nowrap rounded border px-1.5 py-0.5 text-[10px] font-semibold"
            style={{
              transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px) translate(0px, ${stack - 10}px)`,
              borderColor: color,
              backgroundColor: "#ffffff",
              color,
              boxShadow: "0 1px 2px rgba(0,0,0,0.08)",
            }}
          >
            {text}
          </div>
        </EdgeLabelRenderer>
      )}
    </>
  );
}

const edgeTypes = {
  relationEdge: RelationEdge,
  branchEdge: BranchEdge,
};

function BranchEdge(props: EdgeProps) {
  const {
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    style,
  } = props;

  const path = useMemo<string>(() => {
    // Сторону выхода выбирает getEdgeHandles (sourceHandle/targetHandle), а
    // ReactFlow передаёт sourceX/Y в позиции этого хэндла — центр грани.
    // getBezierPath строит кривую из управляющих точек строго наружу от
    // сторон карточек (не коллинеарных), поэтому рёбра выходят из центра
    // стороны, касаются карточки и остаются кривыми.
    const [bezPath] = getBezierPath({
      sourceX,
      sourceY,
      sourcePosition,
      targetX,
      targetY,
      targetPosition,
    });
    return bezPath;
  }, [sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition]);

  return <BaseEdge path={path} style={style} />;
}

function AutoFit({ nodeCount }: { nodeCount: number }) {
  const { fitView } = useReactFlow();
  useEffect(() => {
    if (nodeCount === 0) return;
    const id = requestAnimationFrame(() => {
      fitView({ padding: 0.15, maxZoom: 1, duration: 0 });
    });
    return () => cancelAnimationFrame(id);
  }, [nodeCount, fitView]);
  return null;
}

export function GraphScreen() {
  const { nodes, loading, error, visibleLevel, revealedNodes } = useGraphStore();
  const revealNode = useGraphStore((s) => s.revealNode);
  const pipeline = useGraphStore((s) => s.pipeline);
  const [listOpen, setListOpen] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [hoveredEdgeId, setHoveredEdgeId] = useState<string | null>(null);

  // Показываем только узлы, видимые при базовом уровне ИЛИ раскрытые вручную.
  const visibleNodes = useMemo(
    () => nodes.filter((n) => isNodeVisible(n, nodes, visibleLevel, revealedNodes)),
    [nodes, visibleLevel, revealedNodes],
  );

  const hiddenCount = nodes.length - visibleNodes.length;

  // Узлы, у которых есть дети, которых ещё не видно (для заголовка сайдбара).
  const canDeepen = useMemo(
    () =>
      nodes.filter(
        (n) =>
          isNodeVisible(n, nodes, visibleLevel, revealedNodes) &&
          !(n.level >= 5 || (n.leaf && n.state === "expanded")) &&
          nodes.some((c) => c.parentId === n.id) &&
          nodeHasHiddenChildren(n, nodes, visibleLevel, revealedNodes),
      ),
    [nodes, visibleLevel, revealedNodes],
  );

  const graph = useMemo<{ nodes: FlowNode[]; edges: FlowEdge[] }>(() => {
    const flow = convertTreeToGraphFlow(visibleNodes as never) as unknown as {
      nodes: GraphFlowNode[];
      edges: GraphFlowEdge[];
    };
    return {
      nodes: flow.nodes.map((n) => ({
        id: n.id,
        type: "mindNode",
        position: n.position,
        data: n.data,
      })),
      edges: (() => {
        const groupSize = new Map<string, number>();
        for (const e of flow.edges) {
          if (e.data.kind === "relation") {
            const key = [e.source, e.target].sort().join("|");
            groupSize.set(key, (groupSize.get(key) ?? 0) + 1);
          }
        }
        const cursor = new Map<string, number>();
        return flow.edges.map((e) => {
          if (e.data.kind !== "relation") {
            const color = (e.data as { color?: string }).color;
            const sourceSize = (e.data as { sourceSize?: { w: number; h: number } })
              .sourceSize;
            const stroke = color ?? "#d4d4d8";
            return {
              id: e.id,
              source: e.source,
              target: e.target,
              sourceHandle: e.sourceHandle,
              targetHandle: e.targetHandle,
              type: "branchEdge",
              style: { stroke, strokeWidth: 2, opacity: 0.85 },
              data: { sourceSize },
            };
          }
          const key = [e.source, e.target].sort().join("|");
          const index = cursor.get(key) ?? 0;
          cursor.set(key, index + 1);
          return {
            id: e.id,
            source: e.source,
            target: e.target,
            sourceHandle: e.sourceHandle,
            targetHandle: e.targetHandle,
            type: "relationEdge",
            style: {
              stroke: e.data.color,
              strokeWidth: 1.25,
              strokeDasharray: "5 4",
              opacity: 0.55,
            },
            markerEnd: { type: MarkerType.ArrowClosed, color: e.data.color },
            label: e.data.label,
            interactionWidth: 24,
            data: {
              index,
              groupSize: groupSize.get(key) ?? 1,
              highlighted: hoveredEdgeId === e.id,
            },
          };
        });
      })(),
    };
  }, [visibleNodes, hoveredEdgeId]);

  // Во время активной генерации не прячем дерево за полным спиннером:
  // показываем уже сгенерированную (частичную) часть, а поверх — оверлей
  // «генерируется следующий уровень», чтобы уровни росли прогрессивно.
  const running = pipeline.status === "running";
  if (loading && !running) {
    return (
      <div className="relative h-full">
        <div className="flex h-full items-center justify-center">
          <Spinner />
        </div>
        <BuildOverlay />
      </div>
    );
  }
  // Ошибка без какого-либо сохранённого дерева — полноэкранный баннер.
  if (error && !running && visibleNodes.length === 0) {
    return <ErrorBanner message={error} />;
  }
  if (visibleNodes.length === 0) {
    return (
      <div className="relative flex h-full flex-col items-center justify-center gap-4 p-8 text-center">
        <p className="text-ink-4">Дерево ещё не построено.</p>
        <p className="text-sm text-ink-4">
          Используйте «Фокус», чтобы изучить тему, или перегенерируйте дерево.
        </p>
        <BuildOverlay />
      </div>
    );
  }

  return (
    <div className="relative h-full">
      {error && !running && (
        <div className="absolute left-1/2 top-3 z-20 w-full max-w-md -translate-x-1/2">
          <ErrorBanner
            message={error}
            onDismiss={() => useGraphStore.setState({ error: null })}
          />
        </div>
      )}
      <ReactFlow
        nodes={graph.nodes}
        edges={graph.edges}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        fitView
        fitViewOptions={{ padding: 0.15, maxZoom: 1 }}
        minZoom={0.05}
        defaultViewport={{ x: 0, y: 0, zoom: 0.5 }}
        proOptions={{ hideAttribution: true }}
        onEdgeMouseEnter={(_, edge) => setHoveredEdgeId(edge.id)}
        onEdgeMouseLeave={() => setHoveredEdgeId(null)}
      >
        <AutoFit nodeCount={graph.nodes.length} />
        <Background gap={24} size={1} color="#e4e4e7" />
        <Controls />
        <MiniMap
          nodeColor="#2563eb"
          maskColor="rgba(228,228,231,0.6)"
          className="!bg-surface"
        />
      </ReactFlow>

      {canDeepen.length > 0 && (
        <div className="absolute right-3 top-3 z-10 w-60 rounded-xl border border-border-strong bg-surface-2/95 p-3 shadow-xl backdrop-blur">
          <button
            onClick={() => setListOpen((v) => !v)}
            className="flex w-full items-center justify-between text-left text-sm font-semibold text-ink"
          >
            <span>Есть подразделы ({canDeepen.length})</span>
            <span className="text-ink-4">{listOpen ? "▾" : "▸"}</span>
          </button>
          {hiddenCount > 0 && visibleLevel < 5 && (
            <div className="mt-2 flex items-center gap-2 rounded-md border border-dashed border-border-strong bg-surface-3/50 px-2 py-1.5">
              <span className="flex-1 text-[11px] text-ink-3">
                Скрыто {hiddenCount} узл.
              </span>
            </div>
          )}
          {listOpen && (
            <ul className="mt-2 max-h-72 space-y-1 overflow-y-auto pr-1">
              {canDeepen.map((n) => (
                <li
                  key={n.id}
                  className="flex items-center justify-between gap-2 rounded-md px-1.5 py-1 text-xs hover:bg-surface-3"
                >
                  <span className="min-w-0 flex-1 truncate text-ink-2">{n.label}</span>
                  <button
                    onClick={async () => {
                      setBusyId(n.id);
                      await revealNode(n.id);
                      setBusyId(null);
                    }}
                    disabled={busyId === n.id}
                    className="shrink-0 rounded border border-accent px-1.5 py-0.5 text-[11px] font-semibold text-accent-ink hover:bg-accent disabled:opacity-40"
                    title="Раскрыть подразделы или сгенерировать следующий уровень"
                  >
                    {busyId === n.id ? "…" : "Раскрыть"}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      <BuildOverlay />
    </div>
  );
}
