# Dynamic Pane Splitting - Max Split Configuration

## Splitting Rules Clarified

### Rule 1: NEVER Split Architect's Main Pane (Top-Left)
The Architect's primary chat area is sacred and never gets split.

### Rule 2: Split Right-Side Panes First
When adding agents 5-8, ALWAYS prefer splitting the right-hand portion (the 3 existing panes: Builder, Validator, Specialist).

### Rule 3: Only Split Architect After Right Side is Full
Only split the Architect pane horizontally (adding assistant BELOW) when the right side already has 4 panes and can't fit more.

## Visual Progression

### Level 1: Initial Layout (4 agents)
```
+---------------------------------------+
|                  |    Builder (3)     |
|                  |--------------------+
|   Architect (0)  |   Validator (4)    |
|                  |--------------------+
|                  |   Specialist (5)   |
+---------------------------------------+
```

### Level 2: Add Agent 5 (Split Builder vertically)
```
+---------------------------------------+
|                  | Builder-1 (3) | B2 |
|   Architect (0)  |---------------+---+
|                  |   Validator (4) | S |
|                  |---------------+---+
|                  |   Specialist (5)   |
+---------------------------------------+
```

### Level 3: Add Agent 6 (Split Validator vertically)
```
+---------------------------------------+
|                  | Builder-1 (3) | B2 |
|   Architect (0)  |---------------+---+
|                  | Val-1 (4) | V2 | S |
|                  |---------------+---+
|                  |   Specialist (5)   |
+---------------------------------------+
```

### Level 4: Add Agent 7 (Split Specialist vertically)
```
+---------------------------------------+
|                  | Builder-1 (3) | B2 |
|   Architect (0)  |---------------+---+
|                  | Val-1 (4) | V2 | S |
|                  |---------------+---+
|                  | Spec-1 (5) | Spec-2|
+---------------------------------------+
```

### Level 5: Add Agent 8 (Split Architect horizontally - NOW we split Architect!)
```
+---------------------------------------+
|   Architect (0)  | Builder-1 (3) | B2 |
|-----------------+---------------+---+
| Arch-Assist (8)  | Val-1 (4) | V2 | S |
|                  |---------------+---+
|                  | Spec-1 (5) | Spec-2|
+---------------------------------------+
```

## MAX SPLIT CONFIGURATION (8 agents)

This is the theoretical maximum with the current splitting strategy:

```
+-------------------------------------------------------+
|                                                       |
|                   ARCHITECT (0)                       |
|                 (Main Chat Area)                      |
|                                                       |
+-----------------------+-------------------------------+
|                       |                               |
|   Arch-Assistant (8)  |      Builder-1 (3)  |  B2    |
|   (Planning/Coord)    |---------------------+--------+
|                       |    Validator-1 (4)  |   V2   |
|                       +---------------------+--------+
|                       |   Specialist-1 (5)  |  Spec-2|
|                       +---------------------+--------+
+-----------------------+-------------------------------+
```

### Pane Details (Max Configuration)

| Pane ID | Agent Name | Position | Area | Splits |
|---------|-----------|----------|------|--------|
| 0 | Architect | Top-Left | 50% | Arch-Assistant (below) |
| 8 | Arch-Assistant | Bottom-Left | 50% | None |
| 3 | Builder-1 | Top-Right-1 | 25% | Builder-2 (right) |
| 9 | Builder-2 | Top-Right-2 | 25% | None |
| 4 | Validator-1 | Mid-Right-1 | 12.5% | Validator-2 (right) |
| 10 | Validator-2 | Mid-Right-2 | 12.5% | None |
| 5 | Specialist-1 | Bottom-Right-1 | 12.5% | Specialist-2 (right) |
| 11 | Specialist-2 | Bottom-Right-2 | 12.5% | None |

## Splitting Priority Order (Revised)

When adding a new agent, check in this order:

1. **Builder** (if unsplit) → Split vertically
2. **Validator** (if unsplit) → Split vertically
3. **Specialist** (if unsplit) → Split vertically
4. **Builder-2** (if exists and unsplit) → Split vertically
5. **Validator-2** (if exists and unsplit) → Split vertically
6. **Specialist-2** (if exists and unsplit) → Split vertically
7. **Architect** (ONLY if right side has 4 panes) → Split horizontally

## Split Direction Rules

### Right-Side Panes
- Split **vertically** (`--right`) to add agents side-by-side
- This creates columns: Builder | Builder-2 | ...

### Architect Pane
- Split **horizontally** (`--bottom`) to add assistant below
- NEVER split vertically - Architect's main pane stays intact
- Only split when right side is at maximum capacity (4 panes)

## Why This Layout?

1. **Architect stays visible** - Main coordination pane never disrupted
2. **Right side fills first** - Keeps symmetry and balance
3. **Vertical splits on right** - Standard 4-column layout on right side
4. **Horizontal Architect split** - Only when necessary, creates dedicated planning area

## Capacity Limits

- **Minimum**: 1 agent (Architect only)
- **Standard**: 4 agents (initial team)
- **Extended**: 8 agents (max configuration)
- **Beyond 8**: Would require 3x3 grid or different layout strategy

## Alternative: 3x3 Grid (Future Enhancement)

If we wanted to support 9+ agents:

```
+---------------------+---------------------+---------------------+
|     Architect (0)   |    Builder-1 (3)    |   Validator-1 (6)   |
+---------------------+---------------------+---------------------+
|   Arch-Assist (8)   |    Builder-2 (4)    |   Validator-2 (7)   |
+---------------------+---------------------+---------------------+
|   Arch-Assist-2 (9) |    Builder-3 (5)    |  Specialist-1 (10)  |
+---------------------+---------------------+---------------------+
```

But this splits Architect's main area, which violates Rule 1. So 8 agents is the true max under current constraints.
