from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_roles
from app.db.session import get_db
from app.models.models import User, UserRole
from app.schemas.settings import DashboardSettingsOut, PatchDashboardPoliciesRequest
from app.services.runtime_settings import (
    VET_CAN_VIEW_ALL_KEY,
    build_dashboard_settings_payload,
    set_bool_setting,
)


router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=DashboardSettingsOut)
def get_dashboard_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Any authenticated dashboard user can inspect effective policy values.
    return build_dashboard_settings_payload(db)


@router.patch("", response_model=DashboardSettingsOut)
def patch_dashboard_settings(
    payload: PatchDashboardPoliciesRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
):
    set_bool_setting(
        db,
        key=VET_CAN_VIEW_ALL_KEY,
        value=payload.vet_can_view_all,
        updated_by_user_id=current_user.id,
    )
    db.commit()
    return build_dashboard_settings_payload(db)
