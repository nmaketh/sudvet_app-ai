import { cn } from "@/lib/utils";

export function PageHeader({
  title,
  description,
  eyebrow,
  actions,
  className,
}: {
  title: string;
  description?: string;
  eyebrow?: string;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between", className)}>
      <div className="space-y-1">
        {eyebrow && (
          <p className="sv-eyebrow text-[#BB8927]">{eyebrow}</p>
        )}
        <h1
          className="text-[28px] font-bold leading-[1.08] tracking-[-0.025em] text-[#1D2A25]"
          style={{ fontFamily: "var(--font-sora)" }}
        >
          {title}
        </h1>
        {description && (
          <p className="max-w-2xl text-[13.5px] leading-[1.65] text-[#65756F]">{description}</p>
        )}
      </div>
      {actions && <div className="mt-1 shrink-0">{actions}</div>}
    </div>
  );
}
