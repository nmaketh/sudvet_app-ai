# Mobile API (FastAPI + SQLite) for Flutter Field App

This service powers the Flutter field-worker app (CAHW / field operations).
It is separate from the vet/admin dashboard backend (`ops_api`).

## Run

```powershell
cd mobile_api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Or use the included runner (loads `.env.local.ps1` or legacy `env` if present):

```powershell
cd mobile_api
.\run_mobile_api.ps1
```

## Important

- Local port: `8000`
- Flutter app should connect here (`127.0.0.1:8000` for web/desktop local)
- The web dashboard should connect to `ops_api` on `8002`, not this service
- Health endpoint returns environment/version metadata (`GET /health`)

## Local Env Template

Use `mobile_api/.env.example.ps1` as a template and copy to `mobile_api/.env.local.ps1`.
For backward compatibility, `mobile_api/run_mobile_api.ps1` also reads legacy `mobile_api/env` if present.

## Docker (Deployment / Integration Testing)

```powershell
docker build -t cattle-ai-mobile-api ./mobile_api
docker run --rm -p 8000:8000 --env-file mobile_api/.env.example cattle-ai-mobile-api
```

For strict CORS in production:

- set `CORS_ALLOW_ALL=false`
- set `CORS_ORIGINS=https://your-mobile-web-host.example.com`
