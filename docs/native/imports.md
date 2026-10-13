# Cauldron native: imports (Distill)

The pipeline is pure and lives in `apple/CauldronKit/Sources/CauldronKit/Imports/` (`Distill.url`, `Distill.text`; its two seams are `PageFetcher` and `RecipeExtracting` in `Seams.swift`). The app side is `apple/Cauldron/Imports/`: `URLSessionPageFetcher`, `ImportModel` (the flow, no views), `ImportSheet`, `CoverPhoto`, `DuplicateLinks`, and `RecipeDraft+Import` (the pipeline's draft becomes the editor's draft; nothing is stored until the cook saves). A debug-only list of live links to try is in `ImportLiveChecks.swift`.

## The fetcher's rules

`AddressRules` is a device-sized version of `RemoteFetch.ts`'s address checks, applied to the first request, every redirect hop and the cover image, all of which go through `URLSessionPageFetcher.checked`. A page can point a redirect or its cover image at the cook's router or printer, and a GET there can have side effects. So it refuses: a port other than the scheme's default; `localhost` and names ending `.local`, `.localhost`, `.internal`, `.lan`, `.home.arpa`; IP-literal hosts in loopback, private, link-local, CGNAT, unspecified, multicast and reserved ranges (IPv4 in any spelling `URL` keeps, such as `2130706433`, `0x7f.1` or `127.1`, and IPv6 including IPv4-mapped forms). Each is `FetchError.blocked`, so the cook gets "can't open that link" and the paste fallback. It judges the link as written: a public name that resolves to a private address is not caught, because the device has no resolver to ask.

Plain-http links rely on App Transport Security refusing them (`blocked("insecure")`). Nothing may add an ATS exception to the app without restoring a check in `AddressRules`, because ATS is the only thing stopping a cleartext request to the local network today.

## The cover photo

`CoverPhoto` fetches it through the same fetcher: at most 15 MB, `Accept: image/*`, and 20 seconds for the fetch and the decode together (a decode still running at the limit is left to finish and its result dropped). An image from a page may declare at most 24 megapixels, checked from its header before decoding, because a file under 100 KB can declare 100 megapixels; the picker path keeps its own 100 megapixel cap. A photo that fails for any reason is dropped silently and never fails the import.
