import * as LabelPrimitive from "@radix-ui/react-label";

export function Label({ ...props }: React.ComponentPropsWithoutRef<typeof LabelPrimitive.Root>) {
  return <LabelPrimitive.Root className="text-sm font-medium text-muted" {...props} />;
}
