# Local preview — edit docs-content/*.md and refresh browser
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Push-Location $Root
try {
    $venvMkdocs = Join-Path $Root ".venv\Scripts\mkdocs.exe"
    if (-not (Test-Path $venvMkdocs)) {
        Write-Host "Creating virtual environment..."
        python -m venv .venv
        & .\.venv\Scripts\pip.exe install -r requirements-docs.txt -q
    }

    Write-Host ""
    Write-Host "Starting MkDocs dev server..."
    Write-Host "  URL:  http://127.0.0.1:8000"
    Write-Host "  Edit: docs-content\*.md"
    Write-Host "  Stop: Ctrl+C"
    Write-Host ""

    & $venvMkdocs serve -a 127.0.0.1:8000
}
finally {
    Pop-Location
}
