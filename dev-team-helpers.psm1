# Dev Team Helper Module v9
# All logic for the dev-team-orchestrator

# ════════════════════════════════════════════
# Logging
# ════════════════════════════════════════════

function Write-TeamLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $colors = @{ Info = "Cyan"; Success = "Green"; Warning = "Yellow"; Error = "Red" }
    $icons  = @{ Info = "[*]"; Success = "[+]"; Warning = "[!]"; Error = "[X]" }
    Write-Host "$($icons[$Level]) $Message" -ForegroundColor $colors[$Level]
}

# ════════════════════════════════════════════
# WezTerm CLI Wrappers
# ════════════════════════════════════════════

function Invoke-WezTermSplit {
    param(
        [Parameter(Mandatory)][string]$PaneId,
        [Parameter(Mandatory)][ValidateSet("right","bottom")][string]$Direction,
        [Parameter(Mandatory)][int]$Percent,
        [string]$Cwd = $null,
        [string[]]$SpawnCommand = $null
    )

    $splitArgs = @('cli', 'split-pane', "--$Direction", '--percent', "$Percent", '--pane-id', "$PaneId")

    if ($Cwd) {
        $splitArgs += @('--cwd', $Cwd)
    }

    if ($SpawnCommand) {
        $splitArgs += @('--')
        $splitArgs += $SpawnCommand
    }

    $result = & wezterm $splitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "WezTerm split failed (exit ${LASTEXITCODE}): $result"
    }

    # wezterm cli split-pane returns the new pane ID
    $newPaneId = "$result".Trim()
    return $newPaneId
}

function Send-ToPane {
    param(
        [Parameter(Mandatory)][string]$PaneId,
        [Parameter(Mandatory)][string]$Text
    )
    # Two-step approach: pipe text via stdin, then send Enter separately
    # Piping via stdin is more reliable than passing as CLI argument for long/complex text
    $result = $Text | wezterm cli send-text --pane-id $PaneId --no-paste 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-TeamLog "send-text failed for pane ${PaneId}: $result" -Level Warning
    }
    Start-Sleep -Milliseconds 200
    $result2 = "`r`n" | wezterm cli send-text --pane-id $PaneId --no-paste 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-TeamLog "send-text Enter failed for pane ${PaneId}: $result2" -Level Warning
    }
}

# ════════════════════════════════════════════
# Session Management
# ════════════════════════════════════════════

function Initialize-SessionFiles {
    param(
        [string]$SessionDir,
        [string]$ProjectDir,
        [string]$Task
    )

    New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $SessionDir "archive") -Force | Out-Null

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $taskLabel = if ($Task) { $Task } else { "Awaiting task assignment" }

    # Create scratchpad
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
<!-- Expert writes here -->

### Research Findings
<!-- Research writes here -->
"@
    Set-Content -Path (Join-Path $SessionDir "scratchpad.md") -Value $scratchpad -Encoding UTF8

    # Create inboxes for initial agents
    $agents = @('architect', 'validator', 'expert-1', 'builder-1', 'research-1')
    foreach ($agent in $agents) {
        $baseName = $agent -replace '-\d+$', ''
        $displayName = (Get-Culture).TextInfo.ToTitleCase($baseName)
        $inbox = @"
# Inbox: $displayName ($agent)
## Pending Tasks

## Completed
"@
        Set-Content -Path (Join-Path $SessionDir "inbox-$agent.md") -Value $inbox -Encoding UTF8
    }

    # Create devteam proxy script (agents can't use the profile function)
    $orchestratorPath = "$env:USERPROFILE\.factory\scripts\dev-team-orchestrator.ps1"
    $proxyScript = @'
# devteam proxy - callable from droid EXECUTE tool
# Usage: & .\.devteam\devteam.ps1 msg builder-1 "Your task here"
#        & .\.devteam\devteam.ps1 add-agent expert frontend
param([Parameter(ValueFromRemainingArguments)][string[]]$Params)

$scriptDir = $PSScriptRoot
$cmd = if ($Params.Count -gt 0) { $Params[0] } else { '' }
$arg1 = if ($Params.Count -gt 1) { $Params[1] } else { '' }
$rest = if ($Params.Count -gt 2) { ($Params[2..($Params.Count - 1)] -join ' ') } else { '' }

switch ($cmd) {
    'msg' {
        if (-not $arg1 -or -not $rest) {
            Write-Host "Usage: & .\.devteam\devteam.ps1 msg <agent-name> <message>"
            exit 1
        }
        $sessionFile = Join-Path $scriptDir 'session.json'
        if (-not (Test-Path $sessionFile)) { Write-Error "No session.json found"; exit 1 }
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $paneId = $session.agents.$arg1
        if (-not $paneId) {
            Write-Host "Agent '$arg1' not found. Available agents:"
            foreach ($p in $session.agents.PSObject.Properties) { Write-Host "  - $($p.Name) (pane $($p.Value))" }
            exit 1
        }
        $inboxPath = Join-Path $scriptDir "inbox-$arg1.md"
        if (-not (Test-Path $inboxPath)) {
            Set-Content $inboxPath "# Inbox: $arg1`n## Pending Tasks`n`n## Completed" -Encoding UTF8
        }
        $ts = Get-Date -Format 'HH:mm:ss'
        $content = Get-Content $inboxPath -Raw
        $content = $content -replace '(## Pending Tasks\r?\n)', "`$1- [ ] [$ts from Architect] $rest`n"
        Set-Content $inboxPath $content -Encoding UTF8
        "New task in your inbox from Architect. Read inbox-$arg1.md now." | wezterm cli send-text --pane-id $paneId --no-paste
        Start-Sleep -Milliseconds 200
        "`r`n" | wezterm cli send-text --pane-id $paneId --no-paste
        Write-Host "Message sent to $arg1 (pane $paneId): $rest"
    }
    'add-agent' {
        $orchPath = Join-Path $env:USERPROFILE '.factory\scripts\dev-team-orchestrator.ps1'
        if (Test-Path $orchPath) {
            & $orchPath @Params
        } else {
            Write-Error "Orchestrator not found at $orchPath"
        }
    }
    'notify' {
        # Lightweight: just send a pane notification (no inbox write)
        if (-not $arg1 -or -not $rest) {
            Write-Host "Usage: & .\.devteam\devteam.ps1 notify <agent-name> <message>"
            exit 1
        }
        $sessionFile = Join-Path $scriptDir 'session.json'
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $paneId = $session.agents.$arg1
        if (-not $paneId) { Write-Error "Agent '$arg1' not found"; exit 1 }
        "$rest" | wezterm cli send-text --pane-id $paneId --no-paste
        Start-Sleep -Milliseconds 200
        "`r`n" | wezterm cli send-text --pane-id $paneId --no-paste
        Write-Host "Notified $arg1 (pane $paneId)"
    }
    default {
        $orchPath = Join-Path $env:USERPROFILE '.factory\scripts\dev-team-orchestrator.ps1'
        if (Test-Path $orchPath) {
            & $orchPath @Params
        } else {
            Write-Error "Orchestrator not found at $orchPath"
        }
    }
}
'@
    Set-Content -Path (Join-Path $SessionDir "devteam.ps1") -Value $proxyScript -Encoding UTF8

    Write-TeamLog "Session files created in $SessionDir" -Level Success
}

function Save-Session {
    param(
        [string]$SessionFile,
        [string]$Task,
        [string]$ProjectDir,
        [string]$SessionDir,
        [hashtable]$PaneMap,
        [hashtable]$Rows
    )

    $session = @{
        started     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        task        = $Task
        project     = $ProjectDir
        session_dir = $SessionDir
        agents      = @{}
        rows        = @{
            expert   = @{ agents = @() }
            builder  = @{ agents = @() }
            research = @{ agents = @() }
        }
    }

    foreach ($key in $PaneMap.Keys) {
        $session.agents[$key] = "$($PaneMap[$key])"
    }

    foreach ($rowName in $Rows.Keys) {
        $session.rows[$rowName] = $Rows[$rowName]
    }

    $session | ConvertTo-Json -Depth 10 | Set-Content $SessionFile -Encoding UTF8
}

function Read-Session {
    param([string]$SessionFile)
    if (-not (Test-Path $SessionFile)) {
        throw "No active session. Run 'devteam' first to start a team."
    }
    return (Get-Content $SessionFile -Raw | ConvertFrom-Json)
}

function Update-Session {
    param(
        [string]$SessionFile,
        [PSCustomObject]$Session
    )
    $Session | ConvertTo-Json -Depth 10 | Set-Content $SessionFile -Encoding UTF8
}

# ════════════════════════════════════════════
# Stop Session
# ════════════════════════════════════════════

function Invoke-StopSession {
    param(
        [string]$SessionDir,
        [string]$SessionFile
    )

    if (-not (Test-Path $SessionFile)) {
        Write-TeamLog "No active session found." -Level Warning
        return
    }

    $session = Read-Session -SessionFile $SessionFile
    Write-TeamLog "Stopping team session started at $($session.started)..." -Level Warning

    # Kill all panes (skip the current one - architect)
    $currentPane = $env:WEZTERM_PANE
    foreach ($agentName in $session.agents.PSObject.Properties.Name) {
        $paneId = $session.agents.$agentName
        if ($paneId -and $paneId -ne $currentPane) {
            try {
                wezterm cli kill-pane --pane-id $paneId 2>&1 | Out-Null
            } catch { }
        }
    }

    # Archive session
    $archiveLabel = $session.started -replace ':', '-'
    $archiveDir = Join-Path $SessionDir "archive/$archiveLabel"
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    Move-Item (Join-Path $SessionDir "scratchpad.md") $archiveDir -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $SessionDir "inbox-*.md") | Move-Item -Destination $archiveDir -ErrorAction SilentlyContinue
    Move-Item $SessionFile $archiveDir -ErrorAction SilentlyContinue

    Write-TeamLog "Session archived to $archiveDir" -Level Success
}

# ════════════════════════════════════════════
# Status & Layout
# ════════════════════════════════════════════

function Show-TeamStatus {
    param([string]$SessionFile)

    if (-not (Test-Path $SessionFile)) {
        Write-TeamLog "No active session found." -Level Warning
        return
    }

    $session = Read-Session -SessionFile $SessionFile

    Write-Host ""
    Write-Host "=== Dev Team Status ===" -ForegroundColor Cyan
    Write-Host "Task:    $($session.task)" -ForegroundColor White
    Write-Host "Project: $($session.project)" -ForegroundColor White
    Write-Host "Started: $($session.started)" -ForegroundColor White
    Write-Host ""
    Write-Host "Agents:" -ForegroundColor Yellow

    foreach ($prop in $session.agents.PSObject.Properties) {
        $name = $prop.Name
        $paneId = $prop.Value
        Write-Host "  $name -> pane $paneId" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Rows:" -ForegroundColor Yellow
    foreach ($rowName in @('expert', 'builder', 'research')) {
        $row = $session.rows.$rowName
        $agentNames = ($row.agents | ForEach-Object { $_.name }) -join ', '
        if (-not $agentNames) { $agentNames = "(empty)" }
        Write-Host "  $($rowName.ToUpper()): $agentNames" -ForegroundColor Gray
    }
    Write-Host ""
}

function Show-TeamLayout {
    param([string]$SessionFile)

    if (-not (Test-Path $SessionFile)) {
        Write-Host ""
        Write-Host "Default layout:" -ForegroundColor Cyan
        Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
        Write-Host "  |          | E1 | E2 | E3 |  Expert row" -ForegroundColor Yellow
        Write-Host "  |    A     +----+----+----+" -ForegroundColor Yellow
        Write-Host "  |          | B1 | B2 | B3 |  Builder row" -ForegroundColor Yellow
        Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
        Write-Host "  |    V     | R1 | R2 |    |  Research row" -ForegroundColor Yellow
        Write-Host "  +----------+----+----+----+" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $session = Read-Session -SessionFile $SessionFile

    $expertCount   = ($session.rows.expert.agents   | Measure-Object).Count
    $builderCount  = ($session.rows.builder.agents  | Measure-Object).Count
    $researchCount = ($session.rows.research.agents | Measure-Object).Count

    Write-Host ""
    Write-Host "=== Current Layout ===" -ForegroundColor Cyan
    Write-Host ""

    # Build expert row display
    $expertCells = ($session.rows.expert.agents | ForEach-Object { " $($_.name) " }) -join '|'
    $builderCells = ($session.rows.builder.agents | ForEach-Object { " $($_.name) " }) -join '|'
    $researchCells = ($session.rows.research.agents | ForEach-Object { " $($_.name) " }) -join '|'

    Write-Host "  +----------+$('-' * [Math]::Max(20, $expertCells.Length + 2))+" -ForegroundColor DarkGray
    Write-Host "  |          |$expertCells|" -ForegroundColor White
    Write-Host "  | Architect+$('-' * [Math]::Max(20, $builderCells.Length + 2))+" -ForegroundColor DarkGray
    Write-Host "  |          |$builderCells|" -ForegroundColor White
    Write-Host "  +----------+$('-' * [Math]::Max(20, $researchCells.Length + 2))+" -ForegroundColor DarkGray
    Write-Host "  | Validator|$researchCells|" -ForegroundColor White
    Write-Host "  +----------+$('-' * [Math]::Max(20, $researchCells.Length + 2))+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Totals: $expertCount experts, $builderCount builders, $researchCount researchers" -ForegroundColor Gray
    Write-Host ""
}

# ════════════════════════════════════════════
# Send Message to Agent
# ════════════════════════════════════════════

function Invoke-SendMessage {
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)][string]$Message,
        [string]$SessionDir,
        [string]$SessionFile,
        [string]$CallerName = "user"
    )

    if (-not (Test-Path $SessionFile)) {
        Write-TeamLog "No active session. Run 'devteam' first." -Level Error
        return
    }

    $session = Read-Session -SessionFile $SessionFile

    # Find the pane ID for this agent
    $paneId = $null
    foreach ($prop in $session.agents.PSObject.Properties) {
        if ($prop.Name -eq $AgentName) {
            $paneId = $prop.Value
            break
        }
    }

    if (-not $paneId) {
        Write-TeamLog "Agent '$AgentName' not found in session." -Level Error
        Write-Host "  Active agents:" -ForegroundColor Gray
        foreach ($prop in $session.agents.PSObject.Properties) {
            Write-Host "    - $($prop.Name) (pane $($prop.Value))" -ForegroundColor Gray
        }
        return
    }

    # Append to agent's inbox
    $inboxPath = Join-Path $SessionDir "inbox-$AgentName.md"
    if (-not (Test-Path $inboxPath)) {
        # Create inbox if it doesn't exist yet
        $inbox = @"
# Inbox: $AgentName
## Pending Tasks

## Completed
"@
        Set-Content -Path $inboxPath -Value $inbox -Encoding UTF8
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    $entry = "- [ ] [$timestamp from $CallerName] $Message"

    # Insert the task under "## Pending Tasks"
    $content = Get-Content $inboxPath -Raw
    $content = $content -replace '(## Pending Tasks\r?\n)', "`$1$entry`n"
    Set-Content -Path $inboxPath -Value $content -Encoding UTF8

    # Notify the agent's pane
    $notification = "New task in your inbox from $CallerName. Read inbox-$AgentName.md now."
    Send-ToPane -PaneId $paneId -Text $notification

    Write-TeamLog "Message sent to $AgentName (pane $paneId)" -Level Success
    Write-Host "  Inbox: $inboxPath" -ForegroundColor Gray
    Write-Host "  Message: $Message" -ForegroundColor Gray
}

# ════════════════════════════════════════════
# Add Agent (dynamic splitting)
# ════════════════════════════════════════════

function Invoke-AddAgent {
    param(
        [string]$AgentType,
        [string]$Domain,
        [string]$SessionDir,
        [string]$SessionFile,
        [string]$ProjectDir
    )

    if (-not $AgentType) {
        Write-TeamLog "Usage: devteam add-agent <type> [domain]" -Level Error
        Write-Host "  Types: expert, builder, research" -ForegroundColor Gray
        Write-Host "  Example: devteam add-agent expert frontend" -ForegroundColor Gray
        Write-Host "  Example: devteam add-agent builder" -ForegroundColor Gray
        Write-Host "  Example: devteam add-agent research" -ForegroundColor Gray
        return
    }

    $AgentType = $AgentType.ToLower()
    if ($AgentType -notin @('expert', 'builder', 'research')) {
        Write-TeamLog "Invalid type: $AgentType. Must be: expert, builder, or research" -Level Error
        return
    }

    $session = Read-Session -SessionFile $SessionFile
    $row = $session.rows.$AgentType

    # Find the last agent in this row to split from
    $existingAgents = @($row.agents)
    if ($existingAgents.Count -eq 0) {
        Write-TeamLog "No existing $AgentType agents found in session. Session may be corrupt." -Level Error
        return
    }

    $lastAgent = $existingAgents[-1]
    $lastPaneId = $lastAgent.pane_id

    # Generate new agent name
    $nextNum = $existingAgents.Count + 1
    if ($AgentType -eq 'expert' -and $Domain) {
        $newName = "expert-$($Domain.ToLower() -replace '[^a-z0-9]', '')"
        # Avoid duplicate domain names
        $existing = $existingAgents | Where-Object { $_.name -eq $newName }
        if ($existing) {
            $newName = "${newName}-${nextNum}"
        }
    } else {
        $newName = "$AgentType-$nextNum"
    }

    Write-TeamLog "Adding $AgentType agent: $newName (splitting pane $lastPaneId)..." -Level Info

    # Split the last agent's pane RIGHT to create a side-by-side agent
    try {
        $newPaneId = Invoke-WezTermSplit -PaneId $lastPaneId -Direction "right" -Percent 50 -Cwd $ProjectDir
    } catch {
        Write-TeamLog "Failed to split pane: $_" -Level Error
        return
    }

    Start-Sleep -Milliseconds 300

    # Create inbox for new agent
    $sessionDirForPrompt = $SessionDir.Replace('\', '/')
    $inbox = @"
# Inbox: $newName
## Pending Tasks

## Completed
"@
    Set-Content -Path (Join-Path $SessionDir "inbox-$newName.md") -Value $inbox -Encoding UTF8

    # Build prompt for new agent
    $domainStr = if ($Domain) { " specializing in $Domain" } else { "" }
    $reportBack = "When your work is done, write findings to scratchpad.md, mark tasks complete in your inbox, then NOTIFY THE ARCHITECT by running: & .\.devteam\devteam.ps1 notify architect 'Your-status-message'. You are not done until the Architect knows."

    $rolePrompt = switch ($AgentType) {
        'expert'   { "You are $newName, a domain EXPERT$domainStr. Do your assigned work, write to scratchpad, notify Architect when done." }
        'builder'  { "You are $newName, a BUILDER$domainStr. Implement assigned tasks, write progress to scratchpad, notify Architect when done. If Validator finds issues, fix them." }
        'research' { "You are $newName, a RESEARCHER$domainStr. Search local directory ONLY first. If insufficient, do web research. Write findings to scratchpad Research Findings section, notify Architect when done." }
    }

    $prompt = "$rolePrompt $reportBack Session dir: $sessionDirForPrompt/. Read scratchpad.md and inbox-$newName.md, then announce readiness."

    # Spawn the droid in the new pane
    $escapedPrompt = $prompt -replace "'", "''"
    Send-ToPane -PaneId $newPaneId -Text "droid $AgentType '$escapedPrompt'"

    # Update session.json
    $newAgentEntry = @{ name = $newName; pane_id = $newPaneId; domain = $Domain }

    # PowerShell JSON deserialization creates PSCustomObject arrays, need to handle both cases
    $currentAgents = @($row.agents)
    $updatedAgents = @()
    foreach ($a in $currentAgents) {
        $updatedAgents += @{ name = $a.name; pane_id = $a.pane_id; domain = $a.domain }
    }
    $updatedAgents += $newAgentEntry

    $session.rows.$AgentType.agents = $updatedAgents
    $session.agents | Add-Member -NotePropertyName $newName -NotePropertyValue $newPaneId -Force

    Update-Session -SessionFile $SessionFile -Session $session

    Write-TeamLog "Agent $newName added in pane $newPaneId" -Level Success
    Write-Host "  Inbox: $SessionDir/inbox-$newName.md" -ForegroundColor Gray
    Write-Host "  Pane:  $newPaneId" -ForegroundColor Gray
}

# ════════════════════════════════════════════
# Start Team (main entry point)
# ════════════════════════════════════════════

function Invoke-StartTeam {
    param(
        [string]$Task,
        [string]$ProjectDir,
        [string]$SessionDir,
        [string]$SessionFile
    )

    Write-Host ""
    Write-Host "+==========================================+" -ForegroundColor Magenta
    Write-Host "|   Factory Droid Dev Team v9.0            |" -ForegroundColor Magenta
    Write-Host "+==========================================+" -ForegroundColor Magenta
    Write-Host ""

    # Check for WezTerm
    $basePaneId = $env:WEZTERM_PANE
    if (-not $basePaneId) {
        Write-TeamLog "Not running inside WezTerm. Please start WezTerm first." -Level Error
        exit 1
    }

    # Guard: if a session already exists, only the original Architect pane can restart
    if (Test-Path $SessionFile) {
        try {
            $existingSession = Get-Content $SessionFile -Raw | ConvertFrom-Json
            $architectPane = $existingSession.agents.architect
            if ($architectPane -and $architectPane -ne "$basePaneId") {
                Write-TeamLog "Session already active! Architect is in pane $architectPane, you are in pane $basePaneId." -Level Error
                Write-Host "  If an agent ran 'devteam' by mistake, that's the cause." -ForegroundColor Yellow
                Write-Host "  To restart: run 'devteam stop' from ANY pane first, then 'devteam' again." -ForegroundColor Yellow
                exit 1
            }
        } catch { }
        Write-TeamLog "Found existing session. Archiving..." -Level Warning
        Invoke-StopSession -SessionDir $SessionDir -SessionFile $SessionFile
        Start-Sleep -Milliseconds 300
    }

    # Create session files
    Initialize-SessionFiles -SessionDir $SessionDir -ProjectDir $ProjectDir -Task $Task

    $sessionDirForPrompt = $SessionDir.Replace('\', '/')
    $paneMap = @{}
    $rows = @{
        expert   = @{ agents = @() }
        builder  = @{ agents = @() }
        research = @{ agents = @() }
    }

    # ── STEP 1: Architect is the current pane ──
    Write-TeamLog "1/5 Architect -> current pane $basePaneId" -Level Info
    $paneMap['architect'] = $basePaneId

    # ── STEP 2: Split RIGHT to create the right side (80%) ──
    Write-TeamLog "2/5 Creating right column..." -Level Info
    $rightSideId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "right" -Percent 80 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    # ── STEP 3: Split LEFT column DOWN for Validator (bottom 30%) ──
    Write-TeamLog "3/5 Splitting left column for Validator..." -Level Info
    $validatorId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "bottom" -Percent 30 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    $paneMap['validator'] = $validatorId

    # ── STEP 4: Split RIGHT side DOWN into 3 rows ──
    # rightSideId becomes Expert row (top 33%)
    Write-TeamLog "4/5 Creating Expert, Builder, Research rows..." -Level Info
    $builderResearchId = Invoke-WezTermSplit -PaneId $rightSideId -Direction "bottom" -Percent 67 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    # builderResearchId splits into Builder (top 50%) and Research (bottom 50%)
    $researchId = Invoke-WezTermSplit -PaneId $builderResearchId -Direction "bottom" -Percent 50 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    $expertPaneId  = $rightSideId
    $builderPaneId = $builderResearchId
    $researchPaneId = $researchId

    # Track in rows
    $rows['expert']   = @{ agents = @(@{ name = "expert-1";   pane_id = $expertPaneId;  domain = "" }) }
    $rows['builder']  = @{ agents = @(@{ name = "builder-1";  pane_id = $builderPaneId; domain = "" }) }
    $rows['research'] = @{ agents = @(@{ name = "research-1"; pane_id = $researchPaneId; domain = "" }) }

    $paneMap['expert-1']   = $expertPaneId
    $paneMap['builder-1']  = $builderPaneId
    $paneMap['research-1'] = $researchPaneId

    # ── STEP 5: Spawn agents ──
    Write-TeamLog "5/5 Spawning agents..." -Level Info

    # Build prompts
    $baseCtx = "You are part of an AI dev team in $ProjectDir. Session files: $sessionDirForPrompt/. Read scratchpad.md and your inbox FIRST. Pane IDs are in session.json - use two-step send-text to communicate."

    $architectPrompt = if ($Task) {
        "$baseCtx You are the ARCHITECT (Team Lead). Task: $Task. Read your droid instructions carefully. CRITICAL: use the proxy script for ALL commands. To assign tasks run: & .\.devteam\devteam.ps1 msg AGENT-NAME message - this writes to their inbox AND notifies their pane. To spawn agents run: & .\.devteam\devteam.ps1 add-agent TYPE. Do NOT use bare 'devteam' - it will not work from your EXECUTE tool. WORKFLOW: 1-Assess research needs, spawn researchers. 2-Assign each researcher a topic with the msg command. 3-WAIT for research findings. 4-Based on findings spawn experts and builders. 5-Assign tasks with msg command. 6-Send to Validator with msg command. 7-Build-validate loop until Validator passes. 8-YOU review final result. 9-If anything missing, send back to builders. 10-Only report done when fully complete."
    } else {
        "$baseCtx You are the ARCHITECT (Team Lead). No task yet. Read scratchpad and inbox, announce readiness. Use '& .\.devteam\devteam.ps1 msg AGENT message' to assign tasks and '& .\.devteam\devteam.ps1 add-agent TYPE' to spawn agents. Do NOT use bare 'devteam'. When you get a task, FIRST assess research needs, spawn researchers, wait for findings, THEN spawn experts and builders. Never stop until the full task is delivered."
    }

    $notifyCmd = "& .\.devteam\devteam.ps1 notify architect"

    $validatorPrompt = "$baseCtx You are the VALIDATOR. When you get work to test: test thoroughly, write findings to scratchpad. If PASS - notify Architect with: $notifyCmd 'Validation PASSED'. If FAIL - send issues to Builder with: & .\.devteam\devteam.ps1 msg builder-1 'BUG: details' then notify Architect. The build-validate loop continues until you pass. Read inbox at $sessionDirForPrompt/inbox-validator.md now."

    $expertPrompt = "$baseCtx You are expert-1, a domain EXPERT. Do your assigned work, write findings to scratchpad, then NOTIFY THE ARCHITECT when done with: $notifyCmd 'Expert work complete. See scratchpad.' You are not done until the Architect knows. Read inbox at $sessionDirForPrompt/inbox-expert-1.md now."

    $builderPrompt = "$baseCtx You are builder-1, a BUILDER. Implement assigned tasks, write progress to scratchpad, then NOTIFY THE ARCHITECT when done with: $notifyCmd 'Build complete. Ready for validation.' If Validator finds issues, fix them and notify Architect again. Read inbox at $sessionDirForPrompt/inbox-builder-1.md now."

    $researchPrompt = "$baseCtx You are research-1, a RESEARCHER. Search local directory ONLY first - never look outside project folder. If local insufficient, do web research. Write findings to scratchpad Research Findings section, then NOTIFY THE ARCHITECT when done with: $notifyCmd 'Research complete. Findings in scratchpad.' You are not done until the Architect knows. Read inbox at $sessionDirForPrompt/inbox-research-1.md now."

    # Send droid commands to each pane
    $escapedArchPrompt = $architectPrompt -replace "'", "''"
    Send-ToPane -PaneId $validatorId     -Text "droid validator '$($validatorPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $expertPaneId    -Text "droid expert '$($expertPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $builderPaneId   -Text "droid builder '$($builderPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $researchPaneId  -Text "droid research '$($researchPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300

    # Save session
    Save-Session -SessionFile $SessionFile -Task $Task -ProjectDir $ProjectDir -SessionDir $SessionDir -PaneMap $paneMap -Rows $rows

    # Print summary
    Write-Host ""
    Write-TeamLog "Dev team is ready!" -Level Success
    Write-Host ""
    Write-Host "LAYOUT:" -ForegroundColor Yellow
    Write-Host "  +----------+--------------------+" -ForegroundColor Yellow
    Write-Host "  |          | Expert   (pane $expertPaneId)  |" -ForegroundColor Yellow
    Write-Host "  | Architect+--------------------+" -ForegroundColor Yellow
    Write-Host "  | (pane $basePaneId) | Builder  (pane $builderPaneId)  |" -ForegroundColor Yellow
    Write-Host "  +----------+--------------------+" -ForegroundColor Yellow
    Write-Host "  | Validator| Research (pane $researchPaneId)  |" -ForegroundColor Yellow
    Write-Host "  | (pane $validatorId) |                    |" -ForegroundColor Yellow
    Write-Host "  +----------+--------------------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "WORKFLOW:" -ForegroundColor Yellow
    Write-Host "  You -> Architect -> spawn Researchers -> findings -> spawn Experts/Builders -> Validator" -ForegroundColor Gray
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  devteam add-agent expert [domain]    Add an expert" -ForegroundColor Gray
    Write-Host "  devteam add-agent builder             Add a builder" -ForegroundColor Gray
    Write-Host "  devteam add-agent research             Add a researcher" -ForegroundColor Gray
    Write-Host "  devteam msg <agent> `"message`"        Send task to an agent" -ForegroundColor Gray
    Write-Host "  devteam task `"message`"                Send task to Architect" -ForegroundColor Gray
    Write-Host "  devteam status                        Show team status" -ForegroundColor Gray
    Write-Host "  devteam layout                        Show visual layout" -ForegroundColor Gray
    Write-Host "  devteam stop                          Stop and archive session" -ForegroundColor Gray
    Write-Host ""

    # Now start the Architect droid in the CURRENT pane (this replaces the orchestrator)
    Write-Host "Starting Architect agent..." -ForegroundColor Cyan
    Write-Host ""

    # The Architect droid starts in the current terminal
    droid architect "$escapedArchPrompt"
}

# ════════════════════════════════════════════
# Initialize Fabric Session Files
# ════════════════════════════════════════════

function Initialize-FabricSessionFiles {
    param(
        [string]$SessionDir,
        [string]$ProjectDir,
        [string]$Task
    )

    New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $SessionDir "archive") -Force | Out-Null

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $taskLabel = if ($Task) { $Task } else { "Awaiting task assignment" }

    # Fabric-specific scratchpad
    $scratchpad = @"
# Fabric Team Scratchpad
## Task: $taskLabel
## Project: $ProjectDir
## Started: $timestamp
## Jira Ticket: [pending]

---

### Jira Ticket Details
<!-- Architect writes ticket info here after pulling from Jira -->

### Architecture Decisions
<!-- Architect writes approach after consulting experts -->

### PySpark Expert Notes
<!-- PySpark optimization advice, F8 configs -->

### Big Data Expert Notes
<!-- Schema design, medallion layer, data patterns -->

### Fabric Deployment Log
<!-- Fabric Expert logs each upload/run/result here -->

### Builder Implementation Notes
<!-- Builder documents notebook structure, local test results -->
"@
    Set-Content -Path (Join-Path $SessionDir "scratchpad.md") -Value $scratchpad -Encoding UTF8

    # Create inboxes for Fabric team agents
    $agents = @('architect', 'fabric-expert', 'pyspark-expert-1', 'bigdata-expert-1', 'builder-1')
    foreach ($agent in $agents) {
        $baseName = $agent -replace '-\d+$', ''
        $displayName = (Get-Culture).TextInfo.ToTitleCase($baseName)
        $inbox = @"
# Inbox: $displayName ($agent)
## Pending Tasks

## Completed
"@
        Set-Content -Path (Join-Path $SessionDir "inbox-$agent.md") -Value $inbox -Encoding UTF8
    }

    # Create devteam proxy script (same as standard team)
    $proxyScript = @'
# devteam proxy - callable from droid EXECUTE tool
# Usage: & .\.devteam\devteam.ps1 msg builder-1 "Your task here"
#        & .\.devteam\devteam.ps1 add-agent expert frontend
param([Parameter(ValueFromRemainingArguments)][string[]]$Params)

$scriptDir = $PSScriptRoot
$cmd = if ($Params.Count -gt 0) { $Params[0] } else { '' }
$arg1 = if ($Params.Count -gt 1) { $Params[1] } else { '' }
$rest = if ($Params.Count -gt 2) { ($Params[2..($Params.Count - 1)] -join ' ') } else { '' }

switch ($cmd) {
    'msg' {
        if (-not $arg1 -or -not $rest) {
            Write-Host "Usage: & .\.devteam\devteam.ps1 msg <agent-name> <message>"
            exit 1
        }
        $sessionFile = Join-Path $scriptDir 'session.json'
        if (-not (Test-Path $sessionFile)) { Write-Error "No session.json found"; exit 1 }
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $paneId = $session.agents.$arg1
        if (-not $paneId) {
            Write-Host "Agent '$arg1' not found. Available agents:"
            foreach ($p in $session.agents.PSObject.Properties) { Write-Host "  - $($p.Name) (pane $($p.Value))" }
            exit 1
        }
        $inboxPath = Join-Path $scriptDir "inbox-$arg1.md"
        if (-not (Test-Path $inboxPath)) {
            Set-Content $inboxPath "# Inbox: $arg1`n## Pending Tasks`n`n## Completed" -Encoding UTF8
        }
        $ts = Get-Date -Format 'HH:mm:ss'
        $content = Get-Content $inboxPath -Raw
        $content = $content -replace '(## Pending Tasks\r?\n)', "`$1- [ ] [$ts from Architect] $rest`n"
        Set-Content $inboxPath $content -Encoding UTF8
        "New task in your inbox from Architect. Read inbox-$arg1.md now." | wezterm cli send-text --pane-id $paneId --no-paste
        Start-Sleep -Milliseconds 200
        "`r`n" | wezterm cli send-text --pane-id $paneId --no-paste
        Write-Host "Message sent to $arg1 (pane $paneId): $rest"
    }
    'add-agent' {
        $orchPath = Join-Path $env:USERPROFILE '.factory\scripts\dev-team-orchestrator.ps1'
        if (Test-Path $orchPath) {
            & $orchPath @Params
        } else {
            Write-Error "Orchestrator not found at $orchPath"
        }
    }
    'notify' {
        if (-not $arg1 -or -not $rest) {
            Write-Host "Usage: & .\.devteam\devteam.ps1 notify <agent-name> <message>"
            exit 1
        }
        $sessionFile = Join-Path $scriptDir 'session.json'
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $paneId = $session.agents.$arg1
        if (-not $paneId) { Write-Error "Agent '$arg1' not found"; exit 1 }
        "$rest" | wezterm cli send-text --pane-id $paneId --no-paste
        Start-Sleep -Milliseconds 200
        "`r`n" | wezterm cli send-text --pane-id $paneId --no-paste
        Write-Host "Notified $arg1 (pane $paneId)"
    }
    default {
        $orchPath = Join-Path $env:USERPROFILE '.factory\scripts\dev-team-orchestrator.ps1'
        if (Test-Path $orchPath) {
            & $orchPath @Params
        } else {
            Write-Error "Orchestrator not found at $orchPath"
        }
    }
}
'@
    Set-Content -Path (Join-Path $SessionDir "devteam.ps1") -Value $proxyScript -Encoding UTF8

    Write-TeamLog "Fabric session files created in $SessionDir" -Level Success
}

# ════════════════════════════════════════════
# Start Fabric Team
# ════════════════════════════════════════════

function Invoke-StartFabricTeam {
    param(
        [string]$Task,
        [string]$ProjectDir,
        [string]$SessionDir,
        [string]$SessionFile
    )

    Write-Host ""
    Write-Host "+==========================================+" -ForegroundColor Magenta
    Write-Host "|   Factory Droid Fabric Team v1.0         |" -ForegroundColor Magenta
    Write-Host "+==========================================+" -ForegroundColor Magenta
    Write-Host ""

    # Check for WezTerm
    $basePaneId = $env:WEZTERM_PANE
    if (-not $basePaneId) {
        Write-TeamLog "Not running inside WezTerm. Please start WezTerm first." -Level Error
        exit 1
    }

    # Guard: if a session already exists, only the original Architect pane can restart
    if (Test-Path $SessionFile) {
        try {
            $existingSession = Get-Content $SessionFile -Raw | ConvertFrom-Json
            $architectPane = $existingSession.agents.architect
            if ($architectPane -and $architectPane -ne "$basePaneId") {
                Write-TeamLog "Session already active! Architect is in pane $architectPane, you are in pane $basePaneId." -Level Error
                Write-Host "  If an agent ran 'devteam' by mistake, that's the cause." -ForegroundColor Yellow
                Write-Host "  To restart: run 'devteam stop' from ANY pane first, then 'devteam' again." -ForegroundColor Yellow
                exit 1
            }
        } catch { }
        Write-TeamLog "Found existing session. Archiving..." -Level Warning
        Invoke-StopSession -SessionDir $SessionDir -SessionFile $SessionFile
        Start-Sleep -Milliseconds 300
    }

    # Create Fabric-specific session files
    Initialize-FabricSessionFiles -SessionDir $SessionDir -ProjectDir $ProjectDir -Task $Task

    $sessionDirForPrompt = $SessionDir.Replace('\', '/')
    $paneMap = @{}
    $rows = @{
        expert   = @{ agents = @() }
        builder  = @{ agents = @() }
    }

    # ═══════════════════════════════════════════════════════════════
    # LAYOUT:
    #   +----------+------------------+
    #   |          | PySpark Expert   |  (row grows RIGHT)
    #   | Architect+------------------+
    #   |          | BigData Expert   |  (row grows RIGHT)
    #   +----------+------------------+
    #   | Fabric   | Builder-1        |  (row grows RIGHT)
    #   | Expert   |                  |
    #   +----------+------------------+
    # ═══════════════════════════════════════════════════════════════

    # ── STEP 1: Architect is the current pane ──
    Write-TeamLog "1/5 Architect -> current pane $basePaneId" -Level Info
    $paneMap['architect'] = $basePaneId

    # ── STEP 2: Split RIGHT for the right column (65%) ──
    Write-TeamLog "2/5 Creating right column..." -Level Info
    $rightSideId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "right" -Percent 65 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    # ── STEP 3: Split LEFT column BOTTOM for Fabric Expert (bottom 30%) ──
    Write-TeamLog "3/5 Splitting left column for Fabric Expert..." -Level Info
    $fabricExpertId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "bottom" -Percent 30 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    $paneMap['fabric-expert'] = $fabricExpertId

    # ── STEP 4: Split RIGHT side into 3 rows ──
    Write-TeamLog "4/5 Creating PySpark Expert, BigData Expert, Builder rows..." -Level Info

    # rightSideId becomes PySpark Expert row (top 33%)
    $bigdataBuilderPaneId = Invoke-WezTermSplit -PaneId $rightSideId -Direction "bottom" -Percent 67 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    # bigdataBuilderPaneId splits into BigData Expert (top 50%) and Builder (bottom 50%)
    $builderPaneId = Invoke-WezTermSplit -PaneId $bigdataBuilderPaneId -Direction "bottom" -Percent 50 -Cwd $ProjectDir
    Start-Sleep -Milliseconds 400

    $pysparkPaneId  = $rightSideId
    $bigdataPaneId  = $bigdataBuilderPaneId

    # Track in rows
    $rows['expert']  = @{ agents = @(
        @{ name = "pyspark-expert-1"; pane_id = $pysparkPaneId; domain = "pyspark" },
        @{ name = "bigdata-expert-1"; pane_id = $bigdataPaneId; domain = "bigdata" }
    ) }
    $rows['builder'] = @{ agents = @(@{ name = "builder-1"; pane_id = $builderPaneId; domain = "" }) }

    $paneMap['pyspark-expert-1'] = $pysparkPaneId
    $paneMap['bigdata-expert-1'] = $bigdataPaneId
    $paneMap['builder-1']        = $builderPaneId

    # ── STEP 5: Spawn agents ──
    Write-TeamLog "5/5 Spawning agents..." -Level Info

    $notifyCmd = "& .\.devteam\devteam.ps1 notify architect"
    $baseCtx = "You are part of a Fabric data team in $ProjectDir. Session files: $sessionDirForPrompt/. Read scratchpad.md and your inbox FIRST. CRITICAL: use '& .\.devteam\devteam.ps1 msg AGENT message' for tasks and '& .\.devteam\devteam.ps1 notify AGENT message' for notifications. Do NOT use bare 'devteam'. Pane IDs are in session.json."

    # Architect prompt
    $architectPrompt = if ($Task) {
        "$baseCtx You are the ARCHITECT (Fabric Team Lead). Task: $Task. CRITICAL: use the proxy script for ALL commands. To assign tasks: & .\.devteam\devteam.ps1 msg AGENT-NAME message. To spawn agents: & .\.devteam\devteam.ps1 add-agent TYPE. WORKFLOW: 1-If task is a ticket number (3 digits = BI-XXX), pull from Jira using atlassian___search and atlassian___fetch. 2-Write ticket details to scratchpad. 3-Ask user clarifying questions. 4-Consult pyspark-expert-1 and bigdata-expert-1 for approach. 5-Write architecture decisions to scratchpad. 6-Assign builder-1 to create notebook. 7-When builder reports ready, msg fabric-expert to deploy. 8-If fabric-expert reports errors, coordinate fix cycle. 9-Report success to user when clean logs achieved. NEVER touch Fabric directly. NEVER write notebooks. Your team: fabric-expert (deployment), pyspark-expert-1 (code quality), bigdata-expert-1 (data architecture), builder-1 (notebook creation)."
    } else {
        "$baseCtx You are the ARCHITECT (Fabric Team Lead). No task yet. Read scratchpad and inbox, announce readiness. When you get a task: 1-Parse ticket numbers (3 digits = BI-XXX), 2-Pull from Jira, 3-Consult experts, 4-Assign builder, 5-Trigger fabric-expert for deployment. Use '& .\.devteam\devteam.ps1 msg AGENT message' for all assignments."
    }

    # Fabric Expert prompt
    $fabricExpertPrompt = "$baseCtx You are the FABRIC EXPERT. You own the full Fabric deployment cycle: upload notebooks (with version naming _v1, _v2...), attach lakehouses, run jobs, poll every 60s, download driver logs. Use fabric___* MCP tools (triple underscores). When deployment fails, share errors with ALL experts and builder, wait for fix, re-deploy. Clean up old versions after success. NEVER overwrite notebooks. NEVER retry run_on_demand_job. Read inbox at $sessionDirForPrompt/inbox-fabric-expert.md now."

    # PySpark Expert prompt
    $pysparkExpertPrompt = "$baseCtx You are pyspark-expert-1, a PYSPARK EXPERT. Advise on PySpark patterns, F8 SKU optimization (16 partitions, AQE, broadcast joins), and error diagnosis. When consulted, write to scratchpad PySpark Expert Notes. When error logs arrive, diagnose PySpark issues and advise on fixes. Use memory___search_nodes to check for known patterns. Report back with: $notifyCmd 'PySpark analysis complete'. Read inbox at $sessionDirForPrompt/inbox-pyspark-expert-1.md now."

    # Big Data Expert prompt
    $bigdataExpertPrompt = "$baseCtx You are bigdata-expert-1, a BIG DATA and PIPELINES EXPERT. Advise on medallion architecture (Bronze/Silver/Gold), CDF patterns, Stellantis DMS sources (Auto/Pinnacle/Key/Units), composite keys, mapping files. Write to scratchpad Big Data Expert Notes. Diagnose data-specific errors (join explosions, column mismatches, VOID types). Report back with: $notifyCmd 'Big Data analysis complete'. Read inbox at $sessionDirForPrompt/inbox-bigdata-expert-1.md now."

    # Builder prompt
    $builderPrompt = "$baseCtx You are builder-1, a FABRIC BUILDER. Create PySpark notebooks using notebook___* MCP tools. Test locally with pyspark_execute_code(). Follow architecture from scratchpad (PySpark Expert Notes + Big Data Expert Notes). When done, notify Architect. When Fabric Expert reports errors, fix the notebook and re-test. Report back with: $notifyCmd 'Build complete. Ready for Fabric deployment.' Read inbox at $sessionDirForPrompt/inbox-builder-1.md now."

    # Send droid commands to panes (Fabric Expert, PySpark Expert, BigData Expert, Builder)
    Send-ToPane -PaneId $fabricExpertId -Text "droid fabric-expert '$($fabricExpertPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $pysparkPaneId  -Text "droid pyspark-expert '$($pysparkExpertPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $bigdataPaneId  -Text "droid bigdata-expert '$($bigdataExpertPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300
    Send-ToPane -PaneId $builderPaneId  -Text "droid fabric-builder '$($builderPrompt -replace "'", "''")'"
    Start-Sleep -Milliseconds 300

    # Save session
    Save-Session -SessionFile $SessionFile -Task $Task -ProjectDir $ProjectDir -SessionDir $SessionDir -PaneMap $paneMap -Rows $rows

    # Print summary
    Write-Host ""
    Write-TeamLog "Fabric team is ready!" -Level Success
    Write-Host ""
    Write-Host "LAYOUT:" -ForegroundColor Yellow
    Write-Host "  +----------+------------------------------+" -ForegroundColor Yellow
    Write-Host "  |          | PySpark Expert (pane $pysparkPaneId)  |" -ForegroundColor Yellow
    Write-Host "  | Architect+------------------------------+" -ForegroundColor Yellow
    Write-Host "  | (pane $basePaneId) | BigData Expert (pane $bigdataPaneId)  |" -ForegroundColor Yellow
    Write-Host "  +----------+------------------------------+" -ForegroundColor Yellow
    Write-Host "  | Fabric   | Builder-1      (pane $builderPaneId)  |" -ForegroundColor Yellow
    Write-Host "  | Expert   |                              |" -ForegroundColor Yellow
    Write-Host "  | (pane $fabricExpertId) |                              |" -ForegroundColor Yellow
    Write-Host "  +----------+------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "WORKFLOW:" -ForegroundColor Yellow
    Write-Host "  You -> Architect -> Jira -> Consult Experts -> Builder -> Fabric Expert -> Deploy" -ForegroundColor Gray
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  devteam msg <agent> `"message`"        Send task to an agent" -ForegroundColor Gray
    Write-Host "  devteam task `"message`"                Send task to Architect" -ForegroundColor Gray
    Write-Host "  devteam add-agent expert [domain]    Add another expert" -ForegroundColor Gray
    Write-Host "  devteam add-agent builder             Add another builder" -ForegroundColor Gray
    Write-Host "  devteam status                        Show team status" -ForegroundColor Gray
    Write-Host "  devteam stop                          Stop and archive session" -ForegroundColor Gray
    Write-Host ""

    # Now start the Architect droid in the CURRENT pane
    Write-Host "Starting Fabric Architect agent..." -ForegroundColor Cyan
    Write-Host ""

    $escapedArchPrompt = $architectPrompt -replace "'", "''"
    droid fabric-architect "$escapedArchPrompt"
}

# ════════════════════════════════════════════
# Exports
# ════════════════════════════════════════════

Export-ModuleMember -Function @(
    'Write-TeamLog',
    'Invoke-WezTermSplit',
    'Send-ToPane',
    'Initialize-SessionFiles',
    'Initialize-FabricSessionFiles',
    'Save-Session',
    'Read-Session',
    'Update-Session',
    'Invoke-StopSession',
    'Show-TeamStatus',
    'Show-TeamLayout',
    'Invoke-SendMessage',
    'Invoke-AddAgent',
    'Invoke-StartTeam',
    'Invoke-StartFabricTeam'
)
