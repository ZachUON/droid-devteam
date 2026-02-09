# Development Team Orchestrator v6 for WezTerm
# Spawns coordinated agents with research-first workflow + dynamic splitting
# Session files are created in .devteam/ inside the current working directory.
#
# Usage:
#   devteam                     # Spawn full team, no task
#   devteam "Build a REST API"  # Spawn full team with task
#   devteam stop                # Kill current session
#   devteam status              # Show consolidated team status
#   devteam layout              # Show visual pane layout
#   devteam add-agent expert    # Add domain expert
#   devteam add-agent builder   # Add builder for parallel work
#   devteam add-agent research  # Add researcher
#
# Layout (research-first):
#   +------------------+------------------+
#   |    Architect     |      Expert      |
#   |   (top-left)     +------------------+
#   +------------------+     Builder      |
#   |    Validator     +------------------+
#   |   (bottom-left)  |     Research     |
#   +------------------+------------------+
#
# Workflow:
#   1. User → Architect with task
#   2. Architect → Research (finds examples, best practices)
#   3. Research → Architect (findings)
#   4. Architect → spawns Experts/Builders based on research
#   5. Team → Validator (final QA)
#
# Agent Types:
#   - Architect: Team lead, splits vertically (Architect | Validator)
#   - Expert: Domain knowledge (API, DB, frontend, etc.)
#   - Builder: Implementation (Python, C, etc.)
#   - Research: Code research, GitHub examples, best practices
#   - Validator: QA/testing - single validator sufficient

param(
    [Parameter(Position=0, Mandatory=$false)]
    [string]$Task = "",

    [Parameter(Position=1, Mandatory=$false)]
    [ValidateSet('architect', 'builder', 'validator', 'expert', 'research', 'all', 'add-agent', 'layout')]
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
<!-- Expert writes here -->

### Research Findings
<!-- Research writes here -->
"@
    Set-Content -Path (Join-Path $TeamSessionDir "scratchpad.md") -Value $scratchpad -Encoding UTF8

    $agents = @('architect', 'validator', 'expert', 'builder', 'research')
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
        pane_layout = @{
            left = @{
                agent = "architect"
                pane_id = "$($PaneMap['architect'])"
            }
            right = @{
                agents = @("expert-1", "builder-1", "validator-1", "research-1")
                split_direction = "horizontal"
            }
        }
    }
    foreach ($key in $PaneMap.Keys) {
        $session.agents[$key] = "$($PaneMap[$key])"
    }

    $session | ConvertTo-Json -Depth 10 | Set-Content -Path $SessionFile -Encoding UTF8
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

# ── Dynamic Pane Splitting ──

function Get-SplitCandidate {
    param(
        [hashtable]$Session,
        [string]$AgentType
    )

    $columns = $Session.pane_layout.columns

    # Determine which column to split
    $targetColumn = switch ($AgentType) {
        "expert" { "expert" }
        "builder" { "builder" }
        "research" { "research" }
        default { "builder" }
    }

    $column = $columns.$targetColumn

    # Check if column has 2+ agents
    if ($column.agents.Count -ge 2) {
        # Ask user which column to split
        Write-Host ""
        Write-Host "Multiple columns have 2+ agents. Which column should be split?" -ForegroundColor Yellow
        Write-Host ""

        $choices = @()
        $idx = 1

        foreach ($colName in @('expert', 'builder', 'research')) {
            $col = $columns.$colName
            $agentList = $col.agents -join ', '
            Write-Host "  [$idx] $colName.ToUpper() ($($col.agents.Count) agents: $agentList)" -ForegroundColor Cyan
            $choices += $colName
            $idx++
        }
        Write-Host "  [4] Cancel" -ForegroundColor Yellow
        Write-Host ""

        $choice = Read-Host "Enter choice (1-4)"

        if ($choice -eq "4") {
            return $null
        }

        $selectedIndex = [int]$choice - 1
        if ($selectedIndex -ge 0 -and $selectedIndex -lt 3) {
            $targetColumn = $choices[$selectedIndex]
        }
    }

    # Get the last agent in the target column to split
    $column = $columns.$targetColumn
    $lastAgentName = $column.agents[-1]
    $lastAgentPaneId = $Session.agents.$lastAgentName

    return [PSCustomObject]@{
        pane_id = $lastAgentPaneId
        name = $lastAgentName
        column = $targetColumn
        split_direction = "horizontal"  # Always split horizontally within columns
    }
}

function New-AgentName {
    param(
        [string]$AgentType,
        [hashtable]$Session,
        [string]$Domain = $null
    )

    $column = $Session.pane_layout.columns.$AgentType
    $existingCount = $column.agents.Count
    $newNumber = $existingCount + 1

    # For experts, use domain-specific naming if domain provided
    if ($AgentType -eq "expert" -and $Domain) {
        # Check if expert with this domain already exists
        $domainSlug = $Domain -replace ' ', '-' -replace '[^a-zA-Z0-9-]', ''
        $expertName = "expert-$domainSlug"

        # Check if this expert type already exists
        foreach ($agent in $column.agents) {
            if ($agent -like "*$domainSlug*") {
                Write-Warning "Expert '$domainSlug' already exists. Adding generic expert instead."
                return "expert-$newNumber"
            }
        }

        return $expertName
    }

    # Generic naming
    $baseName = switch ($AgentType) {
        "expert" { "expert" }
        "builder" { "builder" }
        "research" { "research" }
        default { "agent" }
    }

    return "$baseName-$newNumber"
}

function Add-Agent {
    param(
        [string]$AgentType,
        [string]$Domain = $null
    )

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Adding New Agent" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Load session
    if (-not (Test-Path $SessionFile)) {
        Write-Error "No active session. Run 'devteam' first."
        return
    }

    $session = Get-Content $SessionFile -Raw | ConvertFrom-Json

    # Check max capacity (15 panes)
    if ($session.pane_ids.Count -ge 15) {
        Write-Error "Maximum pane capacity reached (15). Cannot add more agents."
        return
    }

    # Validate agent type
    $AgentType = $AgentType.ToLower()
    if ($AgentType -notin @('expert', 'builder', 'validator')) {
        Write-Error "Invalid agent type: $AgentType. Must be: expert, builder, or validator"
        return
    }

    # Find split candidate
    $candidate = Get-SplitCandidate -Session $session -AgentType $AgentType

    if (-not $candidate) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }

    Write-Host "Splitting: $($candidate.name) in $($candidate.column) column" -ForegroundColor Yellow

    # Generate new agent name
    $newAgentName = New-AgentName -AgentType $AgentType -Session $session -Domain $Domain

    # Split horizontally (always within columns)
    $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--pane-id', $candidate.pane_id, '--cwd', $ProjectDir)

    try {
        $null = & $WezTermExe $splitArgs 2>&1
        Start-Sleep -Milliseconds 500

        # Detect new pane
        $knownPanes = @($session.pane_ids | ForEach-Object { "$_" })
        $newPaneId = Get-NewPaneId -KnownPaneIds $knownPanes

        if (-not $newPaneId) {
            Write-Error "Failed to detect new pane."
            return
        }

        Write-Host "New pane ID: $newPaneId" -ForegroundColor Green

        # Determine droid type
        $droidType = switch ($AgentType) {
            "expert" { if ($Domain) { "specialist" } else { "specialist" } }
            "builder" { "builder" }
            "validator" { "validator" }
            default { "builder" }
        }

        # Create prompt for new agent
        $sessionDirForPrompt = $TeamSessionDir.Replace('\', '/')
        $newAgentPrompt = "IMPORTANT: You are part of a dev team working in $ProjectDir. Session files are in $sessionDirForPrompt/. You are the $newAgentName. Read your inbox at $sessionDirForPrompt/inbox-$newAgentName.md and the scratchpad at $sessionDirForPrompt/scratchpad.md. Announce your readiness."

        if ($Domain) {
            $domainTitle = (Get-Culture).TextInfo.ToTitleCase($Domain)
            $newAgentPrompt += " You are a $domainTitle Expert providing specialized knowledge in $Domain domain."
        } else {
            $roleTitle = switch ($AgentType) {
                "expert" { "Domain Expert" }
                "builder" { "Builder" }
                "validator" { "Validator" }
            }
            $newAgentPrompt += " You are the $roleTitle."
        }

        # Spawn the droid in the new pane
        $escapedPrompt = $newAgentPrompt.Replace("'", "''")
        $spawnCmd = "droid $droidType '$escapedPrompt'"

        $null = & $WezTermExe cli send-text --pane-id $newPaneId $spawnCmd 2>&1
        Start-Sleep -Milliseconds 100
        $null = & $WezTermExe cli send-text --pane-id $newPaneId --no-paste "`r`n" 2>&1

        # Update session
        $session.pane_ids += "$newPaneId"
        $session.agents.$newAgentName = "$newPaneId"

        # Update column
        $session.pane_layout.columns.$($candidate.column).agents += $newAgentName

        # Save updated session
        $session | ConvertTo-Json -Depth 10 | Set-Content -Path $SessionFile -Encoding UTF8

        # Create inbox for new agent
        $inboxPath = Join-Path $TeamSessionDir "inbox-$newAgentName.md"
        $displayName = $newAgentName -replace '-', ' '
        $inbox = @"
# Inbox: $(Get-Culture).TextInfo.ToTitleCase($displayName)
## Pending Tasks

## Completed
"@
        Set-Content -Path $inboxPath -Value $inbox -Encoding UTF8

        $domainInfo = if ($Domain) { " ($Domain)" } else { "" }
        Write-Host "SUCCESS: $newAgentName$domainInfo added!" -ForegroundColor Green
        Write-Host "Pane ID: $newPaneId" -ForegroundColor DarkGray
        Write-Host "Inbox: $inboxPath" -ForegroundColor DarkGray

        # Notify Architect
        if ($session.agents.architect) {
            Send-ToPane -PaneId $session.agents.architect -Text "New agent '$newAgentName' has been added (pane $newPaneId). Assign tasks via inbox-$newAgentName.md"
        }

    } catch {
        Write-Error "Failed to add agent: $_"
    }
}

function Show-Layout {
    if (-not (Test-Path $SessionFile)) {
        Write-Host "No active session." -ForegroundColor Yellow
        return
    }

    $session = Get-Content $SessionFile -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Current Pane Layout" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Visual layout
    $architectPane = $session.pane_layout.left.top.pane_id
    $validatorPane = $session.pane_layout.left.bottom.pane_id
    $expertAgents = $session.pane_layout.columns.expert.agents
    $builderAgents = $session.pane_layout.columns.builder.agents
    $researchAgents = $session.pane_layout.columns.research.agents

    # Display layout
    Write-Host "    +----------------------+----------------------+" -ForegroundColor DarkGray
    Write-Host "    |    Architect         |       EXPERT         |" -ForegroundColor Cyan
    Write-Host "    |    (pane $architectPane)    | $($expertAgents[0]) (pane $($session.agents.($expertAgents[0]))) |" -ForegroundColor White

    for ($i = 1; $i -lt $expertAgents.Count; $i++) {
        Write-Host "    |                      +----------------------+" -ForegroundColor DarkGray
        Write-Host "    |                      | $($expertAgents[$i]) (pane $($session.agents.($expertAgents[$i]))) |" -ForegroundColor White
    }

    if ($builderAgents.Count -gt 0) {
        Write-Host "    |                      +----------------------+" -ForegroundColor DarkGray
        Write-Host "    |                      |       BUILDER        |" -ForegroundColor Cyan
        Write-Host "    |                      | $($builderAgents[0]) (pane $($session.agents.($builderAgents[0]))) |" -ForegroundColor White

        for ($i = 1; $i -lt $builderAgents.Count; $i++) {
            Write-Host "    |                      +----------------------+" -ForegroundColor DarkGray
            Write-Host "    |                      | $($builderAgents[$i]) (pane $($session.agents.($builderAgents[$i]))) |" -ForegroundColor White
        }
    }

    if ($researchAgents.Count -gt 0) {
        Write-Host "    |                      +----------------------+" -ForegroundColor DarkGray
        Write-Host "    |                      |       RESEARCH       |" -ForegroundColor Cyan
        Write-Host "    |                      | $($researchAgents[0]) (pane $($session.agents.($researchAgents[0]))) |" -ForegroundColor White

        for ($i = 1; $i -lt $researchAgents.Count; $i++) {
            Write-Host "    |                      +----------------------+" -ForegroundColor DarkGray
            Write-Host "    |                      | $($researchAgents[$i]) (pane $($session.agents.($researchAgents[$i]))) |" -ForegroundColor White
        }
    }

    Write-Host "    +----------------------+----------------------+" -ForegroundColor DarkGray
    Write-Host "    |    Validator         |                      |" -ForegroundColor Cyan
    Write-Host "    |    (pane $validatorPane)    |                      |" -ForegroundColor White
    Write-Host "    +----------------------+----------------------+" -ForegroundColor DarkGray
    Write-Host ""

    # Detailed breakdown
    Write-Host "LEFT COLUMN:" -ForegroundColor Yellow
    Write-Host "  Architect (top): pane $architectPane" -ForegroundColor DarkGray
    Write-Host "  Validator (bottom): pane $validatorPane" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "RIGHT COLUMNS:" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  Expert Column (Top-Right): $($expertAgents.Count) agent(s)" -ForegroundColor Cyan
    foreach ($agent in $expertAgents) {
        Write-Host "    - $agent (pane $($session.agents.$agent))" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Builder Column (Mid-Right): $($builderAgents.Count) agent(s)" -ForegroundColor Cyan
    foreach ($agent in $builderAgents) {
        Write-Host "    - $agent (pane $($session.agents.$agent))" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Research Column (Bottom-Right): $($researchAgents.Count) agent(s)" -ForegroundColor Cyan
    foreach ($agent in $researchAgents) {
        Write-Host "    - $agent (pane $($session.agents.$agent))" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Total panes: $($session.pane_ids.Count)/15" -ForegroundColor Cyan
    Write-Host ""
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

    $architectAutoStart = "$autoStartPrefix You are the ARCHITECT (Team Lead). You can send messages to other agents by writing to their inbox files (inbox-expert.md, inbox-builder.md, inbox-validator.md, inbox-research.md). You can also trigger agents to check their inbox by running: wezterm cli send-text --pane-id PANE_ID `"Check your inbox at $sessionDirForPrompt/inbox-AGENT.md for new tasks.`" then wezterm cli send-text --pane-id PANE_ID --no-paste `"`r`n`". Get pane IDs from session.json. **CRITICAL WORKFLOW:** When you receive a task, ALWAYS start by using the Research agent to find examples, best practices, and similar projects BEFORE spawning Experts/Builders."

    $architectPrompt = if ($Task -ne "") {
        "$architectAutoStart Your team task is: $Task. **WORKFLOW:** 1) Use Research agent to find examples/best practices, 2) Based on findings, spawn appropriate Experts/Builders, 3) Coordinate implementation, 4) Send to Validator. Read the scratchpad, then break down this task."
    } else {
        "$architectAutoStart No task assigned yet. Read the scratchpad, announce your readiness, and wait for the user to provide a task."
    }

    $validatorPrompt = ($autoStartPrefix -replace '{ROLE}', 'validator-1') + " You are the VALIDATOR (QA/testing). Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    $expertPrompt = ($autoStartPrefix -replace '{ROLE}', 'expert-1') + " You are the EXPERT (domain knowledge). Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    $builderPrompt = ($autoStartPrefix -replace '{ROLE}', 'builder-1') + " You are the BUILDER (implementation). Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."
    $researchPrompt = ($autoStartPrefix -replace '{ROLE}', 'research-1') + " You are the RESEARCH agent (code research, examples, best practices). **CRITICAL:** You ONLY search the local directory first (never go outside it). If local files don't have answers, then do web research including GitHub repositories, documentation, and source code examples. Read your inbox and the scratchpad NOW, then announce what tasks you see and your readiness."

    $paneMap = @{}

    Write-Host "[1/5] Current terminal -> Architect (Team Lead)..." -ForegroundColor Cyan
    $panes = & $WezTermExe cli list --format json | ConvertFrom-Json
    $currentPaneId = ($panes | Where-Object { $_.is_active -eq $true } | Select-Object -First 1).pane_id
    $knownPanes = @("$currentPaneId")
    $paneMap['architect'] = $currentPaneId
    Write-Host "      Pane ID: $currentPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    # Split Architect right to create right column
    Write-Host "[2/5] Creating right column..." -ForegroundColor Cyan
    $splitArgs = @('cli', 'split-pane', '--right', '--percent', '50', '--pane-id', "$currentPaneId")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $newPanes = & $WezTermExe cli list --format json | ConvertFrom-Json
    $rightPane = $newPanes | Where-Object { "$($_.pane_id)" -notin $knownPanes }
    $rightPaneId = "$($rightPane.pane_id)"
    $knownPanes += "$rightPaneId"

    # Spawn Expert in right pane
    Write-Host "[3/5] Spawning Expert (top-right)..." -ForegroundColor Cyan
    $escapedExpertPrompt = $expertPrompt.Replace("'", "''")
    $spawnCmd = "droid specialist '$escapedExpertPrompt'"
    $null = & $WezTermExe cli send-text --pane-id $rightPaneId $spawnCmd 2>&1
    Start-Sleep -Milliseconds 100
    $null = & $WezTermExe cli send-text --pane-id $rightPaneId --no-paste "`r`n" 2>&1
    $paneMap['expert-1'] = $rightPaneId
    Write-Host "      Pane ID: $rightPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    # Split right pane for Builder
    Write-Host "[4/5] Spawning Builder (middle-right)..." -ForegroundColor Cyan
    $escapedBuilderPrompt = $builderPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--pane-id', $rightPaneId, '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid builder '$escapedBuilderPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $builderPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $builderPaneId) { Write-Error "Failed to spawn Builder. Aborting."; exit 1 }
    $knownPanes += "$builderPaneId"
    $paneMap['builder-1'] = $builderPaneId
    Write-Host "      Pane ID: $builderPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    # Split Builder for Validator
    Write-Host "[5/5] Spawning Validator (bottom-right-1)..." -ForegroundColor Cyan
    $escapedValidatorPrompt = $validatorPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--pane-id', $builderPaneId, '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid validator '$escapedValidatorPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $validatorPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $validatorPaneId) { Write-Error "Failed to spawn Validator. Aborting."; exit 1 }
    $knownPanes += "$validatorPaneId"
    $paneMap['validator-1'] = $validatorPaneId
    Write-Host "      Pane ID: $validatorPaneId - SUCCESS" -ForegroundColor Green

    Start-Sleep -Milliseconds 300

    # Split Validator for Research
    Write-Host "[6/6] Spawning Research (bottom-right-2)..." -ForegroundColor Cyan
    $escapedResearchPrompt = $researchPrompt.Replace("'", "''")
    $splitArgs = @('cli', 'split-pane', '--bottom', '--percent', '50', '--pane-id', $validatorPaneId, '--cwd', $ProjectDir, '--', 'powershell.exe', '-NoExit', '-Command', "droid specialist '$escapedResearchPrompt'")
    & $WezTermExe $splitArgs 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    $researchPaneId = Get-NewPaneId -KnownPaneIds $knownPanes
    if (-not $researchPaneId) { Write-Error "Failed to spawn Research. Aborting."; exit 1 }
    $knownPanes += "$researchPaneId"
    $paneMap['research-1'] = $researchPaneId
    Write-Host "      Pane ID: $researchPaneId - SUCCESS" -ForegroundColor Green

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
    Write-Host "  |                  |      Expert      |" -ForegroundColor Yellow
    Write-Host "  |                  +------------------+" -ForegroundColor Yellow
    Write-Host "  |                  |     Builder      |" -ForegroundColor Yellow
    Write-Host "  |    Architect     +------------------+" -ForegroundColor Yellow
    Write-Host "  |   (this pane)    |     Validator     |" -ForegroundColor Yellow
    Write-Host "  |                  +------------------+" -ForegroundColor Yellow
    Write-Host "  |                  |     Research     |" -ForegroundColor Yellow
    Write-Host "  +------------------+------------------+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "WORKFLOW:" -ForegroundColor Yellow
    Write-Host "  User → Architect → Research (find examples)" -ForegroundColor Yellow
    Write-Host "  Research → Architect → spawn Experts/Builders" -ForegroundColor Yellow
    Write-Host "  Team → Validator (final QA)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  devteam status        - Show team progress" -ForegroundColor Yellow
    Write-Host "  devteam layout        - Show visual pane layout" -ForegroundColor Yellow
    Write-Host "  devteam add-agent     - Add new agent" -ForegroundColor Yellow
    Write-Host "  devteam stop          - Kill session and archive" -ForegroundColor Yellow
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
    'add-agent' {
        Add-Agent -AgentType $AgentType -Domain $Domain
    }
    'layout' {
        Show-Layout
    }
    default {
        Invoke-SingleAgent -AgentName $Agent -Task $Task
    }
}
