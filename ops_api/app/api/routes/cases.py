import json
import logging
import os
import uuid
from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy import and_, case as sa_case, func, or_, select
from sqlalchemy.orm import Session

from app.api.routes.predict import (
    _build_ml_symptoms,
    _call_ml_service,
    _ensure_gradcam_public_url,
    _extension_from_content_type,
    _ml_to_flutter,
    _parse_float,
    _to_int,
)
from app.core.config import settings
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.ml.explainer import explain as bayesian_explain
from app.ml.predictor import predict as bayesian_predict
from app.core.policy import CasePolicy
from app.models.models import Case, CaseEvent, CaseStatus, Feedback, RiskLevel, TriageStatus, User, UserRole
from app.schemas.case import (
    AssignCaseRequest,
    CaseEventOut,
    CaseOut,
    ClaimCaseRequest,
    FeedbackOut,
    FeedbackRequest,
    PatchCaseRequest,
    RejectCaseRequest,
    VetReviewRequest,
)
from app.services.runtime_settings import get_vet_can_view_all

log = logging.getLogger(__name__)

router = APIRouter(prefix="/cases", tags=["cases"])

_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB


# ── Helpers ────────────────────────────────────────────────────────────────────

def _case_out(item: Case, db: Session) -> CaseOut:
    submitted = db.get(User, item.submitted_by_user_id)
    assigned = db.get(User, item.assigned_to_user_id) if item.assigned_to_user_id else None
    requested_vet = db.get(User, item.requested_vet_id) if item.requested_vet_id else None
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
        requested_vet_id=item.requested_vet_id,
        requested_vet_name=requested_vet.name if requested_vet else None,
        request_note=item.request_note,
        followup_date=item.followup_date,
        notes=item.notes,
        corrected_label=item.corrected_label,
        # Workflow lifecycle fields
        urgent=item.urgent,
        triaged_at=item.triaged_at,
        accepted_at=item.accepted_at,
        resolved_at=item.resolved_at,
        vet_review_json=item.vet_review_json,
        rejection_reason=item.rejection_reason,
    )


def _is_truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _dashboard_visible_filter():
    """Cases that should appear in dashboard/listing views."""
    return or_(
        Case.assigned_to_user_id.is_not(None),
        Case.triage_status == TriageStatus.escalated,
        Case.requested_vet_id.is_not(None),
    )


def _visible_query(db: Session, current_user: User):
    """
    Scope rules:
      ADMIN — sees every case; priority order: urgent first, then escalated,
              then high-risk, then oldest created_at.
      VET   — sees own assigned cases; if vet_can_view_all setting is on,
              sees all non-resolved cases too.
      CAHW  — sees only their own submitted cases.
    """
    if current_user.role == UserRole.ADMIN:
        # Priority score: urgent=3 > escalated=2 > high-risk=1 > else=0
        priority = sa_case(
            (Case.urgent == True, 3),
            (Case.triage_status == TriageStatus.escalated, 2),
            (Case.risk_level == RiskLevel.high, 1),
            else_=0,
        )
        return (
            select(Case)
            .where(_dashboard_visible_filter())
            .order_by(priority.desc(), Case.created_at.asc())
        )

    if current_user.role == UserRole.VET:
        # VET sees:
        #   1. Cases assigned to them (any triage_status, any risk)
        #   2. Escalated + unassigned cases (shared triage queue for claiming)
        #   3. Cases where they were specifically requested (unassigned)
        return (
            select(Case)
            .where(
                or_(
                    Case.assigned_to_user_id == current_user.id,
                    and_(
                        Case.triage_status == TriageStatus.escalated,
                        Case.assigned_to_user_id == None,
                    ),
                    and_(
                        Case.requested_vet_id == current_user.id,
                        Case.assigned_to_user_id == None,
                    ),
                )
            )
            .order_by(Case.created_at.desc())
        )

    # CAHW — own submissions only
    return (
        select(Case)
        .where(Case.submitted_by_user_id == current_user.id)
        .order_by(Case.created_at.desc())
    )


def _ensure_case_access(item: Case, current_user: User):
    """Raise 403 if the current user is not allowed to read/act on this case."""
    if not CasePolicy(item, current_user).can_view():
        raise HTTPException(status_code=403, detail="Not allowed")


def _create_event(db: Session, case_id: str, actor_user_id: int, event_type: str, payload: dict):
    db.add(
        CaseEvent(
            case_id=case_id,
            actor_user_id=actor_user_id,
            event_type=event_type,
            payload_json=payload,
        )
    )


def _ensure_case_write_access(current_user: User):
    if current_user.role not in {UserRole.VET, UserRole.ADMIN}:
        raise HTTPException(status_code=403, detail="Only vet/admin can update case workflow fields")


def _ensure_assigned_vet_lock(item: Case, current_user: User, *, require_assignment: bool = False):
    """Only the assigned vet can perform vet workflow actions on a case."""
    if current_user.role != UserRole.VET:
        return
    if item.assigned_to_user_id is None:
        if require_assignment:
            raise HTTPException(
                status_code=409,
                detail="Case must be assigned to a specific vet before this action",
            )
        return
    if item.assigned_to_user_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="This case is assigned to another vet and cannot be accepted by you",
        )


async def _save_image(file: UploadFile) -> tuple[Optional[str], Optional[bytes], Optional[str]]:
    """Save an uploaded image file. Returns (image_url, image_bytes, content_type)."""
    if not file or not file.filename:
        return None, None, None
    content_type = file.content_type or ""
    # Infer content type from extension when the client omits it (e.g. Flutter web)
    if content_type not in _ALLOWED_IMAGE_TYPES:
        _ext_map = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
                    ".webp": "image/webp", ".gif": "image/gif"}
        fname_lower = (file.filename or "").lower()
        for ext_suffix, mime in _ext_map.items():
            if fname_lower.endswith(ext_suffix):
                content_type = mime
                break
    if content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported image type '{content_type}'. Allowed: jpeg, png, webp",
        )
    image_bytes = await file.read()
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image exceeds 10 MB limit")
    ext = _extension_from_content_type(content_type)
    filename = f"{uuid.uuid4().hex}{ext}"
    from app.core.supabase_client import upload_image
    image_url = upload_image(filename, image_bytes, content_type)
    return image_url, image_bytes, content_type


async def _run_prediction(
    symptoms: dict,
    image_bytes: Optional[bytes],
    image_content_type: Optional[str],
    temperature: Optional[float],
    severity: Optional[float],
) -> dict:
    """Run disease prediction via ML service or Bayesian fallback."""
    ml_symptoms = _build_ml_symptoms(symptoms)
    ml_result = await _call_ml_service(ml_symptoms, image_bytes, image_content_type)

    if ml_result is not None:
        response = _ml_to_flutter(ml_result, temperature, severity)
        await _ensure_gradcam_public_url(response)
        response["engine"] = "ml_service"
        return response

    # Bayesian fallback
    log.info("Bayesian fallback engaged")
    bool_symptoms = {k: bool(_to_int(v)) for k, v in symptoms.items()}
    prediction_result = bayesian_predict(symptoms=bool_symptoms, temperature=temperature, severity=severity)
    explanation = bayesian_explain(prediction_result=prediction_result, temperature=temperature, severity=severity)
    return {
        "display_label": explanation["display_label"],
        "final_label": explanation["label"],
        "prediction": explanation["display_label"],
        "confidence": explanation["confidence"],
        "method": explanation["method"],
        "risk_level": explanation["risk_level"],
        "recommendations": explanation["recommendations"],
        "explain": {
            "gradcam_path": None,
            "feature_importance": explanation["feature_importance"],
            "differential": explanation["differential"],
            "rule_triggers": explanation["rule_triggers"],
            "reasoning": explanation["reasoning"],
            "probabilities": explanation["probabilities"],
            "temperature_note": explanation.get("temperature_note"),
            "severity_note": explanation.get("severity_note"),
        },
        "gradcam_path": None,
        "rule_triggers": explanation["rule_triggers"],
        "feature_importance": explanation["feature_importance"],
        "differential": explanation["differential"],
        "reasoning": explanation["reasoning"],
        "probabilities": explanation["probabilities"],
        "engine": "bayesian_fallback",
    }


# ── Routes ────────────────────────────────────────────────────────────────────

@router.get("", response_model=list[CaseOut])
def list_cases(
    status: str | None = None,
    triage_status: TriageStatus | None = None,
    assigned_to: int | None = None,
    submitted_by: int | None = None,
    risk: str | None = None,
    disease: str | None = None,
    queue: str | None = None,  # "claimable" | "requested_for_me" | "assigned_to_me"
    urgent_only: bool | None = Query(default=None, alias="urgentOnly"),
    animal_id: str | None = Query(default=None, alias="animal_id"),
    animalId: str | None = Query(default=None, alias="animalId"),
    query_text: str | None = Query(default=None, alias="query"),
    limit: int | None = Query(default=None, ge=1, le=500),
    from_date: datetime | None = Query(default=None, alias="from"),
    to_date: datetime | None = Query(default=None, alias="to"),
    q: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = _visible_query(db, current_user)
    filters = []

    status_value = (status or "").strip().lower() if status else None
    if status_value:
        # Flutter field app historically used sync-centric values (pending/synced/failed).
        # Map them to clinical workflow statuses for the shared ops backend.
        status_aliases = {
            "pending": CaseStatus.open,
            "open": CaseStatus.open,
            "in_treatment": CaseStatus.in_treatment,
            "resolved": CaseStatus.resolved,
            "synced": None,
            "failed": None,
        }
        mapped_status = status_aliases.get(status_value)
        if mapped_status is not None:
            filters.append(Case.status == mapped_status)
    if triage_status:
        filters.append(Case.triage_status == triage_status)
    if assigned_to:
        filters.append(Case.assigned_to_user_id == assigned_to)
    if submitted_by:
        filters.append(Case.submitted_by_user_id == submitted_by)
    if risk:
        filters.append(Case.risk_level == risk)
    if urgent_only:
        filters.append(Case.urgent == True)
    if queue:
        if queue == "claimable":
            # Unassigned cases that the current VET can claim
            filters.append(Case.assigned_to_user_id == None)
            filters.append(
                or_(
                    Case.triage_status == TriageStatus.escalated,
                    Case.requested_vet_id == current_user.id,
                )
            )
        elif queue == "requested_for_me":
            filters.append(Case.requested_vet_id == current_user.id)
            filters.append(Case.assigned_to_user_id == None)
        elif queue == "assigned_to_me":
            filters.append(Case.assigned_to_user_id == current_user.id)
    if from_date:
        filters.append(Case.created_at >= from_date)
    if to_date:
        filters.append(Case.created_at <= to_date)
    animal_filter = (animal_id or animalId or "").strip()
    if animal_filter:
        filters.append(Case.animal_id == animal_filter)

    search_text = (q or query_text or "").strip()
    if search_text:
        text = f"%{search_text}%"
        filters.append(or_(Case.id.ilike(text), Case.client_case_id.ilike(text), Case.notes.ilike(text)))

    if filters:
        query = query.where(and_(*filters))
    if limit:
        query = query.limit(limit)

    rows = db.scalars(query).all()
    if disease:
        disease_key = disease.lower()
        rows = [
            item for item in rows
            if str((item.prediction_json or {}).get("final_label", (item.prediction_json or {}).get("label", ""))).lower() == disease_key
        ]
    return [_case_out(item, db) for item in rows]


@router.post("", response_model=CaseOut, status_code=201)
async def create_case(
    payload: str = Form(..., description="JSON: {animalId?, symptoms, temperature?, severity?, notes?, clientCaseId?, urgent?}"),
    files: list[UploadFile] = File(default=[]),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new disease case, run prediction, and persist to database."""
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, ValueError):
        raise HTTPException(status_code=422, detail="payload must be valid JSON")

    symptoms: dict = data.get("symptoms") or {}
    if not isinstance(symptoms, dict):
        raise HTTPException(status_code=422, detail="symptoms must be an object")

    animal_id: Optional[str] = (data.get("animalId") or data.get("animal_id") or "").strip() or None
    temperature: Optional[float] = _parse_float(data.get("temperature"))
    severity: Optional[float] = _parse_float(data.get("severity"))
    notes: Optional[str] = (data.get("notes") or "").strip() or None
    client_case_id: Optional[str] = (data.get("clientCaseId") or data.get("client_case_id") or "").strip() or None
    vet_email: Optional[str] = (data.get("vetEmail") or data.get("vet_email") or "").strip().lower() or None
    allow_assignment_raw = data.get("allowAssignment")
    if allow_assignment_raw is None:
        allow_assignment_raw = data.get("allow_assignment")
    allow_assignment = _is_truthy(allow_assignment_raw)
    urgent: bool = bool(data.get("urgent", False))
    # CAHW can optionally request a specific vet at submission time
    requested_vet_id_raw = data.get("requestedVetId") or data.get("requested_vet_id")
    request_note: Optional[str] = (data.get("requestNote") or data.get("request_note") or "").strip() or None

    # Save first valid uploaded image
    image_url: Optional[str] = None
    image_bytes: Optional[bytes] = None
    image_content_type: Optional[str] = None
    valid_files = [f for f in (files or []) if f and f.filename]
    if valid_files:
        image_url, image_bytes, image_content_type = await _save_image(valid_files[0])

    # Run prediction
    prediction: dict = {}
    method: Optional[str] = None
    confidence: Optional[float] = None
    risk_level = RiskLevel.medium

    if symptoms:
        try:
            prediction = await _run_prediction(symptoms, image_bytes, image_content_type, temperature, severity)
        except Exception:
            log.exception("Prediction failed during case creation")
            prediction = {}

    if prediction:
        prediction["image_url"] = image_url
        prediction["predicted_at"] = datetime.utcnow().isoformat()
        method = prediction.get("method")
        confidence = _parse_float(prediction.get("confidence"))
        raw_risk = prediction.get("risk_level", "medium")
        try:
            risk_level = RiskLevel(raw_risk)
        except ValueError:
            risk_level = RiskLevel.medium

    # All new cases go straight into the vet triage queue — no manual escalation needed.
    # High-risk cases are additionally flagged as urgent.
    if risk_level == RiskLevel.high:
        urgent = True

    # Resolve optional vet request (CAHW can suggest a vet; does not assign directly)
    requested_vet_id: Optional[int] = None
    if requested_vet_id_raw:
        try:
            requested_vet_id = int(requested_vet_id_raw)
        except (ValueError, TypeError):
            raise HTTPException(status_code=422, detail="requestedVetId must be a valid integer")
    requested_vet: Optional[User] = None
    if requested_vet_id is not None:
        requested_vet = db.get(User, requested_vet_id)
        if not requested_vet:
            raise HTTPException(status_code=404, detail="Requested vet not found")
        if requested_vet.role != UserRole.VET:
            raise HTTPException(status_code=400, detail="Requested user must be a VET")

    # Legacy: support vet_email for backwards-compatibility with older Flutter clients
    if vet_email and requested_vet_id is None:
        vet_by_email = db.scalar(select(User).where(User.email == vet_email))
        if not vet_by_email:
            raise HTTPException(status_code=404, detail=f"No user found with email '{vet_email}'")
        if vet_by_email.role != UserRole.VET:
            raise HTTPException(status_code=400, detail="Requested user must be a VET")
        requested_vet_id = vet_by_email.id
        requested_vet = vet_by_email

    triage_status = TriageStatus.escalated if allow_assignment else TriageStatus.needs_review

    case = Case(
        id=str(uuid.uuid4()),
        client_case_id=client_case_id,
        animal_id=animal_id,
        submitted_by_user_id=current_user.id,
        image_url=image_url,
        symptoms_json=symptoms,
        prediction_json=prediction,
        method=method,
        confidence=confidence,
        risk_level=risk_level,
        status=CaseStatus.open,
        triage_status=triage_status,
        requested_vet_id=requested_vet_id,
        request_note=request_note,
        notes=notes,
        urgent=urgent,
    )
    db.add(case)
    _create_event(db, case.id, current_user.id, "case_created", {
        "animal_id": animal_id,
        "symptoms_count": sum(1 for v in symptoms.values() if v),
        "method": method,
        "engine": prediction.get("engine"),
        "allow_assignment": allow_assignment,
        "triage_status": triage_status.value,
        "requested_vet_id": requested_vet_id,
        "requested_vet_email": requested_vet.email if requested_vet else None,
        "urgent": urgent,
    })
    db.commit()
    db.refresh(case)
    return _case_out(case, db)


@router.get("/pending-count")
def pending_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Count of cases that still need model output (prediction sync)."""
    base_query = _visible_query(db, current_user).where(
        and_(
            Case.status == CaseStatus.open,
            or_(Case.method.is_(None), Case.confidence.is_(None)),
        )
    )
    count = db.scalar(select(func.count()).select_from(base_query.subquery()))
    return {"count": count or 0}


@router.post("/sync-pending")
async def sync_pending(
    asyncMode: bool = Query(default=False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-run prediction for open cases that have no prediction result."""
    query = _visible_query(db, current_user).where(Case.status == CaseStatus.open)
    open_cases = db.scalars(query).all()

    synced = 0
    failed = 0
    for item in open_cases:
        symptoms = item.symptoms_json or {}
        if not symptoms:
            continue
        if item.prediction_json and item.prediction_json.get("final_label"):
            continue  # already has a valid prediction
        try:
            prediction = await _run_prediction(symptoms, None, None, None, None)
            prediction["predicted_at"] = datetime.utcnow().isoformat()
            prediction["image_url"] = item.image_url
            item.prediction_json = prediction
            item.method = prediction.get("method")
            item.confidence = _parse_float(prediction.get("confidence"))
            raw_risk = prediction.get("risk_level", "medium")
            try:
                item.risk_level = RiskLevel(raw_risk)
            except ValueError:
                pass
            synced += 1
        except Exception:
            log.exception("Failed to sync case %s", item.id)
            failed += 1

    db.commit()
    return {
        "synced": synced,
        "failed": failed,
        "syncedCount": synced,
        "failedCount": failed,
        "total": len(open_cases),
    }


@router.get("/{case_id}", response_model=CaseOut)
def get_case(case_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)
    return _case_out(item, db)


@router.patch("/{case_id}", response_model=CaseOut)
def patch_case(
    case_id: str,
    payload: PatchCaseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    policy = CasePolicy(item, current_user)
    _ensure_case_access(item, current_user)

    if not policy.can_patch():
        raise HTTPException(
            status_code=403,
            detail="You do not have write access to this case. VETs must claim the case first.",
        )

    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No case fields provided for update")

    allowed = policy.patch_allowed_fields()
    disallowed = [k for k in updates.keys() if k not in allowed]
    if disallowed:
        raise HTTPException(
            status_code=403,
            detail=f"You cannot update field(s): {', '.join(disallowed)}",
        )

    if "corrected_label" in updates and isinstance(updates["corrected_label"], str):
        if not updates["corrected_label"].strip():
            updates["corrected_label"] = None

    changes = {}
    for field, value in updates.items():
        setattr(item, field, value)
        changes[field] = value.isoformat() if isinstance(value, datetime) else value

    if payload.corrected_label is not None:
        pred = dict(item.prediction_json or {})
        if payload.corrected_label:
            pred["corrected_label"] = payload.corrected_label
        else:
            pred.pop("corrected_label", None)
        item.prediction_json = pred

    _create_event(db, item.id, current_user.id, "case_updated", changes)
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/assign", response_model=CaseOut)
def assign_case(
    case_id: str,
    payload: AssignCaseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Admin dispatches a case to a vet. Sets triaged_at SLA timestamp."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can dispatch cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    assignee = db.get(User, payload.assigned_to_user_id)
    if not assignee:
        raise HTTPException(status_code=404, detail="Assignee not found")
    if assignee.role != UserRole.VET:
        raise HTTPException(status_code=400, detail="Assignee must be a VET user")

    item.assigned_to_user_id = payload.assigned_to_user_id
    # triaged_at = SLA timestamp for "time-to-first-assignment"; set only once
    if item.triaged_at is None:
        item.triaged_at = datetime.utcnow()
    if payload.note:
        existing = item.notes or ""
        item.notes = f"[Dispatch] {payload.note.strip()}\n{existing}".strip()

    _create_event(
        db, item.id, current_user.id, "case_assigned",
        {
            "assigned_to_user_id": payload.assigned_to_user_id,
            "assigned_to_name": assignee.name,
            "note": payload.note,
        },
    )
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/claim", response_model=CaseOut)
def claim_case(
    case_id: str,
    payload: ClaimCaseRequest = ClaimCaseRequest(),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """VET self-assigns an unassigned claimable case.
    Claimable = unassigned AND (escalated OR requested_vet_id == current_user.id).
    """
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only vets can claim cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    policy = CasePolicy(item, current_user)
    if not policy.can_claim():
        if item.assigned_to_user_id is not None:
            raise HTTPException(
                status_code=409,
                detail="Case is already assigned to a vet and cannot be claimed",
            )
        raise HTTPException(
            status_code=403,
            detail="This case is not in a claimable state for your account",
        )

    item.assigned_to_user_id = current_user.id
    # SLA: accepted_at = when vet first takes ownership
    if item.accepted_at is None:
        item.accepted_at = datetime.utcnow()
    # triaged_at = time-to-first-assignment; set if not set by admin /assign
    if item.triaged_at is None:
        item.triaged_at = datetime.utcnow()

    if payload.note:
        existing = item.notes or ""
        item.notes = f"[Claim] {payload.note.strip()}\n{existing}".strip()

    _create_event(db, item.id, current_user.id, "case_claimed", {
        "claimed_by_user_id": current_user.id,
        "claimed_by_name": current_user.name,
        "note": payload.note,
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/reject", response_model=CaseOut)
def reject_case(
    case_id: str,
    payload: RejectCaseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    VET returns a case to the admin dispatch queue.
    Clears assignment, resets triage_status to new, stores rejection_reason.
    """
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only assigned vets can reject cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    if item.assigned_to_user_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only reject cases assigned to you")

    prev_assignee_id = item.assigned_to_user_id
    item.assigned_to_user_id = None
    item.triage_status = TriageStatus.escalated  # return to shared vet queue
    item.accepted_at = None  # clear the acceptance timestamp
    item.triaged_at = None   # reset SLA clock so admin can re-dispatch
    item.rejection_reason = payload.reason

    _create_event(db, item.id, current_user.id, "case_rejected", {
        "prev_assigned_to": prev_assignee_id,
        "reason": payload.reason,
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/sync", response_model=CaseOut)
async def sync_case(
    case_id: str,
    asyncMode: bool = Query(default=False),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-run prediction for an existing case."""
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    symptoms = item.symptoms_json or {}
    if not symptoms:
        raise HTTPException(status_code=400, detail="Case has no symptoms to re-run prediction on")

    try:
        prediction = await _run_prediction(symptoms, None, None, None, None)
    except Exception:
        log.exception("Prediction failed during sync for case %s", case_id)
        raise HTTPException(status_code=500, detail="Prediction service unavailable")

    prediction["predicted_at"] = datetime.utcnow().isoformat()
    prediction["image_url"] = item.image_url
    item.prediction_json = prediction
    item.method = prediction.get("method")
    item.confidence = _parse_float(prediction.get("confidence"))
    raw_risk = prediction.get("risk_level", "medium")
    try:
        item.risk_level = RiskLevel(raw_risk)
    except ValueError:
        pass

    _create_event(db, item.id, current_user.id, "case_synced", {
        "method": item.method,
        "engine": prediction.get("engine"),
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/ack", response_model=CaseOut)
def ack_case(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Vet acknowledges a case — marks triage_status as needs_review, sets accepted_at."""
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only assigned vets can acknowledge cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_assigned_vet_lock(item, current_user, require_assignment=True)

    status_val = (body.get("status") or "").strip()
    notes_val = (body.get("notes") or "").strip() or None

    triage_map = {
        "needs_review": TriageStatus.needs_review,
        "escalated": TriageStatus.escalated,
    }
    new_triage = triage_map.get(status_val, TriageStatus.needs_review)
    item.triage_status = new_triage
    # Record when the vet first accepted the case
    if item.accepted_at is None:
        item.accepted_at = datetime.utcnow()
    if notes_val:
        item.notes = notes_val

    _create_event(db, item.id, current_user.id, "case_acknowledged", {
        "triage_status": new_triage.value,
        "sender_role": body.get("senderRole"),
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/close", response_model=CaseOut)
def close_case(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Close a case by setting status to resolved. Sets resolved_at SLA timestamp."""
    if current_user.role not in {UserRole.VET, UserRole.ADMIN}:
        raise HTTPException(status_code=403, detail="Only vets or admins can close cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    if current_user.role == UserRole.VET:
        _ensure_assigned_vet_lock(item, current_user, require_assignment=True)

    outcome = (body.get("outcome") or "resolved").strip()
    notes_val = (body.get("notes") or "").strip() or None

    item.status = CaseStatus.resolved
    item.resolved_at = datetime.utcnow()
    if notes_val:
        item.notes = notes_val

    _create_event(db, item.id, current_user.id, "case_closed", {
        "outcome": outcome,
        "sender_role": body.get("senderRole"),
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/messages")
def add_message(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Add a message to a case (stored as a CaseEvent).

    Chat is strictly CAHW (submitter) ↔ assigned VET.
    ADMIN is excluded — they see the audit timeline but do not participate in chats.
    """
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    # ADMIN must not participate in case chats.
    if current_user.role == UserRole.ADMIN:
        raise HTTPException(
            status_code=403,
            detail="Admins cannot send chat messages. Chat is private between the CAHW and the assigned vet.",
        )

    # VET must be the assigned vet (not just any vet viewing the queue).
    if current_user.role == UserRole.VET and item.assigned_to_user_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="Only the assigned vet can send messages on this case.",
        )

    # CAHW must be the original submitter.
    if current_user.role == UserRole.CAHW and item.submitted_by_user_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="Only the CAHW who submitted this case can send messages.",
        )

    message = (body.get("message") or "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    # Always derive identity from the authenticated session — never trust client-provided values.
    _create_event(db, item.id, current_user.id, "message", {
        "message": message,
        "sender_role": current_user.role.value.lower(),
        "sender_name": current_user.name,
        "sender_email": current_user.email,
    })
    db.commit()
    return {"status": "ok"}


@router.post("/{case_id}/send-to-vet", response_model=CaseOut)
def send_to_vet(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Assign a case to a vet identified by email (admin-only alias for /assign)."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can dispatch cases via email")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    vet_email = (body.get("vetEmail") or "").strip()
    if not vet_email:
        raise HTTPException(status_code=400, detail="vetEmail is required")

    vet = db.scalar(select(User).where(User.email == vet_email))
    if not vet:
        raise HTTPException(status_code=404, detail=f"No user found with email '{vet_email}'")
    if vet.role != UserRole.VET:
        raise HTTPException(status_code=400, detail="Target user is not a VET")

    message = (body.get("message") or "").strip() or None
    notes_val = (body.get("notes") or "").strip() or None

    item.assigned_to_user_id = vet.id
    if item.triaged_at is None:
        item.triaged_at = datetime.utcnow()
    if notes_val:
        item.notes = notes_val

    _create_event(db, item.id, current_user.id, "sent_to_vet", {
        "vet_id": vet.id,
        "vet_name": vet.name,
        "vet_email": vet_email,
        "message": message,
        "sender_role": body.get("senderRole"),
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/escalate")
def escalate_case(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """CAHW requests vet review — moves triage_status to escalated.
    Once escalated, the case becomes visible in the vet triage queue.
    """
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    if current_user.role == UserRole.VET:
        raise HTTPException(status_code=403, detail="Vets cannot escalate cases; use /claim instead.")

    # All cases already start as escalated — this endpoint is kept for backward compatibility
    allow_assignment_raw = body.get("allowAssignment")
    if allow_assignment_raw is None:
        allow_assignment_raw = body.get("allow_assignment")

    requested_vet_id_raw = body.get("requestedVetId")
    if requested_vet_id_raw is None:
        requested_vet_id_raw = body.get("requested_vet_id")
    vet_email = (body.get("vetEmail") or body.get("vet_email") or "").strip().lower() or None
    request_note = (body.get("requestNote") or body.get("request_note") or "").strip() or None

    requested_hint_present = requested_vet_id_raw is not None or vet_email is not None
    if allow_assignment_raw is None:
        # Backward-compatible default: old clients with empty body still escalate to shared queue.
        allow_assignment = not requested_hint_present
    else:
        allow_assignment = _is_truthy(allow_assignment_raw)

    requested_vet_id: Optional[int] = None
    requested_vet: Optional[User] = None
    if requested_vet_id_raw is not None:
        try:
            requested_vet_id = int(requested_vet_id_raw)
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="requestedVetId must be a valid integer")
        requested_vet = db.get(User, requested_vet_id)
        if not requested_vet:
            raise HTTPException(status_code=404, detail="Requested vet not found")
        if requested_vet.role != UserRole.VET:
            raise HTTPException(status_code=400, detail="Requested user must be a VET")

    if vet_email and requested_vet is None:
        vet_by_email = db.scalar(select(User).where(User.email == vet_email))
        if not vet_by_email:
            raise HTTPException(status_code=404, detail=f"No user found with email '{vet_email}'")
        if vet_by_email.role != UserRole.VET:
            raise HTTPException(status_code=400, detail="Requested user must be a VET")
        requested_vet = vet_by_email
        requested_vet_id = vet_by_email.id

    if not allow_assignment and requested_vet_id is None:
        raise HTTPException(
            status_code=400,
            detail="When allowAssignment is false, you must provide requestedVetId or vetEmail",
        )

    item.requested_vet_id = requested_vet_id
    if request_note is not None:
        item.request_note = request_note
    item.triage_status = TriageStatus.escalated if allow_assignment else TriageStatus.needs_review

    _create_event(db, item.id, current_user.id, "case_escalated", {
        "message": "CAHW requested vet review",
        "requested_by": current_user.email,
        "allow_assignment": allow_assignment,
        "triage_status": item.triage_status.value,
        "requested_vet_id": requested_vet_id,
        "requested_vet_email": requested_vet.email if requested_vet else None,
        "request_note": request_note,
    })
    db.commit()
    return {
        "status": "ok",
        "triage_status": item.triage_status.value,
        "allow_assignment": allow_assignment,
        "requested_vet_id": requested_vet_id,
    }


@router.post("/{case_id}/transfer-vet", response_model=CaseOut)
def transfer_vet(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Reassign a case to a different vet. VET can transfer their own; ADMIN can transfer any."""
    if current_user.role not in {UserRole.VET, UserRole.ADMIN}:
        raise HTTPException(status_code=403, detail="Only vets or admins can transfer cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    if current_user.role == UserRole.VET:
        _ensure_assigned_vet_lock(item, current_user, require_assignment=True)

    new_vet_email = (body.get("newVetEmail") or "").strip()
    if not new_vet_email:
        raise HTTPException(status_code=400, detail="newVetEmail is required")

    new_vet = db.scalar(select(User).where(User.email == new_vet_email))
    if not new_vet:
        raise HTTPException(status_code=404, detail=f"No user found with email '{new_vet_email}'")
    if new_vet.role != UserRole.VET:
        raise HTTPException(status_code=400, detail="Target user is not a VET")

    # Prevent transferring to self
    if new_vet.id == item.assigned_to_user_id:
        raise HTTPException(status_code=400, detail="Case is already assigned to this vet")

    prev_assignee = item.assigned_to_user_id
    item.assigned_to_user_id = new_vet.id
    item.triage_status = TriageStatus.needs_review
    item.accepted_at = None  # new vet must re-acknowledge

    _create_event(db, item.id, current_user.id, "vet_transferred", {
        "from_user_id": prev_assignee,
        "to_user_id": new_vet.id,
        "to_vet_name": new_vet.name,
        "to_vet_email": new_vet_email,
        "reason": (body.get("reason") or "").strip() or None,
        "message": (body.get("message") or "").strip() or None,
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.post("/{case_id}/vet/review", response_model=CaseOut)
def vet_review(
    case_id: str,
    payload: VetReviewRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Submit a structured veterinary review with assessment, plan, and prescription."""
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only assigned vets can submit reviews")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_assigned_vet_lock(item, current_user, require_assignment=True)

    # Store structured review separately from free-text notes
    review_data = {
        "assessment": payload.assessment,
        "diagnosis": payload.diagnosis,
        "plan": payload.plan,
        "prescription": payload.prescription,
        "follow_up_date": payload.follow_up_date.isoformat() if payload.follow_up_date else None,
        "message": payload.message,
        "reviewed_at": datetime.utcnow().isoformat(),
        "reviewed_by": current_user.id,
    }
    item.vet_review_json = review_data

    # Mirror confirmed diagnosis to corrected_label for analytics
    if payload.diagnosis:
        item.corrected_label = payload.diagnosis.strip()

    if payload.follow_up_date:
        item.followup_date = payload.follow_up_date

    item.status = CaseStatus.in_treatment
    item.triage_status = TriageStatus.needs_review

    _create_event(db, item.id, current_user.id, "vet_review_submitted", {
        "assessment": payload.assessment,
        "diagnosis": payload.diagnosis,
        "plan": payload.plan,
        "prescription": payload.prescription,
        "follow_up_date": payload.follow_up_date.isoformat() if payload.follow_up_date else None,
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.patch("/{case_id}/notes", response_model=CaseOut)
def update_notes(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update the notes field of a case. Accessible by CAHW (own cases) and VET/ADMIN."""
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    if current_user.role == UserRole.VET:
        _ensure_assigned_vet_lock(item, current_user, require_assignment=False)

    notes_val = (body.get("notes") or "").strip() or None
    item.notes = notes_val
    _create_event(db, item.id, current_user.id, "notes_updated", {"notes": notes_val})
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.patch("/{case_id}/follow-up", response_model=CaseOut)
def update_follow_up(
    case_id: str,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Update the follow-up status or date of a case. Accessible by CAHW and VET/ADMIN."""
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    if current_user.role == UserRole.VET:
        _ensure_assigned_vet_lock(item, current_user, require_assignment=False)

    follow_up_status = (body.get("followUpStatus") or "").strip()
    follow_up_date_str = (body.get("followUpDate") or "").strip()

    if follow_up_status:
        status_map = {
            "completed": CaseStatus.resolved,
            "resolved": CaseStatus.resolved,
            "in_treatment": CaseStatus.in_treatment,
            "open": CaseStatus.open,
        }
        new_status = status_map.get(follow_up_status.lower())
        if new_status:
            item.status = new_status
            # Set resolved_at when case is marked complete
            if new_status == CaseStatus.resolved and item.resolved_at is None:
                item.resolved_at = datetime.utcnow()

    if follow_up_date_str:
        try:
            item.followup_date = datetime.fromisoformat(follow_up_date_str)
        except ValueError:
            pass

    _create_event(db, item.id, current_user.id, "follow_up_updated", {
        "follow_up_status": follow_up_status,
        "follow_up_date": follow_up_date_str,
    })
    db.commit()
    db.refresh(item)
    return _case_out(item, db)


@router.delete("/{case_id}", status_code=204)
def delete_case(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Permanently delete a case. Admin only."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can delete cases")

    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")

    db.delete(item)
    db.commit()


@router.get("/{case_id}/export")
def export_case(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Export a structured case summary."""
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    submitted = db.get(User, item.submitted_by_user_id)
    assigned = db.get(User, item.assigned_to_user_id) if item.assigned_to_user_id else None
    prediction = item.prediction_json or {}

    return {
        "case_id": item.id,
        "client_case_id": item.client_case_id,
        "created_at": item.created_at.isoformat(),
        "status": item.status.value,
        "triage_status": item.triage_status.value,
        "risk_level": item.risk_level.value,
        "urgent": item.urgent,
        "triaged_at": item.triaged_at.isoformat() if item.triaged_at else None,
        "accepted_at": item.accepted_at.isoformat() if item.accepted_at else None,
        "resolved_at": item.resolved_at.isoformat() if item.resolved_at else None,
        "animal": {
            "id": item.animal_id,
            "tag": item.animal.tag if item.animal else None,
        },
        "submitted_by": {
            "id": item.submitted_by_user_id,
            "name": submitted.name if submitted else None,
        },
        "assigned_to": {
            "id": item.assigned_to_user_id,
            "name": assigned.name if assigned else None,
        } if assigned else None,
        "symptoms": item.symptoms_json or {},
        "prediction": {
            "label": prediction.get("final_label") or prediction.get("label"),
            "display_label": prediction.get("display_label"),
            "confidence": prediction.get("confidence"),
            "method": prediction.get("method"),
            "risk_level": prediction.get("risk_level"),
            "reasoning": prediction.get("reasoning"),
            "recommendations": prediction.get("recommendations", []),
        },
        "vet_review": item.vet_review_json,
        "rejection_reason": item.rejection_reason,
        "image_url": item.image_url,
        "notes": item.notes,
        "corrected_label": item.corrected_label,
        "followup_date": item.followup_date.isoformat() if item.followup_date else None,
    }


@router.get("/{case_id}/timeline")
def case_timeline(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return the event timeline for a case in a Flutter-compatible format.

    Top-level keys:
      messages       — chat messages (event_type == "message")
      reviews        — vet review events (event_type == "vet_review_submitted")
      receipts       — workflow status-change events
      workflowStatus — current case status string
      participants   — {chwOwner, assignedVet} name/email dicts
      events         — raw event list (backward-compat for dashboard)
    """
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_case_access(item, current_user)

    events = db.scalars(
        select(CaseEvent).where(CaseEvent.case_id == case_id).order_by(CaseEvent.created_at.asc())
    ).all()

    _RECEIPT_TYPES = {"sent_to_vet", "case_acknowledged", "case_closed", "case_rejected"}

    messages: list[dict] = []
    reviews: list[dict] = []
    receipts: list[dict] = []
    event_list: list[dict] = []

    for e in events:
        payload = e.payload_json or {}
        base = {
            "id": e.id,
            "case_id": e.case_id,
            "actor_user_id": e.actor_user_id,
            "event_type": e.event_type,
            "payload_json": payload,
            "created_at": e.created_at.isoformat(),
        }
        event_list.append(base)

        if e.event_type == "message":
            messages.append({
                "id": e.id,
                "senderRole": payload.get("sender_role"),
                "senderName": payload.get("sender_name"),
                "senderEmail": payload.get("sender_email"),
                "message": payload.get("message", ""),
                "createdAt": e.created_at.isoformat(),
            })
        elif e.event_type == "vet_review_submitted":
            reviews.append(base)
        elif e.event_type in _RECEIPT_TYPES:
            receipts.append(base)

    # Chat privacy: messages are only visible to the CAHW submitter and the assigned VET.
    # ADMIN sees only the audit event_list (not the private chat).
    is_chat_participant = (
        current_user.role == UserRole.CAHW and item.submitted_by_user_id == current_user.id
    ) or (
        current_user.role == UserRole.VET and item.assigned_to_user_id == current_user.id
    )
    if not is_chat_participant:
        messages = []

    # Build participants from user records
    chw_user = db.get(User, item.submitted_by_user_id)
    vet_user = db.get(User, item.assigned_to_user_id) if item.assigned_to_user_id else None
    requested_vet_user = db.get(User, item.requested_vet_id) if item.requested_vet_id else None

    participants: dict[str, Any] = {
        "chwOwner": {
            "id": chw_user.id if chw_user else None,
            "name": chw_user.name if chw_user else None,
            "email": chw_user.email if chw_user else None,
        },
        "assignedVet": {
            "id": vet_user.id if vet_user else None,
            "name": vet_user.name if vet_user else None,
            "email": vet_user.email if vet_user else None,
        } if vet_user else None,
        "requestedVet": {
            "id": requested_vet_user.id if requested_vet_user else None,
            "name": requested_vet_user.name if requested_vet_user else None,
            "email": requested_vet_user.email if requested_vet_user else None,
        } if requested_vet_user else None,
    }

    return {
        "case_id": case_id,
        "workflowStatus": item.status.value if item.status else "open",
        "triageStatus": item.triage_status.value if item.triage_status else "open",
        "assignedVetId": item.assigned_to_user_id,
        "messages": messages,
        "reviews": reviews,
        "receipts": receipts,
        "participants": participants,
        "events": event_list,
    }


@router.post("/{case_id}/feedback", response_model=FeedbackOut)
def add_feedback(
    case_id: str,
    payload: FeedbackRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Submit model accuracy feedback. VET only; syncs corrected_label to case record."""
    if current_user.role != UserRole.VET:
        raise HTTPException(status_code=403, detail="Only assigned vets can submit feedback")
    item = db.get(Case, case_id)
    if not item:
        raise HTTPException(status_code=404, detail="Case not found")
    _ensure_assigned_vet_lock(item, current_user, require_assignment=True)
    if payload.was_correct is False and not (payload.corrected_label or "").strip():
        raise HTTPException(status_code=400, detail="corrected_label is required when marking prediction incorrect")

    feedback = Feedback(
        case_id=case_id,
        user_id=current_user.id,
        was_correct=payload.was_correct,
        corrected_label=payload.corrected_label,
        comment=payload.comment,
    )
    db.add(feedback)

    # Single authoritative sync: corrected_label flows back to the case record
    if payload.corrected_label and payload.corrected_label.strip():
        item.corrected_label = payload.corrected_label.strip()

    _create_event(
        db, case_id, current_user.id, "feedback_submitted",
        {"was_correct": payload.was_correct, "corrected_label": payload.corrected_label},
    )
    db.commit()
    db.refresh(feedback)
    return feedback
