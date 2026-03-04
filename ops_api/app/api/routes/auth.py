import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from jose import JWTError
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.limiter import limiter
from app.core.otp import OTP_EXPIRE_SECONDS, OTP_MAX_RESENDS, generate_otp, send_otp_email
from app.core.security import (
    create_access_from_refresh,
    create_token_pair,
    decode_token,
    get_password_hash,
    is_refresh_token,
    verify_password,
)
from app.db.session import get_db
from app.models.models import User, UserRole
from app.schemas.auth import (
    AuthUser,
    ForgotPasswordRequest,
    ForgotPasswordResponse,
    LoginRequest,
    RegisterRequest,
    ResendOtpRequest,
    ResetPasswordRequest,
    SignupOtpResponse,
    SignupRequest,
    TokenResponse,
    VerifySignupRequest,
)

router = APIRouter(prefix="/auth", tags=["auth"])

def _is_production_env() -> bool:
    return (settings.app_env or "").strip().lower() == "production"


def _dev_otp_value(*, otp: str, email_sent: bool) -> str | None:
    if _is_production_env():
        return None
    return None if email_sent else otp


def _ensure_otp_delivery_configured() -> None:
    if _is_production_env() and not (settings.smtp_host or "").strip():
        raise HTTPException(status_code=503, detail="OTP email delivery is not configured")


@router.post("/register", response_model=AuthUser)
@limiter.limit("5/minute")
def register(
    request: Request,
    payload: RegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Admin-only direct registration — no OTP, returns AuthUser only (no tokens)."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Only admins can create users via /auth/register")

    exists = db.scalar(select(User).where(User.email == payload.email.lower().strip()))
    if exists:
        raise HTTPException(status_code=409, detail="Email already registered")

    user = User(
        name=payload.name.strip(),
        email=payload.email.lower().strip(),
        password_hash=get_password_hash(payload.password),
        role=UserRole.CAHW,
        location=payload.location,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ── OTP signup flow (used by Flutter mobile app) ─────────────────────────────

@router.post("/signup", response_model=SignupOtpResponse)
@limiter.limit("3/minute")
def signup_request_otp(request: Request, payload: SignupRequest, db: Session = Depends(get_db)):
    """Step 1: Request OTP for signup. Creates a pending OTP record.
    If SMTP is configured, sends the code by email.
    If SMTP is not configured (dev mode), returns the code in `devOtp`."""
    _ensure_otp_delivery_configured()
    email = payload.email.lower().strip()

    # Check existing confirmed user
    existing_user = db.scalar(select(User).where(User.email == email))
    if existing_user:
        raise HTTPException(status_code=409, detail="Email already registered")

    # Clean up any prior pending OTP for this email
    db.execute(text("DELETE FROM signup_otps WHERE email = :email"), {"email": email})

    otp = generate_otp()
    signup_token = str(uuid.uuid4())
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=OTP_EXPIRE_SECONDS)

    db.execute(
        text(
            """
            INSERT INTO signup_otps(id, signup_token, name, email, password_hash, otp_code, expires_at, created_at, resend_count)
            VALUES (:id, :signup_token, :name, :email, :password_hash, :otp_code, :expires_at, :created_at, 0)
            """
        ),
        {
            "id": str(uuid.uuid4()),
            "signup_token": signup_token,
            "name": payload.name.strip(),
            "email": email,
            "password_hash": get_password_hash(payload.password),
            "otp_code": otp,
            "expires_at": expires_at,
            "created_at": datetime.now(timezone.utc),
        },
    )
    db.commit()

    email_sent = send_otp_email(to_email=email, to_name=payload.name.strip(), otp=otp, purpose="signup")
    if _is_production_env() and not email_sent:
        raise HTTPException(status_code=503, detail="Unable to send OTP right now. Please try again.")

    return SignupOtpResponse(
        signupToken=signup_token,
        email=email,
        expiresInSeconds=OTP_EXPIRE_SECONDS,
        devOtp=_dev_otp_value(otp=otp, email_sent=email_sent),
    )


@router.post("/signup/verify", response_model=TokenResponse)
@limiter.limit("10/minute")
def signup_verify_otp(request: Request, payload: VerifySignupRequest, db: Session = Depends(get_db)):
    """Step 2: Verify OTP and create the user account. Returns a token pair."""
    row = db.execute(
        text("SELECT * FROM signup_otps WHERE signup_token = :token"),
        {"token": payload.signup_token},
    ).mappings().fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Signup session not found or already used")

    now = datetime.now(timezone.utc)
    expires_at = row["expires_at"]
    # SQLite returns datetime columns as strings; parse them when needed
    if isinstance(expires_at, str):
        expires_at = datetime.fromisoformat(expires_at)
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if now > expires_at:
        db.execute(text("DELETE FROM signup_otps WHERE signup_token = :token"), {"token": payload.signup_token})
        db.commit()
        raise HTTPException(status_code=410, detail="OTP has expired. Please start signup again")

    if row["otp_code"] != payload.otp.strip():
        raise HTTPException(status_code=400, detail="Incorrect OTP code")

    # Guard against race condition: check again for existing user
    existing = db.scalar(select(User).where(User.email == row["email"]))
    if existing:
        db.execute(text("DELETE FROM signup_otps WHERE signup_token = :token"), {"token": payload.signup_token})
        db.commit()
        raise HTTPException(status_code=409, detail="Email already registered")

    user = User(
        name=row["name"],
        email=row["email"],
        password_hash=row["password_hash"],
        role=UserRole.CAHW,
    )
    db.add(user)
    db.execute(text("DELETE FROM signup_otps WHERE signup_token = :token"), {"token": payload.signup_token})
    db.commit()
    db.refresh(user)

    access_token, refresh_token = create_token_pair(subject=str(user.id), role=user.role.value)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=AuthUser.model_validate(user),
    )


@router.post("/signup/resend")
@limiter.limit("2/minute")
def signup_resend_otp(request: Request, payload: ResendOtpRequest, db: Session = Depends(get_db)):
    """Resend the OTP code for an existing signup session."""
    _ensure_otp_delivery_configured()
    row = db.execute(
        text("SELECT * FROM signup_otps WHERE signup_token = :token"),
        {"token": payload.signup_token},
    ).mappings().fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Signup session not found")

    if row["resend_count"] >= OTP_MAX_RESENDS:
        raise HTTPException(status_code=429, detail="Maximum resend attempts reached. Please start signup again")

    otp = generate_otp()
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=OTP_EXPIRE_SECONDS)

    db.execute(
        text(
            """
            UPDATE signup_otps
            SET otp_code = :otp, expires_at = :expires_at, resend_count = resend_count + 1
            WHERE signup_token = :token
            """
        ),
        {"otp": otp, "expires_at": expires_at, "token": payload.signup_token},
    )
    db.commit()

    email_sent = send_otp_email(to_email=row["email"], to_name=row["name"], otp=otp, purpose="signup")
    if _is_production_env() and not email_sent:
        raise HTTPException(status_code=503, detail="Unable to send OTP right now. Please try again.")
    return {"ok": True, "devOtp": _dev_otp_value(otp=otp, email_sent=email_sent)}


# ── Standard auth endpoints ──────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
def login(request: Request, payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email.lower().strip()))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access_token, refresh_token = create_token_pair(subject=str(user.id), role=user.role.value)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token, user=AuthUser.model_validate(user))


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")
async def refresh(request: Request, db: Session = Depends(get_db)):
    try:
        body = await request.json()
    except Exception:
        body = {}
    refresh_token = (body.get("refresh_token") or body.get("refreshToken") or "").strip()
    if not refresh_token:
        raise HTTPException(status_code=422, detail="refresh_token is required")

    try:
        decoded = decode_token(refresh_token)
        if not is_refresh_token(decoded):
            raise HTTPException(status_code=401, detail="Invalid refresh token")
        user_id = decoded.get("sub")
        role = decoded.get("role")
        if not user_id or not role:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid refresh token") from exc

    user = db.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    access_token = create_access_from_refresh(subject=str(user.id), role=user.role.value)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token, user=AuthUser.model_validate(user))


@router.get("/me", response_model=AuthUser)
def me(current_user: User = Depends(get_current_user)):
    return current_user


# ── Password reset flow ───────────────────────────────────────────────────────

@router.post("/forgot-password", response_model=ForgotPasswordResponse)
@limiter.limit("3/minute")
def forgot_password(request: Request, payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Request a password reset OTP. Always returns 200 to avoid email enumeration."""
    _ensure_otp_delivery_configured()
    email = payload.email.lower().strip()

    # Clean up any prior pending reset for this email
    db.execute(text("DELETE FROM password_reset_otps WHERE email = :email"), {"email": email})

    user = db.scalar(select(User).where(User.email == email))

    # Always issue a token (even for unknown emails) to prevent enumeration
    otp = generate_otp()
    reset_token = str(uuid.uuid4())
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=OTP_EXPIRE_SECONDS)

    db.execute(
        text(
            """
            INSERT INTO password_reset_otps(id, reset_token, email, otp_code, expires_at, created_at, used)
            VALUES (:id, :reset_token, :email, :otp_code, :expires_at, :created_at, false)
            """
        ),
        {
            "id": str(uuid.uuid4()),
            "reset_token": reset_token,
            "email": email,
            "otp_code": otp,
            "expires_at": expires_at,
            "created_at": datetime.now(timezone.utc),
        },
    )
    db.commit()

    email_sent = False
    if user:
        email_sent = send_otp_email(to_email=email, to_name=user.name, otp=otp, purpose="password_reset")

    return ForgotPasswordResponse(
        resetToken=reset_token,
        expiresInSeconds=OTP_EXPIRE_SECONDS,
        devOtp=_dev_otp_value(otp=otp, email_sent=email_sent),
    )


@router.post("/reset-password")
@limiter.limit("5/minute")
def reset_password(request: Request, payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    """Verify OTP and set a new password."""
    row = db.execute(
        text("SELECT * FROM password_reset_otps WHERE reset_token = :token"),
        {"token": payload.reset_token},
    ).mappings().fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Reset session not found or already used")

    if row["used"]:
        raise HTTPException(status_code=410, detail="Reset token already used")

    now = datetime.now(timezone.utc)
    expires_at = row["expires_at"]
    if isinstance(expires_at, str):
        expires_at = datetime.fromisoformat(expires_at)
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if now > expires_at:
        db.execute(text("DELETE FROM password_reset_otps WHERE reset_token = :token"), {"token": payload.reset_token})
        db.commit()
        raise HTTPException(status_code=410, detail="OTP has expired. Please request a new one")

    if row["otp_code"] != payload.otp.strip():
        raise HTTPException(status_code=400, detail="Incorrect OTP code")

    user = db.scalar(select(User).where(User.email == row["email"]))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.password_hash = get_password_hash(payload.new_password)
    db.execute(text("DELETE FROM password_reset_otps WHERE reset_token = :token"), {"token": payload.reset_token})
    db.commit()

    return {"ok": True}


# ── Google OAuth ──────────────────────────────────────────────────────────────

@router.post("/google", response_model=TokenResponse)
@limiter.limit("10/minute")
def google_auth(
    request: Request,
    body: dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
):
    """Authenticate (or register) using a Google ID token.

    Accepts the ID token returned by Google Sign-In on the mobile app.
    - Existing users: returns a token pair for the matching email.
    - New users: creates a CAHW account and returns a token pair.
    - Requires GOOGLE_CLIENT_ID to be set; returns 503 if not configured.
    """
    if not settings.google_client_id:
        raise HTTPException(
            status_code=503,
            detail="Google sign-in is not configured on this server.",
        )

    token = (body.get("idToken") or body.get("credential") or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="idToken is required")

    # Verify the ID token with Google's public keys.
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token

        idinfo = google_id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            settings.google_client_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=f"Invalid Google token: {exc}") from exc

    email = (idinfo.get("email") or body.get("email") or "").lower().strip()
    name = (idinfo.get("name") or body.get("name") or "").strip()

    if not email:
        raise HTTPException(status_code=400, detail="Google account has no email address")

    # Find existing user or create a new CAHW account.
    user = db.scalar(select(User).where(User.email == email))
    if not user:
        # Google users get a random unusable password hash — they authenticate via
        # Google tokens, not passwords.  The password login endpoint will correctly
        # reject them because verify_password will always return False.
        user = User(
            name=name or email.split("@")[0],
            email=email,
            password_hash=get_password_hash(f"google-sso-{secrets.token_hex(32)}"),
            role=UserRole.CAHW,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    access_token, refresh_token = create_token_pair(subject=str(user.id), role=user.role.value)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=AuthUser.model_validate(user),
    )
