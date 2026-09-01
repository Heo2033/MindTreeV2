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
  getSmoothStepPath,
  useReactFlow,
  useViewport,
  type Node,
  type Edge,
  type NodeProps,
  type EdgeProps,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { convertTreeToGraphFlow, type GraphFlowNode, type GraphFlowEdge } from "@mindtree/graph";
import { useGraphStore } from "../stores";
import { Spinner, ErrorBanner, ProgressBar } from "@mindtree/ui";

const PHASE_LABELS: Record<string, string> = {
  structure: "Структурирование",
  expand: "Построение дерева",
  validate: "Проверка",
  repair: "Исправление",
  content: "Генерация контента",
  done: "Готово",
};

function BuildOverlay() {
  const pipeline = useGraphStore((s) => s.pipeline);
  if (pipeline.status !== "running" && pipeline.status !== "error") return null;
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
  const expandNode = useGraphStore((s) => s.expandNode);
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);

  const isLeaf = node.leaf || node.level >= 5;

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

  return (
    <div className="w-[200px] rounded-xl border border-border-strong bg-surface p-2.5 shadow-lg">
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
            node.contentLoaded ? "bg-ok" : node.oneLiner ? "bg-ink-4" : "bg-warn"
          }`}
        />
        <span className="min-w-0 flex-1 truncate text-[13px] font-semibold text-ink">
          {node.label || "Без названия"}
        </span>
      </div>
      {node.oneLiner && (
        <p className="mt-1 line-clamp-2 text-[11px] leading-snug text-ink-4">
          {node.oneLiner}
        </p>
      )}
      <div className="mt-2 flex items-center gap-2">
        <button
          onClick={() => navigate("../focus", { state: { nodeId: node.id } })}
          className="rounded-md bg-surface-2 px-2 py-0.5 text-xs text-ink-3 hover:bg-surface-3"
        >
          Изучить
        </button>
        {!isLeaf && (
          <button
            onClick={async () => {
              setBusy(true);
              await expandNode(node.id);
              setBusy(false);
            }}
            disabled={busy}
            className="rounded-md border border-accent px-2 py-0.5 text-xs text-accent-ink hover:bg-accent disabled:opacity-40"
          >
            {busy ? "…" : "Углубить"}
          </button>
        )}
      </div>
    </div>
  );
}

interface KnowledgeNodeLike {
  id: string;
  label: string;
  oneLiner: string;
  leaf: boolean;
  level: number;
  contentLoaded: boolean;
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
  const [path, labelX, labelY] = getSmoothStepPath({
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
  const stack = (index - (groupSize - 1) / 2) * 18;
  const showLabel = zoom >= REL_LABEL_MIN_ZOOM && text.length > 0;

  return (
    <>
      <BaseEdge path={path} markerEnd={markerEnd} style={style} />
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

const edgeTypes = { relationEdge: RelationEdge };

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
  const { nodes, loading, error } = useGraphStore();

  const graph = useMemo<{ nodes: FlowNode[]; edges: FlowEdge[] }>(() => {
    const flow = convertTreeToGraphFlow(nodes as never) as unknown as {
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
            return {
              id: e.id,
              source: e.source,
              target: e.target,
              sourceHandle: e.sourceHandle,
              targetHandle: e.targetHandle,
              type: "smoothstep",
              style: { stroke: "#d4d4d8", strokeWidth: 1 },
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
            style: { stroke: e.data.color, strokeWidth: 1.5 },
            markerEnd: { type: MarkerType.ArrowClosed, color: e.data.color },
            label: e.data.label,
            data: { index, groupSize: groupSize.get(key) ?? 1 },
          };
        });
      })(),
    };
  }, [nodes]);

  if (loading) {
    return (
      <div className="relative h-full">
        <div className="flex h-full items-center justify-center">
          <Spinner />
        </div>
        <BuildOverlay />
      </div>
    );
  }
  if (error) return <ErrorBanner message={error} />;
  if (nodes.length === 0) {
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
      <BuildOverlay />
    </div>
  );
}
