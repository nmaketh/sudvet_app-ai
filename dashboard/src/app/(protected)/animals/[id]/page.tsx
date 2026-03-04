"use client";

import { useParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";

import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { CaseStatusBadge, RiskBadge } from "@/components/ui/domain-badges";
import { Table, TableBody, TableHead, TableRow, Td, Th } from "@/components/ui/table";
import { api } from "@/lib/api";
import type { AnimalItem, CaseItem } from "@/lib/types";

export default function AnimalDetailPage() {
  const params = useParams<{ id: string }>();
  const animalId = params.id;

  const animalQuery = useQuery<AnimalItem>({ queryKey: ["animal", animalId], queryFn: () => api.getAnimal(animalId) });
  const casesQuery = useQuery<CaseItem[]>({ queryKey: ["animal-cases", animalId], queryFn: () => api.animalCases(animalId) });

  return (
    <div className="space-y-4">
      <PageHeader
        eyebrow="Animal Profile"
        title={animalQuery.data ? `Animal ${animalQuery.data.tag}` : "Animal Detail"}
        description="Profile, location context, and timeline of related cases for this animal."
      />

      {animalQuery.data && (
        <Card className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">Tag</p>
            <p className="mt-1 font-semibold">{animalQuery.data.tag}</p>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">Name</p>
            <p className="mt-1 font-semibold">{animalQuery.data.name || "-"}</p>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">Location</p>
            <p className="mt-1 font-semibold">{animalQuery.data.location}</p>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">Created</p>
            <p className="mt-1 font-semibold">{new Date(animalQuery.data.created_at).toLocaleString()}</p>
          </div>
        </Card>
      )}

      <Card>
        <h2 className="mb-3 font-semibold">Case Timeline</h2>
        <Table>
          <TableHead>
            <TableRow>
              <Th>Created</Th>
              <Th>Prediction</Th>
              <Th>Risk</Th>
              <Th>Status</Th>
            </TableRow>
          </TableHead>
          <TableBody>
            {(casesQuery.data || []).map((item) => (
              <TableRow key={item.id} className="hover:bg-[#F5FBF8]">
                <Td>{new Date(item.created_at).toLocaleString()}</Td>
                <Td>{String(item.prediction_json?.label || "unknown")}</Td>
                <Td><RiskBadge value={item.risk_level} /></Td>
                <Td><CaseStatusBadge value={item.status} /></Td>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
