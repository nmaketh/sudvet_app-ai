#!/bin/sh
set -eu

RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-true}"
RUN_SEED_ON_START="${RUN_SEED_ON_START:-false}"
UVICORN_HOST="${UVICORN_HOST:-0.0.0.0}"
UVICORN_PORT="${UVICORN_PORT:-8000}"

if [ "$RUN_MIGRATIONS_ON_START" = "true" ]; then
  alembic upgrade head
fi

if [ "$RUN_SEED_ON_START" = "true" ]; then
  python -m app.seed
fi

exec uvicorn app.main:app --host "$UVICORN_HOST" --port "$UVICORN_PORT"
