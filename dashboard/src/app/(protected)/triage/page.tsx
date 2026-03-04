"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { Activity, Clock3, Filter, Search, ShieldCheck, UserCheck2 } from "lucide-react";

import { PageHeader } from "@/components/layout/page-header";
import { DataTable } from "@/components/ui/data-table";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { CaseStatusBadge, RiskBadge, TriageStatusBadge } from "@/components/ui/domain-badges";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { api } from "@/lib/api";
import { getAuthState } from "@/lib/auth";
import type { CaseItem } from "@/lib/types";

function QueueMetricCard({
  label,
  value,
  subtitle,
  icon: Icon,
  tone,
}: {
  label: string;
  value: number;
  subtitle: string;
  icon: React.ElementType;
  tone: "green" | "amber" | "red" | "slate";
}) {
  const tones = {
    green: { bg: "bg-[#EAF7F1]", text: "text-[#155C45]", ring: "border-[#BEE1D3]" },
    amber: { bg: "bg-[#FBF3DF]", text: "text-[#6E531C]", ring: "border-[#E4CF9F]" },
    red: { bg: "bg-[#FDEEEA]", text: "text-[#8E4433]", ring: "border-[#EDC6BC]" },
    slate: { bg: "bg-[#F4F8F6]", text: "text-[#465851]", ring: "border-border" },
  } as const;
  const c = tones[tone];
  return (
    <div className={`rounded-2xl border p-4 ${c.ring} ${c.bg}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className={`text-[11px] font-semibold uppercase tracking-[0.12em] ${c.text}`}>{label}</p>
          <p className="mt-1 text-2xl font-bold leading-none text-foreground">{value}</p>
          <p className="mt-1 text-xs text-muted">{subtitle}</p>
        </div>
        <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white/80 ${c.text}`}>
          <Icon size={16} />
        </div>
      </div>
    </div>
  );
}

export default function TriagePage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const auth = getAuthState();
  const isVetUser = auth?.user.role === "VET";
  const isAdminUser = auth?.user.role === "ADMIN";

  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [triageStatus, setTriageStatus] = useState("");
  const [activeQueue, setActiveQueue] = useState<"all" | "claimable" | "mine" | "requested">("all");
  const [selected, setSelected] = useState<string[]>([]);
  const [bulkNotice, setBulkNotice] = useState<string | null>(null);

  // When a queue tab is active, it takes precedence over the triage_status filter
  const queueParam = activeQueue !== "all"
    ? activeQueue === "mine" ? "assigned_to_me" : activeQueue === "requested" ? "requested_for_me" : "claimable"
    : "";
  const queryString = new URLSearchParams(
    Object.entries({
      q: search,
      status,
      triage_status: queueParam ? "" : triageStatus,
      queue: queueParam,
    }).filter(([, v]) => v)
  ).toString();

  const casesQuery = useQuery<CaseItem[]>({
    queryKey: ["triage-cases", queryString],
    queryFn: () => api.listCases(queryString),
    refetchInterval: 15000,
    refetchOnWindowFocus: true,
    placeholderData: (prev) => prev, // keep previous data while switching tabs
  });

  // Separate query for global stats (always uses full scope, no queue/search filter)
  const statsQuery = useQuery<CaseItem[]>({
    queryKey: ["triage-stats"],
    queryFn: () => api.listCases(""),
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });

  const canRunBulkActions = isVetUser || isAdminUser;

  const queueStats = useMemo(() => {
    const rows = statsQuery.data || casesQuery.data || [];
    return {
      total: rows.length,
      highRisk: rows.filter((c) => c.risk_level === "high").length,
      needsReview: rows.filter((c) => c.triage_status === "needs_review").length,
      unassigned: rows.filter((c) => !c.assigned_to_user_id).length,
      escalated: rows.filter((c) => c.triage_status === "escalated").length,
    };
  }, [statsQuery.data, casesQuery.data]);

  const selectedCases = useMemo(() => {
    const selectedSet = new Set(selected);
    return (casesQuery.data || []).filter((c) => selectedSet.has(c.id));
  }, [casesQuery.data, selected]);

  const selectedHighRisk = selectedCases.filter((c) => c.risk_level === "high").length;

  const bulkMutation = useMutation({
    mutationFn: async ({ action }: { action: "assign" | "needs_review" | "escalated" }) => {
      for (const id of selected) {
        if (action === "assign" && auth?.user.id) {
          // VET uses /claim (self-service); ADMIN uses /assign (dispatch)
          if (isVetUser) {
            await api.claimCase(id);
          } else {
            await api.assignCase(id, auth.user.id);
          }
        } else if (action === "needs_review") {
          await api.patchCase(id, { triage_status: "needs_review" });
        } else {
          await api.patchCase(id, { triage_status: "escalated" });
        }
      }
      return action;
    },
    onMutate: () => {
      setBulkNotice(null);
    },
    onSuccess: async (action) => {
      const labelMap = {
        assign: "Assigned selected cases to your queue.",
        needs_review: "Selected cases marked as needs review.",
        escalated: "Selected cases escalated for higher-priority review.",
      } as const;
      setBulkNotice(labelMap[action]);
      setSelected([]);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["overview-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics-summary-overview"] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics"] }),
      ]);
    },
    onError: (error) => {
      setBulkNotice(error instanceof Error ? error.message : "Bulk action failed.");
    },
  });

  const columns = useMemo<ColumnDef<CaseItem>[]>(
    () => [
      {
        id: "select",
        header: "",
        cell: ({ row }) => (
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-[#B6CEC4] text-[#1F8A66] focus:ring-[#1F8A66]"
            checked={selected.includes(row.original.id)}
            onClick={(e) => e.stopPropagation()}
            onChange={(e) => {
              const id = row.original.id;
              setSelected((prev) =>
                e.target.checked
                  ? (prev.includes(id) ? prev : [...prev, id])
                  : prev.filter((item) => item !== id)
              );
            }}
          />
        ),
      },
      {
        header: "Created",
        cell: ({ row }) => (
          <div className="w-[88px] shrink-0">
            <p className="text-xs font-semibold text-foreground">
              {new Date(row.original.created_at).toLocaleDateString(undefined, {
                month: "short",
                day: "numeric",
              })}
            </p>
            <p className="text-[11px] text-muted">
              {new Date(row.original.created_at).toLocaleTimeString(undefined, {
                hour: "2-digit",
                minute: "2-digit",
              })}
            </p>
          </div>
        ),
      },
      {
        header: "Case / Animal",
        cell: ({ row }) => (
          <div className="min-w-[140px]">
            <p className="font-mono text-xs font-semibold text-foreground">
              {row.original.id.slice(0, 8).toUpperCase()}
            </p>
            <p className="truncate text-[11px] text-muted">
              {row.original.animal_tag || "Unlinked animal"}
            </p>
            <p className="truncate text-[11px] text-muted/70">
              {row.original.submitted_by_name || `User #${row.original.submitted_by_user_id}`}
            </p>
          </div>
        ),
      },
      {
        header: "Prediction",
        cell: ({ row }) => {
          const confidence = typeof row.original.confidence === "number" ? row.original.confidence : null;
          const pct = confidence !== null ? Math.round(confidence * 100) : null;
          return (
            <div className="min-w-[150px]">
              <p className="text-xs font-semibold capitalize text-foreground">
                {String(
                  row.original.prediction_json?.display_label ||
                    row.original.prediction_json?.final_label ||
                    row.original.prediction_json?.label ||
                    "unknown"
                )}
              </p>
              <p className="text-[11px] text-muted">{row.original.method || "–"}</p>
              {pct !== null && (
                <div className="mt-1 flex items-center gap-1.5">
                  <div className="h-1 w-16 overflow-hidden rounded-full bg-[#E7F1ED]">
                    <div className="h-full rounded-full bg-[#1F8A66]" style={{ width: `${Math.max(3, pct)}%` }} />
                  </div>
                  <span className="text-[11px] font-medium text-muted">{pct}%</span>
                </div>
              )}
            </div>
          );
        },
      },
      {
        header: "State",
        cell: ({ row }) => (
          <div className="flex min-w-[130px] flex-col gap-1">
            <RiskBadge value={row.original.risk_level} />
            <TriageStatusBadge value={row.original.triage_status} />
            <CaseStatusBadge value={row.original.status} />
          </div>
        ),
      },
      {
        header: "Assigned",
        cell: ({ row }) => (
          <div className="min-w-[100px]">
            {row.original.assigned_to_name ? (
              <p className="text-xs font-semibold text-foreground">{row.original.assigned_to_name}</p>
            ) : (
              <span className="inline-flex items-center rounded-full border border-[#E6EEE9] bg-white px-2 py-0.5 text-[11px] text-muted">
                Unassigned
              </span>
            )}
          </div>
        ),
      },
    ],
    [selected]
  );

  const scopeLabel =
    auth?.user.role === "ADMIN" ? "Admin scope"
    : auth?.user.role === "VET" ? "Vet scope"
    : auth?.user.role === "CAHW" ? "Field-worker scope"
    : "Scoped queue";

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Critical Workflow"
          title="Triage Queue"
          description="Prioritize incoming cases, assign ownership, and move from field capture into clinical action."
        />
        <div className="flex shrink-0 flex-wrap items-center gap-2 text-[12px]">
          <span className="flex items-center gap-1.5 rounded-full border border-[#BEE1D3] bg-[#EAF7F1] px-3 py-1.5 font-semibold text-[#155C45]">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#1F8A66]" />
            {scopeLabel}
          </span>
          <span className="rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 font-semibold text-[#1D2A25]">
            {queueStats.total} case{queueStats.total === 1 ? "" : "s"}
          </span>
          <span className="rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 font-medium text-[#65756F]">
            Auto-refresh 15s
          </span>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <QueueMetricCard
          label="Needs Review"
          value={queueStats.needsReview}
          subtitle="New and review-pending cases"
          icon={Activity}
          tone="amber"
        />
        <QueueMetricCard
          label="High Risk"
          value={queueStats.highRisk}
          subtitle="Urgent review candidates"
          icon={ShieldCheck}
          tone="red"
        />
        <QueueMetricCard
          label="Unassigned"
          value={queueStats.unassigned}
          subtitle="Awaiting owner assignment"
          icon={UserCheck2}
          tone="green"
        />
        <QueueMetricCard
          label="Escalated"
          value={queueStats.escalated}
          subtitle="Raised for senior review"
          icon={Clock3}
          tone="slate"
        />
      </div>

      {/* Queue tabs — VET-specific tabs are hidden from admin */}
      <div className="flex flex-wrap gap-2">
        {(
          [
            { key: "all", label: "All cases" },
            // Claimable / My cases / Requested are VET workflow concepts only
            ...(isVetUser ? [
              { key: "claimable", label: "Claimable" },
              { key: "mine", label: "My cases" },
              { key: "requested", label: "Requested for me" },
            ] : []),
          ] as { key: typeof activeQueue; label: string }[]
        ).map(({ key, label }) => (
          <button
            key={key}
            onClick={() => { setActiveQueue(key); setSelected([]); }}
            className={`rounded-full border px-4 py-1.5 text-sm font-medium transition-colors ${
              activeQueue === key
                ? "border-[#1F8A66] bg-[#1F8A66] text-white"
                : "border-[#D1E8DE] bg-white text-[#465851] hover:border-[#1F8A66] hover:text-[#1F8A66]"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <Card className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-[#155C45]">
            <Filter size={16} />
            Queue filters and bulk actions
          </div>
          {selected.length > 0 ? (
            <div className="rounded-xl border border-[#D4E7DF] bg-white px-3 py-2 text-xs text-muted">
              {selected.length} selected
              {selectedHighRisk > 0 ? ` • ${selectedHighRisk} high risk` : ""}
            </div>
          ) : (
            <div className="rounded-xl border border-[#E4EFEA] bg-[#FAFDFC] px-3 py-2 text-xs text-muted">
              Select rows to run bulk triage actions
            </div>
          )}
        </div>

        <div className="grid gap-3 lg:grid-cols-[1.2fr_0.7fr_0.7fr_1.4fr]">
          <div className="space-y-1">
            <label className="text-xs font-medium uppercase tracking-[0.08em] text-muted">Search</label>
            <div className="relative">
              <Search size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
              <Input
                className="pl-9"
                placeholder="Case ID, notes, client reference"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1">
            <label className="text-xs font-medium uppercase tracking-[0.08em] text-muted">Treatment Status</label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All</option>
              <option value="open">Open</option>
              <option value="in_treatment">In Treatment</option>
              <option value="resolved">Resolved</option>
            </Select>
          </div>
          <div className="space-y-1">
            <label className="text-xs font-medium uppercase tracking-[0.08em] text-muted">Queue Status</label>
            <Select
              value={activeQueue !== "all" ? "" : triageStatus}
              onChange={(e) => setTriageStatus(e.target.value)}
              disabled={activeQueue !== "all"}
              title={activeQueue !== "all" ? "Clear the queue tab to use this filter" : undefined}
            >
              <option value="">All</option>
              <option value="escalated">In Vet Queue</option>
              <option value="needs_review">Needs Review</option>
            </Select>
          </div>
          <div className="space-y-1">
            <label className="text-xs font-medium uppercase tracking-[0.08em] text-muted">Bulk Actions</label>
            <div className="flex flex-wrap gap-2">
              <Button
                variant="outline"
                onClick={() => bulkMutation.mutate({ action: "assign" })}
                disabled={!selected.length || !isVetUser || bulkMutation.isPending}
                title={!isVetUser ? "Only vets can self-assign" : undefined}
              >
                Assign to me
              </Button>
              <Button
                variant="outline"
                onClick={() => bulkMutation.mutate({ action: "needs_review" })}
                disabled={!selected.length || !canRunBulkActions || bulkMutation.isPending}
              >
                Mark needs review
              </Button>
              <Button
                variant="outline"
                onClick={() => bulkMutation.mutate({ action: "escalated" })}
                disabled={!selected.length || !canRunBulkActions || bulkMutation.isPending}
              >
                Escalate
              </Button>
            </div>
          </div>
        </div>

        {!canRunBulkActions && (
          <p className="text-xs text-muted">Bulk triage actions require Vet or Admin access.</p>
        )}
        {bulkNotice && (
          <div className="rounded-xl border border-border bg-white px-3 py-2 text-xs text-muted">{bulkNotice}</div>
        )}
        {casesQuery.isError && (
          <div className="rounded-xl border border-[#F0CAC2] bg-[#FFF2EE] px-3 py-2 text-xs text-[#8E4433]">
            {casesQuery.error instanceof Error ? casesQuery.error.message : "Failed to load triage queue."}
          </div>
        )}
      </Card>

      {casesQuery.isPending && !casesQuery.data ? (
        <div className="flex items-center justify-center py-16 text-sm text-muted">
          <svg className="mr-2 h-4 w-4 animate-spin text-primary" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
          </svg>
          Loading cases…
        </div>
      ) : (
        <DataTable
          columns={columns}
          data={casesQuery.data || []}
          onRowClick={(row) => router.push(`/cases/${row.id}`)}
        />
      )}
    </div>
  );
}
