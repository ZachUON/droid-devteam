# Development Team Orchestrator v4 for WezTerm
# Spawns 4 coordinated agents with file-based communication + cross-pane send-text
# Session files are created in .devteam/ inside the current working directory.
#
# Usage:
#   devteam                     # Spawn full team, no task
#   devteam "Build a REST API"  # Spawn full team with task
#   devteam stop                # Kill current session
#   devteam status              # Show consolidated team status
#
# Layout:
#   +------------------+------------------+
#   |                  |     Builder      |
#   |    Architect     +--------+---------+
#   |   (current)      | Valid. | Spec.   |
#   +------------------+--------+---------+

param(
    [Parameter(Position=0, Mandatory=$false)]
    [string]$Task = "",

    [Parameter(Position=1, Mandatory=$false)]
    [ValidateSet('architect', 'builder', 'validator', 'specialist', 'all')]
    [string]$Agent = 'all',

    [Parameter(Position=2, Mandatory=$false)]
    [string]$Domain = $null
)

$ErrorActionPreference = "Stop"
$WezTermExe = "wezterm"

# Session files live in .devteam/ relative to wherever the command is run
$ProjectDir = (Get-Location).Path
$TeamSessionDir = Join-Path $ProjectDir ".devteam"
$SessionFile = Join-Path $TeamSessionDir "session.json"

# ── Handle subcommands: stop, status ──

if ($Task -eq 'stop') {
    if (Test-Path $SessionFile) {
        $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
        Write-Host "Stopping team session (started $($session.started))..." -ForegroundColor Yellow

        foreach ($paneId in $session.pane_ids | Sort-Object -Descending) {
            try {
                & $WezTermExe cli kill-pane --pane-id $paneId 2>&1 | Out-Null
            } catch { }
        }

        $archiveLabel = $session.started -replace ':', '-'
        $archiveDir = Join-Path $TeamSessionDir "archive\$archiveLabel"
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        Move-Item (Join-Path $TeamSessionDir "scratchpad.md") $archiveDir -ErrorAction SilentlyContinue
        Move-Item (Join-Path $TeamSessionDir "inbox-*.md") $archiveDir -ErrorAction SilentlyContinue
        Move-Item $SessionFile $archiveDir -ErrorAction SilentlyContinue

        Write-Host "Session stopped and archived to $archiveDir" -ForegroundColor Green
    } else {
        Write-Host "No active team session in $TeamSessionDir" -ForegroundColor Yellow
    }
    exit 0
}

if ($Task -eq 'status') {
    if (-not (Test-Path $SessionFile)) {
        Write-Host "No active team session in $TeamSessionDir" -ForegroundColor Yellow
        exit 0
    }

    $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Team Session Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Project:  $ProjectDir" -ForegroundColor White
    Write-Host "Started:  $($session.started)" -ForegroundColor White
    Write-Host "Task:     $($session.task)" -ForegroundColor White
    Write-Host ""

    $livePanes = @()
    try {
        $livePanes = (& $WezTermExe cli list --format json | ConvertFrom-Json) | ForEach-Object { "$($_.pane_id)" }
    } catch { }

    Write-Host "AGENTS:" -ForegroundColor Yellow
    $agents = $session.agents.PSObject.Properties
    foreach ($agent in $agents) {
        $alive = if ($agent.Value -in $livePanes) { "ALIVE" } else { "DEAD" }
        $color = if ($alive -eq "ALIVE") { "Green" } else { "Red" }
        Write-Host "  $($agent.Name) (pane $($agent.Value)): $alive" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "INBOXES:" -ForegroundColor Yellow
    foreach ($agentName in @('architect', 'builder', 'validator', 'specialist')) {
        $inboxPath = Join-Path $TeamSessionDir "inbox-$agentName.md"
        if (Test-Path $inboxPath) {
            $content = Get-Content $inboxPath -Raw
            $pending = ([regex]::Matches($content, '- \[ \]')).Count
            $completed = ([regex]::Matches($content, '- \[x\]')).Count
            Write-Host "  $agentName`: $pending pending, $completed completed" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "SCRATCHPAD:" -ForegroundColor Yellow
    $scratchpadPath = Join-Path $TeamSessionDir "scratchpad.md"
    if (Test-Path $scratchpadPath) {
        $scratchpad = Get-Content $scratchpadPath -Raw
        $sections = @('Architecture Decisions', 'Implementation Notes', 'Validation Findings', 'Domain Insights')
        foreach ($section in $sections) {
            $pattern = "### $section\s*\n(.*?)(?=\n### |\z)"
            $match = [regex]::Match($scratchpad, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($match.Success) {
                $body = $match.Groups[1].Value.Trim()
                $hasContent = $body -ne "" -and $body -notmatch '^<!--.*-->$'
                $status = if ($hasContent) { "HAS CONTENT" } else { "empty" }
                $color = if ($hasContent) { "Green" } else { "DarkGray" }
                Write-Host "  $section`: $status" -ForegroundColor $color
            }
        }
    }

    Write-Host ""
    Write-Host "FILES:" -ForegroundColor Yellow
    Write-Host "  $TeamSessionDir" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
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

# ── Session Management ──

function Stop-ExistingSession {
    if (Test-Path $SessionFile) {
        $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
        Write-Host "Killing existing team session (started $($session.started))..." -ForegroundColor Yellow

        foreach ($paneId in $session.pane_ids | Sort-Object -Descending) {
            try {
                & $WezTermExe cli kill-pane --pane-id $paneId 2>&1 | Out-Null
            } catch { }
        }

        $archiveLabel = $session.started -replace ':', '-'
        $archiveDir = Join-Path $TeamSessionDir "archive\$archiveLabel"
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        Move-Item (Join-Path $TeamSessionDir "scratchpad.md") $archiveDir -ErrorAction SilentlyContinue
        Move-Item (Join-Path $TeamSessionDir "inbox-*.md") $archiveDir -ErrorAction SilentlyContinue
        Move-Item $SessionFile $archiveDir -ErrorAction SilentlyContinue

        Start-Sleep -Milliseconds 500
        Write-Host "Previous session archived." -ForegroundColor Green
    }
}

# ── Coordination Files ──

function Initialize-TeamSession {
    param([string]$TaskDescription)

    New-Item -ItemType Directory -Path $TeamSessionDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TeamSessionDir "archive") -Force | Out-Null

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $taskLabel = if ($TaskDescription -ne "") { $TaskDescription } else { "Awaiting task assignment" }

    $scratchpad = @"
# Team Scratchpad
## Task: $taskLabel
## Project: $ProjectDir
## Started: $timestamp

---

### Architecture Decisions
<!-- Architect writes here -->

### Implementation Notes
<!-- Builder writes here -->

### Validation Findings
<!-- Validator writes here -->

### Domain Insights
<!-- Specialist writes here -->
"@
    Set-Content -Path (Join-Path $TeamSessionDir "scratchpad.md") -Value $scratchpad -Encoding UTF8

    $agents = @('architect', 'builder', 'validator', 'specialist')
    foreach ($agent in $agents) {
        $displayName = (Get-Culture).TextInfo.ToTitleCase($agent)
        $inbox = @"
# Inbox: $displayName
## Pending Tasks

## Completed
"@
        Set-Content -Path (Join-Path $TeamSessionDir "inbox-$agent.md") -Value $inbox -Encoding UTF8
    }

    Write-Host "Session files created in $TeamSessionDir" -ForegroundColor Green
}

function Save-SessionMetadata {
    param(
        [string]$TaskDescription,
        [hashtable]$PaneMap
    )

    $session = @{
        started    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        task       = $TaskDescription
        project    = $ProjectDir
        session_dir = $TeamSessionDir
        pane_ids   = @($PaneMap.Values | ForEach-Object { "$_" })
        agents     = @{}
    }
    foreach ($key in $PaneMap.Keys) {
        $session.agents[$key] = "$($PaneMap[$key])"
    }

    $session | ConvertTo-Json -Depth 3 | Set-Content -Path $SessionFile -Encoding UTF8
}

# ── Pane Detection ──

function Get-NewPaneId {
    param([string[]]$KnownPaneIds)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $panes = & $WezTermExe cli list --format json | ConvertFrom-Json
        $newPane = $panes | Where-Object { "$($_.pane_id)" -notin $KnownPaneIds } | Select-Object -First 1

        if ($newPane) {
            return "$($newPane.pane_id)"
        }

        Write-Warning "Attempt $attempt/3: New pane not detected yet, retrying..."
        Start-Sleep -Milliseconds (500 * $attempt)
    }

    Write-Error "FATAL: Failed to detect new pane after 3 attempts. Window may be too small."
    return $null
}

# ── Cross-Pane Communication ──

function Send-ToPane {
    param(
        [string]$PaneId,
        [string]$Text
    )
    try {
        # Step 1: Send the message text
        & $WezTermExe cli send-text --pane-id $PaneId $Text 2>&1 | Out-Null
        Start-Sleep -Milliseconds 100

        # Step 2: Send Enter key using --no-paste with \r\n
        & $WezTermExe cli send-text --pane-id $PaneId --no-paste "`r`n" 2>&1 | Out-Null
    } catch {
        Write-Warning "Failed to send text to pane $PaneId"
    }
}

# ── Main Team Spawn ──

function Invoke-DevTeam {
    param([string]$Task = $null)

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Development Team Orchestrator v4" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Project: $ProjectDir" -ForegroundColor DarkGray
    Write-Host ""

    Stop-ExistingSession

    Initialize-TeamSession -TaskDescription $Task

    $sessionDirForPrompt = $TeamSessionDir.Replace('\', '/')

    $autoStartPrefix = "IMPORTANT: You are part of a 4-agent dev team working in $ProjectDir. Session files are in $sessionDirForPrompt/. Before doing anything else, read the team scratchpad at $sessionDirForPrompt/scratchpad.md and your inbox at $sessionDirForPrompt/inbox-{ROLE}.md. The session metadata with all pane IDs is at $sessionDirForPrompt/session.json."

    $architectAutoStart = "$autoStartPrefix You are the ARCHITECT (Team Lead). You can send messages to other agents by writing to their inbox files (inbox-builder.md, inbox-validator.md, inbox-specialist.md). You can also trigger agents to check their inbox by running: wezterm cli send-text --pane-id PANE_ID --no-paste `"Check your inbox at $sessionDirForPrompt/inbox-AGENT.md for new tasks.`r`" -- CRITICAL: Always include the `` `r `` at the end to send Enter key! Get pane IDs from session.json."

    $architectPrompt = if ($Task -ne "") {
        "$architectAutoStart Your team task is: $Task. Read the scratchpad, then break down this task, write subtasks to each agent's inbox, and coordinate the team."
    } else {
        "$architectAutoStart No task assigned yet. Read the scratchpad, announce your readiness, and wait for the user to provide a task."
    }

    $builderPrompt = ($autoStartPrefix -replace '{ROLE}', 'builder') + " You are the BUILDER. Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    $validatorPrompt = ($autoStartPrefix -replace '{ROLE}', 'validator') + " You are the VALIDATOR. Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    $specialistPrompt = if ($Domain) {
        ($autoStartPrefix -replace '{ROLE}', 'specialist') + " You are the SPECIALIST ($Domain domain). Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    } else {
        ($autoStartPrefix -replace '{ROLE}', 'specialist') + " You are the SPECIALIST. Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    }

    $paneMap = @{}

    Write-Host "[1/4] Current terminal -> Architect (Team Lead)..." -ForegroundColor Cyan
    $panes = & $WezTermExe cli list --format json | ConvertFrom-Json
    $currentPaneId = ($panes | Where-Object { $_.is_active -eq $true } | Select-Object -First 1).pane_id
    $knownPanes = @("$currentPaneId")
    $paneMap['architect'] = $currentPaneId
    Write-Host "      Pane ID: $currentPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    Write-Host "[2/4] Spawning Builder (top-right)..." -ForegroundColor Cyan
    $escapedBuilderPrompt = $builderPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--right', '--percent', '60', '--pane-id', "$currentPaneId", '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid builder '$escapedBuilderPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $builderPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $builderPaneId) { Write-Error "Failed to spawn Builder. Aborting."; exit 1 }
    $knownPanes += "$builderPaneId"
    $paneMap['builder'] = $builderPaneId
    Write-Host "      Pane ID: $builderPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    Write-Host "[3/4] Spawning Validator (bottom-left of right side)..." -ForegroundColor Cyan
    $escapedValidatorPrompt = $validatorPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--pane-id', "$builderPaneId", '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid validator '$escapedValidatorPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $validatorPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $validatorPaneId) { Write-Error "Failed to spawn Validator. Aborting."; exit 1 }
    $knownPanes += "$validatorPaneId"
    $paneMap['validator'] = $validatorPaneId
    Write-Host "      Pane ID: $validatorPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    Write-Host "[4/4] Spawning Specialist (bottom-right)..." -ForegroundColor Cyan
    $escapedSpecialistPrompt = $specialistPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--right', '--percent', '50', '--pane-id', "$validatorPaneId", '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid specialist '$escapedSpecialistPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $specialistPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $specialistPaneId) { Write-Error "Failed to spawn Specialist. Aborting."; exit 1 }
    $knownPanes += "$specialistPaneId"
    $paneMap['specialist'] = $specialistPaneId
    Write-Host "      Pane ID: $specialistPaneId - SUCCESS" -ForegroundColor Green

    Save-SessionMetadata -TaskDescription $Task -PaneMap $paneMap

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Team Spawn Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Project:  $ProjectDir" -ForegroundColor Cyan
    Write-Host "Session:  $TeamSessionDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Active Agents: $($paneMap.Count)/4" -ForegroundColor Cyan
    foreach ($key in $paneMap.Keys) {
        Write-Host "  - $key (pane $($paneMap[$key]))" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "LAYOUT:" -ForegroundColor Yellow
    Write-Host "  +------------------+------------------+" -ForegroundColor Yellow
    Write-Host "  |                  |     Builder      |" -ForegroundColor Yellow
    Write-Host "  |    Architect     +--------+---------+" -ForegroundColor Yellow
    Write-Host "  |   (this pane)    | Valid. | Spec.   |" -ForegroundColor Yellow
    Write-Host "  +------------------+--------+---------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  devteam status   - Show team progress" -ForegroundColor Yellow
    Write-Host "  devteam stop     - Kill session and archive" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SESSION FILES (in project):" -ForegroundColor Yellow
    Write-Host "  .devteam/scratchpad.md" -ForegroundColor DarkGray
    Write-Host "  .devteam/inbox-{agent}.md" -ForegroundColor DarkGray
    Write-Host "  .devteam/session.json" -ForegroundColor DarkGray

    if ($Task -ne "") {
        Write-Host ""
        Write-Host "TASK: $Task" -ForegroundColor Magenta
    }

    Write-Host ""
    Write-Host "Starting Architect..." -ForegroundColor Cyan
    Start-Sleep -Milliseconds 500
    & "droid" "architect" $architectPrompt
}

# ── Single Agent Mode ──

function Invoke-SingleAgent {
    param(
        [string]$AgentName,
        [string]$Task = $null
    )

    Write-Host "Spawning $AgentName agent in $ProjectDir..." -ForegroundColor Cyan

    $prompt = "As the $AgentName, you provide expertise in development."
    if ($AgentName -eq 'architect') {
        $prompt = "As the Architect, you are the team lead. Coordinate development work."
        if ($Task -ne "") { $prompt = "As the Architect, coordinate this task: $Task" }
    }
    if ($AgentName -eq 'builder') {
        $prompt = "As the Builder, you implement features according to specifications."
        if ($Task -ne "") { $prompt = "As the Builder, implement this: $Task" }
    }
    if ($AgentName -eq 'validator') {
        $prompt = "As the Validator, you test and review code to ensure quality."
        if ($Task -ne "") { $prompt = "As the Validator, test and review this: $Task" }
    }
    if ($AgentName -eq 'specialist') {
        $prompt = "As the Specialist, you provide domain expertise."
        if ($Task -ne "") { $prompt = "As the Specialist, provide domain expertise for: $Task" }
    }

    try {
        $escapedPrompt = $prompt.Replace("'", "''")
        $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid $AgentName '$escapedPrompt'")
        & $WezTermExe $splitArgs 2>&1 | Out-Null
        Write-Host "SUCCESS: $AgentName agent spawned!" -ForegroundColor Green
    } catch {
        Write-Error "FAILED: Could not spawn $AgentName agent"
    }
}

# ── Entry Point ──

Write-Host "Running pre-flight checks..." -ForegroundColor Cyan
if (-not (Test-WezTermAvailable)) {
    exit 1
}

switch ($Agent) {
    'all' {
        Invoke-DevTeam -Task $Task
    }
    default {
        Invoke-SingleAgent -AgentName $Agent -Task $Task
    }
}
