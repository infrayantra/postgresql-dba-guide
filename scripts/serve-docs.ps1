# Preview the knowledge base website locally
# Usage: .\scripts\serve-docs.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

& "$Root\scripts\sync-docs.ps1"

if (-not (Test-Path ".venv")) {
    Write-Host "Creating virtual environment..."
    python -m venv .venv
}

& .\.venv\Scripts\Activate.ps1
pip install -q -r requirements-docs.txt

Write-Host ""
Write-Host "Starting MkDocs at http://127.0.0.1:8000"
Write-Host "Press Ctrl+C to stop"
Write-Host ""

mkdocs serve -a 127.0.0.1:8000
