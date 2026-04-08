#!/usr/bin/env bash
# LOOM PostToolUse hook: check for protocol violations after bash commands
# Detects: direct pushes to main, force pushes, scope leaks (AGENT.json/PLAN.md in merges)
#
# Exit 0 = no action (post hooks are advisory)
# Input: JSON on stdin with tool_input.command and tool_result

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Warn on direct push to main
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\bmain\b'; then
  if ! echo "$COMMAND" | grep -q -- '--delete'; then
    echo '{"notification": "LOOM warning: detected push to main. Use PRs for integration unless this is an orchestrator merge."}'
  fi
fi

# Warn on force push
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
  echo '{"notification": "LOOM violation: force push detected. The workspace only moves forward (monotonicity rule)."}'
fi

# Warn on merge that might include protocol files
if echo "$COMMAND" | grep -qE 'git\s+merge'; then
  RESULT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_result',{}).get('stdout',''))" 2>/dev/null || echo "")
  if echo "$RESULT" | grep -qE '(AGENT\.json|PLAN\.md|STATUS\.md)'; then
    echo '{"notification": "LOOM warning: merge included protocol files (AGENT.json, PLAN.md, or STATUS.md). These should not be integrated into the workspace."}'
  fi
fi

exit 0
