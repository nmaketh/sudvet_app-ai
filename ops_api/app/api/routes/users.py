from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.models import Case, CaseStatus, User, UserRole
from app.schemas.user import AssignableUserOut, UpdateRoleRequest, UserOut, UserStatsResponse


router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(
    role: UserRole | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admin can list all users")
    query = select(User).order_by(User.created_at.desc())
    if role:
        query = query.where(User.role == role)
    return db.scalars(query).all()


@router.get("/assignable", response_model=list[AssignableUserOut])
def list_assignable_users(
    role: UserRole | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in {UserRole.CAHW, UserRole.VET, UserRole.ADMIN}:
        raise HTTPException(status_code=403, detail="Only authenticated users can view assignable users")

    assignable_roles = {UserRole.VET}
    if role is not None and role not in assignable_roles:
        raise HTTPException(status_code=400, detail="Assignable role filter must be VET")

    query = (
        select(User)
        .where(User.role.in_(assignable_roles))
        .order_by(User.role.asc(), User.name.asc(), User.created_at.desc())
    )
    if role:
        query = query.where(User.role == role)
    vets = db.scalars(query).all()

    # Count active (open + in_treatment) cases per vet in one query
    active_counts: dict[int, int] = {}
    if vets:
        vet_ids = [v.id for v in vets]
        rows = db.execute(
            select(Case.assigned_to_user_id, func.count(Case.id))
            .where(
                and_(
                    Case.assigned_to_user_id.in_(vet_ids),
                    Case.status.in_([CaseStatus.open, CaseStatus.in_treatment]),
                )
            )
            .group_by(Case.assigned_to_user_id)
        ).all()
        active_counts = {vet_id: count for vet_id, count in rows}

    return [
        AssignableUserOut(
            id=v.id,
            name=v.name,
            email=v.email,
            role=v.role,
            location=v.location,
            created_at=v.created_at,
            active_caseload=active_counts.get(v.id, 0),
        )
        for v in vets
    ]


@router.patch("/{user_id}/role", response_model=UserOut)
def patch_role(
    user_id: int,
    payload: UpdateRoleRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admin can change roles")
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.role = payload.role
    db.commit()
    db.refresh(user)
    return user


@router.get("/{user_id}/stats", response_model=UserStatsResponse)
def user_stats(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in {UserRole.VET, UserRole.ADMIN} and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Not allowed")

    submitted = db.scalar(select(func.count(Case.id)).where(Case.submitted_by_user_id == user_id)) or 0
    handled = db.scalar(select(func.count(Case.id)).where(Case.assigned_to_user_id == user_id)) or 0

    resolved_rows = db.execute(
        select(Case.created_at, Case.followup_date).where(
            and_(Case.assigned_to_user_id == user_id, Case.status == CaseStatus.resolved, Case.followup_date.is_not(None))
        )
    ).all()
    durations = []
    for created_at, followup_date in resolved_rows:
        if isinstance(created_at, datetime) and isinstance(followup_date, datetime):
            durations.append((followup_date - created_at).total_seconds() / 3600)

    avg_resolution = round(sum(durations) / len(durations), 2) if durations else 0.0
    return UserStatsResponse(
        cases_submitted=submitted,
        cases_handled=handled,
        avg_resolution_time_hours=avg_resolution,
    )
