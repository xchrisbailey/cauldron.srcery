# Orchestration

**Roles.**

- Role behaviour has one source: `docs/agents/roles/`. Provider profiles choose models and permissions, not a different implementation/review workflow.
- The **lead** plans, delegates, decides, reviews and retains architecture/schema/project/signing work. `coder` implements bounded briefs; `scout` finds facts; `reviewer` checks criteria and standards; `adversary` supplies failure scenarios; `shepherd` performs assigned verification/upkeep.
- The lead fixes trivial review nits itself. Anything larger goes back to the same coder.
- When a ticket records execution assignments, it uses these roles unless the user names others for that work.

**Delegation.**

- Each delegated task is confined to one ticket, or one clearly bounded piece of one.
- Run it in a subagent or a new thread with its own git worktree and branch.
- The brief must stand alone. Include:
  - the ticket link and its "Done when";
  - the files or area, and the existing services, schemas and copy it should reuse;
  - the `CLAUDE.md` rules that bear on it (the coder reads `CLAUDE.md`, but name the ones that matter);
  - what is out of bounds;
  - stable acceptance-criterion IDs and what focused checks to run;
  - the worker-result JSON and runner-artifact paths to return (see `docs/agents/workflow.md`).
- Coders stop and report open product/architecture questions to the lead. Partial/blocked results preserve work but do not advance the ticket graph. The lead owns the final full check on the integrated head.

**Execution and transport.**

- Parallelism has to buy independent work. Use standalone briefs and separate worktrees for up to three independent coders; keep coding, review and final verification ordered where they depend on each other.
- The main checkout belongs to the lead. New worktrees use the provider's worktree folder; existing dirty checkouts are preserved. Only the lead owns simulator-wide operations; the test runner serializes iOS checks.
- A Claude team task list or OpenCode child-session ID is transport, not acceptance. The worker-result contract and exact-head check records determine whether a result is complete. The lead relays findings and resumes the same coder.
- GitHub comments hold durable review decisions when work is remote. Local run logs/status live under the common Git directory, scoped by checkout/revision; use `python3 tools/workflow.py status` rather than assuming a background job finished.
- Prefer foreground bounded checks when nothing else can advance. Narrate phase changes, findings and blockers, not every mechanical merge or intermediate pending status.

**Parallel work and PRs.**

- Outside an integration branch (below), use one branch and one PR per ticket. Name the branch `<type>/<issue>-<slug>`, such as `feat/12-gather-list`.
- Tickets whose blockers are all merged run in parallel, each in its own worktree, and each PR targets `main`. Parallel work is preferred. Two tickets that each edit `apple/project.yml` regenerate the Xcode project, so they can't both merge as generated; land one, then have the other rerun `make project` on the new base.
- When a ticket depends on work that isn't merged yet, **stack** it:
  - The coder branches from the blocking ticket's branch and opens a draft PR against that branch.
  - The lead owns the stack. Coders never restructure one.
  - Coder branches come from separate worktrees, so build the stack on GitHub with `gh stack link <bottom PR> <next PR> …`, bottom first. It needs no local tracking.
  - A stack is linear. When two tickets share a base, link one into the stack and leave the other as a sibling PR based on the same branch.
  - Merge a stack with `gh stack merge <stack number> --squash --yes`. It merges every layer into `main` atomically. `gh pr merge` refuses a PR that is part of a stack.
  - Land a sibling after its base has merged: `git rebase --onto origin/main <old base branch> <sibling branch>`, push with `--force-with-lease`, retarget with `gh pr edit <pr> --base main`, rerun `make ready`, then `gh pr merge --squash`.
  - `gh stack merge` leaves the merged branches on the remote. Delete them afterwards.
  - When a lower layer changes before the stack merges, restack by hand the same way: rebase each higher branch onto the changed one and force-push with lease.
  - Stacked PRs are in public preview. If `gh stack` fails, skip the stack: merge the bottom PR, then rebase and retarget each PR above it in turn.
- Keep stacks short. Don't stack work that could run in parallel.
- PR descriptions link the ticket with `Closes #<issue>` and name the PR this one is stacked on, if any.
- A skill that asks for one integration branch, such as `implement-spec`, gets the integration-branch workflow below instead of per-ticket PRs.

**Integration branches.**

- When a skill asks for one integration branch and merger agents, follow the skill. For that spec it replaces per-ticket PRs and stacks; everything else in this file still applies.
- Name the branch `feat/<spec issue>-<slug>` and cut it from `origin/main`. Push it, and open one draft PR against `main` after the first ticket merges into it. The PR description lists `Closes #<issue>` for the spec and for each ticket as it lands.
- Each ticket still gets its own worktree and its own branch, `<type>/<issue>-<slug>`, based on the integration branch tip. Tickets whose blockers are all in the integration branch run in parallel.
- A coder's brief names the integration branch as its base and asks for the branch and the check results back, not a PR. The coder merges the integration branch tip into its branch and reruns the checks before reporting done.
- The lead reviews each ticket branch against its "Done when" before it goes in, and the adversarial pass runs at the same points as for a PR. Findings go back to the same coder.
- The lead runs `tools/workflow.py integrate` for a clean, complete, tested worker result. It fast-forwards only after checking the latest integration tip is included and preserves the exact tested head; no merge-only model session is needed. A stale base, conflict, dirty checkout or partial result goes back to its owner, not into an automatic rebase/reset.
- The main checkout still stays on `main` and clean. The integration branch lives in its own worktree.
- Mark the PR ready when every ticket is in and the final review passes. Merging it into `main` still waits for the user.

**Adversarial pass.**

- Run the `adversary` subagent at two points:
  - on the ticket breakdown, before delegating work that spans two or more tickets;
  - on a PR, before the lead's review, when it touches the SwiftData schema or anything that syncs, the ingredient parser or scaling, the macro and target maths, imports and fetches, HealthKit writes, or the export format.
- Give it the tickets or the PR. Keep your own conclusions and the reviewer's pass out of the brief, so its read isn't anchored on them.
- A finding counts when it comes with a scenario that reproduces it. The lead decides each one: fix the breakdown, send it to the coder, or set it aside with the reason in the PR.

**Review.**

- The lead reviews every PR before it's marked ready, checking it against:
  - the ticket's "Done when";
  - the epic (#157) and the tickets it depends on;
  - `CLAUDE.md`, especially its conventions.
- The lead confirms a successful full runner record on the current clean head: `make ready` in `apple/`, run by the lead or an explicitly assigned shepherd. Local hooks gate native pushes using that evidence; there is no native CI. A stale, zero-test, dirty or failed record does not count.
- Some "Done when" lines need a device, a second iCloud device or TestFlight. Those are Chris's to check: list them in the PR, and don't report the ticket as verified.
- The reviewer's first pass covers standards and acceptance criteria; plan fit and the final verdict stay with the lead.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- The lead reports the result to the user. Merge/push only with authorization. Before a `v*` tag, follow signed-artifact/schema preflight in `docs/native/data-model.md`; a pushed tag alone is not proof that TestFlight started or distributed a build.
