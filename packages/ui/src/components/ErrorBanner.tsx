interface ErrorBannerProps {
  message?: string | null;
  onDismiss?: () => void;
}

export function ErrorBanner({ message, onDismiss }: ErrorBannerProps) {
  if (!message) return null;
  return (
    <div className="flex items-start justify-between gap-3 rounded-lg border border-danger/30 bg-danger-soft px-4 py-3 text-sm text-danger">
      <span>{message}</span>
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="text-danger/70 hover:text-danger"
          aria-label="Закрыть"
        >
          ✕
        </button>
      )}
    </div>
  );
}
