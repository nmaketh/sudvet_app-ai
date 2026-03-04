#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile_api"

# Load local env if present
if [ -f ".env.local" ]; then
  set -a
  source .env.local
  set +a
fi

exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
