# Cauldron

A personal recipe box, weekly meal planner and macro tracker, by srcery. It is a native iOS 27 / macOS 27 app with no server, synced through iCloud; the plan is in [#157](https://github.com/xchrisbailey/cauldron.srcery/issues/157) and [`docs/native`](docs/native). Conventions for contributors (human or agent) are in [`CLAUDE.md`](CLAUDE.md).

## The native app

You need Xcode 27. Open `apple/Cauldron.xcodeproj` and run the `Cauldron` scheme on an iPhone simulator or on My Mac. From `apple/`:

```bash
make ready      # lint, then every test (CauldronKit, Mac, iOS simulator)
make format     # rewrite sources with swift-format
make test-kit   # CauldronKit only; this also runs on Linux
make project    # regenerate the Xcode project after editing project.yml (needs XcodeGen)
```

`apple/CauldronKit` is a plain Swift package with the domain logic. It builds and tests on Linux with `swift test`.

## Brand assets

`brand/build.ts` draws the marks in `brand/` and the app icons in `apple/Cauldron/Assets.xcassets/AppIcon.appiconset` from one definition. It needs [Bun](https://bun.sh):

```bash
cd brand && bun install && bun run build
```

## The old web app

Cauldron started as a TypeScript web app and API. It was retired once the native app reached parity ([#186](https://github.com/xchrisbailey/cauldron.srcery/issues/186)), and the last version is at the [`web-final`](https://github.com/xchrisbailey/cauldron.srcery/tree/web-final) tag.
