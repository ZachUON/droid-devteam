# Dynamic Pane Splitting System Design

## Overview
The Architect agent can dynamically split panes to create new subagents on demand, following a logical splitting strategy that maintains a usable layout.

## Pane State Tracking

### Session Structure (session.json)
```json
{
  "started": "2026-02-09T15:30:00",
  "task": "Build a calculator app",
  "project": "C:\\path\\to\\project",
  "session_dir": "C:\\path\\to\\.devteam",
  "pane_layout": {
    "architect": {
      "pane_id": "0",
      "position": "top-left",
      "splits": ["builder-1", "architect-assistant"],
      "split_direction": "horizontal"
    },
    "builder": {
      "pane_id": "3",
      "position": "top-right",
      "splits": [],
      "split_direction": null
    },
    "validator": {
      "pane_id": "4",
      "position": "bottom-right-1",
      "splits": [],
      "split_direction": null
    },
    "specialist": {
      "pane_id": "5",
      "position": "bottom-right-2",
      "splits": [],
      "split_direction": null
    }
  },
  "agents": {
    "architect": "0",
    "builder": "3",
    "validator": "4",
    "specialist": "5"
  },
  "pane_ids": ["0", "3", "4", "5"]
}
```

## Splitting Strategy

### Level 1: Initial Layout (4 agents)
```
+------------------+------------------+
|                  |     Builder      |
|    Architect     +--------+---------+
|                  | Valid. | Spec.   |
+------------------+--------+---------+
```

### Level 2: Split Large Panes First (5-6 agents)
When adding a new agent, find the largest pane (by area) that hasn't been split yet.

**Add Agent 5 (splits Builder):**
```
+------------------+------------------+
|                  |    Builder-1     |
|    Architect     +--------+---------+
|                  | Builder-2|Spec.  |
+------------------+--------+---------+
```

**Add Agent 6 (splits Architect horizontally):**
```
+------------------+------------------+
|    Architect     |    Builder-1     |
+--------+---------+--------+---------+
| Arch. | Builder-2| Valid. | Spec.  |
| Asst. |          +--------+---------+
+--------+---------+--------+---------+
```

### Level 3: Split Deeper (7+ agents)
Continue splitting the largest available panes.

**Add Agent 7 (splits Validator):**
```
+------------------+------------------+
|    Architect     |    Builder-1     |
+--------+---------+--------+---------+
| Arch. | Builder-2| Val-1  | Spec.  |
| Asst. |          +--------+---------+
+--------+---------+ Val-2  | Spec-2 |
+--------+---------+--------+---------+
```

### Maximum Split Configuration
Theoretical max: 8 panes (2x4 grid)

```
+------------------+------------------+
|    Architect     |    Builder-1     |
+--------+---------+--------+---------+
| Arch. | Builder-2| Val-1  | Spec.  |
| Asst. |          +--------+---------+
+--------+---------+ Val-2  | Spec-2 |
| Arch  | Builder-3|        |        |
| Asst-2|          +--------+---------+
+--------+---------+--------+---------+
```

## Splitting Rules

### 1. Never Split the Architect's Primary Pane
- Architect's main chat area (top-left) is sacred
- Can only split horizontally to add assistant BELOW
- Never split vertically or replace the main pane

### 2. Split Largest Pane First
Calculate pane area:
- Full-width pane = 1.0 (e.g., Architect)
- Half-width pane = 0.5 (e.g., Builder)
- Quarter-width pane = 0.25 (e.g., Validator)

Priority order:
1. Builder (0.5, unsplit)
2. Architect (1.0, can only split horizontally)
3. Validator (0.25, unsplit)
4. Specialist (0.25, unsplit)

### 3. Split Direction Logic
- Full-height panes (Architect): Split horizontally (--bottom)
- Half-height panes (Builder, etc.): Split vertically (--right) or horizontally (--bottom) based on existing layout
- Quarter-height panes: Split in opposite direction of parent

### 4. Agent Type Assignment
When splitting, assign the new agent a role:
- If splitting Builder → "builder-{N}" (additional builder)
- If splitting Validator → "validator-{N}" (additional validator)
- If splitting Specialist → "{domain}-specialist-{N}" (domain specialist)
- If splitting Architect → "architect-assistant-{N}" (architect assistant)

## Commands

### Architect Commands
```powershell
# Add a new agent
devteam add-agent [type]

# Examples:
devteam add-agent builder          # Add another builder
devteam add-agent validator        # Add another validator
devteam add-agent specialist       # Add domain specialist
devteam add-agent architect-assist # Add architect assistant

# Remove an agent
devteam remove-agent [agent-name]

# Show current layout
devteam layout
```

### Implementation in architect.md

The Architect droid will have new capabilities:

```
## Dynamic Agent Management

As the Architect, you can spawn new agents dynamically:

1. **Assess current layout**
   - Read .devteam/session.json to see current pane configuration
   - Identify which pane should be split next
   - Check if max capacity (8 panes) is reached

2. **Determine agent type needed**
   - Builder: For implementation tasks
   - Validator: For testing/review tasks
   - Specialist: For domain-specific tasks
   - Architect Assistant: For coordination/planning help

3. **Execute split**
   - Call devteam-orchestrator.ps1 with add-agent parameter
   - Orchestrator handles the actual wezterm split-pane commands
   - Updates session.json with new pane information

4. **Assign task**
   - Write task to new agent's inbox
   - Send notification via send-text
```

## Implementation Functions

### Get-SplitCandidate
```powershell
function Get-SplitCandidate {
    param([hashtable]$PaneLayout)

    # Calculate areas and find best candidate
    # Never return architect's main pane for vertical split
    # Prioritize: Builder > Architect (horizontal) > Validator > Specialist
}
```

### Split-Pane
```powershell
function Split-Pane {
    param(
        [string]$ParentPaneId,
        [string]$NewAgentName,
        [string]$SplitDirection  # 'bottom' or 'right'
    )

    # Execute wezterm cli split-pane
    # Detect new pane ID
    # Update session.json
    # Create new agent inbox
}
```

### Invoke-AddAgent
```powershell
function Invoke-AddAgent {
    param(
        [string]$AgentType,
        [string]$Domain = $null
    )

    # 1. Load session.json
    # 2. Call Get-SplitCandidate
    # 3. Call Split-Pane
    # 4. Spawn agent in new pane
    # 5. Send notification to Architect
}
```

## File Structure

### New Session Files
```
.devteam/
  scratchpad.md
  session.json                # Enhanced with pane_layout
  inbox-architect.md
  inbox-builder.md
  inbox-validator.md
  inbox-specialist.md
  inbox-builder-2.md          # Dynamic
  inbox-validator-2.md        # Dynamic
  inbox-architect-assistant.md # Dynamic
```

### Dynamic Droid Files
```
~/.factory/droids/
  architect.md
  builder.md
  validator.md
  specialist.md
  builder-agent.md            # Generic builder template
  validator-agent.md          # Generic validator template
  specialist-agent.md         # Generic specialist template
  architect-assistant.md      # Architect assistant template
```

## Testing Strategy

1. **Test Level 1**: Spawn initial 4 agents (existing behavior)
2. **Test Level 2**: Add 5th agent (should split Builder)
3. **Test Level 3**: Add 6th agent (should split Architect horizontally)
4. **Test Level 4**: Add 7th agent (should split Validator)
5. **Test Level 5**: Add 8th agent (should split Specialist or other)
6. **Test Max**: Try to add 9th agent (should fail gracefully)

## Edge Cases

1. **Window too small**: Detect if wezterm window can't fit more panes
2. **Session corruption**: Validate session.json before loading
3. **Agent crash**: Handle pane death and update session state
4. **Rapid splitting**: Add delays to ensure pane detection works
5. **Name conflicts**: Auto-generate unique names (builder-2, builder-3, etc.)

## Future Enhancements

1. **Custom layouts**: Allow specifying custom split patterns
2. **Agent merging**: Remove agents and merge panes back
3. **Layout presets**: Save/load common layouts
4. **Auto-balance**: Automatically redistribute agents based on workload
5. **Visual layout editor**: Interactive pane layout management
