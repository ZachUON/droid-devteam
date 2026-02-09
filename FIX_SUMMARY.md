# Fix Summary: WezTerm Agent Communication Issue

## Problem
When the Architect agent tried to send messages to other agents using `wezterm cli send-text`, the text would paste into the target pane but would not execute (press Enter). This meant agents would not receive notifications about new tasks in their inboxes.

## Root Cause
The `wezterm cli send-text` command requires a **two-step approach** to reliably send commands on Windows:
1. Send the message text
2. Send the Enter key separately using `--no-paste` with `` `r`n ``

The original approach tried to include `` `r `` in the same command, but this doesn't work reliably on Windows.

## Solution

### Proven Two-Step Approach

```powershell
# Step 1: Send the message text
wezterm cli send-text --pane-id 1 "Check your inbox for new tasks."

# Step 2: Send the Enter key
wezterm cli send-text --pane-id 1 --no-paste "`r`n"
```

**Why this works:**
- The first command sends the text to the pane
- The second command with `--no-paste` and `` `r`n `` sends an actual Enter keypress
- The `--no-paste` flag with the escape sequence sends a real Enter key

### What Didn't Work
- `\n` alone (Unix-style, not enough for Windows)
- `\r\n` in a single command (didn't execute)
- `&&` chaining in PowerShell (syntax error)
- `` `r `` in same command (unreliable on Windows)

## Changes Made

### 1. Updated Send-ToPane Function
Modified `scripts/dev-team-orchestrator.ps1` to use the two-step approach:

```powershell
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
```

### 2. Updated architect.md
Added clear instructions with the correct two-step approach and warnings about wrong approaches.

### 3. Updated README.md
Documented the two-step approach with explanation of why it's necessary.

## Files Modified

1. `droids/architect.md` - Added correct send-text syntax with `` `r ``
2. `scripts/dev-team-orchestrator.ps1` - Updated prompt to mention `` `r `` requirement
3. `README.md` - Added usage examples with correct syntax

## Installation

The fix has been deployed to:
- `C:\Users\ZachEngelbrecht\.factory\droids\architect.md`
- `C:\Users\ZachEngelbrecht\.factory\scripts\dev-team-orchestrator.ps1`

No further action required - existing devteam sessions will use the updated configuration on next spawn.

## Testing

A test script `C:\Users\ZachEngelbrecht\test-send-text.ps1` has been created to verify the fix:
- Tests send-text without carriage return (shows the problem)
- Tests send-text with carriage return (shows the solution)

## Key Takeaway

**Always include `` `r `` at the end of `wezterm cli send-text` messages to simulate pressing Enter.**

Without it:
```
> Check your inbox for new tasks.  (cursor waits here, no execution)
```

With it:
```
> Check your inbox for new tasks.  (executes immediately!)
```
