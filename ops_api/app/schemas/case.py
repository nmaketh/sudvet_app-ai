from datetime import datetime
from typing import Any

from pydantic import BaseModel, field_validator

from app.models.models import CaseStatus, RiskLevel, TriageStatus


class CaseOut(BaseModel):
    id: str
    client_case_id: str | None
    animal_id: str | None
    animal_tag: str | None = None
    created_at: datetime
    submitted_by_user_id: int
    submitted_by_name: str | None = None
    image_url: str | None
    symptoms_json: dict[str, Any]
    prediction_json: dict[str, Any]
    method: str | None
    confidence: float | None
    risk_level: RiskLevel
    status: CaseStatus
    triage_status: TriageStatus
    assigned_to_user_id: int | None
    assigned_to_name: str | None = None
    requested_vet_id: int | None = None
    requested_vet_name: str | None = None
    request_note: str | None = None
    followup_date: datetime | None
    notes: str | None
    corrected_label: str | None
    # Workflow lifecycle fields
    urgent: bool = False
    triaged_at: datetime | None = None
    accepted_at: datetime | None = None
    resolved_at: datetime | None = None
    vet_review_json: dict[str, Any] | None = None
    rejection_reason: str | None = None


class PatchCaseRequest(BaseModel):
    """PATCH workflow fields only.
    Assignment is done exclusively via /assign (ADMIN) or /claim (VET).
    """
    status: CaseStatus | None = None
    triage_status: TriageStatus | None = None
    followup_date: datetime | None = None
    notes: str | None = None
    corrected_label: str | None = None


class AssignCaseRequest(BaseModel):
    assigned_to_user_id: int
    note: str | None = None  # optional dispatch note from admin


class ClaimCaseRequest(BaseModel):
    """VET self-assigns an unassigned claimable case."""
    note: str | None = None  # optional acceptance note


class RejectCaseRequest(BaseModel):
    """VET returns a case to the shared escalated queue with a mandatory reason."""
    reason: str

    @field_validator("reason")
    @classmethod
    def reason_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Rejection reason cannot be blank")
        return v.strip()


class VetReviewRequest(BaseModel):
    """Structured clinical review submitted by the assigned vet."""
    assessment: str
    diagnosis: str | None = None
    plan: str
    prescription: str | None = None
    follow_up_date: datetime | None = None
    message: str | None = None

    @field_validator("assessment", "plan")
    @classmethod
    def not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Field cannot be blank")
        return v.strip()


class FeedbackRequest(BaseModel):
    was_correct: bool
    corrected_label: str | None = None
    comment: str | None = None


class FeedbackOut(BaseModel):
    id: int
    case_id: str
    user_id: int
    was_correct: bool
    corrected_label: str | None
    comment: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class CaseEventOut(BaseModel):
    id: int
    case_id: str
    actor_user_id: int
    event_type: str
    payload_json: dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True
