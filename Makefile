.PHONY: project open build test core-test clean

# Generates Lanes.xcodeproj from project.yml.
project:
	@command -v xcodegen >/dev/null || { echo "XcodeGen gerekli: brew install xcodegen"; exit 1; }
	xcodegen generate

open: project
	open Lanes.xcodeproj

build: project
	xcodebuild -project Lanes.xcodeproj -scheme Lanes -configuration Debug -destination 'platform=macOS' build

# LanesCore's tests run with plain SwiftPM, on macOS or Linux.
core-test:
	swift test --package-path Packages/LanesCore

test: core-test

clean:
	rm -rf build DerivedData Packages/LanesCore/.build
