# All local checks for the native app. There is no CI: run `make ready` before opening a PR.

SWIFT_SOURCES := Cauldron CauldronImports CauldronShare CauldronWidgets Shared ShareSheet CauldronTests CauldronKit/Package.swift CauldronKit/Sources CauldronKit/Tests
XCODEBUILD := xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -skipPackagePluginValidation
IOS_SIMULATOR ?= platform=iOS Simulator,name=iPhone 17,OS=27.0

.PHONY: ready format lint lint-store lint-buttons test test-kit test-app test-mac test-ios build project

## format, lint, and every test
ready: lint test

## rewrite sources in place
format:
	swift format format --in-place --recursive --parallel $(SWIFT_SOURCES)

## fail on anything `make format` would change, and on lint rules
lint: lint-store lint-buttons
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

## Only CauldronStore may open a store. A container made anywhere else can land on
## SwiftData's default file, which an unsandboxed Mac app shares with other apps. Views take
## the app's container as `.modelContainer(container)`.
lint-store:
	@if grep -rnE --include='*.swift' --exclude-dir=.build --exclude-dir=CauldronKit \
		'ModelContainer(\.init)?\(|ModelContainer *= *(try +)?\.init|ModelConfiguration|\.modelContainer\(' . \
		| grep -v '^\./Cauldron/Data/CauldronStore\.swift:' \
		| grep -vF '.modelContainer(container)'; then \
		echo "error: open stores through CauldronStore.container(_:) only"; exit 1; fi

## `.borderedProminent` draws its label in the tint inside a Form or List, which is also its
## fill, so the text disappears. Use `.brandProminent` instead.
lint-buttons:
	@if grep -rn --include='*.swift' 'borderedProminent' Cauldron CauldronImports CauldronWidgets ShareSheet CauldronShare; then \
		echo "error: use .buttonStyle(.brandProminent), not .borderedProminent"; exit 1; fi

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
