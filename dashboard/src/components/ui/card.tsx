import { cn } from "@/lib/utils";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "sv-glow-card rounded-2xl border border-border bg-panel p-4 text-foreground",
        className
      )}
      {...props}
    />
  );
}
