/**
 * case-policy.ts — client-side mirror of the backend CasePolicy class.
 *
 * Single source of truth for UI visibility/interaction decisions.
 * All checks use only data already present in CaseItem — no extra API calls.
 */
import type { CaseItem, UserItem } from "@/lib/types";

export type CaseUIPolicy = {
  /** Case has no assigned vet (assigned_to_user_id is null) */
  isUnassigned: boolean;
  /** Current VET user can claim this case (unassigned + escalated or requested for them) */
  isClaimable: boolean;
  /** Current user is the assigned vet for this case */
  isOwnedByMe: boolean;
  /** Current VET was explicitly requested by the CAHW (and case is still unassigned) */
  isRequestedForMe: boolean;
  /** Current user can edit clinical fields (status, notes, corrected_label, etc.) */
  canEditClinical: boolean;
  /** Current user can dispatch/assign via /assign endpoint */
  canAssign: boolean;
  /** Show the PATCH workflow form (status, triage_status, notes, followup) */
  canPatchWorkflow: boolean;
};

export function deriveCaseUI(
  caseItem: CaseItem,
  user: Pick<UserItem, "id" | "role">
): CaseUIPolicy {
  const isAdmin = user.role === "ADMIN";
  const isVet = user.role === "VET";
  const isCahw = user.role === "CAHW";

  const isUnassigned = !caseItem.assigned_to_user_id;
  const isOwnedByMe = !isUnassigned && caseItem.assigned_to_user_id === user.id;

  const isRequestedForMe =
    isVet && isUnassigned && caseItem.requested_vet_id === user.id;

  const isClaimable =
    isVet &&
    isUnassigned &&
    (caseItem.triage_status === "escalated" || isRequestedForMe);

  // VET can edit clinical fields only on their own assigned case
  const canEditClinical = isAdmin || (isVet && isOwnedByMe);

  // ADMIN can always dispatch; VET / CAHW cannot
  const canAssign = isAdmin;

  // Show PATCH form: ADMIN always; VET only if they own the case
  const canPatchWorkflow = canEditClinical;

  return {
    isUnassigned,
    isClaimable,
    isOwnedByMe,
    isRequestedForMe,
    canEditClinical,
    canAssign,
    canPatchWorkflow,
  };
}
