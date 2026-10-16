# Share extension measurements (#197)

What it costs to read a recipe inside the share extension, measured on a real iPhone with the
Debug-only Measure panel (`apple/CauldronShare/MeasurePanel.swift`, commit `ea7be86`). Map #191.

- **Device**: iPhone 16 Pro Max (iPhone17,2), iOS 27.2 (24B5099f).
- **Build**: Debug (`-Onone`), so Release should use somewhat less memory.
- **Date**: 2026-10-16.

## What was measured

For each link shared from Safari to Cauldron, the panel ran in this order:

1. **Foundation Models**: `SystemLanguageModel.default.availability`, then one
   `LanguageModelSession` with a one-word prompt.
2. **Import cost**: fetched the page with an ephemeral `URLSession`, then ran
   `Distill.url(link, fetcher:, extractor: nil)` from CauldronKit, so there was no model call.
   `phys_footprint` from `task_vm_info` was sampled every 100 ms, along with
   `os_proc_available_memory()` at the start and at the peak.

**Not measured**: the keychain read and the cloud AI call. Chris chose not to copy his AI key
into a shared keychain access group, so the extension never read a key and made no network
model call. No `keychain-access-groups` entitlement was added. Whether a key in a shared group
is readable from the extension is still unanswered.

## Results

| Link | Fetched | Distill | Footprint start → peak | Available start → at peak | FM availability | FM prompt |
| --- | --- | --- | --- | --- | --- | --- |
| Serious Eats, peanut butter banana breakfast bars | 924,187 B | ok, json-ld, 18 ingredients, 548 ms | 23.6 → 33.6 MB | 196.4 → 186.4 MB | available | ok, 3,715 ms |
| Instagram reel with the recipe in the caption | 820,489 B | ok, text reader, 13 ingredients, 969 ms | 17.7 → 28.0 MB | 202.3 → 192.0 MB | available | ok, 4,123 ms |
| Apple News link (`apple.news/…`) | 7,759 B | failed `noRecipe`, 659 ms | 17.5 → 26.4 MB | 202.5 → 193.6 MB | available | ok, 3,363 ms |

The third link was meant to be a long blog recipe page. Apple News shares an `apple.news` link,
which returns a 7.7 KB stub page instead of the article, so there was no recipe to read. A long
blog page is still unmeasured.

## What it means

- **Memory is not the constraint.** The extension started at about 18–24 MB with about 200 MB
  available, which puts the ceiling near 220 MB on this device. Fetching and distilling a
  ~900 KB page added at most about 10 MB, and the peak never went above 34 MB, about 15% of
  the ceiling. The measured memory cost of the on-device prompt is in the start figure only:
  the sampler ran during the fetch and distill, not during the prompt.
- **The on-device model works in the share extension.** It was available on every run and
  answered every prompt, with no rate-limit error. A cold one-word prompt took 3.4–4.1 s, much
  longer than the whole fetch and distill (0.5–1 s). A real extraction prompt will take longer
  still. That latency, not memory, is the cost to design the review sheet around.
- **Structured pages are fast.** Serious Eats was read from JSON-LD in about half a second with
  no model. The Instagram caption went through the text reader with no model in under a second.
  Its title came out as the caption's "⇩ Full Recipe 🍳 ⇩" header, so a model pass, or a title
  rule, is needed for captions.
- **Apple News links need handling.** They should be resolved to the publisher's URL, or get a
  clear "share from the publisher's page" message, rather than ending in `noRecipe`.

## Still open

- A long blog recipe page (the largest pages, likely with inline scripts).
- The keychain access group read and one cloud AI call from the extension, if Chris later
  agrees to copy a key into a shared group.
- The footprint while Foundation Models runs a full extraction prompt, not just a one-word
  prompt.
