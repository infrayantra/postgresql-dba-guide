# Sync markdown into docs-content/ for MkDocs (preserves source files in repo root)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Dest = Join-Path $Root "docs-content"

if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
New-Item -ItemType Directory -Path $Dest | Out-Null

# Root pages
@("README.md", "INDEX.md", "VERSION.md", "WEBSITE.md", "GITHUB-PAGES.md") | ForEach-Object {
    Copy-Item (Join-Path $Root $_) (Join-Path $Dest $_)
}

# Section folders + cheat-sheets + stylesheets
@(
    "01-getting-started",
    "02-configuration",
    "03-administration",
    "04-backup-recovery",
    "05-replication-ha",
    "06-performance",
    "07-monitoring",
    "08-security",
    "09-maintenance",
    "10-advanced",
    "11-troubleshooting",
    "cheat-sheets",
    "stylesheets",
    "assets"
) | ForEach-Object {
    Copy-Item (Join-Path $Root $_) (Join-Path $Dest $_) -Recurse
}

Write-Host "Synced to docs-content/ ($((Get-ChildItem $Dest -Recurse -File).Count) files)"
