# Batizado — build, test and install. Run `make help`.

SHELL := /bin/bash
.DEFAULT_GOAL := help

APP_NAME    := Batizado
BUNDLE_ID   := io.github.victorhugobn.batizado
VERSION     := 0.1.0

CONFIG      ?= release
BUILD_DIR   ?= build
INSTALL_DIR ?= /Applications

# The Command Line Tools alone cannot compile SwiftUI's @State or XCTest, so every
# target uses the full Xcode toolchain without touching the global xcode-select.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

# Optional, gitignored local overrides (INSTALL_DIR, CONFIG, DEVELOPER_DIR, ...).
-include Makefile.local

SWIFT_PATHS := Package.swift Sources Tests
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
LIFECYCLE   := APP_NAME="$(APP_NAME)" BUNDLE_ID="$(BUNDLE_ID)" INSTALL_DIR="$(INSTALL_DIR)" ./scripts/lifecycle.sh

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' | sort
.PHONY: help

# ──────────────────────────────────────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: build app icon run clean

build: ## Compile the app and the guardian (CONFIG=release|debug)
	swift build -c $(CONFIG)

app: build ## Assemble and ad-hoc sign build/Batizado.app
	@APP_NAME="$(APP_NAME)" BUNDLE_ID="$(BUNDLE_ID)" VERSION="$(VERSION)" \
	  BIN_DIR="$$(swift build -c $(CONFIG) --show-bin-path)" APP_BUNDLE="$(APP_BUNDLE)" \
	  ./scripts/bundle.sh

icon: ## Regenerate assets/AppIcon.icns from assets/AppIcon.svg (commit both)
	./scripts/make-icon.sh

run: app ## Rebuild, quit any running copy, restart the guardian and launch the app
	@$(LIFECYCLE) quit
	@$(LIFECYCLE) restart-guardian
	open "$(APP_BUNDLE)"

clean: ## Remove build products
	swift package clean
	rm -rf "$(BUILD_DIR)"

# ──────────────────────────────────────────────────────────────────────────────
# Quality
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: test fmt fmt-check lint check

test: ## Run the unit tests
	swift test

fmt: ## Format the Swift sources in place
	swift format format --in-place --recursive $(SWIFT_PATHS)

lint: ## Lint the Swift sources (formatting and style, no changes)
	swift format lint --strict --recursive $(SWIFT_PATHS)

fmt-check: lint ## Alias for lint

check: lint build test ## Everything that must pass before a commit

# ──────────────────────────────────────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: install uninstall setup

install: app ## Quit any running copy, copy the app to INSTALL_DIR (default /Applications), restart the guardian
	@$(LIFECYCLE) quit
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@$(LIFECYCLE) restart-guardian
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app. Open it with: open \"$(INSTALL_DIR)/$(APP_NAME).app\""

uninstall: ## Remove the app, its LaunchAgents, state and preferences; print what needs sudo
	@$(LIFECYCLE) uninstall

setup: ## One-time contributor setup: git config and pre-commit hooks
	git config --local include.path ../.gitconfig
	uvx pre-commit install --install-hooks
