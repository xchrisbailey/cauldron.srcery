# UI evidence

Run a focused UI test through the shared runner, for example:

```sh
make -C apple test-focused PLATFORM=ios TEST=CauldronUITests/WeekTargetsUITests/testTargetsRoundtrip()
```

UI tests launch the app with the Debug-only `CAULDRON_UI_TEST_IN_MEMORY=1` contract. This is
deliberately independent of XCTest's app-process environment: the child process may not inherit
`XCTestConfigurationFilePath`. Never use `-localStore` for UI testing. The explicit flag selects
a disposable in-memory SwiftData container and thereby disables the app's synced-store launch
path. UI screenshot attachments are retained in the `.xcresult` bundle; export them to a
non-repository scratch/artifact directory with `xcrun xcresulttool export attachments --path
<result.xcresult> --output-path <artifact-directory>`.

`checks.py ready` is the standard readiness check: it runs lint, package tests, Mac app tests
(`CauldronTests` only), iOS app tests and iOS UI tests, plus tooling tests. The Mac UI suite is
intentionally opt-in because it requires interactive macOS automation. Run it explicitly when
needed, for example `make -C apple test-focused PLATFORM=macos TEST=CauldronUITests/WeekTargetsUITests`.
Focused UI selections retain the runner's positive executed-test and skipped-test failure guards;
opting in never silently counts an omitted or skipped UI suite as passing. Readiness evidence
records required/executed targets and says `macosUITests: opt-in-not-run`; it does not imply those
tests ran.

The `WeekTargetsUITests` suite captures the actual WeekPlanner in its app context: the iPhone
simulator supplies the narrow viewport and the macOS app supplies the wide viewport. It records
target/no-target and light/dark states. Attachment names include the measured app-frame dimensions,
target state and appearance. Export attachments from each `.xcresult` with the command above; these
are full app screenshots, not ImageRenderer approximations.

Attachments prove that a screen rendered, not that it has no clipping or accessibility defects.
Review exported PNGs at representative narrow and wide sizes in light and dark appearance. Human
VoiceOver, real-device sizing, and second-device/iCloud behavior remain manual checks; do not infer
those from simulator screenshots.

The user accepted the prior Mac UI coverage and waived a rerun at the latest head. The accepted Mac
screenshots and their `.xcresult` provenance remain under
`.git/cauldron/runs/357b295c814b44d9b71f171a691dd515/attachments/`, produced at commit `8b521bb`.
They are historical accepted evidence, not a latest-head Mac UI pass. The latest-head Mac UI rerun
is waived, while Mac app tests remain required by standard readiness.
