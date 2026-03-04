from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.models import Case, CaseStatus, RiskLevel, TriageStatus, User, UserRole
from app.schemas.case import CaseOut
from app.services.runtime_settings import get_vet_can_view_all


router = APIRouter(prefix="/vet", tags=["vet"])


def _case_out(item: Case, db: Session) -> CaseOut:
    submitted = db.get(User, item.submitted_by_user_id)
    assigned = db.get(User, item.assigned_to_user_id) if item.assigned_to_user_id else None
    return CaseOut(
        id=item.id,
        client_case_id=item.client_case_id,
        animal_id=item.animal_id,
        animal_tag=item.animal.tag if item.animal else None,
        created_at=item.created_at,
        submitted_by_user_id=item.submitted_by_user_id,
        submitted_by_name=submitted.name if submitted else None,
        image_url=item.image_url,
        symptoms_json=item.symptoms_json or {},
        prediction_json=item.prediction_json or {},
        method=item.method,
        confidence=item.confidence,
        risk_level=item.risk_level,
        status=item.status,
        triage_status=item.triage_status,
        assigned_to_user_id=item.assigned_to_user_id,
        assigned_to_name=assigned.name if assigned else None,
        followup_date=item.followup_date,
        notes=item.notes,
        corrected_label=item.corrected_label,
        urgent=item.urgent,
        triaged_at=item.triaged_at,
        accepted_at=item.accepted_at,
        resolved_at=item.resolved_at,
        vet_review_json=item.vet_review_json,
        rejection_reason=item.rejection_reason,
    )


def _dashboard_visible_filter():
    return or_(
        Case.assigned_to_user_id.is_not(None),
        Case.triage_status == TriageStatus.escalated,
        Case.requested_vet_id.is_not(None),
    )


@router.get("/inbox", response_model=list[CaseOut])
def vet_inbox(
    limit: int = Query(default=50, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Return the authenticated vet's active cases.
    When the vet_can_view_all system setting is enabled, returns all non-resolved
    cases (urgent and escalated first) so vets can self-assign from the full pool.
    Otherwise returns only cases assigned to this vet.
    """
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only vet users can access the inbox")

    if get_vet_can_view_all(db):
        # Show all open/in-treatment cases; urgent + escalated + high-risk surface first
        query = (
            select(Case)
            .where(
                and_(
                    Case.status != CaseStatus.resolved,
                    _dashboard_visible_filter(),
                )
            )
            .order_by(
                Case.urgent.desc(),
                (Case.triage_status == TriageStatus.escalated).desc(),
                (Case.risk_level == RiskLevel.high).desc(),
                Case.created_at.asc(),
            )
            .limit(limit)
        )
    else:
        query = (
            select(Case)
            .where(
                and_(
                    Case.status == CaseStatus.open,
                    Case.assigned_to_user_id == current_user.id,
                )
            )
            .order_by(Case.urgent.desc(), Case.created_at.desc())
            .limit(limit)
        )

    rows = db.scalars(query).all()
    return [_case_out(item, db) for item in rows]
