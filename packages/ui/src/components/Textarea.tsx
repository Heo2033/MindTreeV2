import type { TextareaHTMLAttributes } from "react";

interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
  error?: string;
}

export function Textarea({ label, error, className = "", ...props }: TextareaProps) {
  return (
    <div className="flex flex-col gap-1.5">
      {label && <label className="text-sm font-medium text-ink-2">{label}</label>}
      <textarea
        className={`w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink shadow-card placeholder:text-ink-4 focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none disabled:bg-surface-2 disabled:opacity-60 ${className}`}
        {...props}
      />
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}
