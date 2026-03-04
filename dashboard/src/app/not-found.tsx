import Link from "next/link";

export default function NotFound() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="mx-auto flex min-h-screen w-full max-w-3xl items-center justify-center px-6">
        <div className="w-full rounded-2xl border border-border bg-white p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
            404
          </p>
          <h1 className="mt-2 text-2xl font-semibold">Page not found</h1>
          <p className="mt-2 text-sm text-muted">
            The dashboard route you requested does not exist or has moved.
          </p>
          <div className="mt-4 flex gap-3">
            <Link
              href="/overview"
              className="rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-white"
            >
              Go to Overview
            </Link>
            <Link
              href="/triage"
              className="rounded-xl border border-border px-4 py-2 text-sm font-semibold text-foreground"
            >
              Open Triage Queue
            </Link>
          </div>
        </div>
      </div>
    </main>
  );
}
