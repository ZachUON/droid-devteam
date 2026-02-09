# Agent Communication Quick Reference

## Sending Messages to Other Agents

When you need to notify another agent to check their inbox, use the **two-step approach**:

### Step 1: Send the Text
```powershell
wezterm cli send-text --pane-id PANE_ID "Your message here"
```

### Step 2: Send Enter Key
```powershell
wezterm cli send-text --pane-id PANE_ID --no-paste "`r`n"
```

## Complete Example

To notify the Builder (pane 3) about new tasks:

```powershell
# First, write the task to their inbox
echo "- [ ] [from: Architect] Implement the calculator UI" >> .devteam/inbox-builder.md

# Then notify them
wezterm cli send-text --pane-id 3 "Check your inbox at .devteam/inbox-builder.md for new tasks."
wezterm cli send-text --pane-id 3 --no-paste "`r`n"
```

## Getting Pane IDs

Always read the session file first:
```powershell
Get-Content .devteam/session.json | ConvertFrom-Json
```

Example output:
```json
{
  "agents": {
    "architect": "0",
    "builder": "3",
    "validator": "4",
    "specialist": "5"
  }
}
```

## Common Commands

### Notify Builder
```powershell
wezterm cli send-text --pane-id 3 "Check your inbox at .devteam/inbox-builder.md"
wezterm cli send-text --pane-id 3 --no-paste "`r`n"
```

### Notify Validator
```powershell
wezterm cli send-text --pane-id 4 "Check your inbox at .devteam/inbox-validator.md"
wezterm cli send-text --pane-id 4 --no-paste "`r`n"
```

### Notify Specialist
```powershell
wezterm cli send-text --pane-id 5 "Check your inbox at .devteam/inbox-specialist.md"
wezterm cli send-text --pane-id 5 --no-paste "`r`n"
```

## Troubleshooting

**Problem:** Text pastes but doesn't execute
**Solution:** Make sure you're sending the second command with `--no-paste "`r`n"`

**Problem:** Command not found
**Solution:** Make sure WezTerm is running and you're in a WezTerm session

**Problem:** Pane ID doesn't work
**Solution:** Run `wezterm cli list --format json` to see current pane IDs
