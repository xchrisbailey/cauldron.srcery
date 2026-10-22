# Local checks, completion and release evidence

These commands use Python 3's standard library and the existing Swift/Xcode toolchain. They do not push, tag, deploy schema, or run the live initializer. Evidence and full logs live under the shared Git directory's `cauldron/` folder, not in the checkout. `tools/workflow.py status` reports what actually ran.

## Focused work and final verification

From the repo root:

```sh
make -C apple test-focused PLATFORM=macos TEST=CauldronTests/WeekPlanTests
make -C apple test-focused PLATFORM=ios 'TEST=CauldronTests/WeekViewsTests/theStirSheetsRenderInBothAppearances()'
python3 -B tools/checks.py package --filter CopyTests
make -C apple tooling-test
```

Use exact Xcode identifiers. A method identifier includes its parentheses; an exit-zero run with zero executed tests is a failure. The runner reads result bundles, records actual counts and classifies assertion, compilation, test-runner and selection failures separately. iOS runs share a lock; this is not permission to boot/drive an unrelated simulator.

During behaviour changes, use the relevant failing assertion and then focused green checks. For behaviour-preserving work, record a passing baseline. Compiler failures or intentionally empty code do not establish behavioural red. Copy catalogue, export decoding, schema and cross-platform rendering checks are related contracts, not unrelated unit tests; include them when that surface changes.

Commit the slice, merge the latest integration tip if needed, and run focused checks on the clean resulting head. Dirty-run evidence is retained for diagnosis, but does not establish committed completion. The lead or assigned verifier runs `make -C apple ready` once on the final clean integrated revision, after fixes. It runs existing lint, all package/Mac/iOS tests and tooling tests. An infrastructure retry is recorded separately from the failed run; it does not rewrite the failed record as a pass.

## Worker completion and checked integration

Keep briefs and worker-result JSON in the common Git state directory or another untracked location outside the checkout. The brief identifies one bounded ticket/slice and its acceptance IDs:

```json
{"version":1,"ticket":"example","criteria":["persists-total","rejects-overassignment"]}
```

The worker returns full commit/base SHAs, complete/partial/blocked status, every criterion and evidence, runner-record paths, remaining work, and manual checks. The full interface is in `tooling-contract.md`. A complete status cannot omit criteria, carry remaining work, or rely on failed/zero-test/stale/dirty checks. Human review still judges whether a test or change actually meets the criterion; JSON is not proof of product correctness.

```sh
python3 -B tools/workflow.py worker-check --result /path/worker.json --brief /path/brief.json
python3 -B tools/workflow.py integrate feat/example --result /path/worker.json --brief /path/brief.json
```

Run integration from a clean, non-main integration checkout. The command validates source/target cleanliness, branch head and evidence, then fast-forwards only. Dirty/stale/conflicting work returns to its owner. It does not restructure stacks, create an untested merge commit, close issues or push. The worker must include the latest integration tip and retest before retrying.

## Local Git guardrails

Run `make -C apple setup-hooks` in the owning checkout. Installation is repository-local, refuses a different existing hooks path, and leaves hook files and user changes intact. The configured path is absolute to that checkout; keep it available, and reinstall after relocating it. Hooks use their owning tools but inspect the active worktree.

- Pre-commit checks **staged** Swift formatting/store/button policies, JSON and Python syntax. It never formats, stages or stashes. Partially staged working copies do not substitute for staged content.
- Pre-push requires a clean checked-out revision for native/tooling/release changes. Native changes reuse valid current-head full evidence or run the final runner once. Tooling-only changes run tooling tests. Other revisions must be validated from their own clean checkout. A release tag additionally requires that exact commit/version's successful preflight.
- As with any local Git hook, deliberate `--no-verify` bypasses it; these are local guardrails, not a remote security boundary. Native CI remains intentionally absent. A shared environment that needs enforcement against bypasses should add server-side checks rather than claim the local hook is unbypassable.

## Release preparation

Read `docs/native/data-model.md` before schema work or any `v*` tag. Builds, development schema initialization, production promotion and TestFlight distribution are different events.

1. Commit the intended version and run final full validation on the clean release revision.
2. Use `python3 -B tools/release.py build --configuration Debug`, then the same command with `Release`, to create signed artifacts and revision-bound provenance without launching the app. Read the output paths. Missing or wrong signing fails preflight rather than weakening the runtime guard.
3. If models/registry changed since the preceding release, initialize Development using the guarded scratch-store command, then deploy in CloudKit Console. Record each **performed** step with `record-schema VERSION --phase initialized|deployed --note 'who/what confirmed it'`. These are explicit human attestations, not remote API verification. Stale or missing attestations block preflight; unchanged schema is reported as unchanged.
4. Run `make -C apple release-preflight VERSION=vX.Y.Z DEBUG_APP=/path/Debug/Cauldron.app RELEASE_APP=/path/Release/Cauldron.app`. It checks version, current-head full validation, signed environments/container/team, artifact provenance and required schema attestations. It does not make a tag.
5. Only with user authorization, create/push the version tag at the preflighted commit. The pre-push hook checks that evidence. Verify the Xcode Cloud result separately before claiming distribution.

When a phase changes, report its outcome or blocker. Keep bounded checks in the foreground when nothing independent can advance; do not repeatedly end the task with pending-job messages. Completion names the tested revision, actual results, and any explicit human checks left open.
