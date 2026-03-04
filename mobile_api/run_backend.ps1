$scriptPath = Join-Path $PSScriptRoot 'run_mobile_api.ps1'
if (-not (Test-Path $scriptPath)) {
  throw 'run_mobile_api.ps1 not found. The mobile API folder may be incomplete.'
}
& $scriptPath
