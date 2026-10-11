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
- **Deleted recipes are soft-deleted** with `deletedAt`.

## Duplicates

CloudKit can't enforce uniqueness, so two devices can each create a row that should exist once. `Deduplication.tidy(_:)` resolves them with one rule: **the most recently changed row wins, and the id breaks a tie.** It covers:

- the single-row models (body profile, targets, preferences);
- one weigh-in per day;
- one favourite and one pantry item per key;
- one cook per recipe per day;
- tags by lower-cased name, merging their recipes onto the keeper.

Reads go through `ModelContext.current(_:)` and `weighIn(on:)`, which apply the same rule, so the app shows one answer before a tidy has run.

## Where the store lives

- The store is opened at an explicit URL, `Application Support/computer.srcery.cauldron/Cauldron.store`. **Never open a `ModelContainer` at SwiftData's default location**: for an unsandboxed Mac app that is `~/Library/Application Support/default.store`, one file shared by every such app.
- When the app is hosting a test run it uses an in-memory store. Tests create their own with `CauldronStore.container(.inMemory)`.
- Until the iCloud entitlement lands (#162) the app runs in `.local` mode, with no sync. After that the store moves to the App Group container so the widget and share extension can read it.
