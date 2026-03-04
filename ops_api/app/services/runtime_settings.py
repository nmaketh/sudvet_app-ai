from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.core.config import settings as app_config
from app.models.models import AppSetting


VET_CAN_VIEW_ALL_KEY = "vet_can_view_all"


def _coerce_bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    return default


def get_setting_row(db: Session, key: str) -> AppSetting | None:
    bind = db.get_bind()
    if not inspect(bind).has_table(AppSetting.__tablename__):
        AppSetting.__table__.create(bind, checkfirst=True)
    return db.scalar(select(AppSetting).where(AppSetting.key == key))


def get_bool_setting(db: Session, key: str, default: bool) -> bool:
    row = get_setting_row(db, key)
    if row is None:
        return default
    return _coerce_bool(row.value_json, default)


def set_bool_setting(db: Session, key: str, value: bool, updated_by_user_id: int | None = None) -> AppSetting:
    row = get_setting_row(db, key)
    if row is None:
        row = AppSetting(key=key)
        db.add(row)
    row.value_json = bool(value)
    row.updated_by_user_id = updated_by_user_id
    row.updated_at = datetime.utcnow()
    db.flush()
    return row


def get_vet_can_view_all(db: Session) -> bool:
    return get_bool_setting(db, VET_CAN_VIEW_ALL_KEY, app_config.vet_can_view_all)


def build_dashboard_settings_payload(db: Session) -> dict[str, Any]:
    row = get_setting_row(db, VET_CAN_VIEW_ALL_KEY)
    effective_value = get_vet_can_view_all(db)
    cors_origins = [origin.strip() for origin in app_config.cors_origins.split(",") if origin.strip()]
    return {
        "policies": {
            "vet_can_view_all": effective_value,
        },
        "sources": {
            "vet_can_view_all": "database" if row is not None else "environment",
        },
        "integration": {
            "ml_service_url": app_config.ml_service_url or None,
            "ml_enabled": bool(app_config.ml_service_url),
            "public_base_url": app_config.public_base_url,
            "cors_origins": cors_origins,
        },
        "auth": {
            "strategy": "jwt_access_in_memory_refresh_persisted",
        },
        "metadata": {
            "environment": app_config.app_env,
            "updated_at": row.updated_at.isoformat() if row and row.updated_at else None,
        },
    }
