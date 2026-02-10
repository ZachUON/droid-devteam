#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Factory Droid Development Team Orchestrator v9.1
.DESCRIPTION
    Creates a WezTerm layout with:
    - Left: Architect (top) + Validator (bottom)
    - Right: 3 horizontal rows for Expert, Builder, Researcher agents
    - Each row grows horizontally (RIGHT splits) to add more agents

    Fabric Mode (--fabric):
    - Left: Architect (top) + Fabric Expert (bottom)
    - Right: PySpark Expert, BigData Expert, Builder rows
    - Jira integration, Fabric MCP deployment, autonomous error recovery
.NOTES
    Standard Layout:
      +----------+----+----+----+
      |          | E1 | E2 | E3 |  Expert row (splits RIGHT)
      |    A     +----+----+----+
      |          | B1 | B2 | B3 |  Builder row (splits RIGHT)
      +----------+----+----+----+
      |    V     | R1 | R2 |    |  Research row (splits RIGHT)
      +----------+----+----+----+

    Fabric Layout:
      +----------+------------------+
      |          | PySpark Expert   |
      | Architect+------------------+
      |          | BigData Expert   |
      +----------+------------------+
      | Fabric   | Builder-1        |
      | Expert   |                  |
      +----------+------------------+

    Usage:
      devteam "Build a REST API"          Start team with task
      devteam --fabric "ticket 139"       Start Fabric team with Jira ticket
      devteam --fabric                    Start Fabric team, no task
      devteam                             Start team, no task
      devteam add-agent expert frontend   Add domain expert
      devteam add-agent builder           Add builder
      devteam add-agent research          Add researcher
      devteam msg builder-1 "do X"        Send message to agent
      devteam task "new objective"         Send task to Architect
      devteam stop                        Kill session and archive
      devteam status                      Show team status
      devteam layout                      Show visual layout
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"

# ── Import helper module ──

$HelperModule = Join-Path $PSScriptRoot "dev-team-helpers.psm1"
if (Test-Path $HelperModule) {
    Import-Module $HelperModule -Force
} else {
    Write-Error "Helper module not found at: $HelperModule"
    exit 1
}

# ── Parse arguments ──

# Normalize: strip leading dashes from the command so --fabric, -fabric, fabric all work
$RawCommand = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "" }
$Command = $RawCommand -replace '^-+', ''
$Arg1 = if ($Arguments.Count -gt 1) { $Arguments[1] } else { "" }
$Arg2 = if ($Arguments.Count -gt 2) { $Arguments[2] } else { "" }
$RestArgs = if ($Arguments.Count -gt 2) { ($Arguments[2..($Arguments.Count - 1)] -join ' ') } else { "" }

# ── Resolve paths ──

$ProjectDir = (Get-Location).Path
$SessionDir = Join-Path $ProjectDir ".devteam"
$SessionFile = Join-Path $SessionDir "session.json"

# ── Route subcommands ──

switch ($Command) {
    'stop' {
        Invoke-StopSession -SessionDir $SessionDir -SessionFile $SessionFile
        exit 0
    }
    'status' {
        Show-TeamStatus -SessionFile $SessionFile
        exit 0
    }
    'layout' {
        Show-TeamLayout -SessionFile $SessionFile
        exit 0
    }
    'add-agent' {
        Invoke-AddAgent -AgentType $Arg1 -Domain $Arg2 -SessionDir $SessionDir -SessionFile $SessionFile -ProjectDir $ProjectDir
        exit 0
    }
    'msg' {
        if (-not $Arg1) {
            Write-Host "Usage: devteam msg <agent-name> <message>" -ForegroundColor Yellow
            Write-Host "  Example: devteam msg builder-1 `"Implement the login page`"" -ForegroundColor Gray
            exit 1
        }
        $msgBody = $RestArgs
        if (-not $msgBody) {
            Write-Host "Usage: devteam msg <agent-name> <message>" -ForegroundColor Yellow
            exit 1
        }
        Invoke-SendMessage -AgentName $Arg1 -Message $msgBody -SessionDir $SessionDir -SessionFile $SessionFile -CallerName "user"
        exit 0
    }
    'task' {
        # Shorthand: devteam task "message" -> devteam msg architect "message"
        $taskMsg = if ($Arguments.Count -gt 1) { ($Arguments[1..($Arguments.Count - 1)] -join ' ') } else { "" }
        if (-not $taskMsg) {
            Write-Host "Usage: devteam task <message>" -ForegroundColor Yellow
            Write-Host "  Sends a task to the Architect. Shorthand for: devteam msg architect <message>" -ForegroundColor Gray
            exit 1
        }
        Invoke-SendMessage -AgentName "architect" -Message $taskMsg -SessionDir $SessionDir -SessionFile $SessionFile -CallerName "user"
        exit 0
    }
    'fabric' {
        # Fabric team mode: devteam --fabric "ticket 139" or devteam --fabric "BI-139"
        $fabricTask = if ($Arguments.Count -gt 1) { ($Arguments[1..($Arguments.Count - 1)] -join ' ') } else { "" }
        $fabricTask = $fabricTask -replace '^\s*-Task\s+', ''
        Invoke-StartFabricTeam -Task $fabricTask -ProjectDir $ProjectDir -SessionDir $SessionDir -SessionFile $SessionFile
    }
    default {
        # $Command/$RawCommand is the task string (or empty) -- use original arguments
        $Task = ($Arguments -join ' ')
        # Strip leading "-Task" if the old profile function passed it as a parameter name
        $Task = $Task -replace '^\s*-Task\s+', ''
        Invoke-StartTeam -Task $Task -ProjectDir $ProjectDir -SessionDir $SessionDir -SessionFile $SessionFile
    }
}
