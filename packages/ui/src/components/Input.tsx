import type { InputHTMLAttributes } from "react";

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export function Input({ label, error, className = "", ...props }: InputProps) {
  return (
    <div className="flex flex-col gap-1.5">
      {label && <label className="text-sm font-medium text-ink-2">{label}</label>}
      <input
        className={`w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink shadow-card placeholder:text-ink-4 focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none disabled:bg-surface-2 disabled:opacity-60 ${className}`}
        {...props}
      />
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}
