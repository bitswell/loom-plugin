# Stacked PRs via `stack-project`

**Version**: 1.0.0 | **Protocol**: `loom/2` | **Status**: Draft

How the orchestrator publishes a ladder of stacked PRs over an already-integrated LOOM epic, using the `stack-project` tool. This is the read-only-projection approach: `gh-stack` is an output artifact, not the integration mechanism. LOOM's `--no-ff` merge audit trail is untouched.

See `protocol.md` for the integration model this recipe sits on top of. See `examples.md` for the base LOOM patterns the orchestrator runs before this recipe kicks in.

---

## 1. When to run this recipe

Run `stack-project` when **all** of these hold:

- The epic is a **linear chain** of ≥2 agents connected by `Dependencies:` trailers. Fan-out DAGs (two agents depending on the same parent) are not supported by `gh-stack` itself — use the normal per-`loom/*` PR flow for those.
- All agents in the chain are `Task-Status: COMPLETED` and have been **integrated into the workspace** via the normal `--no-ff` merge path.
- The reviewer benefits from a per-layer diff ladder. For single-agent or two-agent epics where a normal PR already reads well, skip this recipe.
- You own the publish-side state. Don't project an epic that was already projected by another orchestrator session unless you use `reproject: true`.

Do **not** run `stack-project` before integration. The mirror branches are built from the source `loom/<agent>-<slug>` branches, which must be at their final `COMPLETED` state first.

## 2. What the recipe does

Given an integrated epic with sub-tasks `[A, B, C]` in dependency order:

1. The orchestrator collects the integration order from `dag-check`'s `integrationOrder` output (or from the already-known order of `Dependencies:` trailers).
2. It calls `stack-project` with the epic slug and the ordered layer list.
3. `stack-project` builds one mirror branch per layer under `stack/<epic>/<NN>-<agent>-<slug>` by cherry-picking the commits unique to each `loom/*` source branch onto the previous mirror tip. The cherry-pick approach is load-bearing — force-branching to workspace merge commits would leak unrelated workspace history into the per-layer diffs.
4. It runs `gh stack init --base main --adopt <mirror1> <mirror2> <mirror3>` to adopt the mirrors as a `gh-stack` stack.
5. It runs `gh stack submit --auto --draft` (or without `--draft` if `input.draft` is false) to push the mirrors and create the stacked PRs.
6. It returns the mirror branch list and the PR URLs.

The returned PRs are **draft, advisory, and disposable**. Reviewers approve them as a signal, not as a merge event. Integration has already happened via the canonical `loom/*` path. This invariant is what the whole recipe is designed to preserve — see §5.

## 3. Invocation

```json
{
  "tool": "stack-project",
  "input": {
    "epic": "add-auth",
    "order": [
      { "agent": "ratchet", "slug": "auth-middleware", "branch": "loom/ratchet-auth-middleware" },
      { "agent": "moss",    "slug": "api-endpoints",   "branch": "loom/moss-api-endpoints"   },
      { "agent": "ratchet", "slug": "frontend",        "branch": "loom/ratchet-frontend"     }
    ],
    "base": "main",
    "draft": true,
    "reproject": false
  }
}
```

Output:

```json
{
  "mirrorBranches": [
    "stack/add-auth/01-ratchet-auth-middleware",
    "stack/add-auth/02-moss-api-endpoints",
    "stack/add-auth/03-ratchet-frontend"
  ],
  "prUrls": [
    "https://github.com/org/repo/pull/101",
    "https://github.com/org/repo/pull/102",
    "https://github.com/org/repo/pull/103"
  ]
}
```

## 4. Failure handling

Each step of `stack-project` bails cleanly with a typed `err()` on the first failure — no half-published stack is left on GitHub. The error codes are:

| Code | Meaning | Orchestrator response |
|---|---|---|
| `stack-unstack-failed` | `reproject: true` couldn't tear down the existing stack | Resolve manually (`gh stack view --json`, then `gh stack unstack` or manual branch delete), retry |
| `mirror-rev-list-failed` | `git rev-list` couldn't enumerate layer commits | Check that `base` and `layer.branch` both exist and `base` is an ancestor |
| `mirror-branch-failed` | `git branch -f` couldn't move the mirror | Check for uncommitted changes in the worktree |
| `mirror-checkout-failed` | `git checkout` couldn't switch to the mirror | Same as above |
| `mirror-cherry-pick-failed` | A commit conflict during cherry-pick | Don't retry blindly — the layer chain has drifted. Investigate whether `base` moved between integration and projection, or whether an earlier layer was amended. If the workspace is healthy, tear down (`gh stack unstack`), re-run `stack-project` with `reproject: true` |
| `stack-init-failed` | `gh stack init --adopt` rejected the mirror set | Usually means the mirrors are already in a stack. Re-run with `reproject: true` |
| `stack-submit-failed` | `gh stack submit --auto` failed | Check `gh auth status`, retry. If retries fail, tear down with `gh stack unstack` and re-project |

## 5. What this recipe does NOT do

Read this section before reading any other section. These are the load-bearing negatives:

- **It does not merge the stack.** Approving a mirror PR is a reviewer signal. Integration still happens via the canonical `loom/*` branches and the existing `pr-create`/`pr-merge` flow — not via `gh pr merge` on the mirror.
- **It does not modify `loom/<agent>-<slug>` branches.** The `loom/*` namespace is authoritative, scope-enforced, and untouched by this recipe. Cherry-picks land on the `stack/*` namespace only.
- **It does not touch the workspace merge history.** The `--no-ff` merge commits from normal LOOM integration remain exactly as they were.
- **It does not create new trailers, lifecycle states, or worker obligations.** Workers run the exact same protocol as non-stacked LOOM. They do not know their branch will be projected.
- **It does not give reviewers a merge button.** Mirror PRs are drafts and their approval does not move anything. The recipe document published at the top of each mirror PR body explains this — reviewers must be briefed once.

## 6. Teardown

After the epic is fully reviewed and the orchestrator has run its normal post-integration cleanup:

1. `gh stack unstack` on the epic's mirror stack (closes the mirror PRs on GitHub)
2. Delete the local `stack/<epic>/<NN>-*` branches (`git branch -D stack/<epic>/*`)
3. Delete the remote mirror branches (`git push origin --delete stack/<epic>/01-...` for each)

None of this is required for correctness — leaving mirror branches behind is harmless — but the mirror namespace is disposable by design and should not accumulate.

## 7. Re-projection

If the epic is revised after initial projection (e.g. a reviewer requested a change and the orchestrator re-dispatched a worker, re-integrated, and now wants to refresh the stack PRs), call `stack-project` again with `reproject: true`:

```json
{
  "tool": "stack-project",
  "input": {
    "epic": "add-auth",
    "order": [ /* same order as before */ ],
    "reproject": true
  }
}
```

`reproject: true` runs `gh stack unstack` first, then rebuilds the mirrors and resubmits. The prior mirror PRs are closed on GitHub (per `gh stack unstack` semantics) and replaced with fresh ones.

## 8. End-to-end example

A 3-agent `add-auth` epic:

```
Step 1: Workers run and complete via normal LOOM flow
  - loom/ratchet-auth-middleware   COMPLETED
  - loom/moss-api-endpoints        COMPLETED (depends on ratchet-auth-middleware)
  - loom/ratchet-frontend          COMPLETED (depends on moss-api-endpoints)

Step 2: Orchestrator integrates in dependency order via existing pr-create + pr-merge
  - PR #98  loom/ratchet-auth-middleware -> main  (merged --no-ff)
  - PR #99  loom/moss-api-endpoints      -> main  (merged --no-ff)
  - PR #100 loom/ratchet-frontend        -> main  (merged --no-ff)

  main's --first-parent log now shows three merge commits, in order.

Step 3: Orchestrator projects the epic as a read-only stack for reviewer UX
  - Calls stack-project { epic: "add-auth", order: [...], draft: true }
  - Tool builds: stack/add-auth/01-ratchet-auth-middleware (cherry-picked from loom/ratchet-auth-middleware)
                 stack/add-auth/02-moss-api-endpoints      (cherry-picked onto 01)
                 stack/add-auth/03-ratchet-frontend        (cherry-picked onto 02)
  - Tool runs: gh stack init --base main --adopt stack/add-auth/01-... stack/add-auth/02-... stack/add-auth/03-...
  - Tool runs: gh stack submit --auto --draft
  - Returns: three draft PR URLs, one per layer

Step 4: Reviewers read the draft ladder, approve the layers they are happy with
  - Approvals are advisory — the canonical integration at step 2 already happened.

Step 5: Epic complete
  - Orchestrator runs 'gh stack unstack' for the epic's mirror stack.
  - Local stack/add-auth/* branches cleaned up.
```

The `loom/*` branches, the `--no-ff` workspace merge commits, the PRs #98–#100, and the `main` history are all byte-identical to a non-stacked LOOM run. The only addition is the three draft mirror PRs that reviewers used as a reading aid.

---

*End of stacked-prs.md v1.0.0.*
