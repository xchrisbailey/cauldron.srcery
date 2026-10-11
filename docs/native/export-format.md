# Cauldron native: export format

Settings has an **Export** section (`apple/Cauldron/Export/ExportSection.swift`) that writes everything the app holds to files the cook keeps. This note is the contract for those files. Import is not built, but the format is meant to be read back, and a person's saved exports must keep working.

## The files

An export is one folder with two files, handed to the share sheet (Save to Files, AirDrop, Mail):

- `cauldron-export-YYYY-MM-DD.json`: the data, versioned.
- `cauldron-photos-YYYY-MM-DD.zip`: the recipe photos, one entry each at `photos/<photo id>.<ext>`. It is left out when no recipe has an image. The extension comes from the image's first bytes (`jpg`, `png`, `heic`, `webp`, `gif`, `avif`, or `bin` when unknown).

The date is the day the export was made, in the cook's calendar. The zip is written by `ZipWriter` in CauldronKit: stored entries (no compression, since photos are already compressed), UTF-8 names, no Zip64. It needs only Foundation, writes one photo at a time, and `unzip`, Archive Utility and Files all open it.

## The JSON

The code is `CauldronKit/Sources/CauldronKit/Export/ExportFormat.swift`. The types there are the format; they are deliberately separate from the SwiftData models, so the schema can grow without a shipped format changing. `ExportFormatTests` pins the exact JSON of version 1 against a fixture, and `apple/CauldronTests/ExportTests.swift` exports a seeded store end to end.

```
formatVersion   1
exportedAt      moment
app             { name, version? }
recipes         every recipe, banished ones too (deletedAt set)
photos          one per image; file is the zip entry
tags, cooks, planEntries, gatherItems (with sources), pantry,
diary, favourites, weighIns
bodyProfile, targets, preferences      one each, left out when never set
```

Conventions:

- **Ids** are UUID strings. A record points at another by id (`recipeId`, `tagIds`), and a pointer is left out when the target is gone or was never set.
- **Days** are `YYYY-MM-DD` in the cook's calendar, never a moment. **Moments** are ISO 8601 in UTC to the millisecond (`2026-10-11T09:30:00.000Z`); finer precision in the store is rounded.
- **A nil field is left out**, and a list is always present, even empty. Read an absent field as unknown.
- **Enums are plain strings** (`slot: "dinner"`, `unit: "fl_oz"`), so a value a later build adds doesn't make the file unreadable. The values are listed in the doc comments on the types.
- **Quantities** are `{ "min": 2 }` or `{ "min": 1, "max": 2 }`. Ingredients keep everything the recipe holds: section, quantity, unit, item, note, optional, alt measure, the original line and the merge key. A line is never reduced to text.
- **Keys are sorted and the output is indented**, so two exports of the same data are the same bytes.

### What is in, and what is not

In: recipes (with ingredients, steps, source, macros, tags, last cooked), banished recipes, photos, tags, cooks, the week plan, Gather lists with the recipes behind each line, pantry, diary, favourites, weigh-ins, body profile, targets and preferences.

Left out:

- **AI jobs.** They are queued work, not data, and are rebuilt from a recipe or a diary entry.
- **`searchText`.** Derived from titles, ingredients and tags; rebuilt on import.
- **Gather's "in pantry" mark.** Derived from the pantry list.
- **Ingredient or step lines this build cannot read at all.** A line from a newer build is kept with its unknown unit as a string; only a line that is not a valid ingredient object is dropped, as everywhere else in the app.

### Duplicates

CloudKit can't enforce uniqueness (see `data-model.md`), so the store can hold two rows that should be one. The export writes the winner, chosen by the same rule the app reads with (`Deduplication.keeper`: most recently changed, then the id). Duplicate tags are merged: every recipe's `tagIds` names the winning tag. Rows with a day that is not a real day are not exported; the result counts them and the section says so.

## Versions

`formatVersion` is an integer. `CauldronExport.decode` reads the version first and refuses a file from a newer format (`ExportFormatError.newerFormat`) instead of half reading it, and refuses a file that is not an export (`unreadable`).

- **Additive changes keep the version.** A new optional field, or a new record list that a reader can treat as empty when absent, is not a new version. Readers ignore keys they don't know. Add the field to the type, extend the fixture and the format test, and note it here.
- **Anything else is a new version:** renaming or removing a field, changing what a value means or how it is written, making a field required. Bump `CauldronExport.currentVersion`, keep the version 1 types and decoder (the fixture test for version 1 stays), and have `decode` migrate older files to the current types. Write the new fixture beside the old one.
- Never edit the version 1 expectation in `ExportFormatTests` to make a change pass. That test failing means a file people already saved would no longer read the same.

## Checks left to a person

The tests cover the files and the section's controller. Saving through the share sheet to Files on a device, and the section's layout inside Settings, need a human with a device.
