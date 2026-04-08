#!/usr/bin/env bash
# LOOM PreToolUse hook: validate git commit commands have required trailers
# Runs before Bash tool calls. Checks if the command is a git commit and
# validates that Agent-Id and Session-Id trailers are present.
#
# Exit 0 = allow, Exit 2 = block with message
# Input: JSON on stdin with tool_input.command

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+((-C\s+\S+\s+)?commit|commit)'; then
  exit 0
fi

# Allow --allow-empty with no message (unlikely but skip)
# Check for Agent-Id and Session-Id in the commit message
if echo "$COMMAND" | grep -q 'Agent-Id:' && echo "$COMMAND" | grep -q 'Session-Id:'; then
  exit 0
fi

# Missing trailers — block the commit
echo '{"decision": "block", "reason": "LOOM protocol violation: git commit missing required Agent-Id and/or Session-Id trailers. Every commit must include both trailers per LOOM schemas.md Section 7.1."}'
exit 2
