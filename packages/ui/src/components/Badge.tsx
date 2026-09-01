import type { ReactNode } from "react";

export type BadgeVariant =
  | "default"
  | "success"
  | "warning"
  | "danger"
  | "info"
  | "muted";

const variants: Record<BadgeVariant, string> = {
  default: "bg-surface-2 text-ink-2 border border-border",
  success: "bg-ok-soft text-ok border border-ok/20",
  warning: "bg-warn-soft text-warn border border-warn/20",
  danger: "bg-danger-soft text-danger border border-danger/20",
  info: "bg-accent-soft text-accent-ink border border-accent/20",
  muted: "bg-surface-2 text-ink-4 border border-border",
};

interface BadgeProps {
  variant?: BadgeVariant;
  children: ReactNode;
  className?: string;
}

export function Badge({ variant = "default", children, className = "" }: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${variants[variant]} ${className}`}
    >
      {children}
    </span>
  );
}
