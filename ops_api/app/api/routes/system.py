from time import perf_counter
from datetime import datetime

from fastapi import APIRouter, Depends
import httpx
from sqlalchemy import text, select
from sqlalchemy.orm import Session

from app.core.dependencies import require_roles
from app.core.config import settings
from app.db.session import get_db
from app.models.models import ErrorLog, ModelVersion, User, UserRole


router = APIRouter(tags=["system"])


def _probe_ml_service():
    ml_url = (settings.ml_service_url or "").strip().rstrip("/")
    if not ml_url:
        return {"status": "disabled", "latency_ms": None, "url": None}

    health_url = f"{ml_url}/health"
    try:
        started = perf_counter()
        with httpx.Client(timeout=2.5) as client:
            resp = client.get(health_url)
        latency_ms = round((perf_counter() - started) * 1000, 2)
        if 200 <= resp.status_code < 300:
            return {"status": "up", "latency_ms": latency_ms, "url": health_url}
        return {"status": "degraded", "latency_ms": latency_ms, "url": health_url}
    except Exception:
        return {"status": "down", "latency_ms": None, "url": health_url}


@router.get("/health")
def health(db: Session = Depends(get_db)):
    db_ok = True
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        db_ok = False
    ml = _probe_ml_service()
    return {
        "status": "ok" if db_ok else "degraded",
        "api": "up",
        "db": "up" if db_ok else "down",
        "ml": ml["status"],
        "time": datetime.utcnow().isoformat(),
    }


@router.get("/models")
def models(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
):
    rows = db.scalars(select(ModelVersion).order_by(ModelVersion.updated_at.desc())).all()
    return [
        {
            "id": item.id,
            "type": item.type,
            "version": item.version,
            "metrics_json": item.metrics_json,
            "updated_at": item.updated_at.isoformat(),
        }
        for item in rows
    ]


@router.get("/jobs/{job_id}")
def get_job_status(
    job_id: str,
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
):
    """Stub job status endpoint. Returns 'done' for all job IDs."""
    return {"id": job_id, "status": "done", "result": None}


@router.get("/system/errors")
def recent_errors(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
):
    rows = db.scalars(select(ErrorLog).order_by(ErrorLog.created_at.desc()).limit(20)).all()
    return [
        {
            "id": item.id,
            "source": item.source,
            "message": item.message,
            "created_at": item.created_at.isoformat(),
        }
        for item in rows
    ]
