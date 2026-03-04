$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'dashboard')
if (-not $env:NEXT_PUBLIC_API_URL -or $env:NEXT_PUBLIC_API_URL.Trim() -eq '') {
  $env:NEXT_PUBLIC_API_URL = 'http://localhost:8002'
}
npm run dev
