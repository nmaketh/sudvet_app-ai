# Copy this file to `.env.local.ps1` (or keep legacy `env`) and update values.
# This file uses PowerShell syntax because `run_mobile_api.ps1` / `run_backend.ps1`
# imports it with `Invoke-Expression` for local development.

$env:APP_ENV="development"
$env:CORS_ALLOW_ALL="true"
# $env:CORS_ORIGINS="http://localhost:3000,http://127.0.0.1:3000"

$env:INFERENCE_API_URL="https://your-ml-endpoint.example.com"
$env:INFERENCE_ALLOW_RULES_FALLBACK="false"
$env:INFERENCE_STRICT_MODE="true"

# Optional SMTP settings for real OTP emails
# $env:SMTP_HOST="smtp.gmail.com"
# $env:SMTP_PORT="587"
# $env:SMTP_USERNAME="your-user"
# $env:SMTP_PASSWORD="your-password"
# $env:SMTP_FROM="noreply@example.com"
# $env:SMTP_USE_TLS="true"
# $env:SMTP_USE_SSL="false"
