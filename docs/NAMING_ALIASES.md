# Naming Aliases and Migration Notes

## Canonical Names (Use These)

- `mobile_api` -> Flutter/mobile backend (formerly `backend`)
- `ops_api` -> Web dashboard backend (formerly `api`)
- `dashboard` -> Vet/admin web UI
- `cattle_disease_ml` -> ML service + training repo

## Why This Rename Was Needed

Two folders named like generic backends (`backend/` and `api/`) were causing repeated confusion about:

- which backend Flutter should connect to
- which backend the dashboard should connect to
- which port (`8000`) belonged to which service

## Local Launcher Alias Scripts

Use these from repo root:

- `scripts/run-mobile-api.ps1`
- `scripts/run-ops-api.ps1`
- `scripts/run-dashboard.ps1`
- `scripts/run-ml-service.ps1`

These names are product-role-based and easier to remember than folder names.

## Temporary Backend Shim (Windows-safe migration)

If `backend/` still exists after the migration, it is a temporary compatibility shim used to preserve local runtime files (`.venv`, SQLite DB, legacy `env`) while source code lives in `mobile_api/`.
