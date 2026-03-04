import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold tracking-[0.02em]",
  {
    variants: {
      variant: {
        neutral: "border-[#D7E6DE] bg-[#F6FBF9] text-[#5D6D67]",
        success: "border-[#BFE0D2] bg-[#E9F6F0] text-[#1D6A4F]",
        warn: "border-[#E5CF9E] bg-[#FAEFD8] text-[#7B5B20]",
        danger: "border-[#EDC0B4] bg-[#FDE9E4] text-[#8F4434]",
        accent: "border-[#DEC284] bg-[#F7E8BF] text-[#6D531E]",
        deep: "border-[#B7DDD0] bg-[#E6F5EF] text-[#155C45]",
      },
    },
    defaultVariants: {
      variant: "neutral",
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return (
    <span
      className={cn(badgeVariants({ variant }), className)}
      {...props}
    />
  );
}
