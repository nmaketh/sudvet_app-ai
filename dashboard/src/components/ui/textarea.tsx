import { cn } from "@/lib/utils";

export function Textarea({ className, ...props }: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-[100px] w-full rounded-lg border border-border bg-white px-3 py-2 text-sm text-foreground shadow-[0_1px_0_rgba(255,255,255,0.9)_inset] outline-none transition-colors placeholder:text-[#8A9892] focus:border-[#7BC2AB] focus:ring-2 focus:ring-[#D8F0E7]",
        className
      )}
      {...props}
    />
  );
}
