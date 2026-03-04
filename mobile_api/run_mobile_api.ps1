$ErrorActionPreference = "Stop"

# Preferred local env file is `.env.local.ps1`; fall back to legacy `env` during migration.
$envCandidates = @(
  (Join-Path $PSScriptRoot ".env.local.ps1"),
  (Join-Path $PSScriptRoot "env")
)

foreach ($envFile in $envCandidates) {
  if (-not (Test-Path $envFile)) {
    continue
  }

  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
      return
    }
    Invoke-Expression $line
  }
  break
}

Set-Location $PSScriptRoot

# Resolve Python: prefer project .venv311 (3.11), then local .venv, then system
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root '.venv311\Scripts\python.exe'
if (-not (Test-Path $python)) {
  $python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
}
if (-not (Test-Path $python)) {
  $python = 'python'
}

& $python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
