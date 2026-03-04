from __future__ import annotations

from pydantic import BaseModel, Field

class RegisterRequest(BaseModel):
    name: str
    email: str
    password: str = Field(min_length=8)


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshTokenRequest(BaseModel):
    refreshToken: str


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    resetToken: str
    otp: str
    newPassword: str = Field(min_length=8)


class VerifySignupOtpRequest(BaseModel):
    signupToken: str
    otp: str


class ResendSignupOtpRequest(BaseModel):
    signupToken: str


class AnimalCreateRequest(BaseModel):
    name: str | None = None
    dob: str | None = None
    location: str | None = None
    notes: str | None = None


class CaseCreateRequest(BaseModel):
    animalId: str | None = None
    symptoms: dict[str, bool]
    temperature: float | None = None
    severity: float | None = None
    imagePath: str | None = None
    attachments: list[str] = Field(default_factory=list)
    notes: str | None = None
    shouldAttemptSync: bool = True


class FollowUpUpdateRequest(BaseModel):
    followUpStatus: str


class NotesUpdateRequest(BaseModel):
    notes: str


class PredictRequest(BaseModel):
    symptoms: dict[str, bool]
    temperature: float | None = None
    imagePath: str | None = None
    animalId: str | None = None


class AsyncCaseSyncRequest(BaseModel):
    caseId: str


class JobStatusResponse(BaseModel):
    id: str
    type: str
    status: str
    errorMessage: str | None = None
    createdAt: str
    startedAt: str | None = None
    finishedAt: str | None = None
