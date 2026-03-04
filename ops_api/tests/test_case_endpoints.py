"""
Integration tests for case RBAC endpoints.

Covers:
  1. VET cannot GET case assigned to another vet → 403
  2. VET can GET escalated+unassigned case → 200
  3. VET can claim escalated+unassigned → 200; triaged_at set
  4. VET cannot claim needs_review (not requested) → 403
  5. VET cannot claim already-assigned case → 409
  6. ADMIN can assign via /assign; triaged_at set only once (re-assign keeps original)
  7. ADMIN PATCH allowed fields (status, triage_status, notes); corrected_label → 403
  8. VET can PATCH corrected_label on own case
  9. VET can reject own case; case returns to escalated+unassigned
 10. CAHW cannot PATCH any case field → 403

Each test creates fresh case rows (via make_case helper) to avoid state leakage.
"""
from __future__ import annotations

import pytest

from tests.conftest import make_case, token_headers


# ── 1. VET cannot view case assigned to a different vet ──────────────────────

def test_vet_cannot_get_case_assigned_to_other_vet(app_client, db_session, vet_a, vet_b, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="needs_review",
        assigned_to_user_id=vet_b.id,  # assigned to Vet B
    )
    res = app_client.get(f"/cases/{case.id}", headers=token_headers(vet_a))
    assert res.status_code == 403, res.text


# ── 2. VET can GET escalated unassigned case ─────────────────────────────────

def test_vet_can_get_escalated_unassigned(app_client, db_session, vet_a, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="escalated",
        assigned_to_user_id=None,
    )
    res = app_client.get(f"/cases/{case.id}", headers=token_headers(vet_a))
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["id"] == case.id
    assert data["assigned_to_user_id"] is None


# ── 3. VET can claim escalated+unassigned; triaged_at is set ─────────────────

def test_vet_can_claim_escalated_unassigned(app_client, db_session, vet_a, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="escalated",
    )
    res = app_client.post(f"/cases/{case.id}/claim", headers=token_headers(vet_a), json={})
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["assigned_to_user_id"] == vet_a.id
    assert data["triaged_at"] is not None


# ── 4. VET cannot claim needs_review (not requested for them) ────────────────

def test_vet_cannot_claim_needs_review_not_requested(app_client, db_session, vet_a, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="needs_review",
        assigned_to_user_id=None,
        requested_vet_id=None,
    )
    res = app_client.post(f"/cases/{case.id}/claim", headers=token_headers(vet_a), json={})
    assert res.status_code == 403, res.text


# ── 5. VET cannot claim already-assigned case ────────────────────────────────

def test_vet_cannot_claim_already_assigned(app_client, db_session, vet_a, vet_b, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="needs_review",
        assigned_to_user_id=vet_b.id,
    )
    res = app_client.post(f"/cases/{case.id}/claim", headers=token_headers(vet_a), json={})
    assert res.status_code in (403, 409), res.text


# ── 6. ADMIN can assign; triaged_at set only on first assignment ──────────────

def test_admin_assign_sets_triaged_at_once(app_client, db_session, admin_user, vet_a, vet_b, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="escalated",
    )

    # First assignment
    res = app_client.post(
        f"/cases/{case.id}/assign",
        headers=token_headers(admin_user),
        json={"assigned_to_user_id": vet_a.id},
    )
    assert res.status_code == 200, res.text
    first_triaged_at = res.json()["triaged_at"]
    assert first_triaged_at is not None

    # Re-assign to a different vet — triaged_at must not change
    res2 = app_client.post(
        f"/cases/{case.id}/assign",
        headers=token_headers(admin_user),
        json={"assigned_to_user_id": vet_b.id},
    )
    assert res2.status_code == 200, res2.text
    assert res2.json()["triaged_at"] == first_triaged_at


# ── 7. ADMIN PATCH: allowed fields work; corrected_label is forbidden ─────────

def test_admin_patch_allowed_fields(app_client, db_session, admin_user, cahw_user):
    case = make_case(db_session, submitted_by_user_id=cahw_user.id)

    # Allowed fields for ADMIN
    res = app_client.patch(
        f"/cases/{case.id}",
        headers=token_headers(admin_user),
        json={"status": "in_treatment", "notes": "Admin note"},
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "in_treatment"
    assert data["notes"] == "Admin note"


def test_admin_patch_corrected_label_forbidden(app_client, db_session, admin_user, cahw_user):
    case = make_case(db_session, submitted_by_user_id=cahw_user.id)

    res = app_client.patch(
        f"/cases/{case.id}",
        headers=token_headers(admin_user),
        json={"corrected_label": "fmd"},
    )
    assert res.status_code == 403, res.text


# ── 8. VET can PATCH corrected_label on own case ─────────────────────────────

def test_vet_patch_corrected_label_on_own_case(app_client, db_session, vet_a, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="needs_review",
        assigned_to_user_id=vet_a.id,
    )
    res = app_client.patch(
        f"/cases/{case.id}",
        headers=token_headers(vet_a),
        json={"corrected_label": "lsd"},
    )
    assert res.status_code == 200, res.text
    assert res.json()["corrected_label"] == "lsd"


# ── 9. VET can reject own case; case returns to escalated+unassigned ──────────

def test_vet_can_reject_own_case(app_client, db_session, vet_a, cahw_user):
    case = make_case(
        db_session,
        submitted_by_user_id=cahw_user.id,
        triage_status="needs_review",
        assigned_to_user_id=vet_a.id,
    )
    res = app_client.post(
        f"/cases/{case.id}/reject",
        headers=token_headers(vet_a),
        json={"reason": "Outside my speciality"},
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["assigned_to_user_id"] is None
    assert data["triage_status"] == "escalated"
    assert data["rejection_reason"] == "Outside my speciality"


# ── 10. CAHW cannot PATCH any case field ─────────────────────────────────────

def test_cahw_cannot_patch_case(app_client, db_session, cahw_user):
    case = make_case(db_session, submitted_by_user_id=cahw_user.id)
    res = app_client.patch(
        f"/cases/{case.id}",
        headers=token_headers(cahw_user),
        json={"notes": "CAHW trying to write notes"},
    )
    assert res.status_code == 403, res.text
