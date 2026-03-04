$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'mobile_api\\run_mobile_api.ps1'
if (-not (Test-Path $target)) {
  throw 'mobile_api\\run_mobile_api.ps1 not found.'
}
& $target
