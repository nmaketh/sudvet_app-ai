from __future__ import annotations

import json
import uuid
from typing import Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile
from pydantic import ValidationError

from app.case_helpers import _case_export_payload, _case_from_row, _disease_from_prediction, _gradcam_svg_for_case
from app.db import db_conn
from app.inference import _predict_with_external_service
from app.jobs import _enqueue_job, _job_owned_by_user, _job_status_payload
from app.schemas import CaseCreateRequest, FollowUpUpdateRequest, NotesUpdateRequest
from app.security import get_current_user, now_iso

router = APIRouter(tags=['cases'])




@router.get("/cases")
def list_cases(
    query: str = Query(default=""),
    animalId: str | None = Query(default=None),
    status: str | None = Query(default=None),
    disease: str | None = Query(default=None),
    limit: int | None = Query(default=None),
    current_user: dict[str, Any] = Depends(get_current_user),
) -> list[dict[str, Any]]:
    user_id = current_user["id"]
    clauses: list[str] = []
    args: list[Any] = [user_id]

    clauses.append("userId = ?")

    if animalId:
        clauses.append("animalId = ?")
        args.append(animalId)
    if status:
        clauses.append("status = ?")
        args.append(status)
    if query.strip():
        normalized = f"%{query.strip().lower()}%"
        clauses.append(
            "(LOWER(id) LIKE ? OR LOWER(COALESCE(animalName,'')) LIKE ? OR LOWER(COALESCE(animalTag,'')) LIKE ? OR LOWER(COALESCE(predictionJson,'')) LIKE ?)"
        )
        args.extend([normalized, normalized, normalized, normalized])

    where_clause = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    limit_clause = f"LIMIT {limit}" if limit and limit > 0 else ""

    with db_conn() as conn:
        rows = conn.execute(
            f"""
            SELECT *
            FROM cases
            {where_clause}
            ORDER BY createdAt DESC
            {limit_clause}
            """,
            tuple(args),
        ).fetchall()

    mapped = [_case_from_row(row) for row in rows]
    if disease and disease != "all":
        mapped = [item for item in mapped if _disease_from_prediction(item.get("predictionJson")) == disease]
    return mapped


@router.get("/cases/pending-count")
def pending_count(current_user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS count FROM cases WHERE status = 'pending' AND userId = ?",
            (user_id,),
        ).fetchone()
    return {"count": int(row["count"]) if row is not None else 0}


@router.get("/jobs/{job_id}")
def get_job_status(
    job_id: str,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        row = conn.execute(
            """
            SELECT id, type, payload_json, status, error_message, created_at, started_at, finished_at
            FROM background_jobs
            WHERE id = ?
            """,
            (job_id,),
        ).fetchone()
        if row is None or not _job_owned_by_user(row, user_id):
            raise HTTPException(status_code=404, detail="Job not found.")
    return _job_status_payload(row)


@router.get("/cases/{case_id}/export")
def export_case_summary(
    case_id: str,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        row = conn.execute(
            "SELECT * FROM cases WHERE id = ? AND userId = ?",
            (case_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Case not found.")
    return _case_export_payload(row)


@router.get("/cases/{case_id}/gradcam")
def case_gradcam(case_id: str, current_user: dict[str, Any] = Depends(get_current_user)) -> Response:
    user_id = current_user["id"]
    with db_conn() as conn:
        row = conn.execute(
            "SELECT id, userId, symptomsJson FROM cases WHERE id = ? AND userId = ?",
            (case_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Case not found.")
    svg = _gradcam_svg_for_case(row)
    return Response(content=svg, media_type="image/svg+xml")


@router.get("/cases/{case_id}")
def get_case(case_id: str, _: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    user_id = _["id"]
    with db_conn() as conn:
        row = conn.execute(
            "SELECT * FROM cases WHERE id = ? AND userId = ?",
            (case_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Case not found.")
    return _case_from_row(row)


@router.post("/cases")
async def create_case(
    request: Request,
    payload_json: str = Form(..., alias="payload", description="JSON-encoded CaseCreateRequest"),
    files: list[UploadFile] | None = File(default=None),
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    try:
        raw_payload = json.loads(payload_json)
    except (json.JSONDecodeError, ValueError) as ex:
        raise HTTPException(status_code=400, detail=f"Invalid JSON in payload field: {ex}") from ex

    try:
        payload = CaseCreateRequest.model_validate(raw_payload)
    except ValidationError as ex:
        raise HTTPException(status_code=422, detail=ex.errors()) from ex

    case_id = str(uuid.uuid4())
    created_at = now_iso()
    user_id = current_user["id"]

    animal_name: str | None = None
    animal_tag: str | None = None
    with db_conn() as conn:
        if payload.animalId:
            animal = conn.execute(
                "SELECT name, tag FROM animals WHERE id = ? AND userId = ?",
                (payload.animalId, user_id),
            ).fetchone()
            if animal is None:
                raise HTTPException(status_code=404, detail="Animal not found.")
            animal_name = animal["name"]
            animal_tag = animal["tag"]

        prediction_json: dict[str, Any] | None = None
        status = "pending"
        synced_at: str | None = None

        if payload.shouldAttemptSync:
            prediction_json = _predict_with_external_service(
                symptoms=payload.symptoms,
                temperature=payload.temperature,
                image_path=payload.imagePath,
                animal_id=payload.animalId,
            )
            if not prediction_json.get("gradcamPath"):
                prediction_json["gradcamPath"] = (
                    f"{str(request.base_url).rstrip('/')}/cases/{case_id}/gradcam"
                )
            status = "synced"
            synced_at = now_iso()

        conn.execute(
            """
            INSERT INTO cases(
              id, userId, animalId, animalName, animalTag, createdAt, imagePath, symptomsJson, status,
              predictionJson, followUpStatus, followUpDate, notes, syncedAt, temperature, severity, attachmentsJson
            )
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                case_id,
                user_id,
                payload.animalId,
                animal_name,
                animal_tag,
                created_at,
                payload.imagePath,
                json.dumps(payload.symptoms),
                status,
                json.dumps(prediction_json) if prediction_json else None,
                "open",
                None,
                payload.notes.strip() if payload.notes else None,
                synced_at,
                payload.temperature,
                payload.severity,
                json.dumps(payload.attachments),
            ),
        )

        row = conn.execute(
            "SELECT * FROM cases WHERE id = ? AND userId = ?",
            (case_id, user_id),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to create case.")

    return {
        "case": _case_from_row(row),
        "syncedImmediately": payload.shouldAttemptSync,
        "warningMessage": None,
    }


@router.post("/cases/{case_id}/sync")
def sync_case(
    case_id: str,
    request: Request,
    asyncMode: bool = Query(default=False),
    _: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = _["id"]
    gradcam_path = f"{str(request.base_url).rstrip('/')}/cases/{case_id}/gradcam"
    with db_conn() as conn:
        row = conn.execute(
            "SELECT * FROM cases WHERE id = ? AND userId = ?",
            (case_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Case not found.")
        if asyncMode:
            job_id = _enqueue_job(
                conn,
                "sync_case",
                {
                    "caseId": case_id,
                    "userId": user_id,
                    "baseUrl": str(request.base_url).rstrip("/"),
                },
            )
            return {
                "queued": True,
                "jobId": job_id,
                "syncedCount": 0,
                "failedCount": 0,
                "errorMessage": None,
            }
        symptoms = json.loads(row["symptomsJson"] or "{}")
        prediction_json = _predict_with_external_service(
            symptoms=symptoms,
            temperature=row["temperature"],
            image_path=row["imagePath"],
            animal_id=row["animalId"],
        )
        if not prediction_json.get("gradcamPath"):
            prediction_json["gradcamPath"] = gradcam_path
        conn.execute(
            """
            UPDATE cases
            SET predictionJson = ?, status = 'synced', syncedAt = ?
            WHERE id = ? AND userId = ?
            """,
            (json.dumps(prediction_json), now_iso(), case_id, user_id),
        )
    return {"syncedCount": 1, "failedCount": 0, "errorMessage": None}


@router.post("/cases/sync-pending")
def sync_pending(
    request: Request,
    asyncMode: bool = Query(default=False),
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    synced_count = 0
    queued_job_ids: list[str] = []
    with db_conn() as conn:
        rows = conn.execute(
            "SELECT id, symptomsJson, temperature, imagePath, animalId FROM cases WHERE status = 'pending' AND userId = ?",
            (user_id,),
        ).fetchall()
        if asyncMode:
            for row in rows:
                job_id = _enqueue_job(
                    conn,
                    "sync_case",
                    {
                        "caseId": row["id"],
                        "userId": user_id,
                        "baseUrl": str(request.base_url).rstrip("/"),
                    },
                )
                queued_job_ids.append(job_id)
            return {
                "queued": True,
                "queuedCount": len(queued_job_ids),
                "jobIds": queued_job_ids,
                "syncedCount": 0,
                "failedCount": 0,
                "errorMessage": None,
            }
        for row in rows:
            symptoms = json.loads(row["symptomsJson"] or "{}")
            prediction_json = _predict_with_external_service(
                symptoms=symptoms,
                temperature=row["temperature"],
                image_path=row["imagePath"],
                animal_id=row["animalId"],
            )
            if not prediction_json.get("gradcamPath"):
                prediction_json["gradcamPath"] = (
                    f"{str(request.base_url).rstrip('/')}/cases/{row['id']}/gradcam"
                )
            conn.execute(
                """
                UPDATE cases
                SET predictionJson = ?, status = 'synced', syncedAt = ?
                WHERE id = ? AND userId = ?
                """,
                (json.dumps(prediction_json), now_iso(), row["id"], user_id),
            )
            synced_count += 1

    return {"syncedCount": synced_count, "failedCount": 0, "errorMessage": None}


@router.patch("/cases/{case_id}/follow-up")
def update_follow_up(
    case_id: str,
    payload: FollowUpUpdateRequest,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        result = conn.execute(
            "UPDATE cases SET followUpStatus = ? WHERE id = ? AND userId = ?",
            (payload.followUpStatus, case_id, user_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Case not found.")
    return {"ok": True}


@router.patch("/cases/{case_id}/notes")
def update_notes(
    case_id: str,
    payload: NotesUpdateRequest,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        result = conn.execute(
            "UPDATE cases SET notes = ? WHERE id = ? AND userId = ?",
            (payload.notes.strip(), case_id, user_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Case not found.")
    return {"ok": True}


@router.delete("/cases/{case_id}")
def delete_case(case_id: str, current_user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        result = conn.execute("DELETE FROM cases WHERE id = ? AND userId = ?", (case_id, user_id))
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Case not found.")
    return {"ok": True}
