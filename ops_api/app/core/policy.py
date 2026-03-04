"""
CasePolicy — single source of truth for case access-control decisions.

Rules:
  ADMIN  — view all; assign via /assign; PATCH workflow (no corrected_label)
  VET    — view own assigned cases + claimable cases; PATCH own cases (incl. corrected_label)
  CAHW   — view own submissions only; read-only

A case is "assigned" IFF assigned_to_user_id IS NOT NULL.
"assigned" is NOT a triage_status value.
"""
from app.models.models import Case, TriageStatus, User, UserRole


class CasePolicy:
    def __init__(self, case: Case, user: User) -> None:
        self._c = case
        self._u = user

    # ── Visibility ─────────────────────────────────────────────────────────────

    def can_view(self) -> bool:
        role = self._u.role
        if role == UserRole.ADMIN:
            return True
        if role == UserRole.CAHW:
            return self._c.submitted_by_user_id == self._u.id
        if role == UserRole.VET:
            return (
                self._c.assigned_to_user_id == self._u.id
                or self._is_claimable()
            )
        return False

    # ── Ownership helpers ───────────────────────────────────────────────────────

    def is_unassigned(self) -> bool:
        return self._c.assigned_to_user_id is None

    def is_owned_by_me(self) -> bool:
        return self._c.assigned_to_user_id == self._u.id

    def is_requested_for_me(self) -> bool:
        return (
            self._c.requested_vet_id == self._u.id
            and self._c.assigned_to_user_id is None
        )

    def _is_claimable(self) -> bool:
        """Claimable = unassigned AND (escalated or explicitly requested for this vet)."""
        if self._c.assigned_to_user_id is not None:
            return False
        return (
            self._c.triage_status == TriageStatus.escalated
            or self._c.requested_vet_id == self._u.id
        )

    # ── Action permissions ──────────────────────────────────────────────────────

    def can_claim(self) -> bool:
        """VET can claim an unassigned claimable case."""
        return self._u.role == UserRole.VET and self._is_claimable()

    def can_assign(self) -> bool:
        """Only ADMIN can formally dispatch/assign a case to a vet."""
        return self._u.role == UserRole.ADMIN

    def can_patch(self) -> bool:
        """Can the user PATCH workflow fields on this case?"""
        if self._u.role == UserRole.ADMIN:
            return True
        if self._u.role == UserRole.VET:
            return self.is_owned_by_me()
        return False

    def patch_allowed_fields(self) -> set[str]:
        """Return the set of field names the user is allowed to PATCH."""
        if self._u.role == UserRole.ADMIN:
            # Admin manages workflow but cannot set corrected_label (clinical evidence)
            return {"status", "triage_status", "notes", "followup_date"}
        if self._u.role == UserRole.VET and self.is_owned_by_me():
            # Assigned vet has full clinical write access
            return {"status", "triage_status", "notes", "followup_date", "corrected_label"}
        return set()
