#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/cattle_disease_ml"

export PYTHONPATH="$(pwd)/ml"

# Use the ML service's own venv if it exists; fall back to system python3
if [ -f ".venv/bin/python3" ]; then
  PYTHON=".venv/bin/python3"
else
  PYTHON="python3"
fi

exec "$PYTHON" -m uvicorn src.infer.api:app --host 0.0.0.0 --port 8001
