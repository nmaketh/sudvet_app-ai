export default function RootLoading() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <div className="mx-auto flex min-h-screen w-full max-w-6xl items-center justify-center px-6">
        <div className="w-full max-w-md rounded-2xl border border-border bg-white/90 p-6 shadow-sm">
          <div className="mb-4 h-4 w-28 animate-pulse rounded bg-muted/30" />
          <div className="mb-3 h-10 animate-pulse rounded-xl bg-muted/20" />
          <div className="mb-3 h-10 animate-pulse rounded-xl bg-muted/20" />
          <div className="h-11 animate-pulse rounded-xl bg-primary/20" />
        </div>
      </div>
    </main>
  );
}
