"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { DashboardShell } from "@/components/layout/dashboard-shell";
import { canAccessDashboardPath, clearAuthState, getAuthState } from "@/lib/auth";

export default function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setReady(false);
    const auth = getAuthState();
    if (!auth?.refreshToken || !auth.user) {
      clearAuthState();
      router.replace("/login");
      return;
    }
    if (!canAccessDashboardPath(auth.user.role, pathname)) {
      router.replace("/overview");
      return;
    }
    setReady(true);
  }, [pathname, router]);

  if (!ready) {
    return <div className="p-8 text-sm text-slate-500">Checking session...</div>;
  }

  return <DashboardShell>{children}</DashboardShell>;
}
