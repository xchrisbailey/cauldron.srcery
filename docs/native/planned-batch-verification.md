# Planned-batch device checks

The implementation contract is in [Persist planned recipe batches and enforce serving allocation](https://github.com/xchrisbailey/cauldron.srcery/issues/225) and [Show and edit unassigned servings throughout the weekly planner](https://github.com/xchrisbailey/cauldron.srcery/issues/226). These checks supplement local tests; passing an in-memory test or rendering a view is not evidence of iCloud migration, cross-device convergence, or accessible interaction.

## Existing data and sync

Use a backed-up test account and test data, not the only copy of a recipe box.

Before distributing a TestFlight build, deploy the additive development CloudKit schema to production as required by `data-model.md`. Local in-memory tests cannot verify that deployment; record its completion separately from automated check results.

1. Open an existing synced store after upgrading. Existing day assignments remain in place and have no inferred batch totals. Recipe, diary, Gather and cooking history remain readable.
2. Add a six-serving planned batch and assign two servings each to two days. After relaunch and on a second device, its total is six and two servings remain unassigned.
3. Remove both assignments. The batch remains discoverable with six servings unassigned after relaunch and sync.
4. Add the same recipe again. Its total and allocations are independent of the first batch. Editing the recipe's default servings changes neither batch total.
5. On two offline devices, assign the same remaining capacity to different days. Reconnect. No assignment is silently discarded; an over-assigned result is identified rather than shown as a negative remaining count or as complete. Repair it by increasing the total or removing assignments, then check convergence.
6. Exercise deletion while another device is offline, then reconnect. Record any late assignment or nullified relationship; no unrelated meal or recipe may disappear. Verify recovery actions and exported data.
7. If testing mixed app versions, edit a batch-linked entry on the old build (including a move beyond the saved week or recipe-default servings). On the new build, invalid incoming assignments remain visible and can be removed or corrected; they are not silently truncated.

## Week operations

1. Copy a week containing both partially assigned and wholly unassigned batches. The new batches have independent identities and totals; changing the copy does not change the source. Full destination meal slots do not discard the copied batch's unassigned servings.
2. Change the week-start preference. Existing batches remain reachable with their saved allocation ranges. Clear a displayed week: assignments outside the confirmed dates survive, even when they belong to a batch whose start date is visible in that week.
3. Remove an assignment and undo it. Batch identity and remaining counts are restored. Repeat with a banished recipe, then restore the recipe; its assignment contributes to Gather and macros again.
4. With an unknown-yield recipe containing 400 g of an ingredient and an explicitly entered four-serving batch, compare assigning four servings to one day with one serving on four days. Both request 400 g, while two assigned servings request 200 g. Unassigned servings add nothing to Gather or day macro totals.

## Appearance and accessibility

On iPhone and Mac, in light and dark appearance:

- Check initial scheduling, the weekly batch summary and batch editing with zero, some and all servings assigned.
- Check an over-assigned synced state and verify the repair controls remain available.
- Confirm total changes are explicit and an invalid save leaves the input available to correct.
- Use a long recipe title, large text, and a narrow window. Counts and actions remain readable without overlapping or disappearing.
- Navigate using VoiceOver and, on Mac, the keyboard. Controls identify their day/meal or batch, status is not conveyed by colour alone, and destructive batch removal requires confirmation.
- Check that actual Brew/cooking history remains independent of scheduling and unassigned counts.

Record device, OS, app commit and outcomes on the integration PR. Leave checks marked pending until performed.
