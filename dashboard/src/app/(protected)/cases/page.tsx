"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { FolderKanban, Search } from "lucide-react";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { CaseStatusBadge, RiskBadge, TriageStatusBadge } from "@/components/ui/domain-badges";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { api } from "@/lib/api";
import type { CaseItem } from "@/lib/types";

const DISEASE_COLORS: Record<string, string> = {
  lsd: "#E6A817", fmd: "#D94F3D", ecf: "#2E7BA0",
  cbpp: "#7B5EA7", normal: "#2E7D4F", unknown: "#8B9E95",
};
const dColor = (k: string) => DISEASE_COLORS[k.toLowerCase()] ?? "#8B9E95";

export default function CasesPage() {
  const [q,            setQ]            = useState("");
  const [status,       setStatus]       = useState("");
  const [triageStatus, setTriageStatus] = useState("");
  const router = useRouter();

  const params = new URLSearchParams(
    Object.entries({ q, status, triage_status: triageStatus }).filter(([, v]) => v)
  ).toString();

  const casesQuery = useQuery<CaseItem[]>({
    queryKey: ["cases", params],
    queryFn: () => api.listCases(params),
    placeholderData: (prev) => prev,
  });

  const total = casesQuery.data?.length ?? 0;

  const columns = useMemo<ColumnDef<CaseItem>[]>(
    () => [
      {
        header: "Created",
        cell: ({ row }) => (
          <div className="min-w-[108px]">
            <p className="text-[12px] font-semibold text-[#1D2A25]">
              {new Date(row.original.created_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
            </p>
            <p className="text-[11px] text-[#65756F]">
              {new Date(row.original.created_at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })}
            </p>
          </div>
        ),
      },
      {
        header: "Case",
        cell: ({ row }) => (
          <div className="min-w-[120px]">
            <p className="font-mono text-[11.5px] font-semibold text-[#1D2A25]">
              {row.original.id.slice(0, 8).toUpperCase()}
            </p>
            <p className="truncate text-[11px] text-[#65756F]">
              {row.original.client_case_id || "No ref"}
            </p>
          </div>
        ),
      },
      {
        header: "Animal",
        cell: ({ row }) => (
          <span className="text-[12px] text-[#1D2A25]">
            {row.original.animal_tag || <span className="text-[#9BB8A8]">Unlinked</span>}
          </span>
        ),
      },
      {
        header: "Prediction",
        cell: ({ row }) => {
          const label = String(
            row.original.prediction_json?.display_label ||
            row.original.prediction_json?.final_label ||
            row.original.prediction_json?.label || "unknown"
          );
          return (
            <div className="min-w-[110px]">
              <p className="text-[12px] font-semibold capitalize" style={{ color: dColor(label) }}>{label}</p>
              <p className="text-[11px] text-[#65756F]">{row.original.method || "—"}</p>
            </div>
          );
        },
      },
      {
        header: "Conf.",
        cell: ({ row }) => {
          const pct = typeof row.original.confidence === "number"
            ? Math.round(row.original.confidence * 100) : null;
          if (pct === null) return <span className="text-[12px] text-[#9BB8A8]">—</span>;
          return (
            <div className="min-w-[68px]">
              <p className="text-[12px] font-semibold text-[#1D2A25]">{pct}%</p>
              <div className="mt-1 h-1 overflow-hidden rounded-full bg-[#E7F1ED]">
                <div className="h-full rounded-full bg-[#1F8A66]" style={{ width: `${Math.max(3, pct)}%` }} />
              </div>
            </div>
          );
        },
      },
      { header: "Risk",   cell: ({ row }) => <RiskBadge value={row.original.risk_level} /> },
      { header: "Status", cell: ({ row }) => <CaseStatusBadge value={row.original.status} /> },
      { header: "Triage", cell: ({ row }) => <TriageStatusBadge value={row.original.triage_status} /> },
      {
        header: "Assigned",
        cell: ({ row }) => (
          <span className="text-[12px] text-[#65756F]">
            {row.original.assigned_to_name
              || (row.original.assigned_to_user_id ? `User #${row.original.assigned_to_user_id}` : (
                <span className="text-[#9BB8A8]">Unassigned</span>
              ))}
          </span>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Case Registry"
          title="Cases"
          description="Browse all visible cases — filter, search, and open for detailed clinical review."
        />
        <span className="flex shrink-0 items-center gap-1.5 self-start rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 text-[12px] font-semibold text-[#1D2A25]">
          <FolderKanban size={12} className="text-[#1F8A66]" />
          {casesQuery.isLoading ? "Loading…" : `${total} case${total === 1 ? "" : "s"}`}
        </span>
      </div>

      <Card>
        <div className="grid gap-3 md:grid-cols-[1.4fr_0.8fr_0.8fr]">
          <div>
            <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">
              Search
            </label>
            <div className="relative">
              <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[#9BB8A8]" />
              <Input
                className="pl-9 text-[13px]"
                placeholder="Case ID, reference, notes…"
                value={q}
                onChange={(e) => setQ(e.target.value)}
              />
            </div>
          </div>
          <div>
            <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">
              Status
            </label>
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All status</option>
              <option value="open">Open</option>
              <option value="in_treatment">In treatment</option>
              <option value="resolved">Resolved</option>
            </Select>
          </div>
          <div>
            <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">
              Triage
            </label>
            <Select value={triageStatus} onChange={(e) => setTriageStatus(e.target.value)}>
              <option value="">All triage</option>
              <option value="escalated">In Vet Queue</option>
              <option value="needs_review">Needs Review</option>
            </Select>
          </div>
        </div>
      </Card>

      {casesQuery.isError && (
        <div className="rounded-xl border border-[#F0CAC2] bg-[#FFF2EE] px-4 py-3 text-sm text-[#8E4433]">
          {casesQuery.error instanceof Error ? casesQuery.error.message : "Failed to load cases."}
        </div>
      )}
      <DataTable
        columns={columns}
        data={casesQuery.data || []}
        onRowClick={(row) => router.push(`/cases/${row.id}`)}
      />
    </div>
  );
}
