#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Factory Droid Development Team Orchestrator
.DESCRIPTION
    Creates a WezTerm layout with:
    - Left: Architect (top) + Validator (bottom)
    - Right: 3 horizontal rows for Expert, Builder, Researcher agents
    - Agents can be added dynamically by splitting RIGHT within their row
#>

[CmdletBinding()]
param(
    [string]$Task = "",
    [switch]$Debug
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Import helper module
$HelperModule = Join-Path $PSScriptRoot "dev-team-helpers.psm1"
if (Test-Path $HelperModule) {
    Import-Module $HelperModule -Force
} else {
    Write-Error "Helper module not found: $HelperModule"
    exit 1
}

# ── Handle subcommands ──

if ($Task -eq 'stop') {
    Write-Host "Stopping dev team session..." -ForegroundColor Yellow
    # TODO: Implement stop logic
    exit 0
}

if ($Task -eq 'status') {
    Write-Host "Dev team status..." -ForegroundColor Cyan
    $sessionFile = Join-Path (Get-Location).Path ".devteam/session.json"
    if (Test-Path $sessionFile) {
        Get-Content $sessionFile -Raw | ConvertFrom-Json | Format-List
    } else {
        Write-Host "No active session found." -ForegroundColor Yellow
    }
    exit 0
}

if ($Task -eq 'layout') {
    Write-Host "Dev team layout..." -ForegroundColor Cyan
    Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
    Write-Host "  |          | E1 | E2 | E3 |  Expert row" -ForegroundColor Yellow
    Write-Host "  |    A     +----+----+----+" -ForegroundColor Yellow
    Write-Host "  |          | B1 | B2 | B3 |  Builder row" -ForegroundColor Yellow
    Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
    Write-Host "  |    V     | R1 | R2 |    |  Research row" -ForegroundColor Yellow
    Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
    exit 0
}

# ── Main Execution ──

Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   Factory Droid Development Team v8.0     ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

try {
    # Use helper module to create layout
    $layout = Initialize-DevTeamLayout -Debug:$Debug
    
    Write-Host ""
    Write-Host "Spawning initial agents..." -ForegroundColor Cyan
    
    # Get session directory for prompts
    $sessionDir = (Get-Location).Path + "/.devteam"
    if (-not (Test-Path $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }
    
    $sessionDirForPrompt = $sessionDir.Replace('\', '/')
    
    # Architect prompt
    $architectPrompt = if ($Task) {
        "IMPORTANT: You are the ARCHITECT (Team Lead). Session: $sessionDirForPrompt/. Team task: $Task. CRITICAL WORKFLOW: Step 1 - Use Research agent to find examples and best practices. Step 2 - Based on findings, spawn appropriate Experts and Builders. Step 3 - Coordinate implementation. Step 4 - Send to Validator."
    } else {
        "IMPORTANT: You are the ARCHITECT (Team Lead). Session: $sessionDirForPrompt/. Read scratchpad and inbox, announce readiness."
    }
    
    Start-AgentInPane -PaneId $layout.Architect -AgentType "architect" -Prompt $architectPrompt
    Start-Sleep -Milliseconds 500
    
    # Validator prompt
    $validatorPrompt = "IMPORTANT: You are the VALIDATOR (QA/testing). Session: $sessionDirForPrompt/. Read scratchpad and inbox, announce readiness."
    Start-AgentInPane -PaneId $layout.Validator -AgentType "validator" -Prompt $validatorPrompt
    Start-Sleep -Milliseconds 500
    
    # Expert prompt
    $expertPrompt = "IMPORTANT: You are the EXPERT (domain knowledge). Session: $sessionDirForPrompt/. Read scratchpad and inbox, announce readiness."
    Start-AgentInPane -PaneId $layout.ExpertRow -AgentType "expert" -Prompt $expertPrompt -Name "expert-1"
    Start-Sleep -Milliseconds 500
    
    # Builder prompt
    $builderPrompt = "IMPORTANT: You are the BUILDER (implementation). Session: $sessionDirForPrompt/. Read scratchpad and inbox, announce readiness."
    Start-AgentInPane -PaneId $layout.BuilderRow -AgentType "builder" -Prompt $builderPrompt -Name "builder-1"
    Start-Sleep -Milliseconds 500
    
    # Researcher prompt
    $researcherPrompt = "IMPORTANT: You are the RESEARCHER (code research). Session: $sessionDirForPrompt/. **CRITICAL:** You ONLY search the local directory first (never go outside it). If local files don't have answers, then do web research including GitHub repositories, documentation, and source code examples. Read scratchpad and inbox, announce readiness."
    Start-AgentInPane -PaneId $layout.ResearcherRow -AgentType "researcher" -Prompt $researcherPrompt -Name "researcher-1"
    
    Write-Host ""
    Write-Host "✅ Development team is ready!" -ForegroundColor Green
    Write-Host ""
    Write-Host "💡 Layout:" -ForegroundColor Yellow
    Write-Host "   Left: Architect (top) | Validator (bottom)" -ForegroundColor Gray
    Write-Host "   Right: Expert / Builder / Researcher rows - grow right" -ForegroundColor Gray
    Write-Host ""
    Write-Host "📝 To add more agents, use:" -ForegroundColor Yellow
    Write-Host "   Add-Agent -Type Expert -Name 'frontend-expert'" -ForegroundColor Gray
    Write-Host "   Add-Agent -Type Builder -Name 'python-builder'" -ForegroundColor Gray
    Write-Host "   Add-Agent -Type Researcher -Name 'api-researcher'" -ForegroundColor Gray
    Write-Host ""
    
    # Store layout globally for Add-Agent function
    $global:DevTeamLayout = $layout
    $global:LastExpertPane = $layout.ExpertRow
    $global:LastBuilderPane = $layout.BuilderRow
    $global:LastResearcherPane = $layout.ResearcherRow
    
    # Save session metadata
    $session = @{
        started = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        task = $Task
        project = (Get-Location).Path
        pane_ids = @($layout.Architect, $layout.Validator, $layout.ExpertRow, $layout.BuilderRow, $layout.ResearcherRow)
        agents = @{
            architect = $layout.Architect
            validator = $layout.Validator
            'expert-1' = $layout.ExpertRow
            'builder-1' = $layout.BuilderRow
            'researcher-1' = $layout.ResearcherRow
        }
        pane_layout = @{
            left = @{
                architect = $layout.Architect
                validator = $layout.Validator
            }
            rows = @{
                expert = @{ pane_id = $layout.ExpertRow; agents = @('expert-1') }
                builder = @{ pane_id = $layout.BuilderRow; agents = @('builder-1') }
                research = @{ pane_id = $layout.ResearcherRow; agents = @('researcher-1') }
            }
        }
    }
    
    $session | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $sessionDir "session.json") -Encoding UTF8
    
} catch {
    Write-Error "Failed to start dev team: $_"
    exit 1
}
