"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  Activity,
  BarChart3,
  ClipboardList,
  FolderKanban,
  LayoutDashboard,
  LogOut,
  PawPrint,
  Settings2,
  ShieldCheck,
  Users,
} from "lucide-react";

import { RoleBadge } from "@/components/ui/domain-badges";
import { canAccessDashboardPath, clearAuthState, getAuthState } from "@/lib/auth";
import { cn } from "@/lib/utils";

const navItems = [
  { href: "/overview",  label: "Overview",     icon: LayoutDashboard },
  { href: "/triage",    label: "Triage Queue", icon: ClipboardList   },
  { href: "/cases",     label: "Cases",         icon: FolderKanban    },
  { href: "/animals",   label: "Animals",       icon: PawPrint        },
  { href: "/users",     label: "Users",         icon: Users           },
  { href: "/analytics", label: "Analytics",    icon: BarChart3       },
  { href: "/system",    label: "System",        icon: Activity        },
  { href: "/settings",  label: "Settings",      icon: Settings2       },
];

function getAvatarProps(email: string) {
  const name = email.split("@")[0] ?? "U";
  const initials = name.length >= 2
    ? (name[0] + name[name.length - 1]).toUpperCase()
    : name[0].toUpperCase();
  const hue = Array.from(email).reduce((acc, c) => acc + c.charCodeAt(0), 0) % 360;
  return { initials, hue };
}

export function DashboardShell({ children }: { children: React.ReactNode }) {
  const pathname   = usePathname();
  const router     = useRouter();
  const auth       = getAuthState();
  const visibleNav = navItems.filter((item) =>
    auth?.user.role ? canAccessDashboardPath(auth.user.role, item.href) : true
  );
  const avatarProps = auth?.user.email ? getAvatarProps(auth.user.email) : null;

  return (
    <div className="grid min-h-screen grid-cols-1 md:grid-cols-[260px_1fr]">

      {/* ── Sidebar ──────────────────────────────────────────────────────── */}
      <aside className="flex flex-col border-b border-[#D8E7DF] bg-white md:sticky md:top-0 md:h-screen md:overflow-y-auto md:border-b-0 md:border-r">

        {/* Dark brand header */}
        <div className="relative overflow-hidden bg-[#0B3524] px-4 py-5">
          {/* Dot texture */}
          <div className="pointer-events-none absolute inset-0 [background-image:radial-gradient(rgba(255,255,255,0.055)_1px,transparent_1px)] [background-size:18px_18px]" />
          <div className="pointer-events-none absolute right-0 top-0 h-24 w-24 -translate-y-8 translate-x-8 rounded-full bg-[#1F8A66] opacity-20 blur-2xl" />

          <div className="relative flex items-center gap-3">
            <div className="relative grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-[#1F8A66] shadow-[0_0_0_1px_rgba(255,255,255,0.12),inset_0_1px_0_rgba(255,255,255,0.15)]">
              <ShieldCheck size={16} strokeWidth={2.3} className="text-white" />
              <span className="absolute -right-1 -top-1 h-2.5 w-2.5 rounded-full bg-[#BB8927] ring-2 ring-[#0B3524]" />
            </div>
            <div className="min-w-0">
              <p className="text-[14.5px] font-bold leading-tight text-white" style={{ fontFamily: "var(--font-sora)" }}>
                SudVet Operations
              </p>
              <p className="text-[11px] text-[#5A9E7E]">Cattle Disease AI</p>
            </div>
          </div>

          {/* Role context strip */}
          {auth?.user && (
            <div className="relative mt-3 flex items-center gap-2 rounded-lg border border-[#1F5E3A] bg-[#0F2E1C] px-2.5 py-1.5">
              <span className="h-1.5 w-1.5 rounded-full bg-[#4BC997]" />
              <span className="truncate text-[11px] font-medium text-[#6BA88A]">{auth.user.email}</span>
            </div>
          )}
        </div>

        {/* Nav */}
        <nav className="flex-1 overflow-y-auto p-2 pt-2.5">
          <p className="mb-1.5 px-3 text-[10px] font-bold uppercase tracking-[0.12em] text-[#9BB8A8]">Navigation</p>
          <div className="space-y-0.5">
            {visibleNav.map((item) => {
              const active = pathname === item.href || pathname.startsWith(item.href + "/");
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "group relative flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-[13px] font-semibold transition-all duration-150",
                    active
                      ? "bg-[#E8F5EE] text-[#155C45]"
                      : "text-[#65756F] hover:bg-[#F2FBF7] hover:text-[#1D2A25]"
                  )}
                >
                  {active && (
                    <span className="absolute left-0 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full bg-[#1F8A66]" />
                  )}
                  <item.icon
                    size={15}
                    strokeWidth={active ? 2.5 : 2}
                    className={cn(
                      "shrink-0 transition-transform duration-150",
                      active
                        ? "text-[#1F8A66]"
                        : "text-[#9BB8A8] group-hover:scale-110 group-hover:text-[#1F8A66]"
                    )}
                  />
                  {item.label}
                  {active && (
                    <span className="ml-auto h-1.5 w-1.5 rounded-full bg-[#1F8A66]" />
                  )}
                </Link>
              );
            })}
          </div>
        </nav>

        {/* User / sign-out */}
        <div className="border-t border-[#E6EEE9] p-3 space-y-2">
          {auth?.user && (
            <div className="flex items-center gap-2.5 rounded-xl border border-[#E6EEE9] bg-[#F6FCF9] px-3 py-2.5">
              {avatarProps && (
                <div
                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white shadow-sm"
                  style={{ background: `hsl(${avatarProps.hue}, 42%, 42%)` }}
                >
                  {avatarProps.initials}
                </div>
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate text-[11.5px] font-semibold text-[#1D2A25]">{auth.user.name || auth.user.email}</p>
                <div className="mt-0.5">
                  <RoleBadge value={auth.user.role || "CAHW"} />
                </div>
              </div>
            </div>
          )}

          <button
            onClick={() => { clearAuthState(); router.push("/login"); }}
            className="flex w-full items-center gap-2 rounded-xl border border-[#E6EEE9] bg-white px-3 py-2 text-[12.5px] font-semibold text-[#65756F] transition-all hover:border-[#C4D9D0] hover:bg-[#F5FBF8] hover:text-[#1D2A25]"
          >
            <LogOut size={13} strokeWidth={2} />
            Sign out
          </button>
        </div>
      </aside>

      {/* ── Main content ─────────────────────────────────────────────────── */}
      <main className="sv-subtle-grid min-w-0 p-4 md:p-6 lg:p-8">
        <div className="mx-auto w-full max-w-[1400px]">{children}</div>
      </main>
    </div>
  );
}
