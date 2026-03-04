from __future__ import annotations

import smtplib
import sqlite3
from datetime import timedelta
from email.message import EmailMessage

from fastapi import HTTPException

from .security import _now_utc, _parse_iso, _seconds_until, now_iso
from .settings import (
    OTP_EXPIRY_MINUTES,
    OTP_MAX_REQUESTS_PER_HOUR,
    SMTP_FROM,
    SMTP_HOST,
    SMTP_PASSWORD,
    SMTP_PORT,
    SMTP_USE_SSL,
    SMTP_USE_TLS,
    SMTP_USERNAME,
)

def _deliver_otp(email: str, otp: str, purpose: str = "signup") -> None:
    purpose_label = "signup verification" if purpose == "signup" else "password reset"
    if not SMTP_HOST or not SMTP_FROM:
        print(
            f"[OTP] {purpose} email={email} code={otp} (SMTP not configured; using console delivery)"
        )
        return

    message = EmailMessage()
    message["Subject"] = f"Your Cattle Disease App {purpose_label} OTP"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        (
            f"Your {purpose_label} OTP code is: {otp}\n\n"
            f"It expires in {OTP_EXPIRY_MINUTES} minutes.\n"
            "If you did not request this code, please ignore this email."
        )
    )

    try:
        if SMTP_USE_SSL:
            with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
                if SMTP_USERNAME:
                    smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
                smtp.send_message(message)
            return

        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
            if SMTP_USE_TLS:
                smtp.starttls()
            if SMTP_USERNAME:
                smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
            smtp.send_message(message)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send OTP email: {exc}",
        ) from exc

def _enforce_otp_request_rate_limit(conn: sqlite3.Connection, email: str) -> None:
    now = _now_utc()
    row = conn.execute(
        "SELECT window_start, request_count FROM otp_rate_limits WHERE email = ?",
        (email,),
    ).fetchone()

    if row is None:
        conn.execute(
            "INSERT INTO otp_rate_limits(email, window_start, request_count) VALUES(?,?,?)",
            (email, now.isoformat(), 1),
        )
        return

    window_start = _parse_iso(row["window_start"])
    if now - window_start >= timedelta(hours=1):
        conn.execute(
            "UPDATE otp_rate_limits SET window_start = ?, request_count = 1 WHERE email = ?",
            (now.isoformat(), email),
        )
        return

    request_count = int(row["request_count"] or 0)
    if request_count >= OTP_MAX_REQUESTS_PER_HOUR:
        raise HTTPException(
            status_code=429,
            detail="Too many OTP requests. Please try again later.",
        )
    conn.execute(
        "UPDATE otp_rate_limits SET request_count = request_count + 1 WHERE email = ?",
        (email,),
    )
