---
name: implement-spec
description: Implement an approved Cauldron spec and its dependency graph on one integration branch, using bounded workers, checked completion evidence and local mechanical integration. Use when asked to implement a whole spec or several dependent tickets.
---

# Implement a Cauldron spec

Read `docs/agents/orchestration.md` and `docs/agents/workflow.md`. Provider-neutral roles in `docs/agents/roles/` define behaviour; provider profiles select models.

1. Fetch the spec and child tickets; state the spec title and distinguish build tickets from unresolved decisions. If product decisions remain, settle them with the user rather than letting a worker invent them. Scout current domain facts before relying on an ambiguous term.
2. Create one integration branch/worktree from the authorized base, preserving all existing user changes. Brief each ready ticket as a bounded slice with stable acceptance IDs, scope/base/branch/worktree and focused checks. Independent frontier tickets can run concurrently; dependent stages wait.
3. Workers commit and run focused checks, returning complete/partial/blocked JSON and actual runner artifacts. The lead checks the result with `tools/workflow.py worker-check` and reviews the change. A partial or blocked return preserves work but does not unblock descendants. Compiler failure and zero tests are not behavioural red or a pass.
4. Integrate accepted results with `tools/workflow.py integrate`. It verifies clean source/target, current worker head, included integration tip and valid nonzero evidence, then fast-forwards the exact tested commit. Use a coder for substantive conflicts; do not start a model solely for a mechanical Git merge.
5. Open one draft PR after the first accepted slice if remote work is authorized, linking the spec/tickets. Otherwise keep commits local. Resume the same worker for fixes, relay durable review findings, and use GitHub issue state/native dependencies as the graph when available.
6. Run adversarial and standards/spec reviews at the points required by orchestration. Once fixes are integrated, the lead or explicitly assigned verifier runs the single final `make -C apple ready` on the clean head. A background job still running is not completion; prefer foreground checks when no independent work remains.
7. Report exact-head results and manual/device checks. Mark a PR ready only after completion and review; merge, push and release-tag operations require user authorization. Remove only clean integrated worker worktrees when cleanup is authorized; preserve dirty checkouts and branch refs unless their deletion was requested.

Release preparation uses the signed-artifact/schema preflight, not test success alone. This skill neither permits automatic production deployment nor treats a pushed tag as confirmed TestFlight distribution.
