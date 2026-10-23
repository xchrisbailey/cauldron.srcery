# Local workflow tool interfaces

Use Python 3's standard library only. These tools run from a checkout, discover its root with Git, and keep evidence under the shared Git directory's `cauldron/` folder, never in tracked source. They do not push, create release tags, initialize CloudKit or deploy production schema.

## Check runner (`tools/checks.py`)

- `focused --platform macos|ios --test CauldronTests/Suite[/test()]` runs one explicit Xcode selection. Reject malformed selectors; use `.xcresult` counts and fail on zero executed tests. Do not silently repair a method name by assuming its signature. Multiple `--test` values are allowed.
- `package [--filter FILTER]` runs CauldronKit tests and rejects zero executed tests.
- `ready` runs the existing lint, all package tests, all Mac tests and all iOS tests once in order; only an entirely successful, unchanged clean revision earns full evidence. Also run tooling tests (`python3 -B -m unittest discover -s tools/tests`).
- `workflow_support.new_run/finish_run` writes a run record, including revision, command, platform, actual counts, logs and result. `kind=checks`, `scope=focused|full`. Successful full records have positive `counts.package`, `counts.macos`, `counts.ios`, `lint=true` and `tooling=true`. Focused records have positive `testCount`. Failed runs distinguish `assertion-failed`, `build-failed`, `runner-failed`, `zero-tests`, and `interrupted`.
- Store result bundles beside the record. Serialize iOS runners with a lock in the shared state folder; no extra simulator boot/shutdown actions. Print summaries and artifact paths, not the full build log. A failing command cannot produce passing evidence. Dirty-run results are useful for TDD but not completion/release evidence.

## Release preflight (`tools/release.py`)

- `record-schema VERSION --phase initialized|deployed|production-current --note TEXT` records an explicit human attestation at the current revision/model fingerprint. Both production phases require matching initialized evidence; `production-current` means a human checked CloudKit Console and saw nothing pending, not that anything was deployed. Local records are not remote verification.
- `preflight VERSION --debug-app PATH --release-app PATH` is read-only except local evidence. Require a clean unchanged revision, matching source/generated version settings, a not-yet-existing version tag, current full check evidence, and actual signed app version/entitlements: Debug Development and Release Production, matching team/container. Do not substitute build settings for signed artifacts.
- Detect schema-sensitive changes since the previous release tag using model-bearing source files and the store model registry. If changed, require current matching initialization plus either valid deployment or `production-current` evidence for that fingerprint, revision and release; the production evidence timestamp cannot precede initialization. Reject stale or malformed records. No automated production deployment or inference of remote state. If unchanged, report that explicitly without inventing a deployment.
- A successful preflight writes `state_directory()/releases/<VERSION>.json`, with `version=1`, `status=passed`, `head`, `tree`, version label and artifact checks. All checks fail closed. Preflight does not tag or push.

## Git hooks (`tools/hooks.py`, `.githooks/`)

- `install` sets repository-local hooks to this checkout's `.githooks` after refusing an unrelated existing hooks path. It never overwrites custom hooks. Installed dispatchers use the owning tooling checkout but discover the active worktree from their working directory.
- `pre-commit` checks staged Swift content with the repository formatter configuration and existing banned-store/banned-button rules, staged JSON parsing and staged Python syntax. It does not format, stage, discard or change user files. No full test suite at commit time.
- `pre-push` consumes Git's ref updates. Native changes require clean current-head full check evidence; if absent, run `checks.py ready` once for that exact checked-out revision. Never reuse evidence for another branch/revision. Tooling-only changes run tooling tests. Deletions need no validation. A `v*` tag requires passing release preflight evidence for its peeled commit/version. Reject missing/stale evidence, multiple unsupported revisions, and unsupported tag versions rather than guessing. Do not push from a hook.

## Task results and integration (`tools/workflow.py`)

A worker returns JSON with `version: 1`, `status: complete|partial|blocked`, `ticket`, full `head` and `base` SHAs, `criteria` (objects with `id`, `status: met|open`, and nonempty `evidence`), `checks` (runner-record paths), `remaining` and `manual` arrays. The brief has `version: 1`, `ticket`, and `criteria` (the expected unique IDs). A complete result accounts for every expected criterion, has no open criteria or remaining work, and references nonzero successful current-head reproducible checks. Compile failures and intentional placeholder code are not behavioural red evidence. Human review still owns whether the evidence actually satisfies each criterion.

`worker-check --result FILE --brief FILE` refuses partial/blocked/incomplete/stale results; it never advances the task graph. `integrate BRANCH --result FILE --brief FILE` additionally requires clean source/target worktrees, the worker's base to be reachable, the current integration tip to be an ancestor of the exact tested worker head, and a non-main target branch. Fast-forward only; conflicts, dirty state and stale heads stop the command. No model is needed just to execute a clean mechanical integration.

`status` lists actual run statuses, revision and artifact paths for this worktree. Running, interrupted and failed checks are not completion. Prefer foreground checks when there is no independent work to do. Send progress when the phase changes; final completion names the tested revision and any explicit remaining human checks.
