"use client";

import { useMemo, useRef, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Image as ImageIcon,
  Sparkles,
  Stethoscope,
  Clock3,
  Brain,
  BarChart3,
  Activity,
  ListChecks,
  CalendarDays,
  Tag,
  UserRound,
  MessageSquare,
  Send,
  LogOut,
} from "lucide-react";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

import { PageHeader } from "@/components/layout/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  CaseStatusBadge,
  MethodBadge,
  RiskBadge,
  TriageStatusBadge,
} from "@/components/ui/domain-badges";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { api } from "@/lib/api";
import { getAuthState } from "@/lib/auth";
import { deriveCaseUI } from "@/lib/case-policy";
import type { CaseItem, PredictionJson, UserItem } from "@/lib/types";

// ── Disease visual configuration ─────────────────────────────────────────────
const DISEASE_ORDER = ["lsd", "fmd", "ecf", "cbpp", "normal"];

type DiseaseConfig = { label: string; bg: string; bar: string; text: string; border: string };

const DISEASE_CONFIG: Record<string, DiseaseConfig> = {
  lsd:    { label: "Lumpy Skin Disease",               bg: "bg-amber-50",   bar: "bg-amber-500",   text: "text-amber-800",  border: "border-amber-200"  },
  fmd:    { label: "Foot & Mouth Disease",             bg: "bg-red-50",     bar: "bg-red-500",     text: "text-red-800",    border: "border-red-200"    },
  ecf:    { label: "East Coast Fever",                 bg: "bg-purple-50",  bar: "bg-purple-500",  text: "text-purple-800", border: "border-purple-200" },
  cbpp:   { label: "CBPP",                             bg: "bg-sky-50",     bar: "bg-sky-500",     text: "text-sky-800",    border: "border-sky-200"    },
  normal: { label: "No Disease Detected",              bg: "bg-emerald-50", bar: "bg-emerald-500", text: "text-emerald-800",border: "border-emerald-200"},
};

const DEFAULT_CONFIG: DiseaseConfig = {
  label: "Unknown", bg: "bg-slate-50", bar: "bg-slate-400", text: "text-slate-800", border: "border-slate-200",
};

function getDiseaseConfig(key: string): DiseaseConfig {
  return DISEASE_CONFIG[key?.toLowerCase?.()] ?? DEFAULT_CONFIG;
}

function fmtSymptom(key: string): string {
  return key.replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

// ── Sub-components ────────────────────────────────────────────────────────────

function DiseaseProbabilityBars({
  probabilities,
  topDisease,
}: {
  probabilities: Record<string, number>;
  topDisease: string;
}) {
  const ordered = [
    ...DISEASE_ORDER.filter((d) => d in probabilities),
    ...Object.keys(probabilities).filter((d) => !DISEASE_ORDER.includes(d)),
  ];

  return (
    <div className="space-y-2.5">
      {ordered.map((disease) => {
        const score = probabilities[disease] ?? 0;
        const pct = Math.round(score * 100);
        const cfg = getDiseaseConfig(disease);
        const isTop = disease.toLowerCase() === topDisease.toLowerCase();
        return (
          <div key={disease}>
            <div className="mb-1 flex items-center justify-between text-xs">
              <span className={`font-medium ${isTop ? "font-semibold text-slate-900" : "text-slate-500"}`}>
                {cfg.label}
                {isTop && <span className="ml-1.5 text-amber-500">★</span>}
              </span>
              <span className={`tabular-nums font-semibold ${isTop ? cfg.text : "text-slate-400"}`}>
                {pct}%
              </span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-slate-100">
              <div
                className={`h-full rounded-full transition-all duration-700 ${cfg.bar} ${isTop ? "opacity-100" : "opacity-50"}`}
                style={{ width: `${Math.max(2, pct)}%` }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function FeatureImportanceList({ featureImportance }: { featureImportance: Record<string, number> }) {
  const top = Object.entries(featureImportance)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6);
  const maxVal = top[0]?.[1] ?? 1;

  if (!top.length) return <p className="text-sm text-slate-400">No feature data available.</p>;

  return (
    <div className="space-y-2.5">
      {top.map(([symptom, score]) => {
        const relPct = Math.round((score / maxVal) * 100);
        const absPct = Math.round(score * 100);
        return (
          <div key={symptom}>
            <div className="mb-0.5 flex items-center justify-between text-xs">
              <span className="text-slate-700">{fmtSymptom(symptom)}</span>
              <span className="tabular-nums text-slate-400">{absPct}%</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-slate-100">
              <div
                className="h-full rounded-full bg-gradient-to-r from-[#1A5C3A] to-[#4CAF82]"
                style={{ width: `${Math.max(3, relPct)}%` }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── Validation schemas ────────────────────────────────────────────────────────
const updateSchema = z.object({
  status: z.enum(["open", "in_treatment", "resolved"]),
  triage_status: z.enum(["needs_review", "escalated"]),
  followup_date: z.string().optional(),
  notes: z.string().optional(),
  corrected_label: z.string().optional(),
});

const feedbackSchema = z.object({
  was_correct: z.enum(["yes", "no"]),
  corrected_label: z.string().optional(),
  comment: z.string().optional(),
});

// ── Main page ─────────────────────────────────────────────────────────────────
export default function CaseDetailPage() {
  const params = useParams<{ id: string }>();
  const caseId = params.id;
  const auth = getAuthState();
  const userRole = auth?.user.role;
  const isVetUser = userRole === "VET";
  const isAdminUser = userRole === "ADMIN";
  const [showGradcam, setShowGradcam] = useState(false);
  const [dispatchAssignee, setDispatchAssignee] = useState("");
  const [actionNotice, setActionNotice] = useState<{ tone: "success" | "error"; message: string } | null>(null);
  const [chatInput, setChatInput] = useState("");
  const [showRejectForm, setShowRejectForm] = useState(false);
  const [rejectReason, setRejectReason] = useState("");
  const chatEndRef = useRef<HTMLDivElement>(null);
  const queryClient = useQueryClient();

  const caseQuery = useQuery<CaseItem>({
    queryKey: ["case", caseId],
    queryFn: () => api.getCase(caseId),
    refetchInterval: 15000,
    refetchOnWindowFocus: true,
  });
  const usersQuery = useQuery<UserItem[]>({
    queryKey: ["assignable-users-for-case"],
    queryFn: () => api.listAssignableUsers(),
    enabled: isAdminUser,
  });
  const timelineQuery = useQuery<any>({
    queryKey: ["timeline", caseId],
    queryFn: () => api.timeline(caseId),
    refetchInterval: 10000,
    refetchOnWindowFocus: true,
  });

  const updateForm = useForm<z.infer<typeof updateSchema>>({
    resolver: zodResolver(updateSchema),
    values: {
      status: (caseQuery.data?.status || "open") as "open" | "in_treatment" | "resolved",
      triage_status: (caseQuery.data?.triage_status || "escalated") as "needs_review" | "escalated",
      followup_date: caseQuery.data?.followup_date ? caseQuery.data.followup_date.slice(0, 10) : "",
      notes: caseQuery.data?.notes || "",
      corrected_label: caseQuery.data?.corrected_label || "",
    },
  });

  const feedbackForm = useForm<z.infer<typeof feedbackSchema>>({
    resolver: zodResolver(feedbackSchema),
    defaultValues: { was_correct: "yes", corrected_label: "", comment: "" },
  });

  const updateMutation = useMutation({
    mutationFn: (values: z.infer<typeof updateSchema>) =>
      api.patchCase(caseId, {
        ...values,
        followup_date: values.followup_date ? new Date(values.followup_date).toISOString() : null,
      }),
    onMutate: () => setActionNotice(null),
    onSuccess: async () => {
      setActionNotice({ tone: "success", message: "Case workflow updates saved." });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["case", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["timeline", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["overview-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics-summary-overview"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics"] }),
      ]);
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to save case updates.",
      }),
  });

  const feedbackMutation = useMutation({
    mutationFn: (values: z.infer<typeof feedbackSchema>) =>
      api.addFeedback(caseId, {
        was_correct: values.was_correct === "yes",
        corrected_label: values.corrected_label || null,
        comment: values.comment || null,
      }),
    onMutate: () => setActionNotice(null),
    onSuccess: async () => {
      feedbackForm.reset();
      setActionNotice({ tone: "success", message: "Feedback submitted and audit timeline updated." });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["timeline", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["case", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["overview-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics-summary-overview"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics"] }),
      ]);
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to submit feedback.",
      }),
  });

  const assignMutation = useMutation({
    mutationFn: (assignedToUserId: number) => api.assignCase(caseId, assignedToUserId),
    onMutate: () => setActionNotice(null),
    onSuccess: async () => {
      setDispatchAssignee("");
      setActionNotice({ tone: "success", message: "Case assigned to vet queue." });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["case", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["timeline", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["overview-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics-summary-overview"] }),
        queryClient.invalidateQueries({ queryKey: ["analytics"] }),
      ]);
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to assign case.",
      }),
  });

  const sendMessageMutation = useMutation({
    mutationFn: (msg: string) => api.sendMessage(caseId, msg),
    onSuccess: async () => {
      setChatInput("");
      await queryClient.invalidateQueries({ queryKey: ["timeline", caseId] });
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to send message.",
      }),
  });

  // VET self-assign: "Claim Case" — calls POST /claim
  const claimMutation = useMutation({
    mutationFn: () => api.claimCase(caseId),
    onMutate: () => setActionNotice(null),
    onSuccess: async () => {
      setActionNotice({ tone: "success", message: "Case claimed. Chat is now unlocked." });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["case", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["timeline", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
      ]);
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to claim case.",
      }),
  });

  // VET release: "Release Case" — calls POST /reject and returns case to escalated queue
  const rejectMutation = useMutation({
    mutationFn: (reason: string) => api.rejectCase(caseId, reason),
    onMutate: () => setActionNotice(null),
    onSuccess: async () => {
      setShowRejectForm(false);
      setRejectReason("");
      setActionNotice({ tone: "success", message: "Case released back to the vet queue." });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["case", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["timeline", caseId] }),
        queryClient.invalidateQueries({ queryKey: ["triage-cases"] }),
        queryClient.invalidateQueries({ queryKey: ["cases"] }),
      ]);
    },
    onError: (error) =>
      setActionNotice({
        tone: "error",
        message: error instanceof Error ? error.message : "Failed to release case.",
      }),
  });

  const chatMessages: any[] = timelineQuery.data?.messages ?? [];
  const auditEvents: any[] = timelineQuery.data?.events ?? [];

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chatMessages.length]);

  // ── Derived prediction data ───────────────────────────────────────────────
  const predJson: PredictionJson = caseQuery.data?.prediction_json ?? {};
  const predictionLabel = String(predJson.final_label || predJson.label || "unknown").toLowerCase();
  const displayLabel = predJson.display_label || getDiseaseConfig(predictionLabel).label;
  const probabilities = predJson.probabilities ?? {};
  const triggers = predJson.rule_triggers ?? [];
  const featureImportance = predJson.feature_importance ?? {};
  const differential = predJson.differential ?? [];
  const reasoning = predJson.reasoning ?? "";
  const recommendations = predJson.recommendations ?? [];
  const temperatureNote = predJson.temperature_note;
  const severityNote = predJson.severity_note;
  const supportingEvidence = Array.isArray(predJson.supporting_evidence)
    ? predJson.supporting_evidence.map((v) => String(v))
    : [];
  const cautionaryEvidence = Array.isArray(predJson.cautionary_evidence)
    ? predJson.cautionary_evidence.map((v) => String(v))
    : [];
  const modalitySummary =
    typeof predJson.modality_summary === "string" ? predJson.modality_summary : "";
  const evidenceQuality =
    typeof predJson.evidence_quality === "string" ? predJson.evidence_quality : "";
  const confidenceBand =
    typeof predJson.confidence_band === "string" ? predJson.confidence_band : "";

  const symptomEntries = Object.entries((caseQuery.data?.symptoms_json || {}) as Record<string, unknown>);
  const activeSymptoms = symptomEntries.filter(([, v]) => Boolean(v)).map(([k]) => k);

  const gradcamUrl = String(predJson.gradcam_url || predJson.gradcam_path || "");
  const imageSrc = showGradcam && gradcamUrl ? gradcamUrl : caseQuery.data?.image_url;
  const predictionEngine = String(predJson.engine || "").trim();
  const usingFallback = predictionEngine === "bayesian_fallback";

  const topCfg = getDiseaseConfig(predictionLabel);
  const confidence = caseQuery.data?.confidence ?? 0;
  const confidencePct = Math.round(confidence * 100);

  const hasExplainability =
    reasoning ||
    triggers.length > 0 ||
    differential.length > 0 ||
    recommendations.length > 0 ||
    modalitySummary ||
    supportingEvidence.length > 0 ||
    cautionaryEvidence.length > 0;

  const assignableUsers = useMemo(
    () => (usersQuery.data || []).filter((u) => u.role === "VET"),
    [usersQuery.data]
  );

  // Derive UI policy from case state + current user
  const uiPolicy = caseQuery.data && auth?.user
    ? deriveCaseUI(caseQuery.data, auth.user as { id: number; role: "CAHW" | "VET" | "ADMIN" })
    : null;

  if (caseQuery.isError) {
    return (
      <div className="rounded-2xl border border-[#F0CAC2] bg-[#FFF4F0] p-4 text-sm text-[#8E4433]">
        {caseQuery.error instanceof Error ? caseQuery.error.message : "Failed to load case detail."}
      </div>
    );
  }

  if (!caseQuery.data) {
    return (
      <div className="flex items-center justify-center py-20 text-sm text-slate-400">
        Loading case...
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Page header */}
      <PageHeader
        eyebrow="Case Workbench"
        title={`Case ${caseQuery.data.client_case_id || caseQuery.data.id.slice(0, 8)}`}
        description="Clinical review, model explainability, triage decisions, follow-up planning, and audit activity."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <RiskBadge value={caseQuery.data.risk_level} />
            <TriageStatusBadge value={caseQuery.data.triage_status} />
            <CaseStatusBadge value={caseQuery.data.status} />
          </div>
        }
      />

      <Card className="border-[#D7E8E0] bg-[#F8FCFA]">
        <div className="mb-3 flex items-center justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary">Field Intake Packet</p>
            <p className="text-sm text-muted">
              Context captured from the mobile app and handed to the clinical dashboard for triage and review.
            </p>
          </div>
          <Badge variant="neutral">Live refresh 15s</Badge>
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-xl border border-border bg-white p-3">
            <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              <Tag size={12} />
              Animal Tag
            </div>
            <p className="text-sm font-semibold">{caseQuery.data.animal_tag || "Unlinked animal"}</p>
          </div>
          <div className="rounded-xl border border-border bg-white p-3">
            <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              <UserRound size={12} />
              Submitted By
            </div>
            <p className="text-sm font-semibold">
              {caseQuery.data.submitted_by_name || `User #${caseQuery.data.submitted_by_user_id}`}
            </p>
          </div>
          <div className="rounded-xl border border-border bg-white p-3">
            <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              <UserRound size={12} />
              Assigned To
            </div>
            <p className="text-sm font-semibold">
              {caseQuery.data.assigned_to_name ||
                (caseQuery.data.assigned_to_user_id
                  ? `User #${caseQuery.data.assigned_to_user_id}`
                  : "Unassigned")}
            </p>
          </div>
          <div className="rounded-xl border border-border bg-white p-3">
            <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              <CalendarDays size={12} />
              Created
            </div>
            <p className="text-sm font-semibold">{new Date(caseQuery.data.created_at).toLocaleString()}</p>
          </div>
        </div>
      </Card>

      {actionNotice && (
        <Card
          className={
            actionNotice.tone === "success"
              ? "border-[#BEE1D3] bg-[#EEF9F3]"
              : "border-[#F0CAC2] bg-[#FFF4F0]"
          }
        >
          <p className={actionNotice.tone === "success" ? "text-sm text-[#155C45]" : "text-sm text-[#8E4433]"}>
            {actionNotice.message}
          </p>
        </Card>
      )}

      {/* VET: Claim Case call-to-action — shown when case is claimable */}
      {uiPolicy?.isClaimable && (
        <Card className="border-[#BEE1D3] bg-[#EAF7F1]">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="font-semibold text-[#155C45]">
                {uiPolicy.isRequestedForMe
                  ? "This case was specifically requested for you"
                  : "This case is waiting for a vet"}
              </p>
              <p className="text-sm text-[#2B6B4A]">
                Claim it to add to your queue and unlock the chat with the field worker.
                {caseQuery.data.request_note && (
                  <span className="ml-1 italic">"{caseQuery.data.request_note}"</span>
                )}
              </p>
            </div>
            <Button
              onClick={() => claimMutation.mutate()}
              disabled={claimMutation.isPending}
              className="shrink-0 bg-[#1F8A66] hover:bg-[#176F52] text-white"
            >
              {claimMutation.isPending ? "Claiming..." : "Claim Case"}
            </Button>
          </div>
        </Card>
      )}

      {/* Image & Model Output row */}
      <div className="grid gap-4 lg:grid-cols-2">
        {/* Image & Symptoms */}
        <Card className="space-y-3">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <ImageIcon size={16} className="text-primary" />
              <h2 className="font-semibold">Image &amp; Symptoms</h2>
            </div>
            <Button
              variant="outline"
              onClick={() => setShowGradcam((v) => !v)}
              disabled={!gradcamUrl}
              title={gradcamUrl ? "Toggle explainability overlay" : "No Grad-CAM available"}
            >
              {!gradcamUrl ? "Grad-CAM unavailable" : showGradcam ? "Show Original" : "Show Grad-CAM"}
            </Button>
          </div>
          {imageSrc ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={imageSrc}
              alt="case image"
              className="h-56 w-full rounded-xl border border-border object-cover"
            />
          ) : (
            <div className="flex h-40 items-center justify-center rounded-xl border border-dashed border-border bg-slate-50">
              <p className="text-sm text-slate-400">No image available for this case</p>
            </div>
          )}
          <div className="rounded-xl border border-border bg-[#F5FBF8] p-3">
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              Active Symptoms ({activeSymptoms.length})
            </p>
            {activeSymptoms.length ? (
              <div className="flex flex-wrap gap-1.5">
                {activeSymptoms.map((s) => (
                  <Badge key={s} variant="accent">
                    {fmtSymptom(s)}
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-sm text-muted">No positive symptom flags captured in this record.</p>
            )}
          </div>
        </Card>

        {/* Model Output */}
        <Card className="space-y-4">
          <div className="flex items-center gap-2">
            <Sparkles size={16} className="text-[#7C5A1F]" />
            <h2 className="font-semibold">Model Output</h2>
          </div>

          {/* Disease result hero */}
          <div className={`rounded-xl border p-4 ${topCfg.bg} ${topCfg.border}`}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">
                  Top Prediction
                </p>
                <p className={`mt-0.5 text-xl font-bold leading-tight ${topCfg.text}`}>
                  {displayLabel}
                </p>
              </div>
              <div className="flex shrink-0 flex-col items-center rounded-xl bg-white/70 px-3 py-2 shadow-sm">
                <span className={`text-2xl font-black tabular-nums ${topCfg.text}`}>
                  {confidencePct}%
                </span>
                <span className="text-xs font-medium text-slate-500">confidence</span>
              </div>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              <MethodBadge value={caseQuery.data.method} />
              <RiskBadge value={caseQuery.data.risk_level} />
              {predictionEngine ? <Badge variant="neutral">Engine: {predictionEngine}</Badge> : null}
            </div>
          </div>

          {usingFallback ? (
            <div className="rounded-xl border border-[#E5CF9E] bg-[#FAEFD8] px-3 py-2 text-xs text-[#6E531C]">
              ML service was unavailable for this prediction. Bayesian fallback was used.
            </div>
          ) : null}

          {/* Disease probability distribution */}
          <div>
            <div className="mb-2.5 flex items-center gap-2">
              <BarChart3 size={13} className="text-slate-400" />
              <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                Disease Probability Distribution
              </p>
            </div>
            {Object.keys(probabilities).length ? (
              <DiseaseProbabilityBars probabilities={probabilities} topDisease={predictionLabel} />
            ) : (
              <p className="text-sm text-muted">No probability distribution available.</p>
            )}
          </div>

          {/* Feature importance */}
          {Object.keys(featureImportance).length > 0 && (
            <div>
              <div className="mb-2.5 flex items-center gap-2">
                <Activity size={13} className="text-slate-400" />
                <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Key Symptom Contributions
                </p>
              </div>
              <FeatureImportanceList featureImportance={featureImportance} />
            </div>
          )}
        </Card>
      </div>

      {/* AI Reasoning · Differential · Recommendations */}
      {hasExplainability && (
        <div className="grid gap-4 xl:grid-cols-3">
          {/* AI Reasoning + rule triggers */}
          {(reasoning ||
            triggers.length > 0 ||
            temperatureNote ||
            severityNote ||
            modalitySummary ||
            supportingEvidence.length > 0 ||
            cautionaryEvidence.length > 0) && (
            <Card className="space-y-3">
              <div className="flex items-center gap-2">
                <Brain size={16} className="text-purple-500" />
                <h2 className="font-semibold">AI Reasoning</h2>
              </div>
              {(evidenceQuality || confidenceBand) && (
                <div className="flex flex-wrap gap-1.5">
                  {evidenceQuality && (
                    <Badge variant="neutral">
                      Evidence: {evidenceQuality.replaceAll("_", " ")}
                    </Badge>
                  )}
                  {confidenceBand && (
                    <Badge variant="accent">
                      Confidence Band: {confidenceBand.replaceAll("_", " ")}
                    </Badge>
                  )}
                </div>
              )}
              {modalitySummary && (
                <div className="rounded-lg border border-emerald-200 bg-emerald-50/70 px-3 py-2 text-xs text-emerald-900">
                  {modalitySummary}
                </div>
              )}
              {reasoning && (
                <blockquote className="border-l-4 border-purple-300 bg-purple-50 py-3 pl-4 pr-3 text-sm italic leading-relaxed text-slate-700 rounded-r-lg">
                  {reasoning}
                </blockquote>
              )}
              {(supportingEvidence.length > 0 || cautionaryEvidence.length > 0) && (
                <div className="grid gap-2">
                  {supportingEvidence.length > 0 && (
                    <div className="rounded-lg border border-emerald-200 bg-emerald-50 p-3">
                      <p className="mb-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-emerald-700">
                        Supporting Evidence
                      </p>
                      <ul className="space-y-1 text-xs leading-relaxed text-emerald-900">
                        {supportingEvidence.slice(0, 4).map((item, idx) => (
                          <li key={`${idx}-${item}`} className="flex gap-2">
                            <span className="mt-[3px] h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-600" />
                            <span>{item}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {cautionaryEvidence.length > 0 && (
                    <div className="rounded-lg border border-amber-200 bg-amber-50 p-3">
                      <p className="mb-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-amber-700">
                        Review / Cautions
                      </p>
                      <ul className="space-y-1 text-xs leading-relaxed text-amber-900">
                        {cautionaryEvidence.slice(0, 4).map((item, idx) => (
                          <li key={`${idx}-${item}`} className="flex gap-2">
                            <span className="mt-[3px] h-1.5 w-1.5 shrink-0 rounded-full bg-amber-600" />
                            <span>{item}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}
              {(temperatureNote || severityNote) && (
                <div className="space-y-1.5">
                  {temperatureNote && (
                    <div className="flex items-start gap-2 rounded-lg bg-orange-50 px-3 py-2 text-xs text-orange-800 border border-orange-100">
                      <span className="mt-0.5 shrink-0">🌡️</span>
                      <span>{temperatureNote}</span>
                    </div>
                  )}
                  {severityNote && (
                    <div className="flex items-start gap-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-800 border border-red-100">
                      <span className="mt-0.5 shrink-0">⚠️</span>
                      <span>{severityNote}</span>
                    </div>
                  )}
                </div>
              )}
              {triggers.length > 0 && (
                <div>
                  <p className="mb-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    Rule Triggers
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {triggers.map((t) => (
                      <span
                        key={t}
                        className="inline-flex items-center rounded-full bg-emerald-50 px-2.5 py-0.5 text-xs font-medium text-emerald-800 ring-1 ring-inset ring-emerald-300"
                      >
                        {t.replaceAll("_", " ")}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </Card>
          )}

          {/* Differential diagnosis */}
          {differential.length > 0 && (
            <Card className="space-y-3">
              <div className="flex items-center gap-2">
                <Activity size={16} className="text-blue-500" />
                <h2 className="font-semibold">Differential Diagnosis</h2>
              </div>
              <div className="space-y-2">
                {differential.slice(0, 4).map((entry, idx) => {
                  const cfg = getDiseaseConfig(entry.disease);
                  const pct =
                    entry.percentage !== undefined
                      ? Math.round(entry.percentage)
                      : Math.round((entry.score ?? 0) * 100);
                  return (
                    <div
                      key={entry.disease}
                      className={`flex items-center gap-3 rounded-xl border p-3 ${
                        idx === 0 ? `${cfg.bg} ${cfg.border}` : "border-border bg-white"
                      }`}
                    >
                      <div
                        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-bold ${
                          idx === 0 ? `${cfg.bar} text-white` : "bg-slate-100 text-slate-500"
                        }`}
                      >
                        {idx + 1}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p
                          className={`text-sm font-semibold leading-tight ${
                            idx === 0 ? cfg.text : "text-slate-800"
                          }`}
                        >
                          {entry.display_name || cfg.label}
                        </p>
                        {entry.matched_symptoms && entry.matched_symptoms.length > 0 && (
                          <p className="mt-0.5 truncate text-xs text-slate-400">
                            {entry.matched_symptoms.slice(0, 3).map(fmtSymptom).join(" · ")}
                          </p>
                        )}
                      </div>
                      <span
                        className={`shrink-0 text-sm font-bold tabular-nums ${
                          idx === 0 ? cfg.text : "text-slate-500"
                        }`}
                      >
                        {pct}%
                      </span>
                    </div>
                  );
                })}
              </div>
            </Card>
          )}

          {/* Recommendations */}
          {recommendations.length > 0 && (
            <Card className="space-y-3">
              <div className="flex items-center gap-2">
                <ListChecks size={16} className="text-emerald-600" />
                <h2 className="font-semibold">Recommendations</h2>
              </div>
              <ul className="space-y-2.5">
                {recommendations.map((rec, i) => (
                  <li key={i} className="flex items-start gap-3 text-sm">
                    <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                      <span className="text-xs font-bold">{i + 1}</span>
                    </div>
                    <span className="leading-snug text-slate-700">{rec}</span>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}

      {/* Case Actions & Feedback */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Stethoscope size={16} className="text-primary" />
              <h2 className="font-semibold">Case Actions</h2>
            </div>
            <Badge variant={uiPolicy?.canPatchWorkflow ? "deep" : "neutral"}>
              {isAdminUser ? "Admin" : uiPolicy?.isOwnedByMe ? "Assigned Vet" : "Read-only"}
            </Badge>
          </div>

          {isAdminUser ? (
            <div className="space-y-4">
              {/* ── Dispatch / Assign Vet ────────────────────────── */}
              <div className="rounded-xl border border-[#BEE1D3] bg-[#F0FAF5] p-3">
                <p className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-[#155C45]">
                  Assign Vet
                </p>
                {caseQuery.data.assigned_to_name && (
                  <p className="mb-2 text-xs text-muted">
                    Currently assigned to <strong>{caseQuery.data.assigned_to_name}</strong>
                  </p>
                )}
                <div className="space-y-2">
                  <Select
                    value={dispatchAssignee}
                    onChange={(e) => setDispatchAssignee(e.target.value)}
                    disabled={assignMutation.isPending}
                  >
                    <option value="">— Select vet to dispatch —</option>
                    {assignableUsers.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.name}
                      </option>
                    ))}
                  </Select>
                  <Button
                    type="button"
                    disabled={assignMutation.isPending || !dispatchAssignee}
                    onClick={() => {
                      const vetId = Number(dispatchAssignee);
                      if (!Number.isFinite(vetId) || vetId <= 0) return;
                      assignMutation.mutate(vetId);
                    }}
                  >
                    {assignMutation.isPending ? "Dispatching..." : "Dispatch to Vet"}
                  </Button>
                </div>
              </div>

              {/* ── Workflow override ─────────────────────────────── */}
              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Workflow Override
                </p>
                <form
                  className="space-y-3"
                  onSubmit={updateForm.handleSubmit((v) => updateMutation.mutate(v))}
                >
                  <div className="grid gap-3 md:grid-cols-2">
                    <div>
                      <Label>Case Status</Label>
                      <Select {...updateForm.register("status")}>
                        <option value="open">Open</option>
                        <option value="in_treatment">In Treatment</option>
                        <option value="resolved">Resolved</option>
                      </Select>
                    </div>
                    <div>
                      <Label>Queue Status</Label>
                      <Select {...updateForm.register("triage_status")}>
                        <option value="escalated">In Vet Queue</option>
                        <option value="needs_review">Needs Review</option>
                      </Select>
                    </div>
                  </div>
                  <div>
                    <Label>Follow-up Date</Label>
                    <Input type="date" {...updateForm.register("followup_date")} />
                  </div>
                  <div>
                    <Label>Admin Notes</Label>
                    <Textarea placeholder="Dispatch notes, observations..." {...updateForm.register("notes")} />
                  </div>
                  <Button type="submit" disabled={updateMutation.isPending}>
                    {updateMutation.isPending ? "Saving..." : "Save Workflow"}
                  </Button>
                </form>
              </div>
            </div>
          ) : uiPolicy?.isOwnedByMe ? (
            <div className="space-y-4">
              <form className="space-y-3" onSubmit={updateForm.handleSubmit((v) => updateMutation.mutate(v))}>
                <div>
                  <Label>Treatment Progress</Label>
                  <Select {...updateForm.register("status")}>
                    <option value="open">Open — reviewing</option>
                    <option value="in_treatment">In Treatment — vet advice given</option>
                    <option value="resolved">Resolved — case closed</option>
                  </Select>
                </div>
                <div>
                  <Label>Follow-up Date</Label>
                  <Input type="date" {...updateForm.register("followup_date")} />
                </div>
                <div>
                  <Label>AI Prediction Override (if incorrect)</Label>
                  <Input
                    placeholder="e.g. fmd, lsd, ecf, cbpp, normal"
                    {...updateForm.register("corrected_label")}
                  />
                </div>
                <div>
                  <Label>Clinical Notes</Label>
                  <Textarea placeholder="Treatment plan, observations, advice to CAHW..." {...updateForm.register("notes")} />
                </div>
                <Button type="submit" disabled={updateMutation.isPending}>
                  {updateMutation.isPending ? "Saving..." : "Save Updates"}
                </Button>
              </form>

              {/* ── Release case back to vet queue ─────────────────── */}
              <div className="border-t border-border pt-3">
                {!showRejectForm ? (
                  <Button
                    type="button"
                    variant="outline"
                    className="w-full border-red-200 text-red-600 hover:bg-red-50 hover:border-red-300"
                    onClick={() => setShowRejectForm(true)}
                  >
                    <LogOut size={14} className="mr-1.5" />
                    Release case to queue
                  </Button>
                ) : (
                  <div className="rounded-xl border border-red-200 bg-red-50 p-3 space-y-2">
                    <p className="text-xs font-semibold text-red-700">
                      Release reason (required — visible in audit log)
                    </p>
                    <Textarea
                      placeholder="Why are you releasing this case? e.g. outside speciality, needs additional workup"
                      value={rejectReason}
                      onChange={(e) => setRejectReason(e.target.value)}
                      className="bg-white text-sm"
                    />
                    <div className="flex gap-2">
                      <Button
                        type="button"
                        className="bg-red-600 hover:bg-red-700 text-white"
                        disabled={!rejectReason.trim() || rejectMutation.isPending}
                        onClick={() => rejectMutation.mutate(rejectReason.trim())}
                      >
                        {rejectMutation.isPending ? "Releasing..." : "Confirm release"}
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        onClick={() => { setShowRejectForm(false); setRejectReason(""); }}
                      >
                        Cancel
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          ) : (
            <div className="rounded-lg border border-[#E5CF9E] bg-[#FAEFD8] px-3 py-2 text-sm text-[#6E531C]">
              {isVetUser
                ? "Claim this case first to enable clinical updates."
                : "Read-only view. Only the assigned vet or an admin can update this case."}
            </div>
          )}
        </Card>

        <Card>
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Sparkles size={16} className="text-[#7C5A1F]" />
              <h2 className="font-semibold">Submit Feedback</h2>
            </div>
            <Badge variant="accent">Vet only</Badge>
          </div>
          {isVetUser ? (
            <form
              className="space-y-3"
              onSubmit={feedbackForm.handleSubmit((v) => feedbackMutation.mutate(v))}
            >
              <div>
                <Label>Prediction Correct?</Label>
                <Select {...feedbackForm.register("was_correct")}>
                  <option value="yes">Correct</option>
                  <option value="no">Incorrect</option>
                </Select>
              </div>
              <div>
                <Label>Corrected Label</Label>
                <Input {...feedbackForm.register("corrected_label")} />
              </div>
              <div>
                <Label>Comment</Label>
                <Textarea {...feedbackForm.register("comment")} />
              </div>
              <Button type="submit" disabled={feedbackMutation.isPending}>
                {feedbackMutation.isPending ? "Submitting..." : "Submit Feedback"}
              </Button>
            </form>
          ) : (
            <p className="text-sm text-muted">
              Feedback submission is restricted to the assigned vet doctor.
            </p>
          )}
        </Card>
      </div>

      {/* Chat + Audit Timeline row */}
      <div className="grid gap-4 lg:grid-cols-2">
        {/* Chat Panel */}
        <Card className="flex flex-col">
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <MessageSquare size={16} className="text-primary" />
              <h2 className="font-semibold">Case Chat</h2>
            </div>
            <Badge variant="neutral">
              {chatMessages.length} message{chatMessages.length === 1 ? "" : "s"}
            </Badge>
          </div>

          {/* Admin privacy notice — admin cannot see or send chat messages */}
          {isAdminUser ? (
            <div className="flex flex-1 flex-col items-center justify-center rounded-xl border border-border bg-slate-50 p-6 text-center" style={{ minHeight: "200px" }}>
              <MessageSquare size={28} className="mb-2 text-slate-300" />
              <p className="text-sm font-medium text-slate-500">Chat is private</p>
              <p className="mt-1 text-xs text-muted">
                Messages between the CAHW and the assigned vet are end-to-end private.
                Admins can monitor case progress via the Audit Timeline.
              </p>
            </div>
          ) : (
            <>
              {/* Message bubbles */}
              <div className="flex-1 space-y-2 overflow-y-auto rounded-xl border border-border bg-slate-50 p-3" style={{ maxHeight: "360px", minHeight: "200px" }}>
                {chatMessages.length === 0 ? (
                  <p className="py-8 text-center text-sm text-muted">No messages yet. Start the conversation.</p>
                ) : (
                  chatMessages.map((msg: any) => {
                    const isVet = String(msg.senderRole || "").toLowerCase() === "vet";
                    return (
                      <div key={msg.id} className={`flex ${isVet ? "justify-end" : "justify-start"}`}>
                        <div
                          className={`max-w-[80%] rounded-2xl px-3 py-2 text-sm leading-snug ${
                            isVet
                              ? "bg-primary text-white"
                              : "bg-white border border-border text-slate-800"
                          }`}
                        >
                          {!isVet && (
                            <p className="mb-0.5 text-[10px] font-semibold uppercase tracking-wide text-slate-400">
                              {msg.senderName || "CAHW"}
                            </p>
                          )}
                          <p>{msg.message}</p>
                          <p className={`mt-0.5 text-right text-[10px] ${isVet ? "text-white/70" : "text-slate-400"}`}>
                            {new Date(msg.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                          </p>
                        </div>
                      </div>
                    );
                  })
                )}
                <div ref={chatEndRef} />
              </div>

              {/* Input — only the assigned vet can send messages */}
              {(() => {
                const currentUserId = auth?.user.id;
                const assignedVetId = caseQuery.data?.assigned_to_user_id;
                const isAssignedVet = isVetUser && currentUserId != null && currentUserId === assignedVetId;

                if (isAssignedVet) {
                  return (
                    <div className="mt-3 flex gap-2">
                      <input
                        className="flex-1 rounded-xl border border-border bg-white px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                        placeholder="Type a message..."
                        value={chatInput}
                        onChange={(e) => setChatInput(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" && !e.shiftKey && chatInput.trim()) {
                            e.preventDefault();
                            sendMessageMutation.mutate(chatInput.trim());
                          }
                        }}
                        disabled={sendMessageMutation.isPending}
                      />
                      <Button
                        type="button"
                        disabled={sendMessageMutation.isPending || !chatInput.trim()}
                        onClick={() => sendMessageMutation.mutate(chatInput.trim())}
                      >
                        <Send size={14} className="mr-1" />
                        {sendMessageMutation.isPending ? "..." : "Send"}
                      </Button>
                    </div>
                  );
                }

                if (isVetUser && !isAssignedVet) {
                  return (
                    <p className="mt-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-700">
                      You can only reply after claiming this case.
                    </p>
                  );
                }

                return null;
              })()}
            </>
          )}
        </Card>

        {/* Audit Timeline */}
        <Card>
          <div className="mb-3 flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Clock3 size={16} className="text-primary" />
              <h2 className="font-semibold">Audit Timeline</h2>
            </div>
            <Badge variant="neutral">
              {auditEvents.length} event{auditEvents.length === 1 ? "" : "s"}
            </Badge>
          </div>
          {auditEvents.length === 0 ? (
            <p className="text-sm text-muted">No timeline events recorded yet.</p>
          ) : (
            <ul className="max-h-[440px] space-y-2 overflow-y-auto text-sm">
              {auditEvents.map((item: any) => (
                <li key={item.id} className="rounded-xl border border-border bg-[#FCFEFD] p-3">
                  <p className="font-medium capitalize">
                    {String(item.event_type || "").replaceAll("_", " ")}
                  </p>
                  <p className="text-xs text-slate-500">{new Date(item.created_at).toLocaleString()}</p>
                  {item.event_type !== "message" && (
                    <pre className="mt-2 overflow-auto rounded-lg border border-border bg-white p-2 text-xs">
                      {JSON.stringify(item.payload_json, null, 2)}
                    </pre>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
