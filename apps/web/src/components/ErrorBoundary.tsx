import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  message: string | null;
}

/**
 * Ловит ошибки рендера в любом дочернем сабдереве, чтобы одна сломанная
 * страница не валила всё приложение белым экраном.
 */
export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, message: null };
  }

  static getDerivedStateFromError(error: unknown): State {
    return {
      hasError: true,
      message: error instanceof Error ? error.message : String(error),
    };
  }

  componentDidCatch(error: unknown) {
    console.error("[ErrorBoundary]", error);
  }

  private handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div
          className="flex h-screen w-full flex-col items-center justify-center gap-3 bg-canvas p-6 text-center text-ink"
          style={{ fontFamily: "system-ui, sans-serif" }}
        >
          <h1 className="text-xl font-bold">Что-то пошло не так</h1>
          <p className="max-w-md text-sm text-ink-4">
            При рендере страницы произошла ошибка. Перезагрузите страницу или
            попробуйте заново.
          </p>
          {this.state.message && (
            <pre className="max-w-xl overflow-auto rounded-lg border border-border bg-surface p-3 text-left text-xs text-danger">
              {this.state.message}
            </pre>
          )}
          <button
            onClick={this.handleReload}
            className="rounded-lg bg-accent px-4 py-2 text-sm font-medium text-ink transition-colors hover:opacity-90"
          >
            Перезагрузить
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
