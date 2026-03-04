export type AppRole = "CAHW" | "VET" | "ADMIN";

export type AuthUser = {
  id: number;
  name: string;
  email: string;
  role: AppRole;
  location?: string | null;
};

type AuthState = {
  refreshToken: string;
  user: AuthUser;
};

const AUTH_KEY = "cattle-dashboard-auth";
let accessTokenMemory: string | null = null;

const dashboardRouteRestrictions: Partial<Record<AppRole, string[]>> = {
  CAHW: ["/users", "/system"],
  VET: ["/users", "/system"],
};

export function getAuthState(): AuthState | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(AUTH_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AuthState;
  } catch {
    return null;
  }
}

export async function setAuthState(state: AuthState): Promise<void> {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(AUTH_KEY, JSON.stringify(state));
  // Persist refresh token in httpOnly cookie so middleware can verify session
  await fetch("/api/auth/session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: state.refreshToken }),
  }).catch(() => {/* non-blocking — middleware fallback is client-side layout guard */});
}

export function setAccessToken(token: string | null) {
  accessTokenMemory = token;
}

export function getAccessToken() {
  return accessTokenMemory;
}

export function clearAuthState() {
  if (typeof window === "undefined") return;
  accessTokenMemory = null;
  window.localStorage.removeItem(AUTH_KEY);
  // Clear the httpOnly session cookie (fire-and-forget — page redirects anyway)
  fetch("/api/auth/session", { method: "DELETE" }).catch(() => {});
}

export function canAccessDashboardPath(role: AppRole, pathname: string) {
  const restrictedPrefixes = dashboardRouteRestrictions[role] ?? [];
  return !restrictedPrefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  );
}

export function isVetOrAdmin(role: AppRole | undefined | null) {
  return role === "VET" || role === "ADMIN";
}

export function isAdmin(role: AppRole | undefined | null) {
  return role === "ADMIN";
}
