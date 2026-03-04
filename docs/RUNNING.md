# Running the Project Locally

## 1) Flutter Field App + Mobile API

### Start `mobile_api`

```powershell
cd mobile_api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Or use the launcher alias:

```powershell
.\scripts\run-mobile-api.ps1
```

### Run Flutter app

```powershell
flutter run
```

Use backend base URL:
- Web/Desktop: `http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`

## 2) Vet/Admin Dashboard Stack (Docker)

```powershell
docker compose up --build
```

Endpoints:
- Mobile API health: `http://localhost:8000/health`
- Dashboard: `http://localhost:3000`
- Ops API docs: `http://localhost:8002/docs`
- ML service health: `http://localhost:8001/health`

## 3) Vet/Admin Dashboard Stack (Without Docker)

### Start Postgres
Use local Postgres and create database `cattle_ai`, or run a container manually.

### Start `ops_api`

```powershell
cd ops_api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
alembic upgrade head
python -m app.seed
uvicorn app.main:app --reload --host 0.0.0.0 --port 8002
```

Or use the launcher alias:

```powershell
.\scripts\run-ops-api.ps1
```

### Start `dashboard`

```powershell
cd dashboard
npm install
npm run dev
```

Or use the launcher alias:

```powershell
.\scripts\run-dashboard.ps1
```

## 4) ML Service (Local)

```powershell
.\scripts\run-ml-service.ps1
```

This expects ML dependencies to already be installed in `cattle_disease_ml` and runs the inference API on `8001`.

## Production Safety Notes

- `ops_api` container supports:
  - `RUN_MIGRATIONS_ON_START`
  - `RUN_SEED_ON_START` (disable in production)
- `mobile_api` supports CORS hardening:
  - `CORS_ALLOW_ALL=false`
  - `CORS_ORIGINS=https://your-host.example.com`
