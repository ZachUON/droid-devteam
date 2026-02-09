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
    # Two-step approach: send text, then send Enter separately
    wezterm cli send-text --pane-id $PaneId $Text 2>&1 | Out-Null
    Start-Sleep -Milliseconds 100
    wezterm cli send-text --pane-id $PaneId --no-paste "`r`n" 2>&1 | Out-Null
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
    $reportBack = "When your work is done, write findings to scratchpad.md, mark tasks complete in your inbox, then NOTIFY THE ARCHITECT using two-step send-text. You are not done until the Architect knows."

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

    # Stop existing session if any
    if (Test-Path $SessionFile) {
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
        "$baseCtx You are the ARCHITECT (Team Lead). Task: $Task. Read your droid instructions carefully. WORKFLOW: 1-Assess research needs and spawn researchers with 'devteam add-agent research'. 2-Assign each researcher a specific topic via their inbox, notify them. 3-WAIT for findings. 4-Based on findings spawn experts and builders with 'devteam add-agent expert DOMAIN' and 'devteam add-agent builder'. 5-Assign tasks, coordinate. 6-Send to Validator. 7-Build-validate loop until Validator passes. 8-YOU review final result. 9-If anything missing, send back to builders. 10-Only report done when task is fully complete. Agents report back to YOU - do not stop until everything is delivered."
    } else {
        "$baseCtx You are the ARCHITECT (Team Lead). No task yet. Read scratchpad and inbox, announce readiness. When you get a task, FIRST assess research needs, spawn researchers, wait for findings, THEN spawn experts and builders. Never stop until the full task is delivered."
    }

    $validatorPrompt = "$baseCtx You are the VALIDATOR. When you get work to test: test thoroughly, write findings to scratchpad. If PASS - notify Architect. If FAIL - write issues to the Builder inbox AND notify both Builder and Architect. The build-validate loop continues until you pass. Read inbox at $sessionDirForPrompt/inbox-validator.md now."

    $expertPrompt = "$baseCtx You are expert-1, a domain EXPERT. Do your assigned work, write findings to scratchpad, then NOTIFY THE ARCHITECT when done using two-step send-text. You are not done until the Architect knows. Read inbox at $sessionDirForPrompt/inbox-expert-1.md now."

    $builderPrompt = "$baseCtx You are builder-1, a BUILDER. Implement assigned tasks, write progress to scratchpad, then NOTIFY THE ARCHITECT when done. If Validator finds issues, fix them and notify Architect again. Read inbox at $sessionDirForPrompt/inbox-builder-1.md now."

    $researchPrompt = "$baseCtx You are research-1, a RESEARCHER. Search local directory ONLY first - never look outside project folder. If local insufficient, do web research. Write findings to scratchpad Research Findings section, then NOTIFY THE ARCHITECT when done using two-step send-text. You are not done until the Architect knows. Read inbox at $sessionDirForPrompt/inbox-research-1.md now."

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
    Write-Host "  devteam add-agent expert [domain]  Add an expert" -ForegroundColor Gray
    Write-Host "  devteam add-agent builder           Add a builder" -ForegroundColor Gray
    Write-Host "  devteam add-agent research           Add a researcher" -ForegroundColor Gray
    Write-Host "  devteam status                      Show team status" -ForegroundColor Gray
    Write-Host "  devteam layout                      Show visual layout" -ForegroundColor Gray
    Write-Host "  devteam stop                        Stop and archive session" -ForegroundColor Gray
    Write-Host ""

    # Now start the Architect droid in the CURRENT pane (this replaces the orchestrator)
    Write-Host "Starting Architect agent..." -ForegroundColor Cyan
    Write-Host ""

    # The Architect droid starts in the current terminal
    droid architect "$escapedArchPrompt"
}

# ════════════════════════════════════════════
# Exports
# ════════════════════════════════════════════

Export-ModuleMember -Function @(
    'Write-TeamLog',
    'Invoke-WezTermSplit',
    'Send-ToPane',
    'Initialize-SessionFiles',
    'Save-Session',
    'Read-Session',
    'Update-Session',
    'Invoke-StopSession',
    'Show-TeamStatus',
    'Show-TeamLayout',
    'Invoke-AddAgent',
    'Invoke-StartTeam'
)
