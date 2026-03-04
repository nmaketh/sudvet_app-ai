$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'cattle_disease_ml')
$env:PYTHONPATH = (Join-Path $PWD 'ml')

# Use the ML service's own venv if it exists; fall back to system python
$python = Join-Path $PWD '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
  $python = 'python'
}

& $python -m uvicorn src.infer.api:app --host 0.0.0.0 --port 8001

