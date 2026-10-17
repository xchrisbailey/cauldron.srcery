# Orchestration

**Roles.**

- **Opus 5.5** (`claude-opus-5-5`) is the main session, and the lead of an agent team. It plans, breaks work into tickets, delegates, reviews, and decides. It also keeps the cross-cutting work that `CLAUDE.md` reserves for it: architecture, the SwiftData schema, `project.yml` and targets, entitlements and signing. Orchestration and the review verdict are never delegated.
- **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`) does all delegated coding and test writing, through the `coder` agent in `.claude/agents/coder.md`.
- On an agent team, three more agents in `.claude/agents/` take work off the lead:
  - `reviewer` (Sonnet 5.5, high) gives each draft PR a first-pass review;
  - `shepherd` (Haiku) reruns the local checks on a PR branch and cleans up after merges;
  - `scout` (Haiku) is a read-only lookup subagent for gathering what a brief needs. It works in either mode.
- **Fable 5.1** (`claude-fable-5-1`) runs the `adversary` subagent, which tries to break a ticket breakdown or a risky PR. Opus calls it; it is never a teammate.
- Opus fixes trivial review nits itself. Anything larger goes back to a coder.
- When a ticket records execution assignments, it uses these roles unless the user names others for that work.

**Delegation.**

- Each delegated task is confined to one ticket, or one clearly bounded piece of one.
- Run it in a subagent or a new thread with its own git worktree and branch.
- The brief must stand alone. Include:
  - the ticket link and its "Done when";
  - the files or area, and the existing services, schemas and copy it should reuse;
  - the `CLAUDE.md` rules that bear on it (the coder reads `CLAUDE.md`, but name the ones that matter);
  - what is out of bounds;
  - what to report back: the branch, the PR, a summary, the `make ready` result, and anything left open.
- Coders don't widen scope or make product or architecture decisions. They stop and report any open question to Opus.

**Agent teams.**

- Delegate a single ticket to a `coder` subagent. Start an agent team when two or more tickets are ready at once, or the work is a stack. A team costs tokens for every teammate, so it has to buy parallel work.
- The roster is up to three coders, one `reviewer`, and one `shepherd`. Spawn each from its agent type, which sets its model, and name each coder `coder-<issue>`.
- A teammate starts in the main checkout with none of the lead's conversation. The brief still stands alone, and a coder's brief also names its branch, its worktree path `.claude/worktrees/<issue>-<slug>`, and its base.
- The main checkout stays on `main` and clean. Only the lead works in it, and only the lead runs the app on the simulator.
- Give each ticket three tasks, each subject starting with `#<issue>`, and each depending on the one before:
  - `#<issue> code`, for its coder;
  - `#<issue> review`, for the reviewer;
  - `#<issue> verify`, for the shepherd.
    A ticket's `code` task also depends on the `code` task of each ticket that blocks it.
- The coder and reviewer settle first-pass findings between themselves. A question about the ticket, the epic, or product behaviour comes to the lead from either of them.
- Teammates don't survive `/resume`, so GitHub holds everything that matters: coders push and open the draft PR early, and the reviewer posts findings as a PR comment. Brief a replacement teammate from the PR and its comments.
- Shut a teammate down once its tasks are completed.

**Parallel work and PRs.**

- Outside an integration branch (below), use one branch and one PR per ticket. Name the branch `<type>/<issue>-<slug>`, such as `feat/12-gather-list`.
- Tickets whose blockers are all merged run in parallel, each in its own worktree, and each PR targets `main`. Parallel work is preferred. Two tickets that each edit `apple/project.yml` regenerate the Xcode project, so they can't both merge as generated; land one, then have the other rerun `make project` on the new base.
- When a ticket depends on work that isn't merged yet, **stack** it:
  - The coder branches from the blocking ticket's branch and opens a draft PR against that branch.
  - Opus owns the stack. Coders never restructure one.
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
- Opus reviews each ticket branch against its "Done when" before it goes in, and the adversarial pass runs at the same points as for a PR. Findings go back to the same coder.
- A merger subagent merges a reviewed ticket branch into the integration branch, resolves conflicts, reruns the checks on the result, and pushes. It doesn't change behaviour; a conflict it can't resolve mechanically comes back to Opus.
- The main checkout still stays on `main` and clean. The integration branch lives in its own worktree.
- Mark the PR ready when every ticket is in and the final review passes. Merging it into `main` still waits for the user.

**Adversarial pass.**

- Run the `adversary` subagent at two points:
  - on the ticket breakdown, before delegating work that spans two or more tickets;
  - on a PR, before the Opus review, when it touches the SwiftData schema or anything that syncs, the ingredient parser or scaling, the macro and target maths, imports and fetches, HealthKit writes, or the export format.
- Give it the tickets or the PR. Keep your own conclusions and the reviewer's pass out of the brief, so its read isn't anchored on them.
- A finding counts when it comes with a scenario that reproduces it. Opus decides each one: fix the breakdown, send it to the coder, or set it aside with the reason in the PR.

**Review.**

- Opus reviews every PR before it's marked ready, checking it against:
  - the ticket's "Done when";
  - the epic (#157) and the tickets it depends on;
  - `CLAUDE.md`, especially its conventions.
- Opus also confirms the checks pass on the current head: `make ready` in `apple/` as quoted by the coder, or on a team the shepherd's `verify` result. There is no CI. A report without the result doesn't count.
- Some "Done when" lines need a device, a second iCloud device or TestFlight. Those are Chris's to check: list them in the PR, and don't report the ticket as verified.
- On a team, the `reviewer` passes a PR before Opus reviews it. Its pass covers `CLAUDE.md`'s rules and the acceptance criteria; the plan fit and the verdict stay with Opus.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- Opus reports the result to the user. Merge only when the user asks, or has already said to merge PRs that pass review.
