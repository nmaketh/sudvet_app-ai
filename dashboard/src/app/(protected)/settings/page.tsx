"use client";

import { useEffect, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { zodResolver } from "@hookform/resolvers/zod";
import { RefreshCw, ShieldCheck, SlidersHorizontal } from "lucide-react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { api } from "@/lib/api";
import type { DashboardSettings, SystemHealth } from "@/lib/types";

const schema = z.object({
  vet_can_view_all: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

export default function SettingsPage() {
  const settingsQuery = useQuery<DashboardSettings>({
    queryKey: ["dashboard-settings"],
    queryFn: api.getSettings,
    refetchOnWindowFocus: false,
  });

  const healthQuery = useQuery<SystemHealth>({
    queryKey: ["health", "settings-page"],
    queryFn: api.health,
    refetchInterval: 30000,
  });

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { vet_can_view_all: true },
  });

  useEffect(() => {
    if (settingsQuery.data) {
      form.reset({ vet_can_view_all: settingsQuery.data.policies.vet_can_view_all });
    }
  }, [settingsQuery.data, form]);

  const sourceLabel = settingsQuery.data?.sources.vet_can_view_all ?? "environment";
  const environment = settingsQuery.data?.metadata.environment ?? "development";
  const mlEnabled = settingsQuery.data?.integration.ml_enabled ?? false;
  const corsOrigins = useMemo(() => settingsQuery.data?.integration.cors_origins ?? [], [settingsQuery.data]);

  /* ── inline status dot ── */
  const StatusPill = ({ ok, label }: { ok: boolean; label: string }) => (
    <span className={`flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold ${
      ok ? "bg-[#E5F5ED] text-[#1F8A66]" : "bg-[#F4F8F6] text-[#9BB8A8]"
    }`}>
      <span className={`h-1.5 w-1.5 rounded-full ${ok ? "bg-[#1F8A66] animate-pulse" : "bg-[#9BB8A8]"}`} />
      {label}
    </span>
  );

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Operational Policy Control"
          title="Settings"
          description="Backend-managed dashboard policy affecting vet case visibility, triage workflow, and operational consistency."
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="shrink-0 self-start"
          onClick={() => { void Promise.all([settingsQuery.refetch(), healthQuery.refetch()]); }}
        >
          <RefreshCw size={14} />
          Refresh
        </Button>
      </div>

      <div className="grid gap-5 xl:grid-cols-[1.25fr_0.75fr]">

        {/* Policy card */}
        <Card className="space-y-4">
          <div className="flex items-center gap-2 text-[13px] font-bold text-[#204B36]">
            <SlidersHorizontal size={15} />
            Backend-enforced policy
          </div>

          {settingsQuery.isLoading ? (
            <div className="space-y-2">
              <div className="sv-skeleton h-16 w-full rounded-xl" />
              <div className="sv-skeleton h-20 w-full rounded-xl" />
            </div>
          ) : settingsQuery.isError ? (
            <div className="flex items-start gap-3 rounded-xl border border-[#EDC0B4] bg-[#FDE9E4] px-4 py-3 text-[12.5px] text-[#8F4434]">
              {settingsQuery.error instanceof Error ? settingsQuery.error.message : "Failed to load settings"}
            </div>
          ) : (
            <div className="space-y-4">
              {/* RBAC row */}
              <div className="rounded-2xl border border-[#D8E7DF] bg-[#F5FBF8] p-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="rounded-full border border-[#BEE1D3] bg-[#E5F5ED] px-2.5 py-1 text-[11px] font-bold text-[#155C45]">
                    RBAC
                  </span>
                  <span className="text-[13px] font-semibold text-[#1D2A25]">Vet visibility scope</span>
                  <span className="rounded-full border border-[#E6EEE9] bg-white px-2.5 py-1 text-[11px] font-medium text-[#65756F]">
                    {sourceLabel === "database" ? "DB override" : "Env default"}
                  </span>
                </div>
                <p className="mt-2 text-[12.5px] leading-[1.65] text-[#65756F]">
                  Assigned-vet-only visibility is enforced platform-wide. This legacy toggle is displayed for
                  compatibility but does not override access control behavior.
                </p>

                <label className="mt-3 flex cursor-not-allowed items-start gap-3 rounded-xl border border-[#D8E7DF] bg-white p-3 opacity-60">
                  <input
                    type="checkbox"
                    className="mt-0.5 h-4 w-4 rounded border-[#B6CEC4] text-[#1F8A66] focus:ring-[#1F8A66]"
                    disabled
                    {...form.register("vet_can_view_all")}
                  />
                  <div>
                    <p className="text-[12.5px] font-semibold text-[#1D2A25]">Legacy visibility toggle (inactive)</p>
                    <p className="mt-0.5 text-[12px] text-[#65756F]">
                      Access is enforced by role rules — vets see assigned cases only; admins stay in dispatch scope.
                    </p>
                  </div>
                </label>
                {form.formState.errors.vet_can_view_all && (
                  <p className="mt-2 text-[11.5px] text-[#B94E3A]">{form.formState.errors.vet_can_view_all.message}</p>
                )}
              </div>

              {/* Runtime notes */}
              <div className="rounded-2xl border border-[#D8E7DF] bg-white p-4">
                <div className="mb-2.5 flex items-center gap-2 text-[13px] font-semibold text-[#1D2A25]">
                  <ShieldCheck size={15} className="text-[#1F8A66]" />
                  Runtime behavior
                </div>
                <ul className="space-y-1.5">
                  {[
                    "Cases, triage, analytics, and overview all reuse the same backend policy source.",
                    "Public registration creates CAHW users only — VET/ADMIN are admin-controlled.",
                    "System diagnostics and user administration remain admin-only.",
                  ].map((note) => (
                    <li key={note} className="flex items-start gap-2 text-[12.5px] text-[#65756F]">
                      <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-[#9BB8A8]" />
                      {note}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          )}
        </Card>

        {/* Right column */}
        <div className="space-y-4">
          <Card className="space-y-3">
            <p className="text-[13px] font-bold text-[#1D2A25]">System linkage</p>
            <div className="space-y-2">
              {/* API / DB */}
              <div className="rounded-xl border border-[#E6EEE9] bg-[#F6FCF9] p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[11px] font-bold uppercase tracking-[0.09em] text-[#65756F]">API / DB</span>
                  <StatusPill ok={healthQuery.data?.status === "ok"} label={healthQuery.data?.status ?? "checking"} />
                </div>
                <p className="mt-1.5 text-[12.5px] text-[#1D2A25]">
                  Latency: {typeof healthQuery.data?.db_latency_ms === "number"
                    ? `${healthQuery.data.db_latency_ms} ms` : "—"}
                </p>
              </div>

              {/* ML Service */}
              <div className="rounded-xl border border-[#E6EEE9] bg-[#F6FCF9] p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[11px] font-bold uppercase tracking-[0.09em] text-[#65756F]">ML Service</span>
                  <StatusPill ok={mlEnabled} label={mlEnabled ? "configured" : "not set"} />
                </div>
                <p className="mt-1.5 truncate text-[12px] text-[#65756F]">
                  {settingsQuery.data?.integration.ml_service_url || "No ML service URL configured"}
                </p>
              </div>

              {/* Environment */}
              <div className="rounded-xl border border-[#E6EEE9] bg-[#F6FCF9] p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[11px] font-bold uppercase tracking-[0.09em] text-[#65756F]">Environment</span>
                  <span className="rounded-full border border-[#E6EEE9] bg-white px-2.5 py-1 text-[11px] font-semibold text-[#65756F]">
                    {environment}
                  </span>
                </div>
                <p className="mt-1.5 text-[12px] text-[#65756F]">
                  Base: {settingsQuery.data?.integration.public_base_url || "—"}
                </p>
                {corsOrigins.length > 0 && (
                  <p className="mt-0.5 text-[11px] text-[#9BB8A8]">CORS: {corsOrigins.join(", ")}</p>
                )}
              </div>
            </div>
          </Card>

          <Card>
            <p className="text-[13px] font-bold text-[#1D2A25]">Field app continuity</p>
            <p className="mt-1.5 text-[12.5px] leading-[1.65] text-[#65756F]">
              The dashboard is the clinical and supervision workspace. Mobile stays focused on field capture
              and follow-up — this policy panel controls vet workload visibility on the web.
            </p>
          </Card>
        </div>
      </div>
    </div>
  );
}
