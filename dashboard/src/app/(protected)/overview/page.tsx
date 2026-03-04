"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  ClipboardList,
  Inbox,
  TrendingUp,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { CaseStatusBadge, TriageStatusBadge } from "@/components/ui/domain-badges";
import { Table, TableBody, TableHead, TableRow, Td, Th } from "@/components/ui/table";
import { api } from "@/lib/api";
import { getAuthState } from "@/lib/auth";
import type { AnalyticsSummary, CaseItem } from "@/lib/types";

const DISEASE_COLORS: Record<string, string> = {
  lsd:     "#E6A817",
  fmd:     "#D94F3D",
  ecf:     "#2E7BA0",
  cbpp:    "#7B5EA7",
  normal:  "#2E7D4F",
  unknown: "#8B9E95",
};
const DISEASE_LABELS: Record<string, string> = {
  lsd:     "LSD",
  fmd:     "FMD",
  ecf:     "ECF",
  cbpp:    "CBPP",
  normal:  "Normal",
  unknown: "Unknown",
};
const dColor = (k: string) => DISEASE_COLORS[k.toLowerCase()] ?? "#8B9E95";
const dLabel = (k: string) => DISEASE_LABELS[k.toLowerCase()] ?? k;

function KpiCard({
  label, value, description, icon: Icon,
  accentColor, bg, border, loading,
}: {
  label: string; value: number; description: string;
  icon: React.ElementType; accentColor: string;
  bg: string; border: string; loading?: boolean;
}) {
  return (
    <div
      className="relative overflow-hidden rounded-2xl border p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
      style={{ background: bg, borderColor: border }}
    >
      <div className="absolute inset-x-0 top-0 h-[3px] rounded-t-2xl" style={{ background: accentColor }} />
      <div className="flex items-start justify-between gap-2 pt-1">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/60 shadow-sm"
          style={{ color: accentColor }}>
          <Icon size={17} strokeWidth={2.1} />
        </div>
        {loading ? (
          <div className="sv-skeleton mt-1 h-8 w-14 rounded-lg" />
        ) : (
          <span className="text-[32px] font-bold leading-none tracking-tight"
            style={{ fontFamily: "var(--font-sora)", color: accentColor }}>
            {value}
          </span>
        )}
      </div>
      <p className="mt-3 text-[11px] font-bold uppercase tracking-[0.12em]" style={{ color: accentColor }}>
        {label}
      </p>
      <p className="mt-0.5 text-[12px] leading-[1.5] text-[#65756F]">{description}</p>
    </div>
  );
}

function PostureStat({ label, value, note, accent }: { label: string; value: number; note: string; accent: string }) {
  return (
    <div className="flex items-center gap-4 rounded-xl border border-[#E6EEE9] bg-white px-4 py-3">
      <span className="text-[28px] font-bold leading-none tracking-tight"
        style={{ fontFamily: "var(--font-sora)", color: accent }}>
        {value}
      </span>
      <div className="min-w-0">
        <p className="text-[12px] font-semibold text-[#1D2A25]">{label}</p>
        <p className="text-[11px] text-[#65756F]">{note}</p>
      </div>
    </div>
  );
}

function BarTip({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-xl border border-[#D8E7DF] bg-white px-3 py-2 text-[12px] shadow-lg">
      <p className="font-semibold text-[#65756F]">{label}</p>
      <p className="mt-0.5 font-bold text-[#1D2A25]">{payload[0].value} cases</p>
    </div>
  );
}

export default function OverviewPage() {
  const router = useRouter();
  const auth = getAuthState();

  const analyticsQuery = useQuery<AnalyticsSummary>({
    queryKey: ["analytics-summary-overview"],
    queryFn: () => api.analyticsSummary(),
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });

  const casesQuery = useQuery<CaseItem[]>({
    queryKey: ["overview-cases"],
    queryFn: () => api.listCases(),
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });

  const loading = casesQuery.isLoading;

  const kpis = useMemo(() => {
    const cases = casesQuery.data || [];
    const last7 = cases.filter((c) => Date.now() - new Date(c.created_at).getTime() <= 7 * 24 * 3600_000);
    return {
      backlog: last7.filter((c) => c.status !== "resolved").length,
      highRisk: last7.filter((c) => c.risk_level === "high").length,
      needsReview: last7.filter((c) => c.triage_status === "needs_review").length,
      resolved: last7.filter((c) => c.status === "resolved").length,
    };
  }, [casesQuery.data]);

  const queuePosture = useMemo(() => {
    const cases = casesQuery.data || [];
    return {
      unassigned: cases.filter((c) => !c.assigned_to_user_id).length,
      escalated: cases.filter((c) => c.triage_status === "escalated").length,
      openHighRisk: cases.filter((c) => c.risk_level === "high" && c.status !== "resolved").length,
    };
  }, [casesQuery.data]);

  const diseaseData = useMemo(
    () =>
      Object.entries(analyticsQuery.data?.cases_by_disease || {}).map(([k, v]) => ({
        name: dLabel(k),
        value: v as number,
        rawKey: k,
      })),
    [analyticsQuery.data]
  );

  const highRiskCases = useMemo(
    () => (casesQuery.data || []).filter((c) => c.risk_level === "high").slice(0, 8),
    [casesQuery.data]
  );

  const overviewError =
    analyticsQuery.error instanceof Error
      ? analyticsQuery.error.message
      : casesQuery.error instanceof Error
        ? casesQuery.error.message
        : null;

  const roleLabel = auth?.user.role === "ADMIN" ? "Admin view" : auth?.user.role === "VET" ? "Vet view" : "Scoped view";

  return (
    <div className="space-y-6 sv-animate-up">

      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Operations Snapshot"
          title="Overview"
          description="Live pulse on backlog, risk, and review workload — decide what to handle first."
        />
        <div className="flex shrink-0 items-center gap-2 text-[12px]">
          <span className="flex items-center gap-1.5 rounded-full border border-[#BEE1D3] bg-[#EAF7F1] px-3 py-1.5 font-semibold text-[#155C45]">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#1F8A66]" />
            {roleLabel}
          </span>
          <span className="rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 font-medium text-[#65756F]">
            Auto-refresh 30s
          </span>
        </div>
      </div>

      {overviewError && (
        <div className="flex items-start gap-3 rounded-xl border border-[#EDC0B4] bg-[#FDE9E4] px-4 py-3 text-[12.5px] text-[#8F4434]">
          <AlertTriangle size={14} className="mt-0.5 shrink-0" />
          {overviewError}
        </div>
      )}

      {/* KPI row */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard label="Backlog (7d)"     value={kpis.backlog}     loading={loading}
          description="Open or in-treatment cases."
          icon={Inbox}         accentColor="#1F8A66"
          bg="linear-gradient(135deg,#f0faf5,#e5f5ed)" border="rgba(31,138,102,0.18)" />
        <KpiCard label="High Risk"        value={kpis.highRisk}    loading={loading}
          description="Cases needing urgent escalation."
          icon={AlertTriangle} accentColor="#C0432E"
          bg="linear-gradient(135deg,#fef6f4,#fde9e4)" border="rgba(214,107,82,0.18)" />
        <KpiCard label="Needs Review"     value={kpis.needsReview} loading={loading}
          description="Unassigned or awaiting vet decision."
          icon={ClipboardList} accentColor="#8A6020"
          bg="linear-gradient(135deg,#fffaef,#faefd8)" border="rgba(187,137,39,0.18)" />
        <KpiCard label="Resolved (7d)"    value={kpis.resolved}    loading={loading}
          description="Closed with documented follow-up."
          icon={CheckCircle2}  accentColor="#24563D"
          bg="linear-gradient(135deg,#f0faf5,#dff2e8)" border="rgba(69,164,126,0.18)" />
      </div>

      {/* Queue posture */}
      <div>
        <div className="mb-3 flex items-center justify-between">
          <div>
            <p className="sv-eyebrow mb-0.5 text-[#BB8927]">Queue Posture</p>
            <h2 className="text-[15px] font-bold text-[#1D2A25]" style={{ fontFamily: "var(--font-sora)" }}>
              Field-to-Clinic Continuity
            </h2>
          </div>
          <Link href="/triage"
            className="flex items-center gap-1.5 rounded-xl border border-[#D8E7DF] bg-white px-3 py-2 text-[12.5px] font-semibold text-[#1F8A66] transition-colors hover:bg-[#F0FAF5]">
            Open Triage <ArrowRight size={13} />
          </Link>
        </div>
        <div className="grid gap-3 md:grid-cols-3">
          <PostureStat label="Unassigned"    value={queuePosture.unassigned}   note="Need owner assignment" accent="#1F8A66" />
          <PostureStat label="Escalated"     value={queuePosture.escalated}    note="Raised for senior review" accent="#B78935" />
          <PostureStat label="Open High Risk" value={queuePosture.openHighRisk} note="Not yet resolved" accent="#C0432E" />
        </div>
      </div>

      {/* Charts */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="sv-animate-up sv-delay-1">
          <div className="mb-4 flex items-center justify-between">
            <div>
              <h2 className="text-[14px] font-bold text-[#1D2A25]">Submissions by Day</h2>
              <p className="text-[11px] text-[#65756F]">Case volume over time</p>
            </div>
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#E5F5ED] text-[#1F8A66]">
              <TrendingUp size={14} />
            </div>
          </div>
          <div className="h-[220px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={analyticsQuery.data?.cases_by_day || []} barSize={10}>
                <defs>
                  <linearGradient id="barGradOv" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%"   stopColor="#3EAB74" />
                    <stop offset="100%" stopColor="#1F8A66" stopOpacity={0.8} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(31,138,102,0.07)" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} width={24} />
                <Tooltip content={<BarTip />} cursor={{ fill: "rgba(31,138,102,0.05)", radius: 6 }} />
                <Bar dataKey="count" fill="url(#barGradOv)" radius={[5, 5, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>

        <Card className="sv-animate-up sv-delay-2">
          <div className="mb-4">
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Disease Distribution</h2>
            <p className="text-[11px] text-[#65756F]">Prediction breakdown by type</p>
          </div>
          {diseaseData.length === 0 ? (
            <div className="flex h-[220px] items-center justify-center rounded-xl border border-dashed border-[#D8E7DF] text-[13px] text-[#9BB8A8]">
              No data yet
            </div>
          ) : (
            <div className="flex h-[220px] items-center gap-6">
              <ResponsiveContainer width="50%" height="100%">
                <PieChart>
                  <Pie data={diseaseData} dataKey="value" nameKey="name" outerRadius={85} innerRadius={40} paddingAngle={3}>
                    {diseaseData.map((entry) => (
                      <Cell key={entry.rawKey} fill={dColor(entry.rawKey)} />
                    ))}
                  </Pie>
                  <Tooltip contentStyle={{ borderRadius: 10, border: "1px solid #D8E7DF", fontSize: 12 }} />
                </PieChart>
              </ResponsiveContainer>
              <div className="flex flex-1 flex-col gap-2.5">
                {diseaseData.map((entry) => (
                  <div key={entry.rawKey} className="flex items-center gap-2">
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: dColor(entry.rawKey) }} />
                    <span className="flex-1 text-[12px] text-[#65756F]">{entry.name}</span>
                    <span className="text-[12px] font-bold text-[#1D2A25]">{entry.value}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </Card>
      </div>

      {/* Recent high-risk table */}
      <Card className="sv-animate-up sv-delay-3">
        <div className="mb-5 flex items-center justify-between gap-3">
          <div>
            <h2 className="text-[15px] font-bold text-[#1D2A25]">Recent High-Risk Cases</h2>
            <p className="mt-0.5 text-[12px] text-[#65756F]">
              Most likely to need urgent intervention — open any row for clinical review.
            </p>
          </div>
          <Link href="/triage"
            className="flex items-center gap-1.5 whitespace-nowrap rounded-xl border border-[#D8E7DF] bg-white px-3 py-1.5 text-[12.5px] font-semibold text-[#1F8A66] transition-colors hover:bg-[#F0FAF5]">
            Triage Queue <ArrowRight size={13} />
          </Link>
        </div>

        {loading ? (
          <div className="space-y-2">
            {[...Array(4)].map((_, i) => <div key={i} className="sv-skeleton h-9 w-full" />)}
          </div>
        ) : highRiskCases.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-10 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[#E5F5ED]">
              <CheckCircle2 size={20} className="text-[#1F8A66]" />
            </div>
            <p className="mt-3 text-[13.5px] font-semibold text-[#1D2A25]">No high-risk cases</p>
            <p className="mt-1 text-[12px] text-[#65756F]">All recent cases are medium or low risk.</p>
          </div>
        ) : (
          <div className="overflow-auto">
            <Table>
              <TableHead>
                <TableRow>
                  <Th>Date</Th><Th>Case ID</Th><Th>Animal</Th>
                  <Th>Disease</Th><Th>Conf.</Th><Th>Triage</Th><Th>Status</Th>
                </TableRow>
              </TableHead>
              <TableBody>
                {highRiskCases.map((item) => (
                  <TableRow key={item.id} className="sv-row-link" onClick={() => router.push(`/cases/${item.id}`)}>
                    <Td className="text-[11px] text-[#65756F]">
                      {new Date(item.created_at).toLocaleDateString("en-GB", { day: "numeric", month: "short" })}
                    </Td>
                    <Td>
                      <span className="font-mono text-[11.5px] font-semibold text-[#1D2A25]">
                        {item.id.slice(0, 8).toUpperCase()}
                      </span>
                    </Td>
                    <Td className="text-[11.5px] text-[#65756F]">
                      {item.animal_tag ?? <span className="opacity-40">—</span>}
                    </Td>
                    <Td>
                      <span className="text-[12px] font-semibold capitalize"
                        style={{ color: dColor(String(item.prediction_json?.final_label ?? item.prediction_json?.label ?? "unknown")) }}>
                        {dLabel(String(item.prediction_json?.final_label ?? item.prediction_json?.label ?? "unknown"))}
                      </span>
                    </Td>
                    <Td className="text-[12px] font-semibold text-[#1D2A25]">
                      {typeof item.confidence === "number"
                        ? `${Math.round(item.confidence * 100)}%`
                        : <span className="opacity-40">—</span>}
                    </Td>
                    <Td><TriageStatusBadge value={item.triage_status} /></Td>
                    <Td><CaseStatusBadge value={item.status} /></Td>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>
    </div>
  );
}
