import { cn } from "@/lib/utils";

export function Select({ className, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        "h-10 w-full rounded-lg border border-border bg-white px-3 text-sm text-foreground shadow-[0_1px_0_rgba(255,255,255,0.9)_inset] outline-none transition-colors focus:border-[#7BC2AB] focus:ring-2 focus:ring-[#D8F0E7]",
        className
      )}
      {...props}
    />
  );
}
