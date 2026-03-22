# Makefile for CB File Hub
# Cross-platform build system for Flutter application
# Works on: Windows (Git Bash/WSL/MinGW), Linux, macOS

.PHONY: help clean deep-clean deps build-windows-portable build-windows-exe build-windows-msi build-android-apk build-android-aab build-linux build-macos build-ios build-all test analyze format doctor release version version-info bump-build retag retag-one

# Default target
.DEFAULT_GOAL := help

# Variables
PROJECT_DIR := cb_file_manager
FLUTTER := flutter
BUILD_DIR := $(PROJECT_DIR)/build
PUBSPEC := $(PROJECT_DIR)/pubspec.yaml

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
	@echo "  make windows-exe       - Build Windows EXE installer"
	@echo "  make windows-msi       - Build Windows MSI installer"
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
	@echo "  make test              - Run tests"
	@echo "  make analyze           - Analyze code"
	@echo "  make format            - Format code"
	@echo "  make doctor            - Run flutter doctor"
	@echo ""
	@echo "$(GREEN)🚀 Release:$(NC)"
	@echo "  make release-patch     - Create patch release (x.x.X)"
	@echo "  make release-minor     - Create minor release (x.X.0)"
	@echo "  make release-major     - Create major release (X.0.0)"
	@echo "  make retag-one TAG=v1.2.3 - Retag existing version (for beta)"
	@echo "  make version           - Show current version"
	@echo "  make version-info      - Show version + build number separately"
	@echo "  make bump-build        - Bump build number only (auto in CI)"
	@echo ""
	@echo "$(GREEN)💡 Examples:$(NC)"
	@echo "  make windows           # Build Windows portable"
	@echo "  make android           # Build Android APK"
	@echo "  make all               # Build everything"
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
	cd $(PROJECT_DIR) && $(FLUTTER) test

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

# Build Windows EXE Installer
build-windows-exe: build-windows-portable
	@echo "$(BLUE)Building Windows EXE Installer...$(NC)"
	@if ! command -v iscc.exe >/dev/null 2>&1 && ! command -v iscc >/dev/null 2>&1; then \
		echo "$(YELLOW)Inno Setup not found. Install from: https://jrsoftware.org/isdl.php$(NC)"; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)/windows/installer
	iscc.exe installer/windows/installer.iss || iscc installer/windows/installer.iss
	@echo "$(GREEN)Windows EXE Installer build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/windows/installer/CBFileHub-Setup.exe"

# Build Windows MSI Installer
build-windows-msi: build-windows-portable
	@echo "$(BLUE)Building Windows MSI Installer...$(NC)"
	@mkdir -p $(BUILD_DIR)/windows/installer
	@# Check for WiX v4+ (wix.exe) or v3 (candle.exe)
	@if command -v wix.exe >/dev/null 2>&1; then \
		echo "$(BLUE)Using WiX v4+ (wix build)...$(NC)"; \
		wix.exe build installer/windows/installer.wxs -d "SourceDir=$(BUILD_DIR)/windows/x64/runner/Release" -ext WixToolset.UI.wixext -o "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"; \
	elif command -v wix >/dev/null 2>&1; then \
		echo "$(BLUE)Using WiX v4+ (wix build)...$(NC)"; \
		wix build installer/windows/installer.wxs -d "SourceDir=$(BUILD_DIR)/windows/x64/runner/Release" -ext WixToolset.UI.wixext -o "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"; \
	elif [ -f "/c/Program Files/WiX Toolset v7.0/bin/wix.exe" ]; then \
		echo "$(BLUE)Using WiX v7 (wix build)...$(NC)"; \
		"/c/Program Files/WiX Toolset v7.0/bin/wix.exe" build installer/windows/installer.wxs -d "SourceDir=$(BUILD_DIR)/windows/x64/runner/Release" -ext WixToolset.UI.wixext -o "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"; \
	elif [ -f "/c/Program Files/WiX Toolset v5.0/bin/wix.exe" ]; then \
		echo "$(BLUE)Using WiX v5 (wix build)...$(NC)"; \
		"/c/Program Files/WiX Toolset v5.0/bin/wix.exe" build installer/windows/installer.wxs -d "SourceDir=$(BUILD_DIR)/windows/x64/runner/Release" -ext WixToolset.UI.wixext -o "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"; \
	elif [ -f "/c/Program Files/WiX Toolset v4.0/bin/wix.exe" ]; then \
		echo "$(BLUE)Using WiX v4 (wix build)...$(NC)"; \
		"/c/Program Files/WiX Toolset v4.0/bin/wix.exe" build installer/windows/installer.wxs -d "SourceDir=$(BUILD_DIR)/windows/x64/runner/Release" -ext WixToolset.UI.wixext -o "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"; \
	elif command -v candle.exe >/dev/null 2>&1; then \
		echo "$(BLUE)Using WiX v3 (candle/light)...$(NC)"; \
		candle.exe -dSourceDir="$(BUILD_DIR)/windows/x64/runner/Release" -out "$(BUILD_DIR)/windows/installer/installer.wixobj" installer/windows/installer.wxs; \
		light.exe -out "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi" "$(BUILD_DIR)/windows/installer/installer.wixobj" -ext WixUIExtension -sval; \
	elif command -v candle >/dev/null 2>&1; then \
		echo "$(BLUE)Using WiX v3 (candle/light)...$(NC)"; \
		candle -dSourceDir="$(BUILD_DIR)/windows/x64/runner/Release" -out "$(BUILD_DIR)/windows/installer/installer.wixobj" installer/windows/installer.wxs; \
		light -out "$(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi" "$(BUILD_DIR)/windows/installer/installer.wixobj" -ext WixUIExtension -sval; \
	else \
		echo "$(YELLOW)WiX Toolset not found. Install from: https://wixtoolset.org/releases/$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Windows MSI Installer build completed!$(NC)"
	@echo "Output: $(BUILD_DIR)/windows/installer/CBFileHub-Setup.msi"

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
windows-exe: build-windows-exe
windows-msi: build-windows-msi
android: build-android-apk
android-aab: build-android-aab
linux: build-linux
macos: build-macos
ios: build-ios
all: build-all

# Retag: push existing version tag again to trigger CI rebuild with incremented build number
# Use for beta/hotfix builds where version stays same but build number must increase
retag:
	@CURRENT_VER=$$(make -s next-patch 2>/dev/null || echo ""); \
	if [ -n "$$CURRENT_VER" ]; then \
		echo "$(BLUE)Last version: $$CURRENT_VER$(NC)"; \
	fi; \
	echo "$(YELLOW)Enter tag to retag (e.g. v1.2.3):$(NC)"; \
	read -r TAG; \
	if [ -z "$$TAG" ]; then \
		echo "$(RED)Tag cannot be empty$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)Pushing tag $$TAG to trigger CI rebuild...$(NC)"; \
	git push origin "$$TAG" --force; \
	echo "$(GREEN)Done. CI will auto-increment build_number on each build.$(NC)"; \
	echo "$(YELLOW)Monitor at: https://github.com/<owner>/<repo>/actions$(NC)"

# One-liner version (set TAG=v1.2.3 make retag)
retag-one:
	@if [ -z "$(TAG)" ]; then \
		echo "$(RED)Error: TAG not set$(NC)"; \
		echo "Usage: make retag-one TAG=v1.2.3"; \
		exit 1; \
	fi
	@echo "$(BLUE)Pushing tag $(TAG) to trigger CI rebuild...$(NC)"; \
	git push origin $(TAG) --force; \
	echo "$(GREEN)Done. CI will auto-increment build_number on each build.$(NC)"

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
bump-build:
	@echo "$(BLUE)Bumping build number...$(NC)"
	@bash scripts/version.sh bump
	@git add $(PUBSPEC)
	@git commit -m "chore: bump build number to $$(bash scripts/version.sh build)" || echo "$(YELLOW)Nothing to commit$(NC)"
	@echo "$(GREEN)Build number updated$(NC)"

# Release targets — bump version first, then tag
# Tag push triggers CI which auto-bumps build_number per build
release-patch:
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
