"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { Search } from "lucide-react";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";
import type { AnimalItem } from "@/lib/types";

export default function AnimalsPage() {
  const [q, setQ] = useState("");
  const router = useRouter();
  const animalsQuery = useQuery<AnimalItem[]>({
    queryKey: ["animals", q],
    queryFn: () => api.listAnimals(q),
  });

  const columns = useMemo<ColumnDef<AnimalItem>[]>(
    () => [
      { header: "Tag", accessorKey: "tag" },
      { header: "Name", cell: ({ row }) => row.original.name || "-" },
      { header: "Location", accessorKey: "location" },
      { header: "Created", cell: ({ row }) => new Date(row.original.created_at).toLocaleDateString() },
    ],
    []
  );

  return (
    <div className="space-y-4">
      <PageHeader
        eyebrow="Livestock Records"
        title="Animals"
        description="Search by tag, name, or location to view individual animal history and related case timelines."
      />
      <Card>
        <label className="mb-1 block text-xs font-medium uppercase tracking-[0.08em] text-muted">Search Animals</label>
        <div className="relative">
          <Search size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
          <Input
            className="pl-9"
            placeholder="Tag, name, or location"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
        </div>
      </Card>
      <DataTable columns={columns} data={animalsQuery.data || []} onRowClick={(row) => router.push(`/animals/${row.id}`)} />
    </div>
  );
}
