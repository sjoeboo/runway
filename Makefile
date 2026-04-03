# Runway Development Makefile

.PHONY: build test lint format fix check clean help

# Default target
all: check

## Build & Test ──────────────────────────────────

build: ## Build the project
	swift build

test: ## Run all tests
	swift test

run: ## Run the app
	swift run Runway

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

check: build test lint format-check ## Build, test, lint, and format-check (mirrors CI)

precommit: fix lint format-check test ## Auto-fix, then verify everything passes

## Utility ───────────────────────────────────────

clean: ## Clean build artifacts
	swift package clean

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
