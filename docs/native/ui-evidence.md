# UI evidence

Run a focused UI test through the shared runner, for example:

```sh
make -C apple test-focused PLATFORM=ios 'TEST=CauldronUITests/WeekTargetsUITests/testTargetsRoundtrip()'
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

`WeekTargetsUITests/testPopulatedWeekShowsScheduleWithoutScrolling()` checks actual first-meal
visibility without scrolling, for breakfast-first and dinner-only days in both appearances.
Run it on the representative 390 × 844pt iPhone viewport; attachment names record measured size.
Its seven-batch fixture requires both the Debug-only in-memory launch contract and
`CAULDRON_UI_TEST_WEEK=breakfast|dinner`; it cannot populate a local or synced store. Separate
batch additions share a recipe, and two servings remain unassigned. The target-save test also
exercises setup from daily nutrition and return to refreshed daily and weekly comparisons.

Keep accepted historical screenshots and any waived checks in the originating issue and runner
handoff, with the actual producing revision. An accepted waiver is not a current-head test pass.
