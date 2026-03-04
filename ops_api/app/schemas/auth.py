from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models.models import UserRole


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str = Field(min_length=8)
    location: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthUser(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: EmailStr
    role: UserRole
    location: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: AuthUser


class RefreshRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    refresh_token: str = Field(alias="refreshToken")


# OTP signup flow

class SignupRequest(BaseModel):
    name: str
    email: EmailStr
    password: str = Field(min_length=8)
    location: str | None = None


class SignupOtpResponse(BaseModel):
    signupToken: str
    email: str
    expiresInSeconds: int
    otpRequired: bool = True
    # Populated only when SMTP is not configured (dev/test mode)
    devOtp: str | None = None


class VerifySignupRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    signup_token: str = Field(alias="signupToken")
    otp: str


class ResendOtpRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    signup_token: str = Field(alias="signupToken")


# Password reset flow

class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    resetToken: str
    expiresInSeconds: int
    # Populated only when SMTP is not configured (dev/test mode)
    devOtp: str | None = None


class VerifyResetOtpRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    reset_token: str = Field(alias="resetToken")
    otp: str


class ResetPasswordRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    reset_token: str = Field(alias="resetToken")
    otp: str
    new_password: str = Field(min_length=8, alias="newPassword")
