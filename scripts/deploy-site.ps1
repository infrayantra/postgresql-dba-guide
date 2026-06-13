# Sync built site output to repo root (GitHub Pages deploy target)
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Push-Location $Root
try {
    if (-not $SkipBuild) {
        $venvMkdocs = Join-Path $Root ".venv\Scripts\mkdocs.exe"
        if (-not (Test-Path $venvMkdocs)) {
            Write-Host "Creating virtual environment..."
            python -m venv .venv
            & .\.venv\Scripts\pip.exe install -r requirements-docs.txt -q
        }
        Write-Host "Building MkDocs site..."
        & $venvMkdocs build
    }

    $deployDirs = @(
        "01-getting-started", "02-configuration", "03-administration",
        "04-backup-recovery", "05-replication-ha", "06-performance",
        "07-monitoring", "08-security", "09-maintenance", "10-advanced",
        "11-troubleshooting", "cheat-sheets", "INDEX", "VERSION",
        "WEBSITE", "GITHUB-PAGES", "assets", "search", "stylesheets"
    )

    foreach ($item in @("index.html", "404.html", "sitemap.xml", "sitemap.xml.gz", "tags.json", ".nojekyll")) {
        $src = Join-Path "site" $item
        if (Test-Path $src) {
            Copy-Item $src $Root -Force
        }
    }

    foreach ($dir in $deployDirs) {
        $src = Join-Path "site" $dir
        $dst = Join-Path $Root $dir
        if (Test-Path $src) {
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Copy-Item $src $dst -Recurse -Force
        }
    }

    Write-Host "Deployed site/ to repo root for GitHub Pages."
    Write-Host ""
    Write-Host "Next steps to publish:"
    Write-Host "  git add -A"
    Write-Host "  git commit -m ""Update built site"""
    Write-Host "  git push"
    Write-Host ""
    Write-Host "Local preview (exact GitHub Pages output): .\scripts\preview-site.ps1"
    Write-Host "Local dev (edit markdown live):           .\scripts\serve-docs.ps1"
}
finally {
    Pop-Location
}
