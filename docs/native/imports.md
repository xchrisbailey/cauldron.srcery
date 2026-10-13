# Cauldron native: imports (Distill)

The pipeline is pure and lives in `apple/CauldronKit/Sources/CauldronKit/Imports/` (`Distill.url`, `Distill.text`; its two seams are `PageFetcher` and `RecipeExtracting` in `Seams.swift`). The app side is `apple/Cauldron/Imports/`: `URLSessionPageFetcher`, `ImportModel` (the flow, no views), `ImportSheet`, `CoverPhoto`, `DuplicateLinks`, and `RecipeDraft+Import` (the pipeline's draft becomes the editor's draft; nothing is stored until the cook saves). A debug-only list of live links to try is in `ImportLiveChecks.swift`.

## The fetcher's rules

`AddressRules` is a device-sized version of `RemoteFetch.ts`'s address checks, applied to the first request, every redirect hop and the cover image, all of which go through `URLSessionPageFetcher.checked`. A page can point a redirect or its cover image at the cook's router or printer, and a GET there can have side effects. So it refuses: a port other than the scheme's default; `localhost` and names ending `.local`, `.localhost`, `.internal`, `.lan`, `.home.arpa`; IP-literal hosts in loopback, private, link-local, CGNAT, unspecified, multicast and reserved ranges (IPv4 in any spelling `URL` keeps, such as `2130706433`, `0x7f.1` or `127.1`, and IPv6 including IPv4-mapped forms). Each is `FetchError.blocked`, so the cook gets "can't open that link" and the paste fallback. It judges the link as written: a public name that resolves to a private address is not caught, because the device has no resolver to ask.

Plain-http links rely on App Transport Security refusing them (`blocked("insecure")`). Nothing may add an ATS exception to the app without restoring a check in `AddressRules`, because ATS is the only thing stopping a cleartext request to the local network today.

## The cover photo

`CoverPhoto` fetches it through the same fetcher: at most 15 MB, `Accept: image/*`, and 20 seconds for the fetch and the decode together (a decode still running at the limit is left to finish and its result dropped). An image from a page may declare at most 24 megapixels, checked from its header before decoding, because a file under 100 KB can declare 100 megapixels; the picker path keeps its own 100 megapixel cap. A photo that fails for any reason is dropped silently and never fails the import.

## From a photo

A third way into the same sheet (#172): photograph a cookbook page or recipe card. The pages are read on the device and the text goes down the paste path, so everything after it (the draft in the editor, unsure fields flagged, a rough reading warned about, macros queued on save) is the same as for pasted text, with the source recorded as pasted text and no link.

- **Getting pages in.** iPhone and iPad: VisionKit's document scanner (several pages in one go, each straightened) or the photo library. Mac: the photo library, image files from the open panel, or files dropped on the sheet. There is no scanner on the Mac. At most ten pages; a picture over the photo picker's 100 megapixel cap (checked from its header) or 15 MB is refused with the same words the picker uses. The scanner closing without saving is a cancel. A device with no scanner, or a refused camera, says so in plain words and leaves the library and pasting open. Pages stay in memory: nothing is written to disk and no image leaves the device.
- **Reading.** `VisionTextReader` (behind `RecipeTextReader`) uses the Swift Vision API, `RecognizeTextRequest`, at the accurate level with language correction and automatic language detection, on a picture shrunk to 4096 px on its long side so a 48 megapixel photo doesn't fill memory. It runs off the main actor, one page at a time (the wait says "Page 1 of 2"), and honours Stop.
- **Reading order.** Vision returns lines with boxes in no useful order. `ReadingOrder` (CauldronKit, pure) puts them right: a clear vertical gutter makes columns, read left in full then right, with headings and footers that span them in their place; otherwise top to bottom with pieces on one baseline joined. Its rules are written at the top of `ReadingOrder.swift`. Pages are joined in the order captured with a blank line between, and handed to `Distill.text` as a paste is.
- **The first page as the photo.** A switch beside the pages, off by default, makes the first page's picture the recipe's photo (downscaled as the editor does it). The draft's photo row can still remove it.
- **Failures.** No text found, text over `Distill.textMax`, a page that can't be read, and no recipe in the text each get their own plain words and offer "Try again" (the pages as they were) and "Paste the text instead" (what was read comes along to fix, when it fits).

### Not verified yet

- A real cookbook page photographed on an iPhone, the document scanner on a device, and how Vision orders a real two-column page. The reader is tested against a page drawn in the test, not photographed.
- On the Mac, image files from the open panel and drops need `com.apple.security.files.user-selected.read-only` in `Cauldron.entitlements`, which the app doesn't have (it is sandboxed). Without it the panel opens but the files can't be read, and the cook sees "couldn't read that photo". The photo library works either way.

## The Mac's file entitlement

The Mac app is sandboxed. Choosing image files and dropping them onto the import sheet need `com.apple.security.files.user-selected.read-only`, which is in `apple/Cauldron/Cauldron.entitlements`. It lets the app read only the files the cook picks or drops, and nothing else. The app never needs write access to files the cook chooses.
