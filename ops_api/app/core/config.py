from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Cattle Disease AI API"
    app_env: str = "development"
    api_prefix: str = ""
    secret_key: str = "change-me-in-production"
    access_token_expire_minutes: int = 30
    algorithm: str = "HS256"
    database_url: str = "postgresql+psycopg2://postgres:postgres@db:5432/cattle_ai"
    cors_origins: str = "http://localhost:3000"
    upload_dir: str = "./uploads"
    public_base_url: str = "http://localhost:8002"
    vet_can_view_all: bool = True

    # Supabase — required when using Supabase as the backend
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_storage_bucket: str = "case-images"
    ml_service_url: str = "http://127.0.0.1:8001"  # override in production/compose as needed

    # Google OAuth — set to your OAuth 2.0 Web Client ID to enable Google sign-in.
    # Get from: Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client IDs
    # Leave empty to disable the /auth/google endpoint.
    google_client_id: str = ""

    # SMTP — all optional; if smtp_host is unset, OTP emails are skipped (dev mode)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    smtp_tls: bool = True


settings = Settings()

