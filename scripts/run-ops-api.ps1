$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'ops_api')

$python = Join-Path $root '.venv311\Scripts\python.exe'
if (-not (Test-Path $python)) {
  $python = Join-Path $root '.venv\Scripts\python.exe'
}
if (-not (Test-Path $python)) {
  $python = 'python'
}

if (-not $env:DATABASE_URL -or $env:DATABASE_URL.Trim() -eq '') {
  # Stable local DB for shared Flutter + dashboard development.
  $env:DATABASE_URL = 'sqlite:///./ops_api_dev.db'
}
if (-not $env:ML_SERVICE_URL -or $env:ML_SERVICE_URL.Trim() -eq '') {
  $env:ML_SERVICE_URL = 'http://127.0.0.1:8001'
}
if (-not $env:APP_ENV -or $env:APP_ENV.Trim() -eq '') {
  $env:APP_ENV = 'development'
}
if (-not $env:PYTHONPATH -or $env:PYTHONPATH.Trim() -eq '') {
  $env:PYTHONPATH = (Get-Location).Path
}

& $python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8002
