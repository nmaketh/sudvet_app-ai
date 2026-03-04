#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ops_api"

# Resolve python from venv or system
PYTHON="$ROOT/.venv311/bin/python"
[ -x "$PYTHON" ] || PYTHON="$ROOT/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON="python3"

export DATABASE_URL="${DATABASE_URL:-sqlite:///./ops_api_dev.db}"
export ML_SERVICE_URL="${ML_SERVICE_URL:-http://127.0.0.1:8001}"
export APP_ENV="${APP_ENV:-development}"
export PYTHONPATH="${PYTHONPATH:-$(pwd)}"

exec "$PYTHON" -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8002
