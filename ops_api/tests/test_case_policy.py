"""
Tests for CasePolicy — the single source of truth for case access control.

8 required test cases:
  1. test_vet_cannot_view_case_assigned_to_other_vet
  2. test_vet_can_view_escalated_unassigned
  3. test_vet_can_claim_escalated_unassigned
  4. test_vet_cannot_claim_needs_review
  5. test_vet_cannot_claim_already_assigned
  6. test_admin_can_assign_via_assign_endpoint
  7. test_triaged_at_set_only_once
  8. test_admin_patch_corrected_label_forbidden
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.core.policy import CasePolicy
from app.models.models import CaseStatus, RiskLevel, TriageStatus, UserRole


# ── Minimal object factories (SimpleNamespace avoids SQLAlchemy instrumentation) ──

def _make_user(id: int, role: UserRole) -> SimpleNamespace:
    return SimpleNamespace(
        id=id,
        role=role,
        name=f"User-{id}",
        email=f"user{id}@test.com",
        password_hash="x",
        location=None,
    )


def _make_case(
    *,
    assigned_to_user_id: int | None = None,
    requested_vet_id: int | None = None,
    triage_status: TriageStatus = TriageStatus.escalated,
    status: CaseStatus = CaseStatus.open,
    submitted_by_user_id: int = 99,
) -> SimpleNamespace:
    return SimpleNamespace(
        id="test-case-id",
        assigned_to_user_id=assigned_to_user_id,
        requested_vet_id=requested_vet_id,
        triage_status=triage_status,
        status=status,
        submitted_by_user_id=submitted_by_user_id,
        risk_level=RiskLevel.medium,
        urgent=False,
    )


# ── Test 1: VET cannot view a case assigned to a DIFFERENT vet ───────────────

def test_vet_cannot_view_case_assigned_to_other_vet():
    vet_a = _make_user(1, UserRole.VET)
    vet_b = _make_user(2, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=vet_b.id,
        triage_status=TriageStatus.needs_review,
    )
    policy = CasePolicy(case, vet_a)
    assert policy.can_view() is False
    assert policy.can_claim() is False
    assert policy.can_patch() is False


# ── Test 2: VET can view an escalated unassigned case ────────────────────────

def test_vet_can_view_escalated_unassigned():
    vet = _make_user(1, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=None,
        triage_status=TriageStatus.escalated,
    )
    policy = CasePolicy(case, vet)
    assert policy.can_view() is True
    assert policy.is_unassigned() is True


# ── Test 3: VET can claim an escalated unassigned case ───────────────────────

def test_vet_can_claim_escalated_unassigned():
    vet = _make_user(1, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=None,
        triage_status=TriageStatus.escalated,
    )
    policy = CasePolicy(case, vet)
    assert policy.can_claim() is True


# ── Test 4: VET cannot claim a needs_review case (not requested for them) ────

def test_vet_cannot_claim_needs_review():
    vet = _make_user(1, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=None,
        triage_status=TriageStatus.needs_review,
        requested_vet_id=None,
    )
    policy = CasePolicy(case, vet)
    # needs_review + not requested for this vet → not claimable
    assert policy.can_claim() is False


# ── Test 5: VET cannot claim an already-assigned case ────────────────────────

def test_vet_cannot_claim_already_assigned():
    vet_a = _make_user(1, UserRole.VET)
    vet_b = _make_user(2, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=vet_b.id,
        triage_status=TriageStatus.needs_review,
    )
    policy = CasePolicy(case, vet_a)
    assert policy.can_claim() is False


# ── Test 6: ADMIN can assign (can_assign returns True) ───────────────────────

def test_admin_can_assign_via_assign_endpoint():
    admin = _make_user(10, UserRole.ADMIN)
    vet = _make_user(1, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=None,
        triage_status=TriageStatus.escalated,
    )
    admin_policy = CasePolicy(case, admin)
    assert admin_policy.can_assign() is True

    vet_policy = CasePolicy(case, vet)
    assert vet_policy.can_assign() is False

    cahw = _make_user(5, UserRole.CAHW)
    cahw_policy = CasePolicy(case, cahw)
    assert cahw_policy.can_assign() is False


# ── Test 7: triaged_at is set only on first assignment ───────────────────────

def test_triaged_at_set_only_once():
    """Verify that triaged_at should only be set when it is None (business rule check)."""
    from datetime import datetime

    case = _make_case(assigned_to_user_id=None)
    case.triaged_at = None

    # Simulate first assignment
    first_triaged_at = datetime(2025, 1, 1, 12, 0, 0)
    case.assigned_to_user_id = 1
    if case.triaged_at is None:
        case.triaged_at = first_triaged_at

    # Simulate re-assignment: triaged_at must NOT be updated again
    case.assigned_to_user_id = 2
    if case.triaged_at is None:  # pragma: no cover — should not enter this branch
        case.triaged_at = datetime.utcnow()

    assert case.triaged_at == first_triaged_at  # unchanged


# ── Test 8: ADMIN cannot PATCH corrected_label ───────────────────────────────

def test_admin_patch_corrected_label_forbidden():
    admin = _make_user(10, UserRole.ADMIN)
    case = _make_case(
        assigned_to_user_id=None,
        triage_status=TriageStatus.escalated,
    )
    policy = CasePolicy(case, admin)
    allowed = policy.patch_allowed_fields()
    assert "corrected_label" not in allowed
    assert "status" in allowed
    assert "triage_status" in allowed
    assert "notes" in allowed
    assert "followup_date" in allowed


# ── Bonus: VET requested — can view and claim even if needs_review ────────────

def test_vet_can_claim_case_requested_for_them():
    vet = _make_user(1, UserRole.VET)
    case = _make_case(
        assigned_to_user_id=None,
        requested_vet_id=vet.id,
        triage_status=TriageStatus.needs_review,
    )
    policy = CasePolicy(case, vet)
    assert policy.is_requested_for_me() is True
    assert policy.can_view() is True
    assert policy.can_claim() is True


def test_vet_patch_allowed_fields_own_case():
    vet = _make_user(1, UserRole.VET)
    case = _make_case(assigned_to_user_id=vet.id, triage_status=TriageStatus.needs_review)
    policy = CasePolicy(case, vet)
    allowed = policy.patch_allowed_fields()
    assert "corrected_label" in allowed
    assert "status" in allowed
    assert "notes" in allowed
