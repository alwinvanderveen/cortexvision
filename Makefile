SHELL := /bin/bash
OUTPUT_DIR := TestResults
PROJECT_ROOT := $(shell pwd)
COVERAGE_JSON := .build/debug/codecov/CortexVision.json

APP_BUNDLE := .build/CortexVision.app

.PHONY: test test-capture dashboard clean run app start

## Run all tests (or a filtered subset) with coverage and generate dashboard data.
## Uses swift test so the process inherits Terminal's screen recording permission.
##
## Usage:
##   make test                              # all tests
##   make test FILTER="Figure in middle"    # only tests matching filter
##   make test FILTER=DocLayout             # only DocLayout tests
##   make test FILTER=heroBanner            # match by function name
##   make test FILTER=heroBanner DEBUG=1    # with figure detection debug output
FILTER ?=
DEBUG ?=

test:
	@echo "==> Running tests with coverage...$(if $(FILTER), (filter: $(FILTER)),)$(if $(DEBUG), (debug: ON),)"
	@FIGURE_DEBUG=$(DEBUG) swift test --enable-code-coverage $(if $(FILTER),--filter '$(FILTER)',) 2>&1 | tee /tmp/cortexvision-test-output.txt > /dev/null; \
	TEST_EXIT=$${PIPESTATUS[0]}; \
	echo "==> Generating coverage report..."; \
	BIN_DIR=$$(swift build --show-bin-path 2>/dev/null); \
	BIN="$$BIN_DIR/CortexVisionPackageTests.xctest/Contents/MacOS/CortexVisionPackageTests"; \
	if [ -d ".build/debug/codecov" ] && [ -f "$$BIN" ]; then \
		PROFDATA=".build/debug/codecov/default.profdata"; \
		xcrun llvm-profdata merge -sparse .build/debug/codecov/*.profraw -o "$$PROFDATA" 2>/dev/null || true; \
		if [ -f "$$PROFDATA" ]; then \
			xcrun llvm-cov export -instr-profile "$$PROFDATA" "$$BIN" -format=text > $(COVERAGE_JSON) 2>/dev/null || true; \
		fi; \
	fi; \
	echo "==> Parsing results..."; \
	swift Scripts/parse-results.swift /tmp/cortexvision-test-output.txt $(COVERAGE_JSON) $(OUTPUT_DIR) $(PROJECT_ROOT); \
	FAILURES=$$(grep '✘ Test ".*" failed' /tmp/cortexvision-test-output.txt); \
	if [ -n "$$FAILURES" ]; then \
		echo ""; \
		echo "==> FAILED TESTS:"; \
		echo "$$FAILURES" | sed 's/.*Test "\(.*\)" failed.*/  ✘ \1/'; \
		echo ""; \
	fi; \
	echo "==> Done."; \
	exit $$TEST_EXIT

## Run only capture & verification tests
test-capture:
	@echo "==> Running capture verification tests..."
	@swift test --filter "CaptureVerificationTests|CaptureIntegrationTests" 2>&1 | tail -40
	@echo "==> Done."

## Build only (no tests)
build:
	@echo "==> Building..."
	@swift build 2>&1 | tail -10
	@echo "==> Done."

## Build .app bundle and launch (kills existing instance first)
run: app
	@pkill -x CortexVisionApp 2>/dev/null && echo "==> Stopped previous instance." && sleep 0.5 || true
	@echo "==> Launching CortexVision.app..."
	@open $(APP_BUNDLE)

## Launch the last built app bundle without rebuilding
start:
	@pkill -x CortexVisionApp 2>/dev/null && echo "==> Stopped previous instance." && sleep 0.5 || true
	@echo "==> Launching CortexVision.app..."
	@open $(APP_BUNDLE)

## Build a proper .app bundle (required for System Settings visibility)
app: build
	@echo "==> Creating app bundle..."
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp .build/debug/CortexVisionApp $(APP_BUNDLE)/Contents/MacOS/CortexVisionApp
	@cp CortexVisionApp/Resources/Info.plist $(APP_BUNDLE)/Contents/Resources/Info.plist
	@# PkgInfo marks this as an application bundle
	@echo -n "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Info.plist at Contents/ level (macOS convention)
	@cp CortexVisionApp/Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@# Reset screen recording permission for this bundle after rebuild
	@# (new binary = new code signature, old toggle becomes stale)
	@echo "==> Resetting screen recording permission for CortexVision..."
	@tccutil reset ScreenCapture nl.cortexvision.app 2>/dev/null || true
	@echo "==> App bundle created at $(APP_BUNDLE)"

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
