"""OTP generation and email delivery helpers for signup flow."""
from __future__ import annotations

import logging
import random
import smtplib
import string
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import settings

logger = logging.getLogger(__name__)

OTP_LENGTH = 6
OTP_EXPIRE_SECONDS = 300  # 5 minutes
OTP_MAX_RESENDS = 5


def generate_otp() -> str:
    """Return a random 6-digit numeric OTP code."""
    return "".join(random.choices(string.digits, k=OTP_LENGTH))


def _smtp_configured() -> bool:
    return bool(getattr(settings, "smtp_host", "").strip())


def send_otp_email(*, to_email: str, to_name: str, otp: str, purpose: str = "signup") -> bool:
    """
    Send an OTP email.  Returns True on success, False if SMTP is not configured.

    If SMTP_HOST is not set in environment, the function is a no-op (dev mode)
    and callers should surface the OTP code in the API response as `devOtp`.
    """
    if not _smtp_configured():
        logger.info("[OTP dev-mode] %s OTP for %s: %s", purpose, to_email, otp)
        return False

    subject = "Your Cattle AI verification code"
    body_text = (
        f"Hi {to_name},\n\n"
        f"Your verification code is: {otp}\n\n"
        f"This code expires in {OTP_EXPIRE_SECONDS // 60} minutes.\n\n"
        f"If you did not request this, please ignore this email.\n\n"
        f"— Cattle Disease AI"
    )
    body_html = f"""
    <div style="font-family:sans-serif;max-width:480px;margin:auto">
      <h2 style="color:#2E7D4F">Cattle Disease AI</h2>
      <p>Hi <strong>{to_name}</strong>,</p>
      <p>Your verification code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#2E7D4F;padding:16px 0">{otp}</div>
      <p style="color:#666">This code expires in {OTP_EXPIRE_SECONDS // 60} minutes.</p>
      <p style="color:#999;font-size:12px">If you did not request this, please ignore this email.</p>
    </div>
    """

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = getattr(settings, "smtp_from", f"noreply@{getattr(settings, 'smtp_host', 'cattle.ai')}")
    msg["To"] = to_email
    msg.attach(MIMEText(body_text, "plain"))
    msg.attach(MIMEText(body_html, "html"))

    try:
        host = settings.smtp_host  # type: ignore[attr-defined]
        port = int(getattr(settings, "smtp_port", 587))
        user = getattr(settings, "smtp_user", "")
        password = getattr(settings, "smtp_password", "")
        use_tls = getattr(settings, "smtp_tls", True)

        with smtplib.SMTP(host, port, timeout=10) as server:
            if use_tls:
                server.starttls()
            if user:
                server.login(user, password)
            server.sendmail(msg["From"], [to_email], msg.as_string())
        return True
    except Exception:
        logger.exception("Failed to send OTP email to %s", to_email)
        return False
