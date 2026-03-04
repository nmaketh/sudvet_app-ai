"use client";

import { useQuery } from "@tanstack/react-query";
import { Activity, BrainCircuit, DatabaseZap, HeartPulse, ShieldCheck } from "lucide-react";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { api } from "@/lib/api";
import { getAuthState, isAdmin } from "@/lib/auth";
import type { ErrorLogItem, ModelVersionItem, SystemHealth } from "@/lib/types";

/* ── Status dot ─────────────────────────────────────────────────────────────── */
function StatusDot({ value }: { value?: string | null }) {
  const v = (value || "").toLowerCase();
  const isOk = v === "ok" || v === "healthy" || v === "connected";
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-bold ${
      isOk
        ? "bg-[#E5F5ED] text-[#1F8A66]"
        : v
          ? "bg-[#FDE9E4] text-[#C0432E]"
          : "bg-[#F4F8F6] text-[#9BB8A8]"
    }`}>
      <span className={`h-1.5 w-1.5 rounded-full ${isOk ? "bg-[#1F8A66] animate-pulse" : v ? "bg-[#C0432E]" : "bg-[#9BB8A8]"}`} />
      {value || "—"}
    </span>
  );
}

/* ── Health card ─────────────────────────────────────────────────────────────── */
function HealthCard({
  label, value, sub, icon: Icon, iconColor,
}: {
  label: string; value?: string | null; sub?: React.ReactNode;
  icon: React.ElementType; iconColor: string;
}) {
  return (
    <Card>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[11px] font-bold uppercase tracking-[0.1em] text-[#65756F]">{label}</p>
          <div className="mt-2">
            <StatusDot value={value} />
          </div>
          {sub && <div className="mt-1.5">{sub}</div>}
        </div>
        <div className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
          style={{ background: `${iconColor}18`, color: iconColor }}>
          <Icon size={16} strokeWidth={2.1} />
        </div>
      </div>
    </Card>
  );
}

export default function SystemPage() {
  const auth      = getAuthState();
  const canAccess = isAdmin(auth?.user.role);

  const healthQuery = useQuery<SystemHealth>({
    queryKey: ["health"],
    queryFn: api.health,
    enabled: canAccess,
    refetchInterval: 15000,
  });
  const modelsQuery = useQuery<ModelVersionItem[]>({
    queryKey: ["models"],
    queryFn: api.models,
    enabled: canAccess,
    refetchInterval: 60000,
  });
  const errorsQuery = useQuery<ErrorLogItem[]>({
    queryKey: ["errors"],
    queryFn: api.errors,
    enabled: canAccess,
    refetchInterval: 15000,
  });

  if (!canAccess) {
    return (
      <div className="flex items-center gap-3 rounded-xl border border-[#EDC0B4] bg-[#FDE9E4] px-4 py-3 text-[13px] text-[#8F4434]">
        Unauthorized — only ADMIN can access system monitoring.
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Platform Monitoring"
          title="System"
          description="Operational health checks, deployed model versions, and recent API error log summaries."
        />
        <span className="flex shrink-0 items-center gap-1.5 self-start rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 text-[12px] font-medium text-[#65756F]">
          Auto-refresh 15s
        </span>
      </div>

      {/* Health cards */}
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <HealthCard label="API" value={healthQuery.data?.api} icon={HeartPulse} iconColor="#1F8A66" />
        <HealthCard label="Database" value={healthQuery.data?.db} icon={DatabaseZap} iconColor="#BB8927"
          sub={typeof healthQuery.data?.db_latency_ms === "number" && (
            <p className="text-[11.5px] text-[#65756F]">{healthQuery.data.db_latency_ms.toFixed(1)} ms latency</p>
          )} />
        <HealthCard label="Overall Status" value={healthQuery.data?.status} icon={ShieldCheck} iconColor="#204B36" />
        <HealthCard label="ML Service" value={healthQuery.data?.ml} icon={BrainCircuit} iconColor="#7B5EA7"
          sub={
            <>
              {typeof healthQuery.data?.ml_latency_ms === "number" && (
                <p className="text-[11.5px] text-[#65756F]">{healthQuery.data.ml_latency_ms.toFixed(1)} ms</p>
              )}
              {healthQuery.data?.prediction_default_engine && (
                <p className="text-[11px] text-[#65756F]">Engine: {healthQuery.data.prediction_default_engine}</p>
              )}
            </>
          } />
      </div>

      {/* Model versions */}
      <Card>
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Model Versions</h2>
            <p className="text-[11px] text-[#65756F]">Currently deployed inference models</p>
          </div>
          <div className="flex items-center gap-1.5 rounded-full border border-[#BEE1D3] bg-[#EAF7F1] px-2.5 py-1 text-[11px] font-semibold text-[#155C45]">
            <Activity size={11} />
            Deployment inventory
          </div>
        </div>
        <div className="space-y-2">
          {(modelsQuery.data || []).map((item: ModelVersionItem) => {
            const metrics = Object.entries(item.metrics_json || {});
            return (
              <div key={item.id} className="rounded-xl border border-[#E6EEE9] bg-[#F6FCF9] p-3.5">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="text-[12.5px] font-bold text-[#1D2A25]">{item.type}</p>
                    <p className="mt-0.5 font-mono text-[11px] text-[#65756F]">v{item.version}</p>
                  </div>
                  <p className="text-[11px] text-[#9BB8A8]">
                    Updated {new Date(item.updated_at).toLocaleDateString()}
                  </p>
                </div>
                {metrics.length > 0 && (
                  <div className="mt-2.5 flex flex-wrap gap-2">
                    {metrics.map(([k, v]) => (
                      <span key={k} className="rounded-lg border border-[#D8E7DF] bg-white px-2 py-1 text-[11px] text-[#65756F]">
                        <span className="font-semibold text-[#1D2A25]">{k}:</span>{" "}
                        {typeof v === "number" ? v.toFixed(3) : String(v)}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
          {!modelsQuery.data?.length && (
            <p className="py-6 text-center text-[12.5px] text-[#9BB8A8]">No model versions registered yet.</p>
          )}
        </div>
      </Card>

      {/* Error log */}
      <Card className="overflow-hidden">
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-[14px] font-bold text-[#1D2A25]">Recent Errors</h2>
            <p className="text-[11px] text-[#65756F]">Last 20 API error log entries</p>
          </div>
          {(errorsQuery.data?.length ?? 0) > 0 && (
            <span className="rounded-full border border-[#EDC0B4] bg-[#FDE9E4] px-2.5 py-1 text-[11px] font-semibold text-[#8F4434]">
              {errorsQuery.data!.length} logged
            </span>
          )}
        </div>

        {!errorsQuery.data?.length ? (
          <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-[#D8E7DF] py-8 text-center">
            <div className="grid h-10 w-10 place-items-center rounded-full bg-[#E5F5ED]">
              <ShieldCheck size={18} className="text-[#1F8A66]" />
            </div>
            <p className="mt-2 text-[13px] font-semibold text-[#1D2A25]">No errors logged</p>
            <p className="text-[11px] text-[#65756F]">System is running clean.</p>
          </div>
        ) : (
          <div className="overflow-auto rounded-xl border border-[#1D2A25]/10 bg-[#0F1C14]">
            <div className="divide-y divide-white/[0.04]">
              {(errorsQuery.data || []).map((item: ErrorLogItem) => (
                <div key={item.id} className="flex items-start gap-4 px-4 py-3">
                  <span className="shrink-0 font-mono text-[10.5px] text-[#3D7A5C] whitespace-nowrap pt-0.5">
                    {new Date(item.created_at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
                  </span>
                  <span className="shrink-0 rounded-md border border-[#C0432E]/30 bg-[#C0432E]/10 px-1.5 py-0.5 font-mono text-[10px] font-bold text-[#E8857A]">
                    {item.source}
                  </span>
                  <span className="font-mono text-[11.5px] leading-[1.6] text-[#9BB8A8]">{item.message}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
