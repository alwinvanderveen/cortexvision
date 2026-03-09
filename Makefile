SHELL := /bin/bash
RESULT_BUNDLE := TestResults/results.xcresult
OUTPUT_DIR := TestResults
PROJECT_ROOT := $(shell pwd)

.PHONY: test test-swift dashboard clean

## Run tests with coverage and generate dashboard data
test:
	@echo "==> Cleaning previous results..."
	@rm -rf $(RESULT_BUNDLE)
	@echo "==> Running tests..."
	@set -o pipefail && xcodebuild test \
		-scheme CortexVision-Package \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO \
		2>&1 | tail -20
	@echo "==> Parsing results..."
	@swift Scripts/parse-results.swift $(RESULT_BUNDLE) $(OUTPUT_DIR) $(PROJECT_ROOT)
	@echo "==> Done."

## Build only (no tests)
build:
	@echo "==> Building..."
	@swift build 2>&1 | tail -10
	@echo "==> Done."

## Start the test dashboard
dashboard:
	@echo "==> Starting dashboard on http://localhost:5173"
	@cd Dashboard && npm run dev

## Install dashboard dependencies
dashboard-setup:
	@cd Dashboard && npm install

## Clean build artifacts
clean:
	@rm -rf .build DerivedData TestResults/*.json TestResults/*.xcresult
	@echo "Cleaned."
