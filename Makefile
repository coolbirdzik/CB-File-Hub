# Makefile for CB File Hub
# Cross-platform build system for Flutter application
# Works on: Windows (Git Bash/WSL/MinGW), Linux, macOS

.PHONY: help clean deep-clean deps build-windows-portable build-windows-msi build-windows-msix build-windows-msix-store build-android-apk build-android-aab build-linux build-macos build-ios build-all test dev-test dev-test-e2e-failed kill-e2e-app dev-test-e2e-clean dev-test-e2e-only analyze format doctor release version version-info bump-build retag retag-one verify

# Default target
.DEFAULT_GOAL := help

# Variables
PROJECT_DIR := cb_file_manager
FLUTTER := flutter
BUILD_DIR := $(PROJECT_DIR)/build
PUBSPEC := $(PROJECT_DIR)/pubspec.yaml

# Developer testing: integration_test device (override: make dev-test-e2e E2E_DEVICE=macos)
E2E_DEVICE ?= windows

# flutter test reporter: expanded (shows each test name line-by-line), compact, github (CI), json (machine-readable)
TEST_REPORTER ?= expanded

# Get version name and build number from pubspec.yaml
# Uses scripts/version.sh — must be run from Git Bash on Windows
VERSION_FULL := $(shell bash scripts/version.sh full)
VERSION := $(shell bash scripts/version.sh name)
BUILD_NUMBER := $(shell bash scripts/version.sh build)

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Help target
help:
	@echo "$(BLUE)╔════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║     CB File Hub - Build System v$(VERSION)+$(BUILD_NUMBER)    ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)📦 Build Targets:$(NC)"
	@echo "  make windows           - Build Windows portable (ZIP)"
	@echo "  make windows-msi       - Build Windows MSI installer"
	@echo "  make windows-msix      - Build signed Windows MSIX package"
	@echo "  make windows-msix-store - Build signed Store-ready MSIX (x.y.z.0)"
	@echo "  make android           - Build Android APK"
	@echo "  make android-aab       - Build Android AAB"
	@echo "  make linux             - Build Linux"
	@echo "  make macos             - Build macOS"
	@echo "  make ios               - Build iOS"
	@echo "  make all               - Build all platforms"
	@echo ""
	@echo "$(GREEN)🔧 Development:$(NC)"
	@echo "  make clean             - Clean build artifacts"
	@echo "  make deep-clean        - Deep clean (remove all build files)"
	@echo "  make deps              - Install dependencies"
	@echo "  make test              - Run unit/widget tests (same as dev-test)"
	@echo "  make analyze           - Analyze code"
	@echo "  make format            - Format code"
	@echo "  make doctor            - Run flutter doctor"
	@echo ""
	@echo "$(GREEN)🧪 Developer — testing ($(PROJECT_DIR)):$(NC)"
	@echo "  make dev-test                       - Unit + widget + E2E + Allure report (ALL IN ONE) ← DEFAULT"
	@echo "  make dev-test mode=unit             - Unit + widget tests only"
	@echo "  make dev-test mode=e2e              - E2E in PARALLEL + dashboard (default fast path)"
	@echo "  make dev-test mode=e2e SERIAL=1     - E2E serial runner (debug exact order)"
	@echo "  make dev-test mode=e2e MAX_PARALLEL=4  - Limit parallel workers"
	@echo "  make dev-test mode=e2e FULL_STARTUP=1  - Include production-only startup services"
	@echo "  make dev-test mode=e2e FULL_SCREENSHOTS=1  - Screenshot every action"
	@echo "  make dev-test mode=e2e RERUN=1      - E2E: skip passed, rerun only FAILED tests"
	@echo "  make dev-test mode=e2e TEST=Navigation  - Run only Navigation suite"
	@echo "  make dev-test mode=e2e TEST=\"Video Thumbnails\"  - Run only Video Thumbnails suite"
	@echo "  make dev-test mode=e2e TEST_FILE=video_thumbnails_e2e_test  - Run by file name"
	@echo "  make dev-test-e2e-failed            - Shortcut: rerun only previously-failed tests"
	@echo "  make dev-test mode=e2e NO_OPEN=1    - E2E without auto-opening browser"
	@echo "  make dev-test-e2e-only              - E2E plain output (no Allure, useful for debugging)"
	@echo "  make dev-test-e2e-clean             - flutter clean + pub get + E2E (fix MSB3073 / bad build)"
	@echo ""
	@echo "$(GREEN)📊 E2E Dashboard (auto after E2E):$(NC)"
	@echo "  make dev-test             → generates cb_file_manager/build/e2e_dashboard/index.html (auto-opens)"
	@echo "  make dev-test RERUN=1    - fix failures faster (skips passed tests)"
	@echo "  Dashboard link → Screenshot Report → cb_file_manager/build/e2e_report/report.html"
	@echo ""
	@echo "$(GREEN)🚀 Release:$(NC)"
	@echo "  make verify           - Run format + analyze check"
	@echo "  make release-patch     - Create patch release (x.x.X)"
	@echo "  make release-minor     - Create minor release (x.X.0)"
	@echo "  make release-major     - Create major release (X.0.0)"
	@echo "  make retag            - Recreate & retag (interactive)"
	@echo "  bash scripts/retag.sh v1.2.3  - Retag specific version"
	@echo "  make version           - Show current version"
	@echo "  make version-info      - Show version + build number separately"
	@echo "  make bump-build        - Bump build number only (auto in CI)"
	@echo ""
	@echo "$(GREEN)💡 Examples:$(NC)"
	@echo "  make windows           # Build Windows portable"
	@echo "  make android           # Build Android APK"
	@echo "  make all               # Build everything"
	@echo ""
	@echo "$(GREEN)📋 E2E Dashboard (auto after dev-test mode=e2e or all):$(NC)"
	@echo "  • Dashboard auto-generated → cb_file_manager/build/e2e_dashboard/index.html"
	@echo "  • Parallel mode:    make dev-test mode=e2e  (default full E2E run)"
	@echo "  • Serial mode:      make dev-test mode=e2e SERIAL=1"
	@echo "  • Rerun only failed: make dev-test mode=e2e RERUN=1  (skips passed tests)"
	@echo "  • Plain E2E output:  make dev-test-e2e-only"
	@echo "  • IDE: open integration_test/*.dart and use Run/Debug on testWidgets"
	@echo ""

# Clean build artifacts
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) clean
	@echo "$(BLUE)Removing CMake cache...$(NC)"
	@rm -rf $(PROJECT_DIR)/build/windows/CMakeCache.txt 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/build/windows/CMakeFiles 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/build/windows/.cmake 2>/dev/null || true
	@echo "$(BLUE)Removing additional build directories...$(NC)"
	@rm -rf $(PROJECT_DIR)/.dart_tool 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/windows/flutter/ephemeral 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/linux/flutter/ephemeral 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/macos/Flutter/ephemeral 2>/dev/null || true
	@echo "$(GREEN)Clean completed!$(NC)"

# Deep clean (more thorough)
deep-clean:
	@echo "$(BLUE)Performing deep clean...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) clean
	@echo "$(BLUE)Removing CMake cache completely...$(NC)"
	@rm -rf $(PROJECT_DIR)/build/windows 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/build/linux 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/build/macos 2>/dev/null || true
	@echo "$(BLUE)Removing all build artifacts...$(NC)"
	@rm -rf $(PROJECT_DIR)/.dart_tool 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/.flutter-plugins 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/.flutter-plugins-dependencies 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/.packages 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/windows/flutter/ephemeral 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/linux/flutter/ephemeral 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/macos/Flutter/ephemeral 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/ios/.symlinks 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/ios/Flutter/Flutter.framework 2>/dev/null || true
	@rm -rf $(PROJECT_DIR)/ios/Flutter/Flutter.podspec 2>/dev/null || true
	@echo "$(GREEN)Deep clean completed!$(NC)"
	@echo "$(YELLOW)Some files may be locked by running processes$(NC)"
	@echo "$(YELLOW)Run 'make deps' before building$(NC)"

# Install dependencies
deps:
	@echo "$(BLUE)Installing dependencies...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) pub get
	@echo "$(GREEN)Dependencies installed!$(NC)"

# Run flutter doctor
doctor:
	@echo "$(BLUE)Running flutter doctor...$(NC)"
	$(FLUTTER) doctor -v

# Run tests
test:
	@echo "$(BLUE)Running tests...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) test --reporter $(TEST_REPORTER)

# -----------------------------------------------------------------------------
# Developer: testing (cb_file_manager)
# - Unit/widget: test/
# - E2E: integration_test/ with --dart-define=CB_E2E=true (desktop device required)
# - Allure HTML report auto-generated after E2E run (build/allure-report/index.html)
# - RERUN=1 skips passed tests, runs only previously-failed tests
# - If Windows build fails with MSB3073 / cmake_install / INSTALL.vcxproj: run dev-test-e2e-clean
#
# Usage:
#   make dev-test                        # unit + widget + E2E + Allure report  (ALL IN ONE)
#   make dev-test mode=unit              # unit + widget only
#   make dev-test mode=e2e               # E2E only + Allure report (auto-opens browser)
#   make dev-test mode=e2e RERUN=1       # skip passed, rerun only failed tests
#   make dev-test mode=e2e TEST=Navigation  # run only a specific suite (--plain-name)
#   make dev-test mode=e2e NO_OPEN=1     # skip auto-opening browser
#   make dev-test-e2e-failed             # shortcut: rerun only failed tests
#   make dev-test-e2e-only               # E2E without Allure (plain flutter output)
#   make dev-test-e2e-clean              # flutter clean + pub get + E2E
# -----------------------------------------------------------------------------

# mode: unit | e2e | (default = all)
TEST_MODE ?= all
# RERUN=1 skips passed tests, runs only the failed ones from last run
TEST_RERUN_FAILED := $(if $(filter 1,$(RERUN)),--rerun-failed,)
# TEST=<suite> runs only tests matching --plain-name (e.g. TEST=Navigation)
# TEST_FILE=<file> runs a specific test file directly (e.g. TEST_FILE=video_thumbnails_e2e_test)
# Note: use spaces instead of %20 — Bash/Git Bash normalises them automatically.
_TEST_FILTER := $(if $(TEST),--plain-name "$(subst %20, ,$(TEST))",)
_TEST_FILE_FILTER := $(if $(TEST_FILE),--file $(TEST_FILE),)
TEST_FILTER := $(strip $(_TEST_FILTER) $(_TEST_FILE_FILTER))
# NO_OPEN=1 skips auto-opening the browser after E2E run
TEST_NO_OPEN := $(if $(filter 1,$(NO_OPEN)),--no-open,)
# When TEST_FILE is set, disable parallel to go through e2e_allure.dart directly.
# Full E2E runs use the parallel runner by default. SERIAL=1 keeps the old
# single-process runner for debugging exact test order or worker-specific flakes.
_TEST_FULL_E2E := $(if $(filter e2e all,$(TEST_MODE)),$(if $(RERUN)$(TEST_FILE),,yes),)
TEST_PARALLEL := $(if $(filter 1,$(SERIAL)),,$(if $(filter 1,$(PARALLEL)),1,$(if $(_TEST_FULL_E2E),1,)))
# MAX_PARALLEL=N limits the number of parallel workers (runner default: up to 4)
TEST_MAX_PARALLEL := $(if $(MAX_PARALLEL),--max-parallel $(MAX_PARALLEL),)
# FULL_STARTUP=1 disables the E2E fast startup skips.
TEST_FULL_STARTUP := $(if $(filter 1,$(FULL_STARTUP)),--full-startup,)
# FULL_SCREENSHOTS=1 restores action-by-action screenshot capture.
TEST_FULL_SCREENSHOTS := $(if $(filter 1,$(FULL_SCREENSHOTS)),--full-screenshots,)
# Whether E2E will run (used to conditionally print report info)
TEST_RUNS_E2E := $(if $(filter e2e all,$(TEST_MODE)),yes,)

kill-e2e-app:
ifeq ($(OS),Windows_NT)
	@cmd /c "taskkill /F /IM cb_file_hub.exe /T 2>nul & exit /b 0"
else
	@:
endif

# Unified dev-test: runs unit+widget, optionally E2E with Allure report.
# Default: ALL (unit + widget + E2E Allure)
# Overrides: mode=unit (skip E2E) | mode=e2e (skip unit/widget)
dev-test: kill-e2e-app
ifneq ($(filter unit,$(TEST_MODE)),)
	@echo "$(BLUE)[dev] Unit + widget tests ($(PROJECT_DIR)/test) ...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) test --reporter $(TEST_REPORTER)
endif
ifneq ($(filter e2e all,$(TEST_MODE)),)
ifneq ($(RERUN),)
	@echo "$(BLUE)[dev] E2E: rerunning only failed tests ...$(NC)"
else ifneq ($(TEST_FILE),)
	@echo "$(BLUE)[dev] E2E: running test file '$(TEST_FILE)' only ...$(NC)"
else ifneq ($(TEST),)
	@echo "$(BLUE)[dev] E2E: running suite '$(TEST)' only ...$(NC)"
else
	@echo "$(BLUE)[dev] E2E tests + HTML dashboard ...$(NC)"
endif
ifneq ($(TEST_PARALLEL),)
	@echo "$(GREEN)[dev] Using PARALLEL mode (e2e_parallel.dart) ...$(NC)"
	cd $(PROJECT_DIR) && dart run tool/e2e_parallel.dart $(TEST_RERUN_FAILED) $(TEST_NO_OPEN) $(TEST_MAX_PARALLEL) $(TEST_FILTER) $(TEST_FULL_STARTUP) $(TEST_FULL_SCREENSHOTS)
else
	@echo "$(YELLOW)[dev] Using SERIAL mode (e2e_allure.dart) ...$(NC)"
	cd $(PROJECT_DIR) && dart run tool/e2e_allure.dart $(TEST_RERUN_FAILED) $(TEST_NO_OPEN) $(TEST_FILTER) $(TEST_FULL_STARTUP) $(TEST_FULL_SCREENSHOTS)
endif
endif  # end: ifneq ($(filter e2e all,$(TEST_MODE)),)
ifneq ($(TEST_RUNS_E2E),)
	@echo "$(GREEN)[dev] Done. Open dashboard:$(NC)"
	@echo "  file://$$(pwd)/$(PROJECT_DIR)/build/e2e_dashboard/index.html"
endif

# E2E only (no Allure) — plain flutter output, useful for debugging
dev-test-e2e-only: kill-e2e-app
	@echo "$(BLUE)[dev] E2E integration tests (plain output) ...$(NC)"
	cd $(PROJECT_DIR) && dart run tool/run_e2e_with_log.dart $(TEST_FULL_STARTUP) $(TEST_FULL_SCREENSHOTS)

# Rerun only the tests that failed in the last run (shortcut for RERUN=1)
dev-test-e2e-failed: kill-e2e-app
	@echo "$(BLUE)[dev] E2E: rerunning only previously-failed tests ...$(NC)"
	cd $(PROJECT_DIR) && dart run tool/e2e_allure.dart --rerun-failed $(TEST_NO_OPEN) $(TEST_FULL_STARTUP) $(TEST_FULL_SCREENSHOTS)

# Full clean then E2E — fixes stale CMake/MSBuild output that breaks INSTALL.
dev-test-e2e-clean: kill-e2e-app
	@echo "$(BLUE)[dev] flutter clean + pub get + E2E ...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) clean
	cd $(PROJECT_DIR) && $(FLUTTER) pub get
	cd $(PROJECT_DIR) && $(FLUTTER) test integration_test -d $(E2E_DEVICE) --dart-define=CB_E2E=true --dart-define=CB_E2E_FAST=$(if $(filter 1,$(FULL_STARTUP)),false,true) --dart-define=CB_E2E_FULL_SCREENSHOTS=$(if $(filter 1,$(FULL_SCREENSHOTS)),true,false) --reporter $(TEST_REPORTER)

# Analyze code
analyze:
	@echo "$(BLUE)Analyzing code...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) analyze

# Format code
format:
	@echo "$(BLUE)Formatting code...$(NC)"
	cd $(PROJECT_DIR) && dart format .

# Build Windows Portable
build-windows-portable: deps
	@echo "$(BLUE)Building Windows Portable...$(NC)"
	@echo "$(YELLOW)Note: Not cleaning before build to avoid first-build failures$(NC)"
	@echo "$(YELLOW)Run 'make clean' or 'make deep-clean' manually if needed$(NC)"
	@# Fix pdfx plugin CMake compatibility
	@if [ -f "$(PROJECT_DIR)/windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/CMakeLists.txt" ] || [ -f "$(PROJECT_DIR)/windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/DownloadProject.CMakeLists.cmake.in" ]; then \
		echo "$(BLUE)Patching pdfx plugin CMake configuration...$(NC)"; \
		sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.14)/g' "$(PROJECT_DIR)/windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/CMakeLists.txt" 2>/dev/null || true; \
		sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.14)/g' "$(PROJECT_DIR)/windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/DownloadProject.CMakeLists.cmake.in" 2>/dev/null || true; \
	fi
	@# Fix VS BuildTools/Community conflict and force VS 2022
	@export VSINSTALLDIR="C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\" && \
	export VCToolsInstallDir="C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\" && \
	export CMAKE_GENERATOR="Visual Studio 17 2022" && \
	export CMAKE_GENERATOR_PLATFORM="x64" && \
	cd $(PROJECT_DIR) && $(FLUTTER) build windows --release
	@echo "$(BLUE)Creating ZIP package...$(NC)"
	@mkdir -p $(BUILD_DIR)/windows/portable
	@if command -v zip >/dev/null 2>&1; then \
		cd $(BUILD_DIR)/windows/x64/runner/Release && zip -r ../../portable/CBFileHub-Portable.zip ./*; \
	elif command -v 7z >/dev/null 2>&1; then \
		cd $(BUILD_DIR)/windows/x64/runner/Release && 7z a -tzip ../../portable/CBFileHub-Portable.zip ./*; \
	elif command -v powershell.exe >/dev/null 2>&1; then \
		powershell.exe -Command "Compress-Archive -Path '$(BUILD_DIR)/windows/x64/runner/Release/*' -DestinationPath '$(BUILD_DIR)/windows/portable/CBFileHub-Portable.zip' -Force"; \
	else \
		echo "$(YELLOW)No ZIP tool found. Files available at: $(BUILD_DIR)/windows/x64/runner/Release/$(NC)"; \
	fi
	@echo "$(GREEN)Windows Portable build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/windows/portable/CBFileHub-Portable.zip"

# Build Windows MSI Installer
build-windows-msi:
	@bash scripts/build.sh windows-msi

# Build Windows MSIX Package
build-windows-msix:
	@echo "$(BLUE)Building Windows MSIX Package...$(NC)"
	@printf "$(YELLOW)Certificate path: $(NC)"; \
	read -r CERT_PATH; \
	if [ -z "$$CERT_PATH" ]; then \
		echo "$(RED)Certificate path is required$(NC)"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Certificate password: $(NC)"; \
	stty -echo; \
	read -r CERT_PASSWORD; \
	stty echo; \
	echo ""; \
	if [ -z "$$CERT_PASSWORD" ]; then \
		echo "$(RED)Certificate password is required$(NC)"; \
		exit 1; \
	fi; \
	MSIX_CERT_PATH="$$CERT_PATH" MSIX_CERT_PASSWORD="$$CERT_PASSWORD" MSIX_REQUIRE_SIGNING=true bash scripts/build.sh windows-msix

# Build Store-ready Windows MSIX Package
build-windows-msix-store:
	@echo "$(BLUE)Building Store-ready Windows MSIX Package...$(NC)"
	@printf "$(YELLOW)Certificate path: $(NC)"; \
	read -r CERT_PATH; \
	if [ -z "$$CERT_PATH" ]; then \
		echo "$(RED)Certificate path is required$(NC)"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Certificate password: $(NC)"; \
	stty -echo; \
	read -r CERT_PASSWORD; \
	stty echo; \
	echo ""; \
	if [ -z "$$CERT_PASSWORD" ]; then \
		echo "$(RED)Certificate password is required$(NC)"; \
		exit 1; \
	fi; \
	MSIX_CERT_PATH="$$CERT_PATH" MSIX_CERT_PASSWORD="$$CERT_PASSWORD" MSIX_REQUIRE_SIGNING=true MSIX_VERSION_OVERRIDE="$(VERSION).0" bash scripts/build.sh windows-msix

# Build Android APK
build-android-apk: clean deps
	@echo "$(BLUE)Building Android APK...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) build apk --release --split-per-abi
	@echo "$(GREEN)Android APK build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/app/outputs/flutter-apk/"

# Build Android AAB
build-android-aab: clean deps
	@echo "$(BLUE)Building Android AAB...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) build appbundle --release
	@echo "$(GREEN)Android AAB build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/app/outputs/bundle/release/"

# Build Linux
build-linux: clean deps
	@echo "$(BLUE)Building Linux...$(NC)"
	cd $(PROJECT_DIR) && $(FLUTTER) build linux --release
	@echo "$(BLUE)Creating tar.gz package...$(NC)"
	@mkdir -p $(BUILD_DIR)/linux/portable
	cd $(BUILD_DIR)/linux/x64/release && tar -czf ../portable/CBFileHub-Linux.tar.gz bundle/
	@echo "$(GREEN)Linux build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/linux/portable/CBFileHub-Linux.tar.gz"

# Build macOS
build-macos: clean deps
	@echo "$(BLUE)Building macOS...$(NC)"
	@if [ "$$(uname)" != "Darwin" ]; then \
		echo "$(YELLOW)macOS builds can only be done on macOS!$(NC)"; \
		exit 1; \
	fi
	cd $(PROJECT_DIR) && $(FLUTTER) build macos --release
	@echo "$(BLUE)Creating ZIP package...$(NC)"
	@mkdir -p $(BUILD_DIR)/macos/portable
	cd $(BUILD_DIR)/macos/Build/Products/Release && zip -r ../../../portable/CBFileHub-macOS.zip cb_file_hub.app
	@echo "$(GREEN)macOS build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/macos/portable/CBFileHub-macOS.zip"

# Build iOS
build-ios: clean deps
	@echo "$(BLUE)Building iOS...$(NC)"
	@if [ "$$(uname)" != "Darwin" ]; then \
		echo "$(YELLOW)iOS builds can only be done on macOS!$(NC)"; \
		exit 1; \
	fi
	cd $(PROJECT_DIR) && $(FLUTTER) build ios --release --no-codesign
	@echo "$(GREEN)iOS build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/ios/iphoneos/"
	@echo "$(YELLOW)Note: You need to sign the app in Xcode before distribution$(NC)"

# Build all platforms
build-all:
	@echo "$(BLUE)Building for all platforms...$(NC)"
	@$(MAKE) build-windows-portable || echo "$(YELLOW)Windows Portable build failed$(NC)"
	@$(MAKE) build-windows-msi || echo "$(YELLOW)Windows MSI build failed$(NC)"
	@echo "$(YELLOW)Skipping interactive Windows MSIX target in make all$(NC)"
	@$(MAKE) build-android-apk || echo "$(YELLOW)Android APK build failed$(NC)"
	@$(MAKE) build-android-aab || echo "$(YELLOW)Android AAB build failed$(NC)"
	@$(MAKE) build-linux || echo "$(YELLOW)Linux build failed$(NC)"
	@if [ "$$(uname)" = "Darwin" ]; then \
		$(MAKE) build-macos || echo "$(YELLOW)macOS build failed$(NC)"; \
		$(MAKE) build-ios || echo "$(YELLOW)iOS build failed$(NC)"; \
	fi
	@echo "$(GREEN)All builds completed!$(NC)"

# Quick build shortcuts
windows: build-windows-portable
windows-msi: build-windows-msi
windows-msix: build-windows-msix
windows-msix-store: build-windows-msix-store
android: build-android-apk
android-aab: build-android-aab
linux: build-linux
macos: build-macos
ios: build-ios
all: build-all

# Retag: recreate annotated tag and force-push to trigger CI rebuild
# Use for beta/hotfix builds where version stays same but build number must increase
retag:
	@CURRENT_VER=$$(make -s next-patch 2>/dev/null || echo ""); \
	if [ -n "$$CURRENT_VER" ]; then \
		echo "$(BLUE)Last version: $$CURRENT_VER$(NC)"; \
	fi; \
	echo "$(YELLOW)Available git remotes:$(NC)"; \
	REMOTES=$$(git remote); \
	if [ -z "$$REMOTES" ]; then \
		echo "$(RED)No git remotes found. Please add one first.$(NC)"; \
		exit 1; \
	fi; \
	INDEX=1; \
	for R in $$REMOTES; do echo "  $$INDEX) $$R"; INDEX=$$(($$INDEX + 1)); done; \
	echo "$(YELLOW)Enter remote number or name to push to (default: origin):$(NC)"; \
	read -r REMOTE_INPUT; \
	if [ -z "$$REMOTE_INPUT" ]; then \
		REMOTE=origin; \
	elif echo "$$REMOTE_INPUT" | grep -E '^[0-9]+$$' >/dev/null 2>&1; then \
		REMOTE=$$(git remote | awk "NR==$$REMOTE_INPUT{print; exit}"); \
		if [ -z "$$REMOTE" ]; then \
			echo "$(RED)Invalid remote number$(NC)"; \
			exit 1; \
		fi; \
	else \
		REMOTE=$$REMOTE_INPUT; \
	fi; \
	echo "$(YELLOW)Enter tag to retag (e.g. v1.2.3):$(NC)"; \
	read -r TAG; \
	if [ -z "$$TAG" ]; then \
		echo "$(RED)Tag cannot be empty$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)Recreating annotated tag $$TAG and force-pushing to remote $$REMOTE...$(NC)"; \
	git tag -f -a "$$TAG" -m "Rebuild $$TAG - auto-incremented build number"; \
	git push "$$REMOTE" "$$TAG" -f; \
	echo "$(GREEN)Done. CI will auto-increment build_number on each build.$(NC)"; \
	echo "$(YELLOW)Monitor at: https://github.com/<owner>/<repo>/actions$(NC)"

# One-liner: retag a specific version tag and force-push
# Usage: bash scripts/retag.sh v1.2.3
retag-one:
	@echo "$(YELLOW)Use: bash scripts/retag.sh v1.2.3$(NC)"

# Version management
version:
	@echo "$(BLUE)Current version: $(GREEN)$(VERSION)+$(BUILD_NUMBER)$(NC)"

version-info:
	@echo "$(BLUE)Version Name : $(GREEN)$(VERSION)$(NC)"
	@echo "$(BLUE)Build Number : $(GREEN)$(BUILD_NUMBER)$(NC)"
	@echo "$(BLUE)Full        : $(GREEN)$(VERSION)+$(BUILD_NUMBER)$(NC)"

# Calculate next version
next-patch:
	@echo $(VERSION) | awk -F. '{print $$1"."$$2"."$$3+1}'

next-minor:
	@echo $(VERSION) | awk -F. '{print $$1"."$$2+1".0"}'

next-major:
	@echo $(VERSION) | awk -F. '{print $$1+1".0.0"}'

# Update version in pubspec.yaml (keeps current build_number)
update-version:
	@if [ -z "$(NEW_VERSION)" ]; then \
		echo "$(RED)Error: NEW_VERSION not set$(NC)"; \
		echo "Usage: make update-version NEW_VERSION=1.2.3"; \
		exit 1; \
	fi
	@echo "$(BLUE)Updating version to $(NEW_VERSION)...$(NC)"
	@bash scripts/version.sh set-version $(NEW_VERSION)
	@echo "$(GREEN)Version updated to $(NEW_VERSION)+1 (build_number reset)$(NC)"

# Bump build number only (used by CI, and locally before manual build)
# Runs verify first to ensure code quality before commit
bump-build:
	@make verify
	@echo "$(BLUE)Bumping build number...$(NC)"
	@bash scripts/version.sh bump
	@git add $(PUBSPEC)
	@git commit -m "chore: bump build number to $$(bash scripts/version.sh build)" || echo "$(YELLOW)Nothing to commit$(NC)"
	@echo "$(GREEN)Build number updated$(NC)"

# Verify code quality (format + analyze) - used by release and bump-build targets
verify:
	@echo "$(BLUE)Running code verification...$(NC)"
	@cd $(PROJECT_DIR) && dart format --output=none --set-exit-if-changed . || (echo "$(RED)Format check failed. Run 'make format' and commit changes.$(NC)"; exit 1)
	@cd $(PROJECT_DIR) && $(FLUTTER) analyze || (echo "$(RED)Analyze check failed. Fix warnings/errors and commit.$(NC)"; exit 1)
	@echo "$(GREEN)Code verification passed!$(NC)"

verify-format:
	@echo "$(BLUE)Running format check...$(NC)"
	@cd $(PROJECT_DIR) && dart format --output=none --set-exit-if-changed . || (echo "$(RED)Format check failed. Run 'make format'.$(NC)"; exit 1)
	@echo "$(GREEN)Format check passed!$(NC)"

verify-analyze:
	@echo "$(BLUE)Running analyze...$(NC)"
	@cd $(PROJECT_DIR) && $(FLUTTER) analyze || (echo "$(RED)Analyze check failed.$(NC)"; exit 1)
	@echo "$(GREEN)Analyze passed!$(NC)"

# Release targets - bump version first, then tag
# Tag push triggers CI which auto-bumps build_number per build
release-patch:
	@make verify
	@NEW_VER=$$(make -s next-patch); \
	echo "$(BLUE)Creating patch release: $$NEW_VER$(NC)"; \
	make update-version NEW_VERSION=$$NEW_VER; \
	git add $(PUBSPEC); \
	git commit -m "chore: bump version to $$NEW_VER"; \
	git tag -a "v$$NEW_VER" -m "Release v$$NEW_VER"; \
	echo "$(GREEN)Created tag v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)Push with: git push origin main && git push origin v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)CI will auto-increment build_number on each build$(NC)"

release-minor:
	@make verify
	@NEW_VER=$$(make -s next-minor); \
	echo "$(BLUE)Creating minor release: $$NEW_VER$(NC)"; \
	make update-version NEW_VERSION=$$NEW_VER; \
	git add $(PUBSPEC); \
	git commit -m "chore: bump version to $$NEW_VER"; \
	git tag -a "v$$NEW_VER" -m "Release v$$NEW_VER"; \
	echo "$(GREEN)Created tag v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)Push with: git push origin main && git push origin v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)CI will auto-increment build_number on each build$(NC)"

release-major:
	@make verify
	@NEW_VER=$$(make -s next-major); \
	echo "$(BLUE)Creating major release: $$NEW_VER$(NC)"; \
	make update-version NEW_VERSION=$$NEW_VER; \
	git add $(PUBSPEC); \
	git commit -m "chore: bump version to $$NEW_VER"; \
	git tag -a "v$$NEW_VER" -m "Release v$$NEW_VER"; \
	echo "$(GREEN)Created tag v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)Push with: git push origin main && git push origin v$$NEW_VER$(NC)"; \
	echo "$(YELLOW)CI will auto-increment build_number on each build$(NC)"

# Git shortcuts
git-status:
	@git status --short

git-push:
	@git push origin $$(git branch --show-current)
	@echo "$(GREEN)Pushed to origin$(NC)"

git-push-tags:
	@git push --tags
	@echo "$(GREEN)Pushed tags to origin$(NC)"
