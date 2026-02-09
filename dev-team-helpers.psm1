# Dev Team Helper Functions
# Helper module for dev-team-orchestrator.ps1

function Write-TeamLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $colors = @{
        Info = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error = "Red"
    }
    
    $prefix = @{
        Info = "ℹ️ "
        Success = "✅"
        Warning = "⚠️ "
        Error = "❌"
    }
    
    Write-Host "$($prefix[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Invoke-WezTermSplit {
    param(
        [Parameter(Mandatory)]
        [string]$PaneId,
        
        [Parameter(Mandatory)]
        [ValidateSet("right", "left", "top", "bottom")]
        [string]$Direction,
        
        [Parameter(Mandatory)]
        [int]$Percent
    )
    
    $cmd = "wezterm cli split-pane --$Direction --percent $Percent --pane-id $PaneId"
    
    try {
        $result = Invoke-Expression $cmd 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "WezTerm split failed with exit code ${LASTEXITCODE}: $result"
        }
        
        $newPaneId = $result.Trim()
        return $newPaneId
        
    } catch {
        Write-TeamLog "Split failed: $_" -Level Error
        throw
    }
}

function Invoke-AgentCommand {
    param(
        [Parameter(Mandatory)]
        [string]$PaneId,
        
        [Parameter(Mandatory)]
        [string]$Command
    )
    
    # Step 1: Send the command text
    wezterm cli send-text --pane-id $PaneId $Command 2>&1 | Out-Null
    Start-Sleep -Milliseconds 100
    
    # Step 2: Send Enter key separately (two-step approach for Windows)
    wezterm cli send-text --pane-id $PaneId --no-paste "`r`n" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-TeamLog "Failed to send command to pane $PaneId" -Level Warning
    }
}

function Get-WezTermPanes {
    $json = wezterm cli list --format json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list WezTerm panes: $json"
    }
    
    return ($json | ConvertFrom-Json)
}

function Initialize-DevTeamLayout {
    [CmdletBinding()]
    param(
        [switch]$Debug
    )
    
    Write-TeamLog "Creating dev team layout..." -Level Info
    
    # Verify we're running in WezTerm
    $basePaneId = $env:WEZTERM_PANE
    if (-not $basePaneId) {
        throw "Not running in WezTerm (WEZTERM_PANE environment variable not set)"
    }
    
    Write-TeamLog "Base pane ID: $basePaneId" -Level Info
    
    # STEP 1: Split RIGHT - Create left column (20%) + right side (80%)
    Write-TeamLog "Creating left column (Architect + Validator)..." -Level Info
    $rightSideId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "right" -Percent 80
    Start-Sleep -Milliseconds 300
    
    # STEP 2: Split left column DOWN - Architect (top 70%) + Validator (bottom 30%)
    Write-TeamLog "Splitting left column for Validator..." -Level Info
    $validatorId = Invoke-WezTermSplit -PaneId $basePaneId -Direction "bottom" -Percent 30
    Start-Sleep -Milliseconds 300
    
    # STEP 3: Split right side DOWN - Expert row (top 33%) + remaining (67%)
    Write-TeamLog "Creating Expert row..." -Level Info
    $builderResearchRowsId = Invoke-WezTermSplit -PaneId $rightSideId -Direction "bottom" -Percent 67
    Start-Sleep -Milliseconds 300
    
    # STEP 4: Split remaining DOWN - Builder row (50%) + Researcher row (50%)
    Write-TeamLog "Creating Builder and Researcher rows..." -Level Info
    $researcherRowId = Invoke-WezTermSplit -PaneId $builderResearchRowsId -Direction "bottom" -Percent 50
    Start-Sleep -Milliseconds 300
    
    $layout = @{
        Architect = $basePaneId
        Validator = $validatorId
        ExpertRow = $rightSideId
        BuilderRow = $builderResearchRowsId
        ResearcherRow = $researcherRowId
    }
    
    Write-TeamLog "Layout created successfully!" -Level Success
    
    if ($Debug) {
        Write-TeamLog "Pane IDs:" -Level Info
        $layout.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
        }
    }
    
    return $layout
}

function Start-AgentInPane {
    param(
        [Parameter(Mandatory)]
        [string]$PaneId,
        
        [Parameter(Mandatory)]
        [ValidateSet('architect', 'builder', 'validator', 'expert', 'researcher')]
        [string]$AgentType,
        
        [string]$Prompt,
        
        [string]$Name
    )
    
    # Build the droid command with single-quoted prompt to avoid PS escaping issues
    $escapedPrompt = $Prompt -replace "'", "''"
    $droidCmd = "droid $AgentType '$escapedPrompt'"
    
    # Send command text to the pane
    wezterm cli send-text --pane-id $PaneId $droidCmd 2>&1 | Out-Null
    Start-Sleep -Milliseconds 100
    
    # Send Enter key separately (two-step approach for Windows)
    wezterm cli send-text --pane-id $PaneId --no-paste "`r`n" 2>&1 | Out-Null
}

function Add-Agent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('expert', 'builder', 'researcher')]
        $Type,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$Domain = $null
    )
    
    Write-TeamLog "Adding $Type : $Name" -Level Info
    
    # Get the layout from global variable
    if (-not $global:DevTeamLayout) {
        Write-TeamLog "No active dev team layout found. Run devteam first." -Level Error
        return
    }
    
    # Get the last pane of the requested type
    $targetPaneId = switch ($Type) {
        'expert' { $global:LastExpertPane }
        'builder' { $global:LastBuilderPane }
        'researcher' { $global:LastResearcherPane }
    }
    
    if (-not $targetPaneId) {
        Write-TeamLog "No $Type row found in layout." -Level Error
        return
    }
    
    try {
        # Split the target pane RIGHT to add another agent side-by-side
        $newPaneId = Invoke-WezTermSplit -PaneId $targetPaneId -Direction "right" -Percent 50
        Start-Sleep -Milliseconds 200
        
        # Create prompt for the new agent
        $sessionDir = (Get-Location).Path + "/.devteam"
        $sessionDirForPrompt = $sessionDir.Replace('\', '/')
        
        $basePrompt = "IMPORTANT: You are a $($Type.ToUpper()) agent. Session: $sessionDirForPrompt/. Read scratchpad and inbox, announce readiness."
        
        if ($Domain -and $Type -eq 'expert') {
            $basePrompt += " You specialize in: $Domain"
        }
        
        # Spawn agent in the new pane
        Start-AgentInPane -PaneId $newPaneId -AgentType $Type -Prompt $basePrompt -Name $Name
        
        # Update global tracking
        switch ($Type) {
            'expert' { $global:LastExpertPane = $newPaneId }
            'builder' { $global:LastBuilderPane = $newPaneId }
            'researcher' { $global:LastResearcherPane = $newPaneId }
        }
        
        Write-TeamLog "Successfully added $Type '$Name'" -Level Success
        
    } catch {
        Write-TeamLog "Failed to add agent: $_" -Level Error
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Write-TeamLog',
    'Invoke-WezTermSplit',
    'Invoke-AgentCommand',
    'Get-WezTermPanes',
    'Initialize-DevTeamLayout',
    'Start-AgentInPane',
    'Add-Agent'
)
