# Refined Pane Splitting System - Column-Based Layout

## Core Principles

### Agent Type Roles
- **Architect**: Team lead, coordination, planning (NEVER splits)
- **Expert**: Domain knowledge (API, database, frontend, DevOps, security, etc.)
- **Builder**: Implementation and coding
- **Validator**: Testing, QA, code review (single validator sufficient)

### Agent Spawning Rules
1. **More Builders**: When features can be implemented in parallel
2. **More Experts**: When multiple domains are involved (NEVER duplicate same expert type)
3. **More Validators**: NEVER (single validator is sufficient)

### Layout Structure

#### Initial Layout (4 agents)
```
+---------------------+---------------------+
|                     |        Expert       |
|                     +---------------------+
|     Architect       |       Builder       |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

#### Column-Based Splitting
Each agent type has its own "column" on the right side. When adding agents:
- Expert agents split the Expert column
- Builder agents split the Builder column
- Validator agents split the Validator column (rarely needed)

## Visual Progression

### Level 1: Initial Layout (4 agents)
```
+---------------------+---------------------+
|                     |        Expert       |
|                     +---------------------+
|     Architect       |       Builder       |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

### Level 2: Add 2nd Expert (split Expert column)
```
+---------------------+---------------------+
|                     |      Expert-1       |
|                     +---------------------+
|     Architect       |      Expert-2       |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

### Level 3: Add 2nd Builder (split Builder column)
```
+---------------------+---------------------+
|                     |      Expert-1       |
|                     +---------------------+
|     Architect       |      Builder-1      |
|                     +---------------------+
|                     |      Builder-2      |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

### Level 4: Add 3rd Expert (split Expert column again)
```
+---------------------+---------------------+
|                     |      Expert-1       |
|                     +---------------------+
|                     |      Expert-2       |
|     Architect       +---------------------+
|                     |      Builder-1      |
|                     +---------------------+
|                     |      Builder-2      |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

### Level 5: Add 3rd Builder (split Builder column again)
```
+---------------------+---------------------+
|                     |      Expert-1       |
|                     +---------------------+
|                     |      Expert-2       |
|                     +---------------------+
|                     |      Expert-3       |
|     Architect       +---------------------+
|                     |      Builder-1      |
|                     +---------------------+
|                     |      Builder-2      |
|                     +---------------------+
|                     |      Builder-3      |
|                     +---------------------+
|                     |      Validator      |
+---------------------+---------------------+
```

### Level 6: Add 2nd Validator (user prompted, split Validator column)
```
+---------------------+---------------------+
|                     |      Expert-1       |
|                     +---------------------+
|                     |      Expert-2       |
|                     +---------------------+
|                     |      Expert-3       |
|     Architect       +---------------------+
|                     |      Builder-1      |
|                     +---------------------+
|                     |      Builder-2      |
|                     +---------------------+
|                     |      Builder-3      |
|                     +---------------------+
|                     |     Validator-1     |
|                     +---------------------+
|                     |     Validator-2     |
+---------------------+---------------------+
```

## Column-Based Splitting Logic

### Expert Column (Top)
Can split multiple times for different domain experts:
- API Expert
- Database Expert
- Frontend Expert
- DevOps Expert
- Security Expert
- Performance Expert
- etc.

**Rule:** Never duplicate the same expert type. If "API Expert" exists, don't create another.

### Builder Column (Middle)
Can split multiple times for parallel implementation:
- Builder-1 (Feature A)
- Builder-2 (Feature B)
- Builder-3 (Feature C)
- etc.

**Rule:** Add when features can be implemented in parallel without conflicts.

### Validator Column (Bottom)
Rarely splits. Single validator is usually sufficient.
- Validator-1 (Main QA)

**Rule:** Only add second validator if user explicitly requests it.

## User Interaction for Split Selection

When columns reach capacity (2+ agents per column), ask user:

```powershell
# Example: Adding 4th expert, but all columns have 2+ agents
> Which column should be split?
  [1] Expert (3 agents: API, DB, Frontend)
  [2] Builder (3 agents: Feature A, B, C)
  [3] Validator (1 agent)
  [4] Cancel

Enter choice (1-4): _
```

## Session Structure (session.json)

```json
{
  "started": "2026-02-09T15:30:00",
  "task": "Build full-stack app",
  "project": "C:\\path\\to\\project",
  "session_dir": "C:\\path\\to\\.devteam",
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
        "agents": ["builder-1", "builder-2", "builder-3"],
        "split_direction": "horizontal"
      },
      "validator": {
        "position": "bottom-right",
        "agents": ["validator-1"],
        "split_direction": "horizontal"
      }
    }
  },
  "agents": {
    "architect": "0",
    "expert-1": "3",
    "expert-2": "4",
    "builder-1": "5",
    "builder-2": "6",
    "builder-3": "7",
    "validator-1": "8"
  },
  "pane_ids": ["0", "3", "4", "5", "6", "7", "8"]
}
```

## Commands

### Add Expert
```powershell
# Add domain expert (Architect determines domain from context)
devteam add-agent expert

# Add specific expert type
devteam add-agent expert --domain frontend

# Add expert with specialization
devteam add-agent expert --domain "minimal design"
```

### Add Builder
```powershell
# Add additional builder for parallel work
devteam add-agent builder
```

### Add Validator
```powershell
# Add second validator (rare, prompts user)
devteam add-agent validator
```

### Show Layout
```powershell
# Visual representation of current layout
devteam layout
```

## Splitting Algorithm

```powershell
function Get-SplitCandidate {
    $column = Get-ColumnByAgentType($AgentType)

    if ($column.agents.Count -ge 2) {
        # Ask user which column to split
        $choice = Prompt-UserForSplitChoice
        $column = Get-ColumnByChoice($choice)
    }

    # Split the bottom pane in the column
    $targetPane = $column.agents[-1]  # Last agent in column
    return $targetPane
}
```

## Expert Type Examples

When creating experts, Architect should assign specific domains:

- `frontend-expert` - UI/UX, CSS, accessibility
- `api-expert` - REST, GraphQL, API design
- `database-expert` - SQL, NoSQL, data modeling
- `devops-expert` - CI/CD, deployment, infrastructure
- `security-expert` - Authentication, authorization, security
- `performance-expert` - Optimization, caching, scalability
- `testing-expert` - Test strategy, automation
- `documentation-expert` - Docs, guides, API references

Each expert gets a specialized droid configuration:

```
~/.factory/droids/
  expert-frontend.md
  expert-api.md
  expert-database.md
  expert-devops.md
  expert-security.md
  expert-performance.md
```

## Maximum Capacity

With column-based layout, theoretical maximum is higher:
- Architect: 1 (fixed)
- Experts: 6+ (different domains)
- Builders: 6+ (parallel features)
- Validators: 2 (rarely needed)

**Practical max**: ~12-15 agents before layout becomes unusable.

## Layout Advantages

1. **Clear separation**: Each agent type has its own column
2. **Easy to understand**: New agents join their type's column
3. **Scalable**: Can add many agents per type
4. **Never splits Architect**: Main coordination pane stays intact
5. **Logical grouping**: Related agents are visually grouped
