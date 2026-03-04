# Ops API (FastAPI + PostgreSQL)

This service powers the vet/admin web dashboard (`dashboard/`).

## Run (Local, no Docker)

```powershell
cd ops_api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
alembic upgrade head
python -m app.seed
uvicorn app.main:app --reload --host 0.0.0.0 --port 8002
```

## Run (Docker compose from repo root)

```powershell
docker compose up --build
```

- API docs: `http://localhost:8002/docs`
- Dashboard UI: `http://localhost:3000`
- Mobile API (Flutter backend): `http://localhost:8000`

## Notes

- Uses PostgreSQL + SQLAlchemy + Alembic
- RBAC roles: `CAHW`, `VET`, `ADMIN`
- Can proxy to ML service via `ML_SERVICE_URL`
- Container startup is controlled by env flags:
  - `RUN_MIGRATIONS_ON_START=true|false`
  - `RUN_SEED_ON_START=true|false` (keep `false` in production)
