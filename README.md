# Cauldron

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="brand/lockup-dark.svg">
  <img src="brand/lockup-light.svg" alt="Cauldron, by srcery" width="360">
</picture>

Your recipes, the week's meals, and what you eat. Cauldron is a native app for iPhone and Mac, with a personal recipe box, meal planning, a shopping list, and macro tracking.

**Cauldron is in alpha.** It works, but expect bugs and changes. Builds are distributed through TestFlight, not the App Store. Tester applications aren't open yet.

[Landing page](https://xchrisbailey.github.io/cauldron.srcery/) · [Report a bug](https://github.com/xchrisbailey/cauldron.srcery/issues)

## What it does

- Keep recipes with structured ingredients, serving sizes, photos, and cooking steps.
- Import recipes from a link, pasted text, or a photographed page. Send links and text from other apps through the share sheet.
- Plan meals for the week and gather ingredients into a shopping list.
- Cook with scaled quantities and timers, then log meals and track macros.
- Keep your collection on your devices, with sync through your private iCloud database. There is no Cauldron account or app server.

AI recipe extraction and nutrition estimates use your own Gemini, OpenAI, or Claude API key. Requests go directly from your device to the selected provider; provider charges may apply. Estimates are marked as estimates and should be checked. See [how AI works](docs/native/ai.md) for data handling and fallback behaviour.

## Run the app

You'll need Xcode 27 and an iOS 27 simulator or macOS 27. Open [`apple/Cauldron.xcodeproj`](apple/Cauldron.xcodeproj), select the `Cauldron` scheme, and run it on an iPhone simulator or My Mac. Running on your own device requires signing and the relevant iCloud capabilities.

From `apple/`:

```sh
make ready      # lint and all tests: domain package, Mac, iOS simulator
make format     # format Swift sources
make build      # build for Mac and iOS simulator
make test-kit   # domain tests only; also works on Linux
make project    # regenerate the project after editing project.yml; needs XcodeGen
```

[`CauldronKit`](apple/CauldronKit) contains the platform-independent Swift domain logic. Run `swift test --package-path apple/CauldronKit` without Xcode, including on Linux.

## Landing page

[`site/`](site) is a static HTML/CSS/JavaScript page. It uses the existing brand marks and bundled Geist font, with no framework, dependencies, analytics, or third-party requests.

```sh
node site/build.mjs
python3 -m http.server 8080 --directory _site
```

Open <http://localhost:8080>. The testing form is an explicitly disabled preview. It does not collect, submit, or store applications. Connect a real endpoint and add the appropriate privacy notice before enabling it.

The [Pages workflow](.github/workflows/pages.yml) builds and deploys the site when landing-page or brand assets change on `main`. In the repository's **Settings → Pages → Build and deployment**, choose **GitHub Actions** as the source. No custom domain is configured.

## Brand and development notes

The marks live in [`brand/`](brand); the app and website use Geist and Catppuccin Latte/Mocha. To regenerate the marks and app icons, run `bun install && bun run build` from `brand/`.

- [Contributor conventions](CLAUDE.md)
- [Native architecture and decisions](docs/native/decisions.md)
- [Recipe imports](docs/native/imports.md)
- [Export format](docs/native/export-format.md)

Cauldron began as a web app. That version is retired and preserved at [`web-final`](https://github.com/xchrisbailey/cauldron.srcery/tree/web-final); the Swift app is the current product.
