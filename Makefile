# Runway Development Makefile
#
# CI uses Xcode 16.3 (Swift 6.1) which is stricter about concurrency than
# newer toolchains. Use `make ci-check` to match CI strictness locally, or
# set XCODE_PATH to a specific Xcode version.

.PHONY: build test lint format fix check ci-check clean help package dmg dist

# Override to match CI toolchain, e.g.: make build XCODE_PATH=/Applications/Xcode_16.3.app
XCODE_PATH ?=
SWIFT := $(if $(XCODE_PATH),DEVELOPER_DIR=$(XCODE_PATH)/Contents/Developer xcrun swift,swift)

# Default target
all: check

## Build & Test ──────────────────────────────────

build: ## Build the project
	$(SWIFT) build

test: ## Run all tests
	$(SWIFT) test

run: ## Run the app
	$(SWIFT) run Runway

## Linting & Formatting ──────────────────────────

lint: ## Run SwiftLint (check only)
	swiftlint lint --strict

format-check: ## Check formatting (no changes)
	swift-format lint --strict --recursive Sources/ Tests/

## Auto-fix ──────────────────────────────────────

fix: ## Auto-fix all lint and format issues
	swiftlint --fix
	swift-format format --recursive --in-place Sources/ Tests/

fix-lint: ## Auto-fix SwiftLint violations only
	swiftlint --fix

fix-format: ## Auto-fix formatting only
	swift-format format --recursive --in-place Sources/ Tests/

## Combined ──────────────────────────────────────

check: build test lint format-check ## Build, test, lint, and format-check

ci-check: ## Build with CI-matching strictness (Xcode 16.3 / Swift 6.1)
	@if [ -d /Applications/Xcode_16.3.app ]; then \
		echo "Using Xcode 16.3 to match CI..."; \
		DEVELOPER_DIR=/Applications/Xcode_16.3.app/Contents/Developer xcrun swift build 2>&1; \
		DEVELOPER_DIR=/Applications/Xcode_16.3.app/Contents/Developer xcrun swift test 2>&1; \
	else \
		echo "⚠️  Xcode 16.3 not installed — building with strict concurrency flags instead"; \
		swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors 2>&1; \
		swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors 2>&1; \
	fi
	swiftlint lint --strict
	swift-format lint --strict --recursive Sources/ Tests/

precommit: fix lint format-check test ## Auto-fix, then verify everything passes

## Packaging ─────────────────────────────────────

package: ## Build release universal .app bundle
	./scripts/package.sh --release --universal

dmg: ## Create DMG installer (run 'make package' first)
	./scripts/create-dmg.sh

dist: package dmg ## Full distribution build (package + DMG)

## Utility ───────────────────────────────────────

clean: ## Clean build artifacts
	$(SWIFT) package clean

install-hooks: ## Install git pre-commit hook
	@mkdir -p $$(git rev-parse --git-common-dir)/hooks
	cp scripts/pre-commit $$(git rev-parse --git-common-dir)/hooks/pre-commit
	chmod +x $$(git rev-parse --git-common-dir)/hooks/pre-commit
	@echo "✅ Pre-commit hook installed"

setup: install-hooks ## Install development tools via Homebrew + hooks
	brew install swiftlint swift-format

## Help ──────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
