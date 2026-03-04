import { Badge } from "@/components/ui/badge";

type RiskLevel = "low" | "medium" | "high";
type CaseStatus = "open" | "in_treatment" | "resolved";
type TriageStatus = "needs_review" | "escalated";
type Role = "CAHW" | "VET" | "ADMIN";

export function RiskBadge({ value }: { value: RiskLevel | string }) {
  const normalized = String(value).toLowerCase();
  const variant =
    normalized === "high" ? "danger" : normalized === "medium" ? "warn" : "success";
  return <Badge variant={variant}>{normalized.replace("_", " ")}</Badge>;
}

const CASE_STATUS_LABELS: Record<string, string> = {
  open: "Open",
  in_treatment: "In Treatment",
  resolved: "Resolved",
};

export function CaseStatusBadge({ value }: { value: CaseStatus | string }) {
  const normalized = String(value).toLowerCase();
  const variant =
    normalized === "resolved"
      ? "success"
      : normalized === "in_treatment"
        ? "warn"
        : "deep";
  return <Badge variant={variant}>{CASE_STATUS_LABELS[normalized] ?? normalized.replace("_", " ")}</Badge>;
}

const TRIAGE_STATUS_LABELS: Record<string, string> = {
  needs_review: "Needs Review",
  escalated: "In Vet Queue",
};

export function TriageStatusBadge({ value }: { value: TriageStatus | string }) {
  const normalized = String(value).toLowerCase();
  const variant =
    normalized === "escalated"
      ? "danger"
      : normalized === "needs_review"
        ? "warn"
        : "neutral";
  return <Badge variant={variant}>{TRIAGE_STATUS_LABELS[normalized] ?? normalized.replace("_", " ")}</Badge>;
}

export function RoleBadge({ value }: { value: Role | string }) {
  const normalized = String(value).toUpperCase();
  const variant =
    normalized === "ADMIN" ? "danger" : normalized === "VET" ? "deep" : "neutral";
  return <Badge variant={variant}>{normalized}</Badge>;
}

export function MethodBadge({ value }: { value?: string | null }) {
  const normalized = String(value || "unknown").toLowerCase();
  const variant =
    normalized === "hybrid"
      ? "deep"
      : normalized === "clinical_rules"
        ? "accent"
        : normalized === "image"
          ? "success"
          : "neutral";
  return <Badge variant={variant}>{normalized.replace("_", " ")}</Badge>;
}
