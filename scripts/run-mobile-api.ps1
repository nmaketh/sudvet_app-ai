$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'mobile_api')
if (Test-Path '.\\run_mobile_api.ps1') {
  & .\\run_mobile_api.ps1
} else {
  & .\\run_backend.ps1
}
