import { useMemo, type ReactNode } from "react";
import katex from "katex";
import "katex/dist/katex.min.css";

interface FormattedTextProps {
  text?: string;
  fallback?: string;
}

interface Segment {
  type: "text" | "math-display" | "math-inline";
  content: string;
}

function parseSegments(text: string): Segment[] {
  const segments: Segment[] = [];
  let rest = text;

  while (rest.length > 0) {
    const displayIdx = rest.indexOf("$$");
    const inlineIdx = rest.indexOf("$");

    let nextIdx: number;
    let type: Segment["type"];

    if (displayIdx !== -1 && (inlineIdx === -1 || displayIdx <= inlineIdx)) {
      nextIdx = displayIdx;
      type = "math-display";
    } else if (inlineIdx !== -1) {
      nextIdx = inlineIdx;
      type = "math-inline";
    } else {
      segments.push({ type: "text", content: rest });
      break;
    }

    if (nextIdx > 0) {
      segments.push({ type: "text", content: rest.slice(0, nextIdx) });
    }

    const delimLen = type === "math-display" ? 2 : 1;
    const endIdx = rest.indexOf(type === "math-display" ? "$$" : "$", nextIdx + delimLen);

    if (endIdx === -1) {
      segments.push({ type: "text", content: rest.slice(nextIdx) });
      break;
    }

    const formula = rest.slice(nextIdx + delimLen, endIdx);
    if (formula.trim().length > 0) {
      segments.push({ type, content: formula });
    } else {
      segments.push({ type: "text", content: rest.slice(nextIdx, endIdx + delimLen) });
    }

    rest = rest.slice(endIdx + delimLen);
  }

  return segments;
}

function renderSegment(seg: Segment, key: number): ReactNode {
  if (seg.type === "text") {
    return <span key={key}>{seg.content}</span>;
  }

  try {
    const html = katex.renderToString(seg.content, {
      displayMode: seg.type === "math-display",
      throwOnError: false,
      strict: false,
    });
    return (
      <span
        key={key}
        className={seg.type === "math-display" ? "katex-display-block" : ""}
        dangerouslySetInnerHTML={{ __html: html }}
      />
    );
  } catch {
    return (
      <code key={key}         className="text-danger">
        {seg.content}
      </code>
    );
  }
}

export function FormattedText({ text, fallback }: FormattedTextProps) {
  const content = text || fallback || "";
  const nodes = useMemo(() => parseSegments(content).map(renderSegment), [content]);
  return <>{nodes}</>;
}

export default FormattedText;
