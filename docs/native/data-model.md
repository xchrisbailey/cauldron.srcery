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
- **Enums are stored as raw strings** with a typed accessor, so an unknown value from a newer build doesn't crash an older one.
- **The stored lists are read one line at a time.** A line an older build can't read (a unit added later, say) is skipped, not the whole list, and `canRewriteIngredients` / `canRewriteSteps` turn false. An editor must not save over a recipe while they are false, or it would drop that line on every device. A list that can't be encoded leaves the stored one untouched.
- **Large lists still sync.** CloudKit's 1 MB record limit doesn't apply: the mirroring moves a large value into an asset by itself, so these columns don't need external storage.
- **`updatedAt` is set for you.** `ChangeStamps` stamps every changed row as the app's main context saves. Work done in another context has to install its own or set `updatedAt` itself.
- **`searchText` is rebuilt by `RecipeRecord.refreshSearchText()`**; call it after changing a title, ingredients or tags.
- **Deleted recipes are soft-deleted** with `deletedAt`.

## Duplicates

CloudKit can't enforce uniqueness, so two devices can each create a row that should exist once. The rule: **the most recently changed row wins, and the id breaks a tie.**

Reads apply it. `ModelContext.current(_:)` and `weighIn(on:)` return the winner, so the app shows one answer however many rows there are. Screens edit the row those return.

`Deduplication.tidy(_:)` deletes the losers, but only once they have gone unchanged for a week (`Deduplication.grace`). A delete syncs and beats any later edit of the same row, and a tag's recipes can arrive after the tag, so a recent duplicate is left alone. It covers:

- the single-row models (body profile, targets, preferences);
- one weigh-in per day;
- one favourite and one pantry item per key;
- one cook per recipe per day;
- tags by lower-cased name, merging their recipes onto the keeper.

## Where the store lives

- The store is opened at an explicit URL, `Application Support/computer.srcery.cauldron/Cauldron.store`. **Never open a `ModelContainer` at SwiftData's default location**: for an unsandboxed Mac app that is `~/Library/Application Support/default.store`, one file shared by every such app.
- The Mac app is sandboxed (`Cauldron.entitlements`), so that path, and any default one, resolves inside `~/Library/Containers/computer.srcery.cauldron`. A test pins this.
- Only `CauldronStore` creates a `ModelContainer` or `ModelConfiguration`; `make lint` fails on one anywhere else.
- When the app is hosting a test run it uses an in-memory store. Tests create their own with `CauldronStore.container(.inMemory)`.
- Until the iCloud entitlement lands (#162) the app runs in `.local` mode, with no sync. After that the store moves to the App Group container so the widget and share extension can read it.

## Left for later tickets

- **A store that won't open** stops the app at launch (`CauldronApp`), and an export can't run without an open store. It needs a recovery screen that can at least hand over the store files, before the first TestFlight build that changes the schema. It has no ticket yet.
- **AI jobs have no owner**, so two devices could both run the same one. #170 decides how a device claims a job.
