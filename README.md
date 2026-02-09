# droid-devteam

Multi-agent development team orchestrator for [Factory](https://factory.ai) Droid CLI + WezTerm.

Spawns 4 coordinated AI agents in a WezTerm split layout, each with a specialized role. Agents communicate through file-based inboxes and a shared scratchpad created in your project directory.

```
+------------------+------------------+
|                  |     Builder      |
|    Architect     +--------+---------+
|   (team lead)    | Valid. | Spec.   |
+------------------+--------+---------+
```

## Agents

| Agent | Role | Responsibilities |
|-------|------|-----------------|
| **Architect** | Team Lead | Requirements analysis, architecture design, task delegation |
| **Builder** | Implementer | Feature implementation, code quality, unit tests |
| **Validator** | QA | Testing, code review, bug finding, security review |
| **Specialist** | Domain Expert | Database, API, frontend, DevOps, security, performance |

## How It Works

1. `devteam` creates a `.devteam/` folder in your current directory with:
   - `scratchpad.md` -- shared workspace for architecture decisions, notes, findings
   - `inbox-{agent}.md` -- task queues for each agent
   - `session.json` -- pane IDs for cross-agent communication
2. Four WezTerm panes spawn, each running a Droid with a specialized custom droid definition
3. Agents read their inboxes, write to the scratchpad, and notify each other via `wezterm cli send-text`
4. Session files persist in your project directory as a form of session memory

## Prerequisites

- [Factory Droid CLI](https://docs.factory.ai/cli/getting-started/quickstart) installed and authenticated
- [WezTerm](https://wezfurlong.org/wezterm/install) terminal emulator
- PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)

## Installation

### One-liner (after repo is on GitHub)

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

1. Copy `scripts/` to `~/.factory/scripts/`
2. Copy `droids/` to `~/.factory/droids/`
3. Add to your PowerShell profile:

```powershell
function devteam {
    $task = $args -join ' '
    & "$env:USERPROFILE\.factory\scripts\dev-team-orchestrator.ps1" -Task $task
}
```

## Usage

```powershell
# Spawn full team with a task
devteam "Build a REST API with JWT authentication"

# Spawn team, assign task later
devteam

# Check team progress
devteam status

# Kill session and archive
devteam stop
```

### Session Files

All session files are created in `.devteam/` inside your current working directory:

```
your-project/
  .devteam/
    scratchpad.md          # shared workspace
    inbox-architect.md     # architect's task queue
    inbox-builder.md       # builder's task queue
    inbox-validator.md     # validator's task queue
    inbox-specialist.md    # specialist's task queue
    session.json           # pane IDs, metadata
    archive/               # previous sessions
```

Add `.devteam/` to your `.gitignore` if you don't want session files committed:

```
.devteam/
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

The installer will:
- Verify `droid` and `wezterm` are installed
- Copy scripts to `~/.factory/scripts/`
- Copy droid definitions to `~/.factory/droids/` (backs up existing ones)
- Add the `devteam` function to the user's PowerShell profile

After install, the user needs to restart their terminal.

## License

MIT
