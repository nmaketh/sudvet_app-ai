"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Users } from "lucide-react";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { RoleBadge } from "@/components/ui/domain-badges";
import { Select } from "@/components/ui/select";
import { Table, TableBody, TableHead, TableRow, Td, Th } from "@/components/ui/table";
import { api } from "@/lib/api";
import { getAuthState } from "@/lib/auth";
import type { UserItem } from "@/lib/types";

type UserWithStats = UserItem & {
  stats: { cases_submitted: number; cases_handled: number; avg_resolution_time_hours: number };
};

/** Deterministic avatar hue from email */
function avatarHue(email: string) {
  return Array.from(email).reduce((acc, c) => acc + c.charCodeAt(0), 0) % 360;
}
function initials(name: string) {
  const parts = name.trim().split(/\s+/);
  return parts.length >= 2
    ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
    : name.slice(0, 2).toUpperCase();
}

export default function UsersPage() {
  const auth         = getAuthState();
  const queryClient  = useQueryClient();
  const [roleFilter, setRoleFilter] = useState("");
  const canManageRoles = auth?.user.role === "ADMIN";
  const canAccessUsers = auth?.user.role === "ADMIN";

  const usersQuery = useQuery<UserWithStats[]>({
    queryKey: ["users", roleFilter],
    enabled: canAccessUsers,
    queryFn: async () => {
      const users = await api.listUsers(roleFilter);
      const stats = await Promise.all(
        users.map(async (user: UserItem) => ({ userId: user.id, stats: await api.userStats(user.id) }))
      );
      const map = new Map(stats.map((item) => [item.userId, item.stats]));
      return users.map((user: UserItem) => ({ ...user, stats: map.get(user.id) }));
    },
  });

  const patchRoleMutation = useMutation({
    mutationFn: ({ id, role }: { id: number; role: string }) => api.patchUserRole(id, role),
    onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["users"] }); },
  });

  const rows     = useMemo(() => usersQuery.data || [], [usersQuery.data]);
  const maxCases = useMemo(() => Math.max(...rows.map((r) => r.stats?.cases_handled ?? 0), 1), [rows]);

  if (!canAccessUsers) {
    return (
      <div className="flex items-center gap-3 rounded-xl border border-[#EDC0B4] bg-[#FDE9E4] px-4 py-3 text-[13px] text-[#8F4434]">
        Unauthorized — only ADMIN can access user administration.
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="People and Permissions"
          title="User Administration"
          description="Manage workforce accounts, review workload stats, and control role assignments."
        />
        <span className="flex shrink-0 items-center gap-1.5 self-start rounded-full border border-[#E6EEE9] bg-white px-3 py-1.5 text-[12px] font-semibold text-[#1D2A25]">
          <Users size={12} className="text-[#1F8A66]" />
          {rows.length} user{rows.length === 1 ? "" : "s"}
        </span>
      </div>

      <Card>
        <div className="max-w-xs">
          <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.09em] text-[#65756F]">
            Filter by role
          </label>
          <Select value={roleFilter} onChange={(e) => setRoleFilter(e.target.value)}>
            <option value="">All roles</option>
            <option value="CAHW">CAHW</option>
            <option value="VET">VET</option>
            <option value="ADMIN">ADMIN</option>
          </Select>
        </div>
      </Card>

      <Card className="overflow-hidden p-0">
        <Table>
          <TableHead>
            <TableRow>
              <Th>User</Th>
              <Th>Role</Th>
              <Th>Location</Th>
              <Th>Submitted</Th>
              <Th>Handled</Th>
              <Th>Workload</Th>
              <Th>Avg Res. (h)</Th>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((user) => {
              const hue  = avatarHue(user.email);
              const ini  = initials(user.name || user.email);
              const pct  = Math.round(((user.stats?.cases_handled ?? 0) / maxCases) * 100);
              return (
                <TableRow key={user.id}>
                  <Td>
                    <div className="flex items-center gap-2.5 min-w-[180px]">
                      <div
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white shadow-sm"
                        style={{ background: `hsl(${hue}, 42%, 42%)` }}
                      >
                        {ini}
                      </div>
                      <div className="min-w-0">
                        <p className="truncate text-[12.5px] font-semibold text-[#1D2A25]">{user.name || "—"}</p>
                        <p className="truncate text-[11px] text-[#65756F]">{user.email}</p>
                      </div>
                    </div>
                  </Td>
                  <Td>
                    {canManageRoles ? (
                      <div className="w-[130px]">
                        <Select
                          value={user.role}
                          onChange={(e) => patchRoleMutation.mutate({ id: user.id, role: e.target.value })}
                        >
                          <option value="CAHW">CAHW</option>
                          <option value="VET">VET</option>
                          <option value="ADMIN">ADMIN</option>
                        </Select>
                      </div>
                    ) : (
                      <RoleBadge value={user.role} />
                    )}
                  </Td>
                  <Td className="text-[12px] text-[#65756F]">{user.location || "—"}</Td>
                  <Td>
                    <span className="text-[12px] font-semibold text-[#1D2A25]">
                      {user.stats?.cases_submitted ?? 0}
                    </span>
                  </Td>
                  <Td>
                    <span className="text-[12px] font-semibold text-[#1D2A25]">
                      {user.stats?.cases_handled ?? 0}
                    </span>
                  </Td>
                  <Td>
                    <div className="min-w-[80px]">
                      <div className="h-1.5 overflow-hidden rounded-full bg-[#E7F1ED]">
                        <div
                          className="h-full rounded-full bg-[#1F8A66] transition-all"
                          style={{ width: `${Math.max(2, pct)}%` }}
                        />
                      </div>
                    </div>
                  </Td>
                  <Td>
                    <span className="text-[12px] font-semibold text-[#1D2A25]">
                      {user.stats?.avg_resolution_time_hours ?? 0}
                    </span>
                  </Td>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
