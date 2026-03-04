# Local Port Map

## Reserved Ports in This Repo

- `3000`: `dashboard` (Next.js UI)
- `5432`: PostgreSQL for `ops_api`
- `8000`: `mobile_api` (Flutter backend)
- `8001`: `cattle_disease_ml` (ML inference service)
- `8002`: `ops_api` (dashboard backend)

## Why This Matters

The biggest source of local confusion was two different FastAPI backends both using `8000`.
This repo now reserves:

- `8000` only for the Flutter/mobile backend
- `8002` only for the dashboard/ops backend

## Client Base URLs

### Flutter app (field app)

- Web/Desktop local: `http://127.0.0.1:8000`
- Android emulator local: `http://10.0.2.2:8000`

### Next.js dashboard

- Local API base: `http://localhost:8002`

## Docker Compose Ports (Root `docker-compose.yml`)

- `mobile_api`: `8000:8000`
- `dashboard`: `3000:3000`
- `ops_api`: `8002:8000`
- `ml`: `8001:8000`
- `db`: `5432:5432`
