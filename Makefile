SHELL := /bin/bash
OUTPUT_DIR := TestResults
PROJECT_ROOT := $(shell pwd)
COVERAGE_JSON := .build/debug/codecov/CortexVision.json
LOG_DIR := TestResults/logs
LATEST_LOG := $(LOG_DIR)/latest.log
LATEST_DEBUG := $(LOG_DIR)/latest-debug.log

APP_BUNDLE := .build/CortexVision.app

.PHONY: test test-capture dashboard clean run app start test-log

## Run all tests (or a filtered subset) with coverage and generate dashboard data.
## Uses swift test so the process inherits Terminal's screen recording permission.
## Debug output (FIGURE_DEBUG) is ON by default — written to TestResults/logs/.
##
## Usage:
##   make test                              # all tests (debug output saved to file)
##   make test FILTER="Figure in middle"    # only tests matching filter
##   make test FILTER=DocLayout             # only DocLayout tests
##   make test DEBUG=0                      # disable debug output
##   make test KEEP=1                       # archive log with timestamp instead of overwriting
FILTER ?=
DEBUG ?= 1
KEEP ?=

test:
	@mkdir -p $(LOG_DIR)
	@echo "==> Running tests with coverage...$(if $(FILTER), (filter: $(FILTER)),) (debug: $(if $(filter 0,$(DEBUG)),OFF,ON))"
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
	echo ""; \
	echo "==> Generating test report..."; \
	TIMESTAMP=$$(date '+%Y-%m-%d_%H%M%S'); \
	FILTER_TAG="$(if $(FILTER),_$(shell echo '$(FILTER)' | tr ' ' '_' | tr -cd 'a-zA-Z0-9_'),_all)"; \
	{ \
		echo "# CortexVision Test Report"; \
		echo "# Date: $$(date '+%Y-%m-%d %H:%M:%S')"; \
		echo "# Filter: $(if $(FILTER),$(FILTER),all)"; \
		echo "# Debug: $(if $(filter 0,$(DEBUG)),OFF,ON)"; \
		echo ""; \
		echo "## Summary"; \
		grep -E '^Tests:' /tmp/cortexvision-test-output.txt 2>/dev/null || echo "No summary found"; \
		grep -E '^Coverage:' /tmp/cortexvision-test-output.txt 2>/dev/null || true; \
		echo ""; \
		echo "## Failed Tests"; \
		FAILURES=$$(grep '✘ Test ".*" failed' /tmp/cortexvision-test-output.txt); \
		if [ -n "$$FAILURES" ]; then \
			echo "$$FAILURES" | sed 's/.*Test "\(.*\)" failed.*/  ✘ \1/'; \
		else \
			echo "  (none)"; \
		fi; \
		echo ""; \
		echo "## All Test Results"; \
		grep -E '(✔ Test|✘ Test|◇ Test)' /tmp/cortexvision-test-output.txt | \
			sed 's/.*✔ Test "\(.*\)" passed.*/  ✔ PASS  \1/' | \
			sed 's/.*✘ Test "\(.*\)" failed.*/  ✘ FAIL  \1/' | \
			sed 's/.*◇ Test "\(.*\)" skipped.*/  ◇ SKIP  \1/'; \
		echo ""; \
		echo "## Failure Details"; \
		grep -B 2 -A 5 'Expectation failed' /tmp/cortexvision-test-output.txt 2>/dev/null || echo "  (no expectation details found)"; \
		echo ""; \
		echo "## Debug Output"; \
		grep -E '(^\[FIGURE_DEBUG\]|^FIGURE_DEBUG|^DenHaagDoet|^BlackBackground|^Propinion|figure|Figure|candidate|saliency|instance|content.map|hypothesis|variance|crop|boundary)' /tmp/cortexvision-test-output.txt 2>/dev/null | head -200 || echo "  (no debug output)"; \
	} > $(LATEST_LOG); \
	if [ -n "$(KEEP)" ]; then \
		cp $(LATEST_LOG) "$(LOG_DIR)/$$TIMESTAMP$$FILTER_TAG.log"; \
		echo "==> Report archived: $(LOG_DIR)/$$TIMESTAMP$$FILTER_TAG.log"; \
	fi; \
	cp /tmp/cortexvision-test-output.txt $(LATEST_DEBUG); \
	echo "==> Report: $(LATEST_LOG)"; \
	echo "==> Full output: $(LATEST_DEBUG)"; \
	FAILURES=$$(grep '✘ Test ".*" failed' /tmp/cortexvision-test-output.txt); \
	if [ -n "$$FAILURES" ]; then \
		echo ""; \
		echo "==> FAILED TESTS:"; \
		echo "$$FAILURES" | sed 's/.*Test "\(.*\)" failed.*/  ✘ \1/'; \
		echo ""; \
	fi; \
	echo "==> Done."; \
	exit $$TEST_EXIT

## Show the latest test report without re-running tests
test-log:
	@if [ -f $(LATEST_LOG) ]; then \
		cat $(LATEST_LOG); \
	else \
		echo "No test report found. Run 'make test' first."; \
	fi

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
