# The native app's local checks. There is no CI for these: run them before pushing.
# `make ready` is everything; CauldronKit targets also work on Linux.

SWIFT_PATHS := apple/Cauldron apple/CauldronTests apple/CauldronKit/Package.swift \
	apple/CauldronKit/Sources apple/CauldronKit/Tests
PROJECT := apple/Cauldron.xcodeproj
DERIVED := apple/.build/DerivedData
SIMULATOR ?= iPhone 18 Pro
XCODEBUILD := xcodebuild -quiet -project $(PROJECT) -scheme Cauldron -derivedDataPath $(DERIVED)

.PHONY: lint format test test-kit test-app test-ios build project ready

lint:
	swift format lint --strict --recursive $(SWIFT_PATHS)

format:
	swift format format --in-place --recursive $(SWIFT_PATHS)

# CauldronKit, then the app's tests as a Mac app.
test: test-kit test-app

test-kit:
	swift test --package-path apple/CauldronKit

test-app:
	$(XCODEBUILD) -destination 'platform=macOS' test

test-ios:
	$(XCODEBUILD) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' test

# Builds the app for the Mac and for the iPhone simulator.
build:
	$(XCODEBUILD) -destination 'platform=macOS' build
	$(XCODEBUILD) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' build

# Regenerates the Xcode project from apple/project.yml. Needs XcodeGen.
project:
	cd apple && xcodegen generate --quiet

ready: lint test test-ios
