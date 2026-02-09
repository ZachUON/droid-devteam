# Column-Based Dynamic Agent Layout - Implementation Summary

## Overview
Refactored the devteam orchestrator to use a column-based layout where each agent type has its own column on the right side, with Architect fixed on the left.

## Key Changes

### 1. Agent Type Changes
- **Renamed**: "Specialist" → "Expert"
- **Expert Role**: Domain knowledge (API, database, frontend, DevOps, security, etc.)
- **Builder Role**: Implementation and coding (add for parallel work)
- **Validator Role**: QA/testing (single validator sufficient)
- **Architect Role**: Team lead, NEVER splits

### 2. New Layout Structure

**Initial Layout (4 agents):**
```
+---------------------+---------------------+
|                     |      Expert         |
|                     +---------------------+
|     Architect       |     Builder         |
|                     +---------------------+
|                     |    Validator        |
+---------------------+---------------------+
```

**Column-Based Splitting:**
- Expert column splits horizontally (top)
- Builder column splits horizontally (middle)
- Validator column splits horizontally (bottom)

### 3. Agent Spawning Rules

**When to Add Agents:**
- **More Experts**: When multiple domains are involved (NEVER duplicate same expert type)
- **More Builders**: When features can be implemented in parallel
- **More Validators**: NEVER (single validator is sufficient)

**Examples:**
```powershell
# Add frontend expert
devteam add-agent expert --domain frontend

# Add API expert
devteam add-agent expert --domain api

# Add builder for parallel work
devteam add-agent builder
```

### 4. User Interaction for Split Selection

When columns have 2+ agents, user is prompted:

```powershell
> Which column should be split?
  [1] EXPERT (3 agents: frontend, api, database)
  [2] BUILDER (3 agents: feature-a, feature-b, feature-c)
  [3] VALIDATOR (1 agent)
  [4] Cancel

Enter choice (1-4): _
```

## Technical Implementation

### Session Structure (session.json)

```json
{
  "pane_layout": {
    "architect": {
      "pane_id": "0",
      "position": "left",
      "fixed": true
    },
    "columns": {
      "expert": {
        "position": "top-right",
        "agents": ["expert-1", "expert-2"],
        "split_direction": "horizontal"
      },
      "builder": {
        "position": "middle-right",
        "agents": ["builder-1", "builder-2"],
        "split_direction": "horizontal"
      },
      "validator": {
        "position": "bottom-right",
        "agents": ["validator-1"],
        "split_direction": "horizontal"
      }
    }
  }
}
```

### Key Functions

**Get-SplitCandidate:**
- Determines which column to split based on agent type
- Prompts user if all columns have 2+ agents
- Returns the bottom pane in target column for horizontal split

**New-AgentName:**
- For experts: Uses domain-specific naming (e.g., "expert-frontend")
- Checks for duplicate expert types (e.g., won't create two "expert-api")
- Falls back to generic naming (expert-2, builder-2, etc.)

**Add-Agent:**
- Handles all agent type additions
- Splits bottom pane of target column horizontally
- Updates session.json with new pane info
- Creates inbox for new agent
- Notifies Architect of new agent

**Show-Layout:**
- Displays visual representation of column layout
- Shows agents in each column with pane IDs
- Useful for understanding current team structure

## File Changes

### Modified Files

1. **scripts/dev-team-orchestrator.ps1**
   - Updated header comments with v5 and new layout
   - Changed parameter validation: specialist → expert
   - Updated Initialize-TeamSession to use expert instead of specialist
   - Rewrote Save-SessionMetadata with column-based structure
   - Rewrote Get-SplitCandidate for column-based logic
   - Rewrote New-AgentName to handle domain experts
   - Rewrote Add-Agent to use column-based splitting
   - Rewrote Show-Layout with visual column display
   - Updated Invoke-DevTeam spawn order: Expert → Builder → Validator
   - Updated layout display in spawn success message
   - Updated entry point to handle "expert" and "layout" commands

2. **droids/architect.md**
   - Updated with expert terminology (replaced specialist)
   - Added dynamic agent management section
   - Added commands for adding agents
   - Added explanation of automatic splitting logic
   - Added capacity limits and examples

### New Files Created

1. **REFINED_LAYOUT_DESIGN.md** - Complete design documentation
2. **COLUMN_BASED_LAYOUT_SUMMARY.md** - This file
3. **MAX_SPLIT_VISUALIZATION.md** - Visual progression (old, replaced by refined version)

## Usage Examples

### Basic Team Spawn
```powershell
# Spawn standard 4-agent team
devteam "Build a REST API"

# Spawn team without task
devteam
```

### Add Domain Experts
```powershell
# Add frontend design expert
devteam add-agent expert --domain "minimal design"

# Add database expert
devteam add-agent expert --domain database

# Add DevOps expert
devteam add-agent expert --domain devops
```

### Add Builders for Parallel Work
```powershell
# Add second builder
devteam add-agent builder

# Add third builder
devteam add-agent builder
```

### View Layout
```powershell
# Show visual pane layout
devteam layout
```

## Expert Type Examples

When creating experts, the Architect should assign specific domains:

- **expert-frontend** - UI/UX, CSS, accessibility, visual design
- **expert-api** - REST, GraphQL, API design, integration
- **expert-database** - SQL, NoSQL, data modeling, migrations
- **expert-devops** - CI/CD, deployment, infrastructure
- **expert-security** - Authentication, authorization, security
- **expert-performance** - Optimization, caching, scalability
- **expert-testing** - Test strategy, automation frameworks
- **expert-documentation** - Docs, guides, API references

Each expert gets specialized context in their prompt:

```
You are the Frontend Expert providing specialized knowledge in Frontend domain.
```

## Maximum Capacity

With column-based layout:
- Architect: 1 (fixed, never splits)
- Experts: 6+ (different domains, no duplicates)
- Builders: 6+ (parallel features)
- Validators: 2+ (rarely needed, user choice)

**Practical max**: ~12-15 agents before layout becomes unusable

## Advantages of Column-Based Layout

1. **Clear separation**: Each agent type has its own column
2. **Easy to understand**: New agents join their type's column
3. **Scalable**: Can add many agents per type
4. **Never splits Architect**: Main coordination pane stays intact
5. **Logical grouping**: Related agents are visually grouped
6. **Flexible**: User can choose which column to split when needed

## Testing Checklist

- [ ] Spawn initial 4-agent team
- [ ] Verify column layout (Expert top, Builder middle, Validator bottom)
- [ ] Add 2nd expert (should split Expert column)
- [ ] Add 2nd builder (should split Builder column)
- [ ] Add 3rd expert (should split Expert column again)
- [ ] Verify layout display shows correct structure
- [ ] Add agents until prompt appears for column selection
- [ ] Test cancel operation in column selection
- [ ] Verify session.json structure is correct
- [ ] Verify inboxes are created for all agents
- [ ] Verify Architect is notified of new agents
- [ ] Test with duplicate expert domain (should reject)

## Future Enhancements

1. **Remove agents**: Allow removing agents and merging panes back
2. **Custom layouts**: Allow specifying custom split patterns
3. **Auto-balance**: Automatically redistribute agents based on workload
4. **Expert templates**: Create specialized droid files for each expert type
5. **Layout presets**: Save/load common team configurations
6. **Agent renaming**: Allow renaming agents after creation

## Migration Notes

### For Existing Users

If you have existing sessions with "specialist" agents:

1. Stop your current session: `devteam stop`
2. The old session will be archived
3. Start a new session: `devteam`
4. The new session will use "expert" terminology

### Breaking Changes

- "specialist" agent type is now "expert"
- Initial agent names changed:
  - specialist → expert-1
  - builder → builder-1
  - validator → validator-1
- Session structure changed significantly (old sessions won't work)

### Compatibility

- Old sessions are archived and not migratable
- New sessions use the column-based layout exclusively
- Both systems can coexist on the same machine (different sessions)
