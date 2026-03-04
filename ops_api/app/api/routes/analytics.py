from collections import Counter, defaultdict
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.models import Case, CaseStatus, RiskLevel, TriageStatus, User, UserRole
from app.schemas.analytics import AnalyticsSummaryResponse


router = APIRouter(prefix="/analytics", tags=["analytics"])


def _dashboard_visible_filter():
    return or_(
        Case.assigned_to_user_id.is_not(None),
        Case.triage_status == TriageStatus.escalated,
        Case.requested_vet_id.is_not(None),
    )


@router.get("/summary", response_model=AnalyticsSummaryResponse)
def analytics_summary(
    from_date: datetime | None = Query(default=None, alias="from"),
    to_date: datetime | None = Query(default=None, alias="to"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(Case)
    if from_date:
        query = query.where(Case.created_at >= from_date)
    if to_date:
        query = query.where(Case.created_at <= to_date)
    if current_user.role == UserRole.CAHW:
        query = query.where(Case.submitted_by_user_id == current_user.id)
    elif current_user.role == UserRole.VET:
        query = query.where(Case.assigned_to_user_id == current_user.id)
    else:
        query = query.where(_dashboard_visible_filter())

    rows = db.scalars(query).all()

    by_disease = Counter(
        (item.prediction_json or {}).get("final_label", (item.prediction_json or {}).get("label", "unknown"))
        for item in rows
    )
    by_day_counter = Counter(item.created_at.date().isoformat() for item in rows)
    by_day = [{"day": day, "count": by_day_counter[day]} for day in sorted(by_day_counter)]

    backlog = sum(1 for item in rows if item.status != CaseStatus.resolved)
    high_risk = sum(1 for item in rows if item.risk_level == RiskLevel.high)
    high_risk_rate = round((high_risk / len(rows)) * 100, 2) if rows else 0.0

    resolution_durations = []
    resolution_per_day = defaultdict(list)
    resolved_by_day_counter = Counter()
    for item in rows:
        if item.status == CaseStatus.resolved and item.followup_date:
            hours = (item.followup_date - item.created_at).total_seconds() / 3600
            resolution_durations.append(hours)
            resolution_day = item.followup_date.date().isoformat()
            resolution_per_day[resolution_day].append(hours)
            resolved_by_day_counter[resolution_day] += 1

    avg_resolution = round(sum(resolution_durations) / len(resolution_durations), 2) if resolution_durations else 0.0
    resolution_trend = [
        {"day": day, "avg_hours": round(sum(vals) / len(vals), 2)}
        for day, vals in sorted(resolution_per_day.items())
    ]

    backlog_trend = []
    running_backlog = 0
    timeline_days = sorted(set(by_day_counter) | set(resolved_by_day_counter))
    for day in timeline_days:
        running_backlog += by_day_counter.get(day, 0)
        running_backlog -= resolved_by_day_counter.get(day, 0)
        running_backlog = max(0, running_backlog)
        backlog_trend.append({"day": day, "backlog": running_backlog})

    return AnalyticsSummaryResponse(
        cases_by_disease=dict(by_disease),
        cases_by_day=by_day,
        backlog_count=backlog,
        avg_resolution_time=avg_resolution,
        high_risk_rate=high_risk_rate,
        resolution_time_trend=resolution_trend,
        backlog_trend=backlog_trend,
    )
