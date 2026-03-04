from __future__ import annotations

import os

APP_TITLE = "Cattle Disease Backend"
APP_VERSION = "1.0.0"
APP_ENV = os.getenv("APP_ENV", "development").strip().lower() or "development"

OTP_EXPIRY_MINUTES = 5
OTP_RESEND_COOLDOWN_SECONDS = 60
OTP_MAX_VERIFY_ATTEMPTS = 5
OTP_LOCK_MINUTES = 15
OTP_MAX_REQUESTS_PER_HOUR = 6
OTP_MAX_RESENDS_PER_CHALLENGE = 5
ACCESS_TOKEN_TTL_MINUTES = 30
REFRESH_TOKEN_TTL_DAYS = 30

SMTP_HOST = os.getenv("SMTP_HOST", "").strip()
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME", "").strip()
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "").strip()
SMTP_FROM = os.getenv("SMTP_FROM", "").strip()
SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "true").strip().lower() == "true"
SMTP_USE_SSL = os.getenv("SMTP_USE_SSL", "false").strip().lower() == "true"
INFERENCE_API_URL = os.getenv("INFERENCE_API_URL", "").strip()
INFERENCE_TIMEOUT_SECONDS = int(os.getenv("INFERENCE_TIMEOUT_SECONDS", "8"))
INFERENCE_STRICT_MODE = os.getenv("INFERENCE_STRICT_MODE", "false").strip().lower() == "true"
INFERENCE_ALLOW_RULES_FALLBACK = (
    os.getenv("INFERENCE_ALLOW_RULES_FALLBACK", "false").strip().lower() == "true"
)

CORS_ALLOW_ALL = os.getenv("CORS_ALLOW_ALL", "false").strip().lower() == "true"
CORS_ORIGINS = os.getenv("CORS_ORIGINS", "").strip()


def build_cors_origins() -> list[str]:
    if CORS_ALLOW_ALL:
        return ["*"]
    origins = [item.strip() for item in CORS_ORIGINS.split(",") if item.strip()]
    return origins or ["http://localhost:3000", "http://127.0.0.1:3000"]
