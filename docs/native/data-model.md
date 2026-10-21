# Cauldron native: data model

The SwiftData models live in `apple/Cauldron/Data/`. They sync through the CloudKit private database `iCloud.computer.srcery.cauldron`. This note records the rules the schema has to keep and the decisions behind it.

## CloudKit rules

CloudKit rejects a schema that breaks any of these, and only at runtime. `DataModelTests` checks them against `CauldronStore.schema`, so a new model or property fails a test instead.

- Every property is optional or has a default value.
- Every relationship is optional and has an inverse.
- No `@Attribute(.unique)`.
- No `.deny` delete rule.

## Changing the schema

- Changes are **additive only** once a build has shipped: add models and properties, never rename or remove them. A production CloudKit schema can't drop a record type or field.
- Deploy the development schema to production in the CloudKit console **before the first TestFlight build**, and again before any build that adds to it. A build whose schema isn't in production silently fails to sync.
- A renamed property is a new field to CloudKit. Add the new one, copy the values across, and leave the old one in place.

## Decisions

- **Ingredients and steps are stored as JSON on the recipe**, as encoded `[Ingredient]` and `[Step]` from CauldronKit, not as their own models. They are always read and written with their recipe, they stay structured (quantity, unit, item, note, original line), and a recipe syncs as one record instead of dozens. `searchText` on the recipe carries what search needs.
- **Days are stored as `YYYY-MM-DD` strings** (`LocalDate` keys), so a day means the same day on every device and time zone.
- **Photos use external storage**, which CloudKit syncs as an asset.
- **Explicit photo removal declines pending imported covers.** `RecipeRecord.coverDeclined` defaults to false. Removing a photo saves true in the same transaction as the recipe; replacing it resets false, and keeping it preserves the choice. Cover fetches check the saved choice before and after awaiting the image. This additive field closes the crash window that a separate retained-draft marker could not protect.
- **Enums are stored as raw strings** with a typed accessor, so an unknown value from a newer build doesn't crash an older one.
- **The stored lists are read one line at a time.** A line an older build can't read (a unit added later, say) is skipped, not the whole list, and `canRewriteIngredients` / `canRewriteSteps` turn false. An editor must not save over a recipe while they are false, or it would drop that line on every device. A list that can't be encoded leaves the stored one untouched.
- **Large lists still sync.** CloudKit's 1 MB record limit doesn't apply: the mirroring moves a large value into an asset by itself, so these columns don't need external storage.
- **`updatedAt` is set for you.** `ChangeStamps` stamps every changed row as the app's main context saves. Work done in another context has to install its own or set `updatedAt` itself.
- **`searchText` is rebuilt by `RecipeRecord.refreshSearchText()`**; call it after changing a title, ingredients or tags.
- **Deleted recipes are soft-deleted** with `deletedAt`.

- **A removed Health weigh-in leaves a `HealthDismissalRecord`**, which syncs, so the iPhone that reads Health doesn't import the reading again. Duplicates of one are harmless and are not tidied.

## Duplicates

CloudKit can't enforce uniqueness, so two devices can each create a row that should exist once. The rule: **the most recently changed row wins, and the id breaks a tie.**

Reads apply it. `ModelContext.current(_:)` and `weighIn(on:)` return the winner, so the app shows one answer however many rows there are. Screens edit the row those return.

`Deduplication.tidy(_:)` deletes the losers, but only once they have gone unchanged for a week (`Deduplication.grace`). A delete syncs and beats any later edit of the same row, and a tag's recipes can arrive after the tag, so a recent duplicate is left alone. It covers:

- the single-row models (body profile, targets, preferences);
- one weigh-in per day;
- one favourite and one pantry item per key;
- one cook per recipe per day;
- one gathered Gather line per week and merge key (lines added by hand are never merged). **A tick belongs to the line, not to one row of it:** the newest row is usually the one nobody touched (a second device builds its own set of rows before the first one's have synced), so the most-recently-changed rule would lose the tick. A line reads as ticked when any of its rows is; `setChecked` writes the value to every row of the line; a rebuild that unticks a line (the week now needs more) clears every row; and `tidy` carries a deleted row's tick onto the row it keeps. The winning row still decides which text and amount are shown;
- tags by lower-cased name, merging their recipes onto the keeper.

## Gather weeks

- A Gather list belongs to a week start, as in the web app. The first day of the week can be any day (`PreferencesRecord.weekStartsOnRaw`, numbered as `Weekday`: 0 for Sunday to 6 for Saturday; an unknown value reads as Monday). Changing it, from Settings or the Week page, re-keys the list: the week's hand-added items and ticks stay stored under the old week start and are no longer shown.
- **Known limit:** a device that rebuilds a week against a plan it has only half received (Gather rows before the plan entries, or the reverse) can delete lines or untick them, because the rebuild believes the week no longer needs them. This needs a design decision once sync is on (#162).

## Where the store lives

- The store is opened at an explicit URL inside the App Group container, `<group container>/computer.srcery.cauldron/Cauldron.store`, so the widget and the share extension read the same data. A build without the App Group (no signing team) falls back to `Application Support/computer.srcery.cauldron/`. **Never open a `ModelContainer` at SwiftData's default location**: for an unsandboxed Mac app that is `~/Library/Application Support/default.store`, one file shared by every such app.
- The Mac app is sandboxed (`Cauldron-macOS.entitlements`), so any path it opens resolves inside its own container or the App Group's (`~/Library/Group Containers/group.computer.srcery.cauldron`). A test pins the file name.
- The macros widget (#183) never opens the store, since that would run CloudKit mirroring inside an extension. The app writes today's totals, targets and a waiting-estimate flag as `TodayMacros.json` at the root of the App Group container (`TodayMacrosSnapshot`, `TodayMacrosFile`) and asks WidgetKit to reload; the widget only reads that file. The app writes it after every diary write (`DiaryEditor`), targets save and check-in, and queue drain, when it launches, comes forward or goes away, and at midnight. A change that arrives by sync is picked up the next time the app comes forward.
- Only `CauldronStore` creates a `ModelContainer` or `ModelConfiguration`; `make lint` fails on one anywhere else.
- When the app is hosting a test run it uses an in-memory store. Tests create their own with `CauldronStore.container(.inMemory)`.
- The app opens the synced store (`.synced`), mirrored to the iCloud private database. In debug builds `-localStore` opens a separate on-device file, `Cauldron-local.store`, which is the only store `-seed` fills, so demo data never reaches iCloud.

## Left for later tickets

- **A store that won't open** stops the app at launch (`CauldronApp`), and an export can't run without an open store. It needs a recovery screen that can at least hand over the store files, before the first TestFlight build that changes the schema. It has no ticket yet.
- **AI jobs have no owner**, so two devices could both run the same one. #170 decides how a device claims a job.
