import { useEffect, useId, useRef, useState } from "react";

interface Option {
  value: string;
  label: string;
}

interface SelectProps {
  label?: string;
  options: Option[];
  value?: string | number | null;
  placeholder?: string;
  error?: string;
  disabled?: boolean;
  className?: string;
  onChange?: (e: { target: { value: string } }) => void;
}

export function Select({
  label,
  options,
  value,
  placeholder,
  error,
  disabled = false,
  className = "",
  onChange,
}: SelectProps) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  const selected = options.find((o) => String(o.value) === String(value));

  useEffect(() => {
    if (!open) return;
    function onDocClick(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  function choose(o: Option) {
    setOpen(false);
    onChange?.({ target: { value: o.value } });
  }

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={id} className="text-sm font-medium text-ink-2">
          {label}
        </label>
      )}
      <div ref={rootRef} className="relative">
        <button
          type="button"
          id={id}
          disabled={disabled}
          aria-haspopup="listbox"
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
          className={`flex w-full items-center justify-between gap-2 rounded-lg border border-border bg-surface px-3 py-2 text-left text-sm text-ink shadow-card focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none disabled:bg-surface-2 disabled:opacity-60 ${className}`}
        >
          <span className={selected ? "" : "text-ink-4"}>
            {selected ? selected.label : placeholder ?? "Выберите…"}
          </span>
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            className={`shrink-0 text-ink-4 transition-transform ${open ? "rotate-180" : ""}`}
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        </button>

        {open && (
          <ul
            role="listbox"
            className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded-lg border border-border bg-surface py-1 shadow-pop"
          >
            {options.map((o) => {
              const active = String(o.value) === String(value);
              return (
                <li
                  key={o.value}
                  role="option"
                  aria-selected={active}
                  onClick={() => choose(o)}
                  className={`cursor-pointer px-3 py-2 text-sm ${
                    active ? "bg-accent-soft text-accent-ink" : "text-ink hover:bg-surface-2 hover:text-ink"
                  }`}
                >
                  {o.label}
                </li>
              );
            })}
          </ul>
        )}
      </div>
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}
