# Dev Team Orchestrator - Working Multi-Row Layout

## Solution by Sonnet 4.5

This orchestrator creates a **multi-row layout** where each agent type has its own dedicated horizontal row, and rows grow horizontally to add more agents.

## The Layout

```
+----------+----+----+----+
|          | E1 | E2 | E3 |  ← Expert row (splits RIGHT)
|    A     +----+----+----+
|          | B1 | B2 | B3 |  ← Builder row (splits RIGHT)
+----------+----+----+----+
|    V     | R1 | R2 |    |  ← Researcher row (splits RIGHT)
+----------+----+----+----+
```

- **Left column**: Architect (top), Validator (bottom) - fixed
- **Right side**: 3 horizontal rows for Expert, Builder, Researcher
- Each row grows horizontally (splits RIGHT) to add more agents

## Usage

### Spawn the team
```powershell
# From WezTerm
devteam

# Or with a task
devteam "Build a REST API"
```

### Add more agents dynamically
```powershell
# Using the helper module
Import-Module ./dev-team-helpers.psm1

# Add more experts (top row grows right)
Add-Agent -Type expert -Name "expert-frontend"
Add-Agent -Type expert -Name "expert-api"

# Add more builders (middle row grows right)
Add-Agent -Type builder -Name "builder-python"
Add-Agent -Type builder -Name "builder-javascript"

# Add more researchers (bottom row grows right)
Add-Agent -Type researcher -Name "researcher-ui"
Add-Agent -Type researcher -Name "researcher-backend"
```

## The Key Insight

**DOWN splits create horizontal rows**
**RIGHT splits grow rows horizontally**

This was the missing piece! The correct sequence:

1. Split Architect **RIGHT** → Creates left column + right side
2. Split left column **DOWN** → Architect (top) + Validator (bottom)
3. Split right side **DOWN** → Expert row + remaining space
4. Split remaining **DOWN** → Builder row + Researcher row

Then to add agents:
- Split any agent's pane **RIGHT** (50%) → adds another agent side-by-side in that row

## Files

- **`dev-team-orchestrator.ps1`** - Main orchestrator entry point
- **`dev-team-helpers.psm1`** - Helper module with split logic
- **`~/.factory/scripts/dev-team-orchestrator.ps1`** - Factory installed version (if you want to install there)

## Credits

Initial working implementation by **Sonnet 4.5** via claude context, with refinement of the split sequence and integration into the droid-devteam project structure.

## Research-First Workflow

The orchestrator preserves the research-first approach:

1. **User** → Architect with task
2. **Architect** → Research agent: "Find examples of X"
3. **Research** → Returns findings to scratchpad
4. **Architect** → Based on findings, adds experts/builders
5. **Team** → Validator for final QA

This ensures informed decisions based on actual research rather than assumptions.

## Testing

```powershell
# Test with debug output
pwsh dev-team-orchestrator.ps1 -Debug

# Should show:
# ℹ️  Creating dev team layout...
# ℹ️  Base pane ID: 0
# ℹ️  Creating left column (Architect + Validator)...
# ℹ️  Splitting left column for Validator...
# ℹ️  Creating Expert row...
# ℹ️  Creating Builder and Researcher rows...
# ✅ Layout created successfully!
# ℹ️  Pane IDs: Architect: 0, Validator: 1, ExpertRow: 2, BuilderRow: 3, ResearcherRow: 4
```
