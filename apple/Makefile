# All local checks for the native app. There is no CI: run `make ready` before opening a PR.

SWIFT_SOURCES := Cauldron CauldronImports CauldronShare CauldronWidgets Shared ShareSheet CauldronTests CauldronUITests CauldronKit/Package.swift CauldronKit/Sources CauldronKit/Tests
XCODEBUILD := xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -skipPackagePluginValidation
IOS_SIMULATOR ?= platform=iOS Simulator,name=iPhone 17,OS=27.0
PLATFORM ?= macos
CONFIGURATION ?= Debug

.PHONY: ready format lint lint-store lint-buttons lint-copy test test-kit test-app test-mac test-ios build project test-focused tooling-test setup-hooks workflow-status release-build release-preflight

## standard readiness; Mac UI automation is opt-in (docs/native/ui-evidence.md)
ready:
	python3 -B ../tools/checks.py ready

## rewrite sources in place
format:
	swift format format --in-place --recursive --parallel $(SWIFT_SOURCES)

## fail on anything `make format` would change, and on lint rules
lint: lint-store lint-buttons lint-copy
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

## Only CauldronStore may open a store. A container made anywhere else can land on
## SwiftData's default file, which an unsandboxed Mac app shares with other apps. Views take
## the app's container as `.modelContainer(container)`.
lint-store:
	python3 -B ../tools/hooks.py lint-native --policy store

## `.borderedProminent` draws its label in the tint inside a Form or List, which is also its
## fill, so the text disappears. Use `.brandProminent` instead.
lint-buttons:
	python3 -B ../tools/hooks.py lint-native --policy buttons

## SwiftSyntax parses app view expressions so only visible literal copy is caught.
lint-copy:
	python3 -B ../tools/hooks.py lint-native --policy copy

test: test-kit test-app

## CauldronKit only. This is the one that also runs on Linux.
test-kit:
	swift test --package-path CauldronKit

test-app: test-mac test-ios

test-mac:
	$(XCODEBUILD) -destination "platform=macOS" test

test-ios:
	$(XCODEBUILD) -destination "$(IOS_SIMULATOR)" test

## build the app for both platforms without running tests
build:
	$(XCODEBUILD) -destination "platform=macOS" build
	$(XCODEBUILD) -destination "$(IOS_SIMULATOR)" build

## regenerate Cauldron.xcodeproj after editing project.yml
project:
	xcodegen generate --spec project.yml

## a focused app suite/method; method selectors include parentheses
test-focused:
	python3 -B ../tools/checks.py focused --platform "$(PLATFORM)" --test "$(TEST)"

tooling-test:
	python3 -B -m unittest discover -s ../tools/tests -v

setup-hooks:
	python3 -B ../tools/hooks.py install

workflow-status:
	python3 -B ../tools/workflow.py status

## build signed artifacts without launching the app or initializing CloudKit
release-build:
	python3 -B ../tools/release.py build --configuration "$(CONFIGURATION)"

## read-only release gate; this target neither tags nor pushes
release-preflight:
	python3 -B ../tools/release.py preflight "$(VERSION)" --debug-app "$(DEBUG_APP)" --release-app "$(RELEASE_APP)"
