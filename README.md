# droid-devteam

Multi-agent development team orchestrator for [Factory](https://factory.ai) Droid CLI + WezTerm.

Spawns a coordinated team of AI agents in a WezTerm split layout. The Architect leads with a **research-first workflow**: assess the task, spawn researchers, gather findings, then spawn experts and builders. A build-validate feedback loop ensures quality. Agents communicate through file-based inboxes, a shared scratchpad, and WezTerm pane notifications.

```
+----------+----+----+----+
|          | E1 | E2 | E3 |  Expert row (grows RIGHT)
|    A     +----+----+----+
|          | B1 | B2 | B3 |  Builder row (grows RIGHT)
+----------+----+----+----+
|    V     | R1 | R2 |    |  Research row (grows RIGHT)
+----------+----+----+----+
```

**Left column:** Architect (top) + Validator (bottom) — fixed.
**Right side:** Three rows for Expert, Builder, and Research agents — each row grows horizontally as the Architect spawns more agents.

## Agents

| Agent | Role | Responsibilities |
|-------|------|-----------------|
| **Architect** | Team Lead | Assesses research needs, spawns agents, delegates tasks, reviews final output |
| **Research** | Researcher | Investigates topics (local-first, then web), reports findings to Architect |
| **Expert** | Domain Specialist | Deep domain knowledge (frontend, API, security, etc.), advises team |
| **Builder** | Implementer | Writes code, implements features, fixes issues from Validator |
| **Validator** | QA | Tests work, reports pass/fail, drives the build-validate loop |

## Research-First Workflow

```
User -> Architect -> decide research needs -> spawn Researchers -> assign tasks -> WAIT
  -> findings arrive -> decide experts/builders needed -> spawn them -> assign tasks
  -> implementation complete -> send to Validator -> Validator tests
  -> FAIL? -> issues go to Builder -> Builder fixes -> back to Validator (loop)
  -> PASS? -> Architect reviews final result -> missing feature? -> back to building
  -> ALL DONE -> Architect confirms to User
```

The Architect **never** jumps straight to building. Research comes first, always.

## Platform

**Windows only.** Uses PowerShell and WezTerm CLI on Windows. Linux/macOS support is not currently planned.

## Prerequisites

- Windows 10/11
- [Factory Droid CLI](https://docs.factory.ai/cli/getting-started/quickstart) installed and authenticated
- [WezTerm](https://wezfurlong.org/wezterm/install) terminal emulator
- PowerShell 5.1+

## Installation

### One-liner

```powershell
irm https://raw.githubusercontent.com/ZachUON/droid-devteam/main/install.ps1 | iex
```

### From clone

```powershell
git clone https://github.com/ZachUON/droid-devteam.git
cd droid-devteam
.\install.ps1
```

### Manual

1. Copy `dev-team-orchestrator.ps1` and `dev-team-helpers.psm1` to `~/.factory/scripts/`
2. Copy all files in `droids/` to `~/.factory/droids/`
3. Add to your PowerShell profile:

```powershell
function devteam {
    & "$env:USERPROFILE\.factory\scripts\dev-team-orchestrator.ps1" @args
}
```

The installer handles all of this automatically, including backing up any existing droid definitions.

## Usage

### Start a team

```powershell
# Spawn team with a task (Architect begins research-first workflow)
devteam "Build a REST API with JWT authentication"

# Spawn team, assign task later
devteam
```

### Add agents mid-session

The Architect does this automatically based on research findings, but you can also do it manually:

```powershell
devteam add-agent expert frontend     # Add a frontend expert
devteam add-agent expert security     # Add a security expert
devteam add-agent builder             # Add another builder
devteam add-agent research            # Add another researcher
```

Each new agent splits the rightmost pane in its row, growing the row horizontally.

### Message agents

```powershell
# Send a task to any agent (writes to inbox + notifies their pane)
devteam msg builder-1 "Implement the login page with JWT auth"
devteam msg expert-1 "Review the database schema for normalization issues"

# Give the Architect a new task (shorthand for devteam msg architect)
devteam task "Add dark mode support to the UI"
```

### Monitor and control

```powershell
devteam status      # Show all agents, pane IDs, and row assignments
devteam layout      # Show visual ASCII layout with current agents
devteam stop        # Kill all agent panes and archive the session
```

## How It Works

1. `devteam` creates a `.devteam/` folder in your current directory with:
   - `scratchpad.md` — shared workspace for architecture decisions, notes, findings
   - `inbox-{agent}.md` — task queue for each agent
   - `session.json` — pane IDs, agent roster, row assignments
2. WezTerm panes split to create the layout (Architect + Validator on left, 3 agent rows on right)
3. Each agent is a Factory Droid with a custom droid definition defining its role
4. Agents read their inboxes, write to the scratchpad, and notify each other via `wezterm cli send-text`
5. The Architect orchestrates the full research-first workflow and build-validate loop

### Inter-Agent Communication

Agents use a **two-step `send-text`** approach for reliable WezTerm pane communication on Windows:

```powershell
# Step 1: Send the message text
wezterm cli send-text --pane-id 3 "Check your inbox for new tasks."

# Step 2: Send the Enter key (required!)
wezterm cli send-text --pane-id 3 --no-paste "`r`n"
```

The first command sends the text, the second with `--no-paste` and `` `r`n `` sends an actual Enter keypress. Both steps are required for the command to execute.

### Session Files

```
your-project/
  .devteam/
    scratchpad.md          # shared workspace
    inbox-architect.md     # architect's task queue
    inbox-builder-1.md     # builder's task queue
    inbox-validator.md     # validator's task queue
    inbox-expert-1.md      # expert's task queue
    inbox-research-1.md    # researcher's task queue
    session.json           # pane IDs, agent roster, rows
    archive/               # previous sessions
```

Add `.devteam/` to your `.gitignore`:

```
.devteam/
```

## File Structure

```
droid-devteam/
  dev-team-orchestrator.ps1   # Main entry point (argument routing)
  dev-team-helpers.psm1       # All core logic (splitting, spawning, session mgmt)
  install.ps1                 # Installer
  droids/
    architect.md              # Architect droid definition
    builder.md                # Builder droid definition
    validator.md              # Validator droid definition
    expert.md                 # Expert droid definition
    research.md               # Research droid definition
```

## Agent Installation Instructions

If you're an AI agent installing this for a user, run:

```powershell
# 1. Clone the repo
git clone https://github.com/ZachUON/droid-devteam.git C:\temp\droid-devteam

# 2. Run the installer
& "C:\temp\droid-devteam\install.ps1"

# 3. Clean up
Remove-Item C:\temp\droid-devteam -Recurse -Force
```

The installer will verify prerequisites, copy scripts and droid definitions, and set up the `devteam` command. The user needs to restart their terminal after installation.

## License

MIT
