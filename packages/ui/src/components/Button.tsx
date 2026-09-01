import type { ButtonHTMLAttributes } from "react";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost";
  size?: "sm" | "md" | "lg";
}

const variants = {
  primary:
    "bg-accent text-white hover:bg-accent-hover active:bg-accent-active shadow-sm",
  secondary:
    "bg-surface text-ink border border-border hover:border-border-strong hover:bg-surface-2 active:bg-surface-3 shadow-card",
  ghost: "bg-transparent text-ink-2 hover:bg-surface-2 hover:text-ink active:bg-surface-3",
};

const sizes = {
  sm: "px-3 py-1.5 text-[13px]",
  md: "px-4 py-2 text-sm",
  lg: "px-6 py-3 text-[15px]",
};

export function Button({
  variant = "primary",
  size = "md",
  className = "",
  ...props
}: ButtonProps) {
  return (
    <button
      className={`inline-flex items-center justify-center gap-2 rounded-lg font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    />
  );
}
