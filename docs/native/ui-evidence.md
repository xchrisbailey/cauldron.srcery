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

The focused `CauldronTests/WeekViewsTests/weeklyTargetSummaryAndSetupRenderAtBothWidthsAndAppearances()`
test exports full WeekPlanner PNGs at 390pt and 1100pt in both appearances, with and without saved
targets, under the runner record's `ui-rendered/` directory. The test writes image bytes to its
XCTest log and the runner decodes them into shared artifacts, avoiding writes outside the app's
sandbox. These ImageRenderer outputs are inspectable layout artifacts, not substitutes for
simulator screenshots or human review.

Attachments prove that a screen rendered, not that it has no clipping or accessibility defects.
Review exported PNGs at representative narrow and wide sizes in light and dark appearance. Human
VoiceOver, real-device sizing, and second-device/iCloud behavior remain manual checks; do not infer
those from simulator screenshots.
