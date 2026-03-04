"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { CalendarRange, TrendingDown, TrendingUp } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";
import type { AnalyticsSummary } from "@/lib/types";

const DISEASE_COLORS: Record<string, string> = {
  lsd: "#E6A817", fmd: "#D94F3D", ecf: "#2E7BA0",
  cbpp: "#7B5EA7", normal: "#2E7D4F", unknown: "#8B9E95",
};
const dColor = (k: string) => DISEASE_COLORS[k.toLowerCase()] ?? "#8B9E95";

function ChartTooltip({ active, payload, label }: { active?: boolean; payload?: { value: number; name?: string }[]; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-xl border border-[#D8E7DF] bg-white px-3 py-2 text-[12px] shadow-lg">
      <p className="mb-1 font-semibold text-[#65756F]">{label}</p>
      {payload.map((p, i) => (
        <p key={i} className="font-bold text-[#1D2A25]">{p.name ? `${p.name}: ` : ""}{p.value}</p>
      ))}
    </div>
  );
}

function StatPill({ label, value, icon: Icon, color }: { label: string; value: string | number; icon: React.ElementType; color: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-[#E6EEE9] bg-white px-4 py-3">
      <div className="grid h-9 w-9 shrink-0 place-items-center rounded-lg" style={{ background: `${color}18`, color }}>
        <Icon size={15} strokeWidth={2.1} />
      </div>
      <div>
        <p className="text-[21px] font-bold leading-none text-[#1D2A25]" style={{ fontFamily: "var(--font-sora)" }}>{value}</p>
        <p className="mt-0.5 text-[11px] text-[#65756F]">{label}</p>
      </div>
    </div>
  );
}

export default function AnalyticsPage() {
  const [from, setFrom] = useState("");
  const [to,   setTo]   = useState("");
  const queryString = new URLSearchParams(Object.entries({ from, to }).filter(([, v]) => v)).toString();

  const analyticsQuery = useQuery<AnalyticsSummary>({
    queryKey: ["analytics", queryString],
    queryFn: () => api.analyticsSummary(queryString),
    refetchInterval: 60000,
    refetchOnWindowFocus: true,
  });

  const diseaseData = useMemo(
    () => Object.entries(analyticsQuery.data?.cases_by_disease || {})
      .map(([name, count]) => ({ name: name.toUpperCase(), rawKey: name, count })),
    [analyticsQuery.data]
  );

  const totalCases = useMemo(
    () => Object.values(analyticsQuery.data?.cases_by_disease || {}).reduce((s, v) => s + (v as number), 0),
    [analyticsQuery.data]
  );

  const avgResolution = analyticsQuery.data?.avg_resolution_time
    ? `${Math.round(analyticsQuery.data.avg_resolution_time)}h`
    : "—";

  const highRiskRate = analyticsQuery.data?.high_risk_rate != null
    ? `${Math.round(analyticsQuery.data.high_risk_rate * 100)}%`
    : "—";

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Clinical Analytics"
          title="Analytics"
          description="Track case volume, disease distribution, backlog behavior, and resolution performance over time."
        />
        <span className="flex shrink-0 items-center gap-1.5 self-start rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 text-[12px] font-medium text-[#65756F]">
          Auto-refresh 60s
        </span>
      </div>

      {/* Summary stats */}
      <div className="grid gap-3 sm:grid-cols-3">
        <StatPill label="Total cases" value={totalCases} icon={TrendingUp} color="#1F8A66" />
        <StatPill label="Avg resolution" value={avgResolution} icon={TrendingDown} color="#BB8927" />
        <StatPill label="High-risk rate" value={highRiskRate} icon={TrendingUp} color="#C0432E" />
      </div>

      {/* Date range */}
      <Card>
        <div className="mb-3 flex items-center gap-2 text-[13px] font-semibold text-[#204B36]">
          <CalendarRange size={15} />
          Date range
        </div>
        <div className="flex flex-wrap gap-3">
          <div>
            <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">From</label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-auto" />
          </div>
          <div>
            <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">To</label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-auto" />
          </div>
        </div>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* Submissions bar */}
        <Card>
          <div className="mb-4 flex items-center justify-between">
            <div>
              <h2 className="text-[14px] font-bold text-[#1D2A25]">Submissions by Day</h2>
              <p className="text-[11px] text-[#65756F]">Case volume over selected period</p>
            </div>
            <div className="grid h-8 w-8 place-items-center rounded-lg bg-[#E5F5ED] text-[#1F8A66]">
              <TrendingUp size={14} />
            </div>
          </div>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={analyticsQuery.data?.cases_by_day || []} barSize={10}>
                <defs>
                  <linearGradient id="barGradA" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#3EAB74" />
                    <stop offset="100%" stopColor="#1F8A66" stopOpacity={0.8} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(31,138,102,0.07)" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} width={24} />
                <Tooltip content={<ChartTooltip />} cursor={{ fill: "rgba(31,138,102,0.05)", radius: 6 }} />
                <Bar dataKey="count" fill="url(#barGradA)" radius={[5, 5, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>

        {/* Disease bar */}
        <Card>
          <div className="mb-4">
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Cases by Disease</h2>
            <p className="text-[11px] text-[#65756F]">Prediction breakdown across disease types</p>
          </div>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={diseaseData} barSize={28}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(31,138,102,0.07)" vertical={false} />
                <XAxis dataKey="name" tick={{ fontSize: 11, fill: "#9BB8A8" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} width={24} />
                <Tooltip content={<ChartTooltip />} cursor={{ fill: "rgba(31,138,102,0.05)", radius: 6 }} />
                <Bar dataKey="count" radius={[5, 5, 0, 0]}>
                  {diseaseData.map((entry) => (
                    <Cell key={entry.rawKey} fill={dColor(entry.rawKey)} fillOpacity={0.85} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>

        {/* Resolution trend */}
        <Card>
          <div className="mb-4">
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Resolution Time Trend</h2>
            <p className="text-[11px] text-[#65756F]">Average hours from open to resolved</p>
          </div>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={analyticsQuery.data?.resolution_time_trend || []}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(31,138,102,0.07)" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} width={32} />
                <Tooltip content={<ChartTooltip />} />
                <Legend wrapperStyle={{ fontSize: 11, color: "#65756F" }} />
                <Line type="monotone" dataKey="avg_hours" stroke="#1F8A66" strokeWidth={2}
                  dot={{ fill: "#1F8A66", r: 3 }} activeDot={{ r: 5 }} name="Avg hours" />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Card>

        {/* Backlog trend */}
        <Card>
          <div className="mb-4">
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Backlog Trend</h2>
            <p className="text-[11px] text-[#65756F]">Unresolved case count over time</p>
          </div>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={analyticsQuery.data?.backlog_trend || []}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(31,138,102,0.07)" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: "#9BB8A8" }} axisLine={false} tickLine={false} width={24} />
                <Tooltip content={<ChartTooltip />} />
                <Legend wrapperStyle={{ fontSize: 11, color: "#65756F" }} />
                <Line type="monotone" dataKey="backlog" stroke="#BB8927" strokeWidth={2}
                  dot={{ fill: "#BB8927", r: 3 }} activeDot={{ r: 5 }} name="Backlog" />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>
    </div>
  );
}
