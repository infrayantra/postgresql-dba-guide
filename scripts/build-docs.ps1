# Build static site to ./site/
# Usage: .\scripts\build-docs.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

& "$Root\scripts\sync-docs.ps1"

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}

& .\.venv\Scripts\Activate.ps1
pip install -q -r requirements-docs.txt

mkdocs build --clean

Write-Host ""
Write-Host "Site built: $Root\site\index.html"
Write-Host "Open in browser or serve with: python -m http.server 8080 --directory site"
