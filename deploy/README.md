# Production Deployment Templates

This folder contains deployment templates for VM/container deployments.

## Included

- `docker-compose.prod.yml` - production-oriented compose template (no auto-seeding)
- `nginx/cattle-ai.conf` - reverse proxy for dashboard + APIs
- `systemd/*.service` - VM service unit templates

## Compose Quick Start (from repo root)

1. Create environment files from examples:
   - `copy mobile_api\\.env.production.example mobile_api\\.env.production`
   - `copy ops_api\\.env.production.example ops_api\\.env.production`
2. Set `POSTGRES_USER` and `POSTGRES_PASSWORD` in your shell (or in a root `.env` file).
3. Build and start:
   - `docker compose -f deploy/docker-compose.prod.yml up -d --build`
4. Check services:
   - `docker compose -f deploy/docker-compose.prod.yml ps`

## Deployment Model (Recommended)

- `dashboard` (Next.js) behind Nginx on localhost:3000
- `ops_api` (FastAPI) behind Nginx on localhost:8002
- `mobile_api` (FastAPI) behind Nginx on localhost:8000
- `ml` (optional public exposure) on localhost:8001, typically internal only
- PostgreSQL on private network / managed service

## Production Safety Checklist

- Set strong `SECRET_KEY` values and real DB credentials
- Disable `RUN_SEED_ON_START` for `ops_api`
- Set strict CORS origins (`mobile_api`, `ops_api`)
- Configure HTTPS certificates in Nginx (Let's Encrypt / managed certs)
- Enable DB backups and log rotation
- Put `.env` files outside the repo on production hosts
