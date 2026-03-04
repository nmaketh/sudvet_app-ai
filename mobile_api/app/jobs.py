from __future__ import annotations

import json
import sqlite3
import threading
from typing import Any

from .db import db_conn
from .inference import _predict_with_external_service
from .otp import _deliver_otp
from .security import _new_job_id, now_iso

_job_worker_thread: threading.Thread | None = None
_job_worker_stop = threading.Event()
_job_worker_lock = threading.Lock()

def _enqueue_job(conn: sqlite3.Connection, job_type: str, payload: dict[str, Any]) -> str:
    job_id = _new_job_id()
    conn.execute(
        """
        INSERT INTO background_jobs(id, type, payload_json, status, error_message, created_at, started_at, finished_at)
        VALUES(?,?,?,?,?,?,?,?)
        """,
        (job_id, job_type, json.dumps(payload), "pending", None, now_iso(), None, None),
    )
    return job_id


def _job_status_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "type": row["type"],
        "status": row["status"],
        "errorMessage": row["error_message"],
        "createdAt": row["created_at"],
        "startedAt": row["started_at"],
        "finishedAt": row["finished_at"],
    }


def _job_owned_by_user(row: sqlite3.Row, user_id: str) -> bool:
    payload_raw = row["payload_json"]
    if not payload_raw:
        return False
    try:
        payload = json.loads(payload_raw)
    except json.JSONDecodeError:
        return False
    if not isinstance(payload, dict):
        return False
    return str(payload.get("userId", "")).strip() == user_id


def _next_pending_job(conn: sqlite3.Connection) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT id, type, payload_json
        FROM background_jobs
        WHERE status = 'pending'
        ORDER BY created_at ASC
        LIMIT 1
        """
    ).fetchone()


def _process_background_job(job_type: str, payload: dict[str, Any]) -> None:
    if job_type == "send_otp_email":
        _deliver_otp(
            email=str(payload.get("email", "")),
            otp=str(payload.get("otp", "")),
            purpose=str(payload.get("purpose", "signup")),
        )
        return

    if job_type == "sync_case":
        case_id = str(payload.get("caseId", ""))
        user_id = str(payload.get("userId", ""))
        base_url = str(payload.get("baseUrl", "")).rstrip("/")
        if not case_id or not user_id:
            raise ValueError("sync_case payload missing caseId/userId")
        with db_conn() as conn:
            row = conn.execute(
                "SELECT * FROM cases WHERE id = ? AND userId = ?",
                (case_id, user_id),
            ).fetchone()
            if row is None:
                raise ValueError("Case not found for async sync.")
            symptoms = json.loads(row["symptomsJson"] or "{}")
            prediction_json = _predict_with_external_service(
                symptoms=symptoms,
                temperature=row["temperature"],
                image_path=row["imagePath"],
                animal_id=row["animalId"],
            )
            if not prediction_json.get("gradcamPath"):
                if base_url:
                    prediction_json["gradcamPath"] = f"{base_url}/cases/{case_id}/gradcam"
                else:
                    prediction_json["gradcamPath"] = f"/cases/{case_id}/gradcam"
            conn.execute(
                """
                UPDATE cases
                SET predictionJson = ?, status = 'synced', syncedAt = ?
                WHERE id = ? AND userId = ?
                """,
                (json.dumps(prediction_json), now_iso(), case_id, user_id),
            )
        return

    raise ValueError(f"Unsupported job type: {job_type}")


def _job_worker_loop() -> None:
    while not _job_worker_stop.is_set():
        claimed_job: sqlite3.Row | None = None
        try:
            with db_conn() as conn:
                job = _next_pending_job(conn)
                if job is None:
                    pass
                else:
                    conn.execute(
                        "UPDATE background_jobs SET status = 'running', started_at = ? WHERE id = ?",
                        (now_iso(), job["id"]),
                    )
                    claimed_job = job
        except Exception:
            # Keep worker alive even if one cycle fails.
            pass
        if claimed_job is not None:
            try:
                payload = json.loads(claimed_job["payload_json"] or "{}")
                if not isinstance(payload, dict):
                    payload = {}
                _process_background_job(claimed_job["type"], payload)
                with db_conn() as conn:
                    conn.execute(
                        """
                        UPDATE background_jobs
                        SET status = 'completed', finished_at = ?, error_message = NULL
                        WHERE id = ?
                        """,
                        (now_iso(), claimed_job["id"]),
                    )
            except Exception as exc:
                with db_conn() as conn:
                    conn.execute(
                        """
                        UPDATE background_jobs
                        SET status = 'failed', finished_at = ?, error_message = ?
                        WHERE id = ?
                        """,
                        (now_iso(), str(exc), claimed_job["id"]),
                    )
        _job_worker_stop.wait(0.8)


def _start_job_worker() -> None:
    global _job_worker_thread
    with _job_worker_lock:
        if _job_worker_thread is not None and _job_worker_thread.is_alive():
            return
        _job_worker_stop.clear()
        _job_worker_thread = threading.Thread(
            target=_job_worker_loop,
            name="background-job-worker",
            daemon=True,
        )
        _job_worker_thread.start()


def _stop_job_worker() -> None:
    _job_worker_stop.set()
