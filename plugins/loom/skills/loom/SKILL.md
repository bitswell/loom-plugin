---
name: loom
version: 0.1.0
description: "Coordinate multiple AI agents through git worktrees using the LOOM protocol. Use for: orchestrate agents, decompose task, spawn workers, multi-agent coordination, parallelize work, LOOM protocol, agent lifecycle, plan gate, worktree isolation, divide and conquer. Replaces manual multi-agent coordination."
author: bitswell
---

# LOOM Orchestrator Skill

You ARE the LOOM orchestrator. You decompose tasks, spawn worker agents in isolated git worktrees, review their plans, approve implementation, integrate results, and clean up.

## Non-Negotiable Rules

1. Only you write to the workspace. Agents write to their own worktrees. Never allow cross-contamination.
2. Every agent works in its own git worktree. Never share worktrees between agents.
3. Every agent commit MUST include `Agent-Id` and `Session-Id` trailers. Reject commits without them at integration.
4. Always run the plan gate. Review ALL plans before ANY implementation starts. No exceptions.
5. Integrate in topological order of the dependency DAG. Never integrate an agent before its dependencies.
6. Never delete failed agent branches. Retain for 30 days minimum.
7. Never force-push the workspace. The workspace only moves forward (monotonicity).
8. Use `git worktree add` for isolation. Do NOT depend on any specific CLI tool beyond git.
9. Dependencies MUST form a DAG. Reject cycles at assignment time.
10. Validate scope at integration: reject commits that touch files outside the agent's `scope` from AGENT.json.

## Core Flow

The 10-step orchestration sequence. The Agent tool is blocking, so use two-phase spawn.

```
 1. Receive task from user.
 2. Decompose into sub-tasks. For each: assign agent-id, scope, dependencies, budget.
 3. Create worktrees:
      git worktree add .loom/agents/<agent-name>/worktrees/<org>_<repo>_<slug> -b loom/<slug>
 4. Write AGENT.json into the assignment directory (parent of worktree). Commit task as ASSIGNED commit on the branch.
 5. PLANNING PHASE: Spawn each worker via Agent tool.
      Read references/worker-template.md, substitute placeholders, pass as prompt.
      For parallel agents, put multiple Agent calls in the same message.
 6. Wait for all agents to return (they will have committed with Task-Status trailers).
 7. PLAN GATE: Read every PLANNING commit body. Check for scope overlaps, missing coverage,
      unrealistic estimates. Approve or append a feedback commit to the branch and re-plan.
 8. IMPLEMENTATION PHASE: Re-spawn each agent with "Implement your approved plan."
      Respect dependency order: agents with unmet deps wait until deps are integrated.
 9. On completion: validate Task-Status is COMPLETED, verify scope, merge --no-ff
      in dependency order, run project validation after each merge.
10. Read Key-Finding trailers from each agent. Clean up worktrees.
```

## Worker Injection Pattern

Build the Agent tool prompt by reading and filling the worker template.

1. Read `references/worker-template.md` to get the full worker DNA.
2. Replace `{{WORKTREE_PATH}}` with the absolute worktree path.
3. Replace `{{AGENT_ID}}` with the agent's kebab-case ID.
4. Replace `{{SESSION_ID}}` with a freshly generated UUID. Use `python3 -c "import uuid; print(uuid.uuid4())"`.
5. For the **planning** spawn, append to the prompt:
   `"This is your PLANNING phase. Read the ASSIGNED commit and AGENT.json. Write your plan in the body of an empty PLANNING commit (Task-Status: PLANNING). Then return. Do NOT implement. Do NOT write PLAN.md or any other protocol file to the worktree."`
6. For the **implementation** spawn, append:
   `"This is your IMPLEMENTATION phase. Your plan was approved. Read the PLANNING commit body from your branch history, implement the work, set Task-Status to COMPLETED, commit, and return."`

Pass the filled template as the Agent tool prompt. Each agent gets its own prompt with its own substitutions.

## Command Patterns

Canonical bash commands for every orchestrator operation.

```bash
# Create worktree + branch
git worktree add .loom/agents/<name>/worktrees/<org>_<repo>_<slug> -b loom/<slug>

# Commit assignment (on the worktree branch)
git -C <worktree-path> commit --allow-empty -m "$(cat <<'EOF'
task(<agent-id>): <short task description>

<Full task description with acceptance criteria>

Agent-Id: bitswell
Session-Id: <orchestrator-session-id>
Task-Status: ASSIGNED
Assigned-To: <agent-id>
Assignment: <slug>
Scope: <paths>
Dependencies: <agent/slug refs or "none">
Budget: <integer>
EOF
)"

# Read agent status
git log -1 --format='%(trailers:key=Task-Status,valueonly)' --grep='Task-Status:' loom/<slug>

# Check scope compliance
git -C <worktree-path> diff --name-only $(git -C <worktree-path> merge-base HEAD main)..HEAD

# Integrate (merge into workspace)
git merge --no-ff loom/<slug> -m "$(cat <<'EOF'
feat(loom): integrate <slug>

Agent-Id: bitswell
Session-Id: <orchestrator-session-id>
EOF
)"

# Clean up worktree
git worktree remove <worktree-path>
```

## Task Recipes

### Single Agent

Skip the parallel gate ceremony. One worktree, one plan spawn, review, one implementation spawn, integrate.

1. Create worktree, commit ASSIGNED with task spec in commit body.
2. Spawn planning phase. Read the PLANNING commit body when it returns. Approve.
3. Spawn implementation phase. On return, verify COMPLETED, validate scope, merge, clean up.

### Parallel Independent Agents

No dependencies between agents. Maximum concurrency.

1. Create all worktrees. Commit ASSIGNED for each.
2. Spawn ALL planning agents in a single message (parallel Agent calls).
3. Plan gate: read all PLANNING commit bodies. Check for scope overlaps. Approve or provide feedback.
4. Spawn ALL implementation agents in a single message (parallel Agent calls).
5. Integrate in any order (no dependency constraints). Run validation after each merge.
6. Clean up all worktrees.

### Agents with Dependencies

Dependency DAG dictates integration order. Planning is still parallel.

1. Create all worktrees. Declare dependencies in each ASSIGNED commit.
2. Spawn ALL planning agents in parallel (planning does not require deps integrated).
3. Plan gate: review all plans, check scope overlaps across the dependency chain.
4. Implement and integrate in topological order:
   - Spawn agents with no unmet deps. Wait for completion.
   - Integrate completed agent.
   - Spawn next tier of agents whose deps are now met.
   - Repeat until all agents are integrated.

### Error: Resource Limit

Agent hits 90% budget, commits BLOCKED with Blocked-Reason: resource_limit.

1. Read Key-Finding trailers to understand what was completed and what remains.
2. Create a continuation agent branching from the blocked agent's branch.
3. Write a new ASSIGNED commit covering only the remaining work.
4. Run the standard two-phase cycle on the continuation agent.

### Error: Merge Conflict

Integration merge fails with conflicts.

1. Abort immediately: `git merge --abort`. The workspace stays clean.
2. Option A -- rebase: `git rebase HEAD loom/<slug>`. If clean, integrate.
3. Option B -- fresh agent: spawn a new agent from current workspace HEAD.
4. Retain the failed branch (never delete).

## References

Detailed material lives in the reference files. Read them as needed.

- `references/protocol.md` -- Full LOOM protocol: lifecycle states, operations, error model, security, observability.
- `references/worker-template.md` -- Worker DNA template. Read this to build Agent tool prompts.
- `references/schemas.md` -- All file format schemas: commit messages, trailers, branch naming, AGENT.json.
- `references/examples.md` -- Five worked end-to-end examples.
