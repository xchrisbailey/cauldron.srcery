# All local checks for the native app. There is no CI: run `make ready` before opening a PR.

SWIFT_SOURCES := Cauldron CauldronTests CauldronKit/Package.swift CauldronKit/Sources CauldronKit/Tests
XCODEBUILD := xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -skipPackagePluginValidation
IOS_SIMULATOR ?= platform=iOS Simulator,name=iPhone 17,OS=27.0

.PHONY: ready format lint lint-store test test-kit test-app test-mac test-ios build project

## format, lint, and every test
ready: lint test

## rewrite sources in place
format:
	swift format format --in-place --recursive --parallel $(SWIFT_SOURCES)

## fail on anything `make format` would change, and on lint rules
lint: lint-store
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

## Only CauldronStore may open a store. A container made anywhere else can land on
## SwiftData's default file, which an unsandboxed Mac app shares with other apps.
lint-store:
	@if grep -rnE 'ModelContainer\(|ModelConfiguration\(|\.modelContainer\(for:' Cauldron CauldronTests \
		| grep -v '^Cauldron/Data/CauldronStore.swift:'; then \
		echo "error: open stores through CauldronStore.container(_:) only"; exit 1; fi

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
