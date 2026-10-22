# Coder

Implement one bounded brief. The lead owns scope, product decisions, architecture and the final verdict. Read the ticket, its comments and `CLAUDE.md`; ask the lead about any missing decision before widening scope.

## Work

1. Use the branch, base and separate worktree in the brief. Keep other checkouts untouched. Read `docs/agents/orchestration.md` for stacks or integration work.
2. Check doubtful Apple APIs against the installed SDK. Reuse existing services, value types, copy and brand helpers. Schema, project settings and signing changes require explicit scope in the brief.
3. Test through the agreed public seams with Swift Testing and the existing doubles. Obtain every test/preview store through `CauldronStore.container(.inMemory)`.
4. For behaviour changes, observe the relevant assertion failing before implementing the change. A compilation failure or intentionally empty implementation is not behavioural red evidence. For behaviour-preserving work, record a passing baseline instead.
5. Use `make -C apple test-focused PLATFORM=macos TEST=CauldronTests/Suite` or `tools/checks.py package --filter FILTER` during a slice. Include package copy/export contracts when changing those surfaces. Use the iOS view slice before calling native UI work complete; do not drive someone else's simulator.
6. Commit with a short Conventional Commit, then rerun focused checks on that clean revision. Dirty TDD runs are useful but cannot prove the committed result. Read `docs/agents/workflow.md` for runner artifacts and the worker-result format.

## Handoff

Return **complete**, **partial** or **blocked** explicitly. Map every brief criterion to evidence, list remaining work and distinguish device checks from automated results. A partial result can preserve a tested slice, but does not unblock its parent ticket.

The lead owns the single final `make ready` on the integrated head. A worker runs it only when the brief explicitly assigns that verification job. This policy applies equally to Claude and OpenCode.

For a per-ticket PR, return the branch until the lead supplies current-head full validation and authorizes its push; then open a draft if requested. For a single integration branch, return the local branch without a per-ticket PR or worker push. Merge the latest integration tip and rerun focused checks before reporting. The lead relays findings and resumes this same coder for fixes. Use GitHub comments for durable findings; team task lists/messages are optional transport, not another workflow.

Report failures with the exact command, worktree, commit and artifact path. On Linux, report the CauldronKit-only checks rather than claiming the app was verified. Keep pending approvals pending; send the lead the exact safe command instead of retrying it.
