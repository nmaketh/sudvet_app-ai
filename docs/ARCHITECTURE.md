# Architecture Overview

## Systems

1. Flutter App (field workers / CAHW)
- Captures cases in the field
- Uses `mobile_api` for auth, animals, cases, sync, and OTP flows

2. Mobile API (`mobile_api`)
- FastAPI + SQLite
- Serves Flutter auth routes (`/auth/forgot-password`, `/auth/reset-password`, etc.)
- Can call an external inference endpoint via `INFERENCE_API_URL`

3. Ops Dashboard (`dashboard`)
- Next.js App Router dashboard for vets/admins/supervisors
- Uses `ops_api` for triage, analytics, users, system monitoring

4. Ops API (`ops_api`)
- FastAPI + PostgreSQL + SQLAlchemy + Alembic
- RBAC roles: CAHW / VET / ADMIN
- Can proxy to ML service (`ML_SERVICE_URL`) for hybrid inference

5. ML Service (`cattle_disease_ml`)
- Training + inference FastAPI microservice
- Hybrid model pipeline (image + symptoms + rules)
- Separate nested repo / gitlink in this monorepo

## Data / Request Flows

### Field Workflow

Flutter app -> `mobile_api` (8000) -> optional external model -> SQLite

### Vet/Admin Workflow

Dashboard (3000) -> `ops_api` (8002) -> PostgreSQL (5432)
                              -> ML service (8001) (optional / configured)

## Why Two APIs Exist

They serve different product surfaces and auth/workflow requirements:

- `mobile_api`: field app auth + offline/online case capture flow
- `ops_api`: case triage, assignments, analytics, RBAC admin management

Keeping them separate is acceptable if the boundaries are documented and ports are fixed.
