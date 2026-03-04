"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { AlertCircle, ArrowRight, Eye, EyeOff, Loader2 } from "lucide-react";
import { z } from "zod";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api } from "@/lib/api";
import { setAccessToken, setAuthState } from "@/lib/auth";

const schema = z.object({
  email:    z.string().email("Enter a valid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});
type LoginForm = z.infer<typeof schema>;

/* ── Static left-panel data ──────────────────────────────────────────────────── */
const STATS = [
  { value: "2,847", label: "Cases processed" },
  { value: "94.3%", label: "AI accuracy" },
  { value: "4 min",  label: "Avg triage time" },
];

const DISEASES = [
  { key: "LSD",  pct: 38, color: "#E6A817" },
  { key: "FMD",  pct: 27, color: "#D94F3D" },
  { key: "ECF",  pct: 21, color: "#7B5EA7" },
  { key: "CBPP", pct: 14, color: "#2E7BA0" },
];

/* ── Sparkline SVG (last-7-week trend) ──────────────────────────────────────── */
function Sparkline() {
  const pts = [58, 42, 62, 35, 50, 28, 45, 18, 32];
  const w = 280;
  const h = 52;
  const step = w / (pts.length - 1);
  const max  = Math.max(...pts);
  const coords = pts.map((v, i) => `${i * step},${h - (v / max) * (h - 4)}`).join(" ");
  const area = `0,${h} ${coords} ${w},${h}`;

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="none">
      <defs>
        <linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stopColor="#4BC997" stopOpacity="0.25" />
          <stop offset="100%" stopColor="#4BC997" stopOpacity="0"    />
        </linearGradient>
      </defs>
      <polygon points={area} fill="url(#sparkFill)" />
      <polyline
        points={coords}
        fill="none"
        stroke="#4BC997"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* last point dot */}
      {(() => {
        const last = pts.length - 1;
        const cx = last * step;
        const cy = h - (pts[last] / max) * (h - 4);
        return <circle cx={cx} cy={cy} r="3" fill="#4BC997" />;
      })()}
    </svg>
  );
}

/* ── Page ───────────────────────────────────────────────────────────────────── */
export default function LoginPage() {
  const router = useRouter();
  const [error,      setError]      = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [showPw,     setShowPw]     = useState(false);

  const form = useForm<LoginForm>({
    resolver: zodResolver(schema),
    defaultValues: { email: "", password: "" },
  });

  const onSubmit = async (values: LoginForm) => {
    setError("");
    setSubmitting(true);
    try {
      const res = await api.login(values);
      const accessToken  = res.access_token ?? res.token;
      const refreshToken = res.refresh_token ?? res.refreshToken;
      if (!accessToken || !refreshToken || !res.user) {
        throw new Error("Login response missing token fields.");
      }
      setAccessToken(accessToken);
      await setAuthState({ refreshToken, user: res.user });
      router.push("/overview");
    } catch (e) {
      const message = e instanceof Error ? e.message : "Login failed";
      setError(message.replace(/^Error:\s*/i, ""));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen">

      {/* ════════════════════════════════════════════════════════════════════════
          LEFT PANEL — dark forest, desktop only
      ════════════════════════════════════════════════════════════════════════ */}
      <aside className="relative hidden w-[44%] flex-col justify-between overflow-hidden bg-[#091F14] px-12 py-10 lg:flex xl:px-16">

        {/* Dot-grid texture */}
        <div className="absolute inset-0 [background-image:radial-gradient(rgba(255,255,255,0.055)_1px,transparent_1px)] [background-size:22px_22px]" />

        {/* Glow blobs — intentional, not generic */}
        <div className="pointer-events-none absolute inset-0">
          <div className="absolute -left-24 top-1/3 h-80 w-80 rounded-full bg-[#1F8A66] opacity-[0.12] blur-[90px]" />
          <div className="absolute -bottom-16 right-8 h-64 w-64 rounded-full bg-[#BB8927] opacity-[0.07] blur-[70px]" />
        </div>

        {/* Top: brand ─────────────────────────────────────────── */}
        <div className="relative z-10 flex items-center gap-3">
          <div className="relative grid h-9 w-9 place-items-center rounded-xl bg-[#1F8A66] shadow-[0_0_0_1px_rgba(255,255,255,0.10),inset_0_1px_0_rgba(255,255,255,0.14)]">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none"
              stroke="white" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
            </svg>
            <span className="absolute -right-1 -top-1 h-2.5 w-2.5 rounded-full bg-[#BB8927] ring-2 ring-[#091F14]" />
          </div>
          <div>
            <p className="text-[15px] font-bold leading-tight text-white" style={{ fontFamily: "var(--font-sora)" }}>
              SudVet Ops
            </p>
            <p className="text-[11px] text-[#5A9E7E]">Cattle Disease AI</p>
          </div>
        </div>

        {/* Middle: headline + viz ──────────────────────────────── */}
        <div className="relative z-10 max-w-[340px]">
          {/* Status pill */}
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#1F8A66]/30 bg-[#1F8A66]/15 px-3.5 py-1.5">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#4BC997]" />
            <span className="text-[10.5px] font-bold tracking-widest text-[#4BC997]">SYSTEM OPERATIONAL</span>
          </div>

          <h1 className="text-[36px] font-bold leading-[1.07] tracking-[-0.03em] text-white"
            style={{ fontFamily: "var(--font-sora)" }}>
            Disease caught early.<br />
            <span className="text-[#4BC997]">Animals saved.</span>
          </h1>
          <p className="mt-4 text-[13.5px] leading-[1.75] text-[#6BA88A]">
            The operations layer connecting field CHAWs to veterinary supervisors.
            Triage AI-flagged cases, track treatment, and monitor team performance.
          </p>

          {/* Disease breakdown bars */}
          <div className="mt-9">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-[10.5px] font-bold uppercase tracking-[0.13em] text-[#3D7A5C]">
                Case distribution · 30 days
              </p>
              <p className="text-[10.5px] text-[#3D7A5C]">n=847</p>
            </div>
            <div className="space-y-2.5">
              {DISEASES.map(({ key, pct, color }) => (
                <div key={key} className="flex items-center gap-3">
                  <span className="w-10 shrink-0 text-[12px] font-semibold text-white/60">{key}</span>
                  <div className="relative h-[5px] flex-1 overflow-hidden rounded-full bg-white/[0.07]">
                    <div
                      className="absolute inset-y-0 left-0 rounded-full"
                      style={{ width: `${pct}%`, backgroundColor: color, opacity: 0.85 }}
                    />
                  </div>
                  <span className="w-8 text-right text-[12px] font-semibold text-white/40">{pct}%</span>
                </div>
              ))}
            </div>
          </div>

          {/* Weekly trend sparkline */}
          <div className="mt-9">
            <p className="mb-2.5 text-[10.5px] font-bold uppercase tracking-[0.13em] text-[#3D7A5C]">
              Weekly submissions
            </p>
            <Sparkline />
            <div className="mt-1.5 flex justify-between">
              {["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "Now"].map((w) => (
                <span key={w} className="text-[9.5px] text-[#2E5E42]">{w}</span>
              ))}
            </div>
          </div>
        </div>

        {/* Bottom: stats row ───────────────────────────────────── */}
        <div className="relative z-10 grid grid-cols-3 gap-3">
          {STATS.map(({ value, label }) => (
            <div
              key={label}
              className="rounded-xl border border-white/[0.07] bg-white/[0.04] px-3 py-3.5 backdrop-blur-sm"
            >
              <p className="text-[21px] font-bold text-white" style={{ fontFamily: "var(--font-sora)" }}>
                {value}
              </p>
              <p className="mt-0.5 text-[11px] text-[#5A9E7E]">{label}</p>
            </div>
          ))}
        </div>
      </aside>

      {/* ════════════════════════════════════════════════════════════════════════
          RIGHT PANEL — sign-in form
      ════════════════════════════════════════════════════════════════════════ */}
      <main className="relative flex flex-1 flex-col items-center justify-center overflow-hidden bg-white px-6 py-12 sm:px-10">

        {/* Subtle ambient tint */}
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_100%_0%,rgba(31,138,102,0.06),transparent_48%),radial-gradient(ellipse_at_0%_100%,rgba(187,137,39,0.04),transparent_42%)]" />

        {/* Mobile-only brand strip */}
        <div className="relative mb-8 flex items-center gap-3 lg:hidden">
          <div className="grid h-9 w-9 place-items-center rounded-xl bg-[#1F8A66] shadow-[0_4px_14px_rgba(31,138,102,0.32)]">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
              stroke="white" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
            </svg>
          </div>
          <div>
            <p className="text-[16px] font-bold text-[#1D2A25]" style={{ fontFamily: "var(--font-sora)" }}>
              SudVet Ops
            </p>
            <p className="text-[11px] text-[#65756F]">Cattle Disease AI Dashboard</p>
          </div>
        </div>

        <div className="relative w-full max-w-[400px] sv-animate-up">

          {/* Eyebrow + heading */}
          <div className="mb-8">
            <p className="sv-eyebrow mb-2 text-[#BB8927]">Operator sign-in</p>
            <h2
              className="text-[34px] font-bold leading-[1.06] tracking-[-0.03em] text-[#1D2A25]"
              style={{ fontFamily: "var(--font-sora)" }}
            >
              Welcome back
            </h2>
            <p className="mt-2 text-[13.5px] leading-[1.65] text-[#65756F]">
              Dashboard access is restricted to vets and supervisors. Field workers use the mobile app.
            </p>
          </div>

          {/* Form */}
          <form onSubmit={form.handleSubmit(onSubmit)} noValidate className="space-y-5">

            {/* Email */}
            <div className="space-y-1.5">
              <Label htmlFor="email" className="text-[13px] font-semibold text-[#1D2A25]">
                Email address
              </Label>
              <Input
                id="email"
                type="email"
                placeholder="vet@cattle.ai"
                autoComplete="email"
                className="h-12 rounded-xl border-[#D8E7DF] bg-[#F6FCF9] text-[14px] placeholder:text-[#A8C0B5] focus:border-[#1F8A66] focus:bg-white"
                disabled={submitting}
                {...form.register("email")}
              />
              {form.formState.errors.email && (
                <p className="flex items-center gap-1.5 text-[11.5px] text-[#8F4434]">
                  <span className="h-1 w-1 shrink-0 rounded-full bg-[#8F4434]" />
                  {form.formState.errors.email.message}
                </p>
              )}
            </div>

            {/* Password + toggle */}
            <div className="space-y-1.5">
              <Label htmlFor="password" className="text-[13px] font-semibold text-[#1D2A25]">
                Password
              </Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPw ? "text" : "password"}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  className="h-12 rounded-xl border-[#D8E7DF] bg-[#F6FCF9] pr-11 text-[14px] placeholder:text-[#A8C0B5] focus:border-[#1F8A66] focus:bg-white"
                  disabled={submitting}
                  {...form.register("password")}
                />
                <button
                  type="button"
                  onClick={() => setShowPw((v) => !v)}
                  tabIndex={-1}
                  aria-label={showPw ? "Hide password" : "Show password"}
                  className="absolute right-3.5 top-1/2 -translate-y-1/2 text-[#8DBFA8] transition-colors hover:text-[#1F8A66]"
                >
                  {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                </button>
              </div>
              {form.formState.errors.password && (
                <p className="flex items-center gap-1.5 text-[11.5px] text-[#8F4434]">
                  <span className="h-1 w-1 shrink-0 rounded-full bg-[#8F4434]" />
                  {form.formState.errors.password.message}
                </p>
              )}
            </div>

            {/* Error banner */}
            {error && (
              <div className="flex items-start gap-3 rounded-xl border border-[#EDC0B4] bg-[#FDE9E4] px-4 py-3 text-[12.5px] text-[#8F4434] sv-animate-scale">
                <AlertCircle size={14} className="mt-0.5 shrink-0" />
                <span>{error}</span>
              </div>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={submitting}
              className="
                flex h-12 w-full items-center justify-center gap-2 rounded-xl
                bg-[#1F8A66] text-[14px] font-semibold text-white
                shadow-[0_4px_18px_rgba(31,138,102,0.28)]
                transition-all duration-150
                hover:bg-[#197A5A] hover:shadow-[0_6px_24px_rgba(31,138,102,0.38)]
                active:scale-[0.985]
                disabled:cursor-not-allowed disabled:opacity-60
              "
            >
              {submitting ? (
                <>
                  <Loader2 size={15} className="animate-spin" />
                  Signing in…
                </>
              ) : (
                <>
                  Sign in to Dashboard
                  <ArrowRight size={14} />
                </>
              )}
            </button>
          </form>

          {/* Footer */}
          <div className="mt-8 space-y-4">
            <div className="flex items-center gap-3">
              <div className="h-px flex-1 bg-[#E6EEE9]" />
              <span className="text-[11px] font-medium text-[#9DB8A8]">Ops portal only</span>
              <div className="h-px flex-1 bg-[#E6EEE9]" />
            </div>
            <p className="text-center text-[11.5px] text-[#9DB8A8]">
              API must be running to sign in.{" "}
              <Link href="/overview" className="font-semibold text-[#1F8A66] hover:underline">
                Continue existing session →
              </Link>
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}
