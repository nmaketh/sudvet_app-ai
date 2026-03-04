from __future__ import annotations

import hashlib
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import bcrypt
from fastapi import Header, HTTPException

from .db import db_conn
from .settings import ACCESS_TOKEN_TTL_MINUTES, REFRESH_TOKEN_TTL_DAYS

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _bcrypt_input(password: str) -> bytes:
    # Pre-hash to fixed length to avoid bcrypt's 72-byte password limit.
    digest = hashlib.sha256(password.encode("utf-8")).hexdigest()
    return digest.encode("ascii")


def hash_password(password: str) -> str:
    hashed = bcrypt.hashpw(_bcrypt_input(password), bcrypt.gensalt())
    return hashed.decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        stored = password_hash.encode("utf-8")
        # Preferred path for newly hashed passwords.
        if bcrypt.checkpw(_bcrypt_input(password), stored):
            return True
        # Backward compatibility with previously stored raw-bcrypt entries.
        return bcrypt.checkpw(password.encode("utf-8"), stored)
    except Exception:
        return False

def _token_from_header(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header.")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Invalid Authorization scheme.")
    return authorization[7:].strip()


def get_current_user(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    token = _token_from_header(authorization)
    with db_conn() as conn:
        token_row = conn.execute(
            "SELECT user_id, expires_at FROM auth_tokens WHERE token = ?",
            (token,),
        ).fetchone()
        if token_row is None:
            raise HTTPException(status_code=401, detail="Invalid or expired token.")
        expires_at_raw = token_row["expires_at"]
        if expires_at_raw:
            expires_at = _parse_iso(expires_at_raw)
            if _now_utc() >= expires_at:
                conn.execute("DELETE FROM auth_tokens WHERE token = ?", (token,))
                raise HTTPException(status_code=401, detail="Invalid or expired token.")
        user_row = conn.execute(
            "SELECT id, name, email FROM users WHERE id = ?",
            (token_row["user_id"],),
        ).fetchone()
        if user_row is None:
            raise HTTPException(status_code=401, detail="User not found.")
        return {"id": user_row["id"], "name": user_row["name"], "email": user_row["email"]}

def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _new_token() -> str:
    return secrets.token_urlsafe(32)


def _new_signup_token() -> str:
    return secrets.token_urlsafe(36)


def _new_reset_token() -> str:
    return secrets.token_urlsafe(36)


def _new_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _new_job_id() -> str:
    return f"job-{uuid.uuid4()}"


def _new_tag() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ123456789"
    value = "".join(secrets.choice(alphabet) for _ in range(6))
    return f"COW-{value}"

def _parse_iso(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _issue_tokens(conn: sqlite3.Connection, user_id: str) -> tuple[str, str]:
    now = _now_utc()
    access_token = _new_token()
    refresh_token = _new_token()
    access_expires = (now + timedelta(minutes=ACCESS_TOKEN_TTL_MINUTES)).isoformat()
    refresh_expires = (now + timedelta(days=REFRESH_TOKEN_TTL_DAYS)).isoformat()

    conn.execute(
        """
        INSERT INTO auth_tokens(token, user_id, created_at, expires_at)
        VALUES(?,?,?,?)
        """,
        (access_token, user_id, now.isoformat(), access_expires),
    )
    conn.execute(
        """
        INSERT INTO auth_refresh_tokens(token, user_id, created_at, expires_at, revoked_at)
        VALUES(?,?,?,?,NULL)
        """,
        (refresh_token, user_id, now.isoformat(), refresh_expires),
    )
    return access_token, refresh_token


def _seconds_until(moment: datetime, now: datetime) -> int:
    return max(0, int((moment - now).total_seconds()))
