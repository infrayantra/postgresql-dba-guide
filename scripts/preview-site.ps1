# Preview the built site exactly as GitHub Pages serves it (repo root)
param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "deploy-site.ps1")

Write-Host ""
Write-Host "Serving built site from repo root..."
Write-Host "  URL:  http://127.0.0.1:$Port"
Write-Host "  Stop: Ctrl+C"
Write-Host ""

Push-Location $Root
try {
    python -m http.server $Port --bind 127.0.0.1
}
finally {
    Pop-Location
}
