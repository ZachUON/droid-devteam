# Development Team Orchestrator v7
# Multi-row layout on right side: Expert, Builder, Research rows (each grows horizontally)
# Session files are created in .devteam/ inside the current working directory.
#
# Layout:
#   +----------+----+----+----+
#   |          | E1 | E2 | E3 |  ← Expert row (splits RIGHT)
#   |    A     +----+----+----+
#   |          | B1 | B2 | B3 |  ← Builder row (splits RIGHT)
#   +----------+----+----+----+
#   |    V     | R1 | R2 |    |  ← Research row (splits RIGHT)
#   +----------+----+----+----+
#
# Split sequence:
#   1. Architect RIGHT 80% → Left column (20%) + Right side (80%)
#   2. Architect DOWN 30% → Architect (70%) + Validator (30%)
#   3. Right side DOWN 67% → Expert row (33%) + Remaining (67%)
#   4. Remaining DOWN 50% → Builder row (50%) + Research row (50%)
#
# Adding agents:
#   - devteam add-agent expert → splits last Expert pane RIGHT (50%)
#   - devteam add-agent builder → splits last Builder pane RIGHT (50%)
#   - devteam add-agent research → splits last Research pane RIGHT (50%)
#
# Workflow:
#   1. User → Architect with task
#   2. Architect → Research (finds examples/best practices)
#   3. Research → Architect (findings)
#   4. Architect → spawns Experts/Builders based on research
#   5. Team → Validator (final QA)

param(
    [Parameter(Position=0, Mandatory=$false)]
    [string]$Task = "",

    [Parameter(Position=1, Mandatory=$false)]
    [ValidateSet('architect', 'builder', 'validator', 'expert', 'research', 'all', 'add-agent', 'layout', 'stop', 'status')]
    [string]$Agent = 'all',

    [Parameter(Position=2, Mandatory=$false)]
    [string]$AgentType = $null,

    [Parameter(Position=3, Mandatory=$false)]
    [string]$Domain = $null
)

$ErrorActionPreference = "Stop"
$WezTermExe = "wezterm"

# Session files live in .devteam/ relative to wherever the command is run
$ProjectDir = (Get-Location).Path
$TeamSessionDir = Join-Path $ProjectDir ".devteam"
$SessionFile = Join-Path $TeamSessionDir "session.json"

# ── Handle subcommands: stop, status ──

if ($Agent -eq 'stop') {
    . ~/.factory/scripts/dev-team-orchestrator.ps1 @PSBoundParameters
    exit
}

if ($Agent -eq 'status') {
    . ~/.factory/scripts/dev-team-orchestrator.ps1 @PSBoundParameters
    exit
}

# ── Pre-flight ──

function Test-WezTermAvailable {
    try {
        $null = & $WezTermExe cli list --format json 2>&1
        return $true
    } catch {
        Write-Error "WezTerm is not available or not running. Please start WezTerm first."
        return $false
    }
}

if (-not (Test-WezTermAvailable)) {
    exit 1
}

# ── Main Team Spawn ──

function Invoke-DevTeam {
    param([string]$Task = $null)

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Development Team Orchestrator v7" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Project: $ProjectDir" -ForegroundColor DarkGray
    Write-Host ""

    . ~/.factory/scripts/dev-team-orchestrator.ps1 -Task $Task -Agent 'all'
}

# ── Entry Point ──

switch ($Agent) {
    'all' {
        Invoke-DevTeam -Task $Task
    }
    'add-agent' {
        . ~/.factory/scripts/dev-team-orchestrator.ps1 @PSBoundParameters
    }
    'layout' {
        . ~/.factory/scripts/dev-team-orchestrator.ps1 @PSBoundParameters
    }
    default {
        Write-Host "Unknown agent: $Agent" -ForegroundColor Red
        Write-Host "Valid agents: all, add-agent, layout, stop, status" -ForegroundColor Yellow
    }
}
