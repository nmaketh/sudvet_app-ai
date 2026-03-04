from datetime import datetime

from pydantic import BaseModel, EmailStr

from app.models.models import UserRole


class UserOut(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: UserRole
    location: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class AssignableUserOut(BaseModel):
    """VET user returned from /users/assignable, enriched with current caseload."""
    id: int
    name: str
    email: EmailStr
    role: UserRole
    location: str | None
    created_at: datetime
    active_caseload: int = 0  # open + in_treatment cases currently assigned to this vet

    class Config:
        from_attributes = True


class UpdateRoleRequest(BaseModel):
    role: UserRole


class UserStatsResponse(BaseModel):
    cases_submitted: int
    cases_handled: int
    avg_resolution_time_hours: float
