# Quick launcher for Dev Team Orchestrator
# Usage: devteam [task]        - Spawn team with optional task
#        devteam stop          - Kill current session
#        devteam status        - Show team progress

$task = $args -join ' '
& "$PSScriptRoot\dev-team-orchestrator.ps1" -Task $task
