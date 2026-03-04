"use client";

type Props = {
  error: Error & { digest?: string };
  reset: () => void;
};

export default function RootError({ error, reset }: Props) {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="mx-auto flex min-h-screen w-full max-w-3xl items-center justify-center px-6">
        <div className="w-full rounded-2xl border border-red-200 bg-white p-6 shadow-sm">
          <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-red-700">
            Dashboard Error
          </p>
          <h1 className="text-2xl font-semibold text-slate-900">
            Something went wrong while loading the dashboard.
          </h1>
          <p className="mt-2 text-sm text-slate-600">
            Try again. If the problem persists, check the API health and server logs.
          </p>
          <pre className="mt-4 max-h-36 overflow-auto rounded-xl border border-slate-200 bg-slate-50 p-3 text-xs text-slate-700">
            {error.message || "Unknown error"}
          </pre>
          <div className="mt-4 flex gap-3">
            <button
              type="button"
              onClick={reset}
              className="rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-white"
            >
              Retry
            </button>
            <a
              href="/system"
              className="rounded-xl border border-border px-4 py-2 text-sm font-semibold text-foreground"
            >
              Open System Page
            </a>
          </div>
        </div>
      </div>
    </main>
  );
}
