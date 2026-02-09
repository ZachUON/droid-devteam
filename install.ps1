# droid-devteam installer v9
# Run: irm https://raw.githubusercontent.com/ZachUON/droid-devteam/main/install.ps1 | iex
# Or:  .\install.ps1

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
if (-not $RepoRoot -or -not (Test-Path "$RepoRoot\dev-team-orchestrator.ps1")) {
    # Running via pipe (irm | iex) -- clone first
    $TempDir = Join-Path $env:TEMP "droid-devteam-install"
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
    Write-Host "Cloning droid-devteam..." -ForegroundColor Cyan
    git clone https://github.com/ZachUON/droid-devteam.git $TempDir 2>&1 | Out-Null
    if (-not (Test-Path "$TempDir\dev-team-orchestrator.ps1")) {
        Write-Error "Clone failed. Check git is installed and the repo URL is correct."
        exit 1
    }
    $RepoRoot = $TempDir
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  droid-devteam installer v9" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check prerequisites ──
Write-Host "[1/4] Checking prerequisites..." -ForegroundColor Yellow

$missing = @()
if (-not (Get-Command "droid" -ErrorAction SilentlyContinue)) { $missing += "droid (Factory CLI -- https://docs.factory.ai/cli/getting-started/quickstart)" }
if (-not (Get-Command "wezterm" -ErrorAction SilentlyContinue)) { $missing += "wezterm (https://wezfurlong.org/wezterm/install)" }

if ($missing.Count -gt 0) {
    Write-Host "  Missing:" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host "    - $m" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Install the above and re-run this script." -ForegroundColor Yellow
    exit 1
}
Write-Host "  droid: OK" -ForegroundColor Green
Write-Host "  wezterm: OK" -ForegroundColor Green

# ── 2. Copy scripts ──
Write-Host "[2/4] Installing scripts..." -ForegroundColor Yellow

$ScriptDest = "$env:USERPROFILE\.factory\scripts"
New-Item -ItemType Directory -Path $ScriptDest -Force | Out-Null

Copy-Item "$RepoRoot\dev-team-orchestrator.ps1" "$ScriptDest\dev-team-orchestrator.ps1" -Force
Copy-Item "$RepoRoot\dev-team-helpers.psm1" "$ScriptDest\dev-team-helpers.psm1" -Force
Write-Host "  dev-team-orchestrator.ps1 -> $ScriptDest" -ForegroundColor Green
Write-Host "  dev-team-helpers.psm1 -> $ScriptDest" -ForegroundColor Green

# ── 3. Copy droid definitions ──
Write-Host "[3/4] Installing droid definitions..." -ForegroundColor Yellow

$DroidDest = "$env:USERPROFILE\.factory\droids"
New-Item -ItemType Directory -Path $DroidDest -Force | Out-Null

foreach ($droid in @('architect', 'builder', 'validator', 'expert', 'research')) {
    $src = "$RepoRoot\droids\$droid.md"
    $dst = "$DroidDest\$droid.md"
    if (Test-Path $dst) {
        $backup = "$dst.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $dst $backup
        Write-Host "  Backed up existing $droid.md" -ForegroundColor DarkGray
    }
    Copy-Item $src $dst -Force
    Write-Host "  $droid.md -> $DroidDest" -ForegroundColor Green
}

# ── 4. Add devteam function to PowerShell profile ──
Write-Host "[4/4] Setting up 'devteam' command..." -ForegroundColor Yellow

$ProfilePath = $PROFILE.CurrentUserAllHosts
if (-not $ProfilePath) { $ProfilePath = $PROFILE }

if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
}

$profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue

# New v9 function definition that passes all args through
$newFunctionDef = @'

# droid-devteam: multi-agent development team orchestrator
# Usage: devteam "task", devteam add-agent expert frontend, devteam msg builder-1 "task", devteam stop
function devteam {
    & "$env:USERPROFILE\.factory\scripts\dev-team-orchestrator.ps1" @args
}
'@

if ($profileContent -and $profileContent.Contains('function devteam')) {
    # Replace existing devteam function with updated version
    # Remove the old function block (handles both old and new formats)
    $pattern = '(?s)#[^\n]*devteam[^\n]*\r?\nfunction devteam \{[^}]+\}'
    $updatedContent = [regex]::Replace($profileContent, $pattern, $newFunctionDef.Trim())
    Set-Content -Path $ProfilePath -Value $updatedContent -Encoding UTF8
    Write-Host "  Updated 'devteam' function in $ProfilePath" -ForegroundColor Green
} else {
    Add-Content -Path $ProfilePath -Value $newFunctionDef -Encoding UTF8
    Write-Host "  Added 'devteam' function to $ProfilePath" -ForegroundColor Green
}

# ── Done ──
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Restart your terminal, then:" -ForegroundColor White
Write-Host '  devteam "Build a REST API"             # spawn team with a task' -ForegroundColor DarkGray
Write-Host '  devteam                                 # spawn team, assign task later' -ForegroundColor DarkGray
Write-Host '  devteam add-agent expert frontend       # add a domain expert' -ForegroundColor DarkGray
Write-Host '  devteam add-agent builder               # add a builder' -ForegroundColor DarkGray
Write-Host '  devteam msg builder-1 "implement X"     # send task to an agent' -ForegroundColor DarkGray
Write-Host '  devteam task "new task for team"         # give architect a new task' -ForegroundColor DarkGray
Write-Host '  devteam status                          # check team progress' -ForegroundColor DarkGray
Write-Host '  devteam stop                            # kill session and archive' -ForegroundColor DarkGray
Write-Host ""

# Clean up temp dir if we cloned
if ($RepoRoot -eq (Join-Path $env:TEMP "droid-devteam-install")) {
    Remove-Item $RepoRoot -Recurse -Force -ErrorAction SilentlyContinue
}
