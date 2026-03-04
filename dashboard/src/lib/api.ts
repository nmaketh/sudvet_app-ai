import { getAccessToken, getAuthState, setAccessToken, setAuthState } from "@/lib/auth";
import type { DashboardSettings, ErrorLogItem, ModelVersionItem, SystemHealth, UserItem } from "@/lib/types";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002";
const REQUEST_TIMEOUT_MS = 15000;

type LoginLikeResponse = {
  access_token?: string;
  refresh_token?: string;
  token?: string;
  refreshToken?: string;
  user?: any;
};

function normalizeTokens(data: LoginLikeResponse) {
  const accessToken = data.access_token ?? data.token ?? "";
  const refreshToken = data.refresh_token ?? data.refreshToken ?? "";
  return { accessToken, refreshToken, user: data.user };
}

async function refreshAccessToken(refreshToken: string) {
  const candidates: Array<Record<string, string>> = [
    { refresh_token: refreshToken },
    { refreshToken },
  ];

  for (const payload of candidates) {
    const res = await fetch(`${API_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      cache: "no-store",
    });

    if (!res.ok) {
      continue;
    }

    const data = (await res.json()) as LoginLikeResponse;
    const normalized = normalizeTokens(data);
    if (normalized.accessToken) {
      return normalized;
    }
  }

  return null;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const auth = getAuthState();
  let accessToken = getAccessToken();

  if (!accessToken && auth?.refreshToken) {
    const refreshed = await refreshAccessToken(auth.refreshToken);
    if (refreshed?.accessToken) {
      setAccessToken(refreshed.accessToken);
      setAuthState({ refreshToken: refreshed.refreshToken || auth.refreshToken, user: refreshed.user || auth.user });
      accessToken = refreshed.accessToken;
    }
  }

  const headers = new Headers(init?.headers);
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (accessToken) {
    headers.set("Authorization", `Bearer ${accessToken}`);
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...init,
      headers,
      cache: "no-store",
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`Request timed out after ${REQUEST_TIMEOUT_MS / 1000}s`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
  if (!res.ok) {
    const text = await res.text();
    let message = text || `Request failed: ${res.status}`;
    try {
      const parsed = JSON.parse(text || "{}");
      message = parsed.detail || parsed.message || message;
    } catch {
      // keep raw text fallback
    }
    throw new Error(message);
  }
  return (await res.json()) as T;
}

export const api = {
  login: (payload: { email: string; password: string }) =>
    request<LoginLikeResponse>("/auth/login", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  refresh: refreshAccessToken,
  me: () => request<any>("/auth/me"),

  listCases: async (params = "") => {
    const payload = await request<any>(`/cases${params ? `?${params}` : ""}`);
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  },
  getCase: (id: string) => request<any>(`/cases/${id}`),
  patchCase: (id: string, payload: Record<string, unknown>) =>
    request<any>(`/cases/${id}`, { method: "PATCH", body: JSON.stringify(payload) }),
  assignCase: (id: string, assigned_to_user_id: number) =>
    request<any>(`/cases/${id}/assign`, {
      method: "POST",
      body: JSON.stringify({ assigned_to_user_id }),
    }),
  claimCase: (id: string, note?: string) =>
    request<any>(`/cases/${id}/claim`, {
      method: "POST",
      body: JSON.stringify({ note: note ?? null }),
    }),
  rejectCase: (id: string, reason: string) =>
    request<any>(`/cases/${id}/reject`, {
      method: "POST",
      body: JSON.stringify({ reason }),
    }),
  addFeedback: (id: string, payload: Record<string, unknown>) =>
    request<any>(`/cases/${id}/feedback`, { method: "POST", body: JSON.stringify(payload) }),
  timeline: (id: string) => request<any>(`/cases/${id}/timeline`),
  sendMessage: (id: string, message: string) =>
    request<any>(`/cases/${id}/messages`, {
      method: "POST",
      body: JSON.stringify({ message, senderRole: "vet" }),
    }),

  listAnimals: async (q = "") => {
    const payload = await request<any>(`/animals${q ? `?q=${encodeURIComponent(q)}` : ""}`);
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  },
  getAnimal: (id: string) => request<any>(`/animals/${id}`),
  animalCases: async (id: string) => {
    const payload = await request<any>(`/animals/${id}/cases`);
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  },

  listUsers: async (role = "") => {
    const payload = await request<any>(`/users${role ? `?role=${role}` : ""}`);
    if (Array.isArray(payload)) return payload as UserItem[];
    if (payload && Array.isArray(payload.items)) return payload.items as UserItem[];
    return [] as UserItem[];
  },
  listAssignableUsers: async (role = "") => {
    const payload = await request<any>(`/users/assignable${role ? `?role=${role}` : ""}`);
    if (Array.isArray(payload)) return payload as UserItem[];
    if (payload && Array.isArray(payload.items)) return payload.items as UserItem[];
    return [] as UserItem[];
  },
  patchUserRole: (id: number, role: string) =>
    request<any>(`/users/${id}/role`, { method: "PATCH", body: JSON.stringify({ role }) }),
  userStats: (id: number) => request<any>(`/users/${id}/stats`),

  analyticsSummary: (params = "") => request<any>(`/analytics/summary${params ? `?${params}` : ""}`),
  getSettings: () => request<DashboardSettings>("/settings"),
  patchSettings: (payload: { vet_can_view_all: boolean }) =>
    request<DashboardSettings>("/settings", { method: "PATCH", body: JSON.stringify(payload) }),

  health: () => request<SystemHealth>("/health"),
  models: () => request<ModelVersionItem[]>("/models"),
  errors: () => request<ErrorLogItem[]>("/system/errors"),
};

