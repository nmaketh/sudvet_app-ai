from __future__ import annotations

from datetime import timedelta
import uuid
from typing import Any

from fastapi import APIRouter, HTTPException

from app.db import db_conn
from app.jobs import _enqueue_job
from app.otp import _enforce_otp_request_rate_limit
from app.schemas import (
    ForgotPasswordRequest,
    LoginRequest,
    RefreshTokenRequest,
    RegisterRequest,
    ResendSignupOtpRequest,
    ResetPasswordRequest,
    VerifySignupOtpRequest,
)
from app.security import (
    _issue_tokens,
    _new_otp,
    _new_reset_token,
    _new_signup_token,
    _normalize_email,
    _now_utc,
    _parse_iso,
    _seconds_until,
    hash_password,
    now_iso,
    verify_password,
)
from app.settings import (
    ACCESS_TOKEN_TTL_MINUTES,
    OTP_EXPIRY_MINUTES,
    OTP_LOCK_MINUTES,
    OTP_MAX_RESENDS_PER_CHALLENGE,
    OTP_MAX_VERIFY_ATTEMPTS,
    OTP_RESEND_COOLDOWN_SECONDS,
)

router = APIRouter(tags=['auth'])

@router.post("/auth/register")
@router.post("/auth/signup")
@router.post("/register")
@router.post("/signup")
def register(payload: RegisterRequest) -> dict[str, Any]:
    email = _normalize_email(payload.email)
    now = _now_utc()
    with db_conn() as conn:
        existing = conn.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if existing is not None:
            raise HTTPException(status_code=409, detail="Email already registered.")
        _enforce_otp_request_rate_limit(conn, email)
        signup_token = _new_signup_token()
        otp = _new_otp()
        expires_at = (now + timedelta(minutes=OTP_EXPIRY_MINUTES)).isoformat()
        conn.execute("DELETE FROM signup_otps WHERE email = ?", (email,))
        conn.execute(
            """
            INSERT INTO signup_otps(
              signup_token, name, email, password_hash, otp_code, expires_at, created_at,
              attempt_count, resend_count, last_sent_at, locked_until
            )
            VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                signup_token,
                payload.name.strip(),
                email,
                hash_password(payload.password),
                otp,
                expires_at,
                now_iso(),
                0,
                0,
                now.isoformat(),
                None,
            ),
        )
        delivery_job_id = _enqueue_job(
            conn,
            "send_otp_email",
            {"email": email, "otp": otp, "purpose": "signup"},
        )
    return {
        "otpRequired": True,
        "signupToken": signup_token,
        "email": email,
        "expiresInSeconds": OTP_EXPIRY_MINUTES * 60,
        "message": "OTP sent to your email.",
        "deliveryJobId": delivery_job_id,
    }


@router.post("/auth/signup/resend")
@router.post("/signup/resend")
def resend_signup_otp(payload: ResendSignupOtpRequest) -> dict[str, Any]:
    signup_token = payload.signupToken.strip()
    if not signup_token:
        raise HTTPException(status_code=400, detail="Invalid signup token.")
    now = _now_utc()

    with db_conn() as conn:
        row = conn.execute(
            """
            SELECT email, resend_count, last_sent_at, locked_until
            FROM signup_otps
            WHERE signup_token = ?
            """,
            (signup_token,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Signup session not found.")

        _enforce_otp_request_rate_limit(conn, row["email"])

        locked_until_raw = row["locked_until"]
        if locked_until_raw:
            locked_until = _parse_iso(locked_until_raw)
            if now < locked_until:
                wait_seconds = _seconds_until(locked_until, now)
                raise HTTPException(
                    status_code=429,
                    detail=f"OTP verification temporarily locked. Try again in {wait_seconds} seconds.",
                )

        resend_count = int(row["resend_count"] or 0)
        if resend_count >= OTP_MAX_RESENDS_PER_CHALLENGE:
            raise HTTPException(
                status_code=429,
                detail="Resend limit reached. Start signup again.",
            )

        last_sent_raw = row["last_sent_at"]
        if last_sent_raw:
            last_sent_at = _parse_iso(last_sent_raw)
            next_allowed = last_sent_at + timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS)
            if now < next_allowed:
                wait_seconds = _seconds_until(next_allowed, now)
                raise HTTPException(
                    status_code=429,
                    detail=f"Please wait {wait_seconds} seconds before requesting another OTP.",
                )

        otp = _new_otp()
        expires_at = (now + timedelta(minutes=OTP_EXPIRY_MINUTES)).isoformat()
        conn.execute(
            """
            UPDATE signup_otps
            SET otp_code = ?, expires_at = ?, resend_count = resend_count + 1,
                attempt_count = 0, last_sent_at = ?, locked_until = NULL
            WHERE signup_token = ?
            """,
            (otp, expires_at, now.isoformat(), signup_token),
        )
        delivery_job_id = _enqueue_job(
            conn,
            "send_otp_email",
            {"email": row["email"], "otp": otp, "purpose": "signup"},
        )
    return {
        "message": "A new OTP has been sent.",
        "expiresInSeconds": OTP_EXPIRY_MINUTES * 60,
        "deliveryJobId": delivery_job_id,
    }


@router.post("/auth/signup/verify")
@router.post("/signup/verify")
def verify_signup_otp(payload: VerifySignupOtpRequest) -> dict[str, Any]:
    signup_token = payload.signupToken.strip()
    otp = payload.otp.strip()
    if not signup_token:
        raise HTTPException(status_code=400, detail="Invalid signup token.")
    if not otp:
        raise HTTPException(status_code=400, detail="OTP is required.")

    with db_conn() as conn:
        pending = conn.execute(
            """
            SELECT signup_token, name, email, password_hash, otp_code, expires_at, attempt_count, locked_until
            FROM signup_otps
            WHERE signup_token = ?
            """,
            (signup_token,),
        ).fetchone()
        if pending is None:
            raise HTTPException(status_code=404, detail="Signup session not found.")

        now = _now_utc()
        locked_until_raw = pending["locked_until"]
        if locked_until_raw:
            locked_until = _parse_iso(locked_until_raw)
            if now < locked_until:
                wait_seconds = _seconds_until(locked_until, now)
                raise HTTPException(
                    status_code=429,
                    detail=f"OTP verification temporarily locked. Try again in {wait_seconds} seconds.",
                )

        expires_at = _parse_iso(pending["expires_at"])
        if now > expires_at:
            conn.execute("DELETE FROM signup_otps WHERE signup_token = ?", (signup_token,))
            raise HTTPException(status_code=400, detail="OTP expired. Request a new OTP.")

        if pending["otp_code"] != otp:
            attempt_count = int(pending["attempt_count"] or 0) + 1
            if attempt_count >= OTP_MAX_VERIFY_ATTEMPTS:
                lock_until = (now + timedelta(minutes=OTP_LOCK_MINUTES)).isoformat()
                conn.execute(
                    "UPDATE signup_otps SET attempt_count = ?, locked_until = ? WHERE signup_token = ?",
                    (attempt_count, lock_until, signup_token),
                )
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many invalid OTP attempts. Try again in {OTP_LOCK_MINUTES} minutes.",
                )
            conn.execute(
                "UPDATE signup_otps SET attempt_count = ? WHERE signup_token = ?",
                (attempt_count, signup_token),
            )
            raise HTTPException(status_code=400, detail="Invalid OTP code.")

        existing = conn.execute("SELECT id FROM users WHERE email = ?", (pending["email"],)).fetchone()
        if existing is not None:
            conn.execute("DELETE FROM signup_otps WHERE signup_token = ?", (signup_token,))
            raise HTTPException(status_code=409, detail="Email already registered.")

        user_id = str(uuid.uuid4())
        conn.execute(
            "INSERT INTO users(id, name, email, password_hash, created_at) VALUES(?,?,?,?,?)",
            (user_id, pending["name"], pending["email"], pending["password_hash"], now_iso()),
        )
        conn.execute("DELETE FROM signup_otps WHERE signup_token = ?", (signup_token,))

        token, refresh_token = _issue_tokens(conn, user_id)

    return {
        "token": token,
        "refreshToken": refresh_token,
        "accessTokenExpiresInSeconds": ACCESS_TOKEN_TTL_MINUTES * 60,
        "user": {"id": user_id, "name": pending["name"], "email": pending["email"]},
    }


@router.post("/auth/forgot-password")
@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest) -> dict[str, Any]:
    email = _normalize_email(payload.email)
    now = _now_utc()

    with db_conn() as conn:
        user = conn.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="Email not registered.")

        _enforce_otp_request_rate_limit(conn, email)

        existing = conn.execute(
            """
            SELECT reset_token, resend_count, last_sent_at, locked_until
            FROM password_reset_otps
            WHERE email = ?
            """,
            (email,),
        ).fetchone()

        if existing is not None:
            locked_until_raw = existing["locked_until"]
            if locked_until_raw:
                locked_until = _parse_iso(locked_until_raw)
                if now < locked_until:
                    wait_seconds = _seconds_until(locked_until, now)
                    raise HTTPException(
                        status_code=429,
                        detail=f"Reset verification temporarily locked. Try again in {wait_seconds} seconds.",
                    )

            last_sent_raw = existing["last_sent_at"]
            if last_sent_raw:
                last_sent_at = _parse_iso(last_sent_raw)
                next_allowed = last_sent_at + timedelta(seconds=OTP_RESEND_COOLDOWN_SECONDS)
                if now < next_allowed:
                    wait_seconds = _seconds_until(next_allowed, now)
                    raise HTTPException(
                        status_code=429,
                        detail=f"Please wait {wait_seconds} seconds before requesting another OTP.",
                    )

            resend_count = int(existing["resend_count"] or 0)
            if resend_count >= OTP_MAX_RESENDS_PER_CHALLENGE:
                raise HTTPException(
                    status_code=429,
                    detail="Reset request limit reached. Please try again later.",
                )

            reset_token = existing["reset_token"]
            otp = _new_otp()
            expires_at = (now + timedelta(minutes=OTP_EXPIRY_MINUTES)).isoformat()
            conn.execute(
                """
                UPDATE password_reset_otps
                SET otp_code = ?, expires_at = ?, resend_count = resend_count + 1,
                    attempt_count = 0, last_sent_at = ?, locked_until = NULL
                WHERE reset_token = ?
                """,
                (otp, expires_at, now.isoformat(), reset_token),
            )
        else:
            reset_token = _new_reset_token()
            otp = _new_otp()
            expires_at = (now + timedelta(minutes=OTP_EXPIRY_MINUTES)).isoformat()
            conn.execute(
                """
                INSERT INTO password_reset_otps(
                  reset_token, email, otp_code, expires_at, created_at, attempt_count,
                  resend_count, last_sent_at, locked_until
                )
                VALUES(?,?,?,?,?,?,?,?,?)
                """,
                (
                    reset_token,
                    email,
                    otp,
                    expires_at,
                    now_iso(),
                    0,
                    0,
                    now.isoformat(),
                    None,
                ),
            )
        delivery_job_id = _enqueue_job(
            conn,
            "send_otp_email",
            {"email": email, "otp": otp, "purpose": "reset"},
        )
    return {
        "resetToken": reset_token,
        "email": email,
        "expiresInSeconds": OTP_EXPIRY_MINUTES * 60,
        "message": "Password reset OTP sent.",
        "deliveryJobId": delivery_job_id,
    }


@router.post("/auth/reset-password")
@router.post("/reset-password")
def reset_password(payload: ResetPasswordRequest) -> dict[str, Any]:
    reset_token = payload.resetToken.strip()
    otp = payload.otp.strip()
    if not reset_token:
        raise HTTPException(status_code=400, detail="Invalid reset token.")
    if not otp:
        raise HTTPException(status_code=400, detail="OTP is required.")

    with db_conn() as conn:
        pending = conn.execute(
            """
            SELECT reset_token, email, otp_code, expires_at, attempt_count, locked_until
            FROM password_reset_otps
            WHERE reset_token = ?
            """,
            (reset_token,),
        ).fetchone()
        if pending is None:
            raise HTTPException(status_code=404, detail="Reset session not found.")

        now = _now_utc()
        locked_until_raw = pending["locked_until"]
        if locked_until_raw:
            locked_until = _parse_iso(locked_until_raw)
            if now < locked_until:
                wait_seconds = _seconds_until(locked_until, now)
                raise HTTPException(
                    status_code=429,
                    detail=f"Reset verification temporarily locked. Try again in {wait_seconds} seconds.",
                )

        expires_at = _parse_iso(pending["expires_at"])
        if now > expires_at:
            conn.execute("DELETE FROM password_reset_otps WHERE reset_token = ?", (reset_token,))
            raise HTTPException(status_code=400, detail="OTP expired. Request a new reset OTP.")

        if pending["otp_code"] != otp:
            attempt_count = int(pending["attempt_count"] or 0) + 1
            if attempt_count >= OTP_MAX_VERIFY_ATTEMPTS:
                lock_until = (now + timedelta(minutes=OTP_LOCK_MINUTES)).isoformat()
                conn.execute(
                    """
                    UPDATE password_reset_otps
                    SET attempt_count = ?, locked_until = ?
                    WHERE reset_token = ?
                    """,
                    (attempt_count, lock_until, reset_token),
                )
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many invalid OTP attempts. Try again in {OTP_LOCK_MINUTES} minutes.",
                )
            conn.execute(
                "UPDATE password_reset_otps SET attempt_count = ? WHERE reset_token = ?",
                (attempt_count, reset_token),
            )
            raise HTTPException(status_code=400, detail="Invalid OTP code.")

        user = conn.execute("SELECT id FROM users WHERE email = ?", (pending["email"],)).fetchone()
        if user is None:
            conn.execute("DELETE FROM password_reset_otps WHERE reset_token = ?", (reset_token,))
            raise HTTPException(status_code=404, detail="User not found.")

        conn.execute(
            "UPDATE users SET password_hash = ? WHERE id = ?",
            (hash_password(payload.newPassword), user["id"]),
        )
        conn.execute("DELETE FROM password_reset_otps WHERE reset_token = ?", (reset_token,))
        conn.execute("DELETE FROM auth_tokens WHERE user_id = ?", (user["id"],))
        conn.execute("DELETE FROM auth_refresh_tokens WHERE user_id = ?", (user["id"],))

    return {"message": "Password reset successful."}


@router.post("/auth/login")
@router.post("/login")
def login(payload: LoginRequest) -> dict[str, Any]:
    email = _normalize_email(payload.email)
    with db_conn() as conn:
        row = conn.execute(
            "SELECT id, name, email, password_hash FROM users WHERE email = ?",
            (email,),
        ).fetchone()
        if row is None or not verify_password(payload.password, row["password_hash"]):
            raise HTTPException(status_code=401, detail="Invalid credentials.")

        token, refresh_token = _issue_tokens(conn, row["id"])

    return {
        "token": token,
        "refreshToken": refresh_token,
        "accessTokenExpiresInSeconds": ACCESS_TOKEN_TTL_MINUTES * 60,
        "user": {"id": row["id"], "name": row["name"], "email": row["email"]},
    }


@router.post("/auth/refresh")
@router.post("/refresh")
def refresh_access_token(payload: RefreshTokenRequest) -> dict[str, Any]:
    refresh_token = payload.refreshToken.strip()
    if not refresh_token:
        raise HTTPException(status_code=400, detail="Refresh token is required.")

    with db_conn() as conn:
        row = conn.execute(
            """
            SELECT token, user_id, expires_at, revoked_at
            FROM auth_refresh_tokens
            WHERE token = ?
            """,
            (refresh_token,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="Invalid refresh token.")

        if row["revoked_at"] is not None:
            raise HTTPException(status_code=401, detail="Refresh token revoked.")

        expires_at = _parse_iso(row["expires_at"])
        if _now_utc() >= expires_at:
            conn.execute("DELETE FROM auth_refresh_tokens WHERE token = ?", (refresh_token,))
            raise HTTPException(status_code=401, detail="Refresh token expired.")

        user = conn.execute(
            "SELECT id, name, email FROM users WHERE id = ?",
            (row["user_id"],),
        ).fetchone()
        if user is None:
            conn.execute(
                "DELETE FROM auth_refresh_tokens WHERE token = ?",
                (refresh_token,),
            )
            raise HTTPException(status_code=401, detail="User not found.")

        conn.execute(
            "UPDATE auth_refresh_tokens SET revoked_at = ? WHERE token = ?",
            (now_iso(), refresh_token),
        )
        token, new_refresh_token = _issue_tokens(conn, user["id"])

    return {
        "token": token,
        "refreshToken": new_refresh_token,
        "accessTokenExpiresInSeconds": ACCESS_TOKEN_TTL_MINUTES * 60,
        "user": {"id": user["id"], "name": user["name"], "email": user["email"]},
    }
