#!/usr/bin/env bash

# CB File Hub - Interactive Build Script
# Cross-platform build system with CLI menu
# Works on: Windows (Git Bash/WSL), Linux, macOS

set -e

# Configuration
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_DIR/cb_file_manager"
BUILD_DIR="$PROJECT_DIR/build"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     CB File Hub - Build System            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

escape_powershell_single_quotes() {
    echo "${1//\'/\'\'}"
}

xml_escape() {
    local value="$1"
    value=${value//&/&amp;}
    value=${value//\"/&quot;}
    value=${value//</&lt;}
    value=${value//>/&gt;}
    printf '%s' "$value"
}

generate_wix_harvest_fragment() {
    local source_dir="$1"
    local output_file="$2"
    local file_count=0

    if [ ! -d "$source_dir" ]; then
        print_error "WiX source directory not found: $source_dir"
        return 1
    fi

    print_info "Generating WiX file manifest..."

    {
        cat <<'EOF'
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
EOF

        while IFS= read -r -d '' file_path; do
            file_count=$((file_count + 1))

            local relative_path="${file_path#$source_dir/}"
            local windows_relative_path="${relative_path//\//\\}"
            local subdirectory=""
            local windows_file_path="$file_path"
            local component_id
            local file_id

            if [[ "$windows_relative_path" == *\\* ]]; then
                subdirectory="${windows_relative_path%\\*}"
            fi

            if command -v cygpath &> /dev/null; then
                windows_file_path=$(cygpath -w "$file_path")
            fi

            component_id=$(printf "AutoCmp%05d" "$file_count")
            file_id=$(printf "AutoFile%05d" "$file_count")

            if [ -n "$subdirectory" ]; then
                printf '      <Component Id="%s" Subdirectory="%s">\n' \
                    "$component_id" "$(xml_escape "$subdirectory")"
            else
                printf '      <Component Id="%s">\n' "$component_id"
            fi

            printf '        <File Id="%s" Source="%s" KeyPath="yes" />\n' \
                "$file_id" "$(xml_escape "$windows_file_path")"
            printf '      </Component>\n'
        done < <(find "$source_dir" -type f -print0)

        cat <<'EOF'
    </ComponentGroup>
  </Fragment>
</Wix>
EOF
    } > "$output_file"

    if [ "$file_count" -eq 0 ]; then
        print_error "No files found to include in MSI package."
        return 1
    fi

    print_info "WiX manifest generated with $file_count files."
    return 0
}

# Verify required runtime files exist in Windows release bundle.
verify_windows_release_bundle() {
    local release_dir="$1"
    local missing_files=()

    if [ ! -d "$release_dir" ]; then
        print_error "Release directory not found: $release_dir"
        return 1
    fi

    [ -f "$release_dir/cb_file_hub.exe" ] || missing_files+=("cb_file_hub.exe")
    [ -f "$release_dir/flutter_windows.dll" ] || missing_files+=("flutter_windows.dll")

    local ffmpeg_patterns=(
        "avcodec-*.dll"
        "avformat-*.dll"
        "avutil-*.dll"
        "swscale-*.dll"
    )

    local old_nullglob
    old_nullglob=$(shopt -p nullglob || true)
    shopt -s nullglob
    for pattern in "${ffmpeg_patterns[@]}"; do
        local matches=("$release_dir"/$pattern)
        if [ ${#matches[@]} -eq 0 ]; then
            missing_files+=("$pattern")
        fi
    done
    eval "$old_nullglob"

    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing required runtime files in Windows release bundle:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        return 1
    fi

    return 0
}

# Get current version
get_version_line() {
    grep "^version:" "$PUBSPEC" | sed 's/version: //'
}

get_version_name() {
    local version_line
    version_line=$(get_version_line)
    echo "${version_line%%+*}"
}

get_version_code() {
    local version_line
    version_line=$(get_version_line)
    if [[ "$version_line" == *"+"* ]]; then
        echo "${version_line##*+}"
    else
        echo "0"
    fi
}

get_version() {
    local version_line
    version_line=$(get_version_line)
    echo "$version_line"
}

set_version_line() {
    local version_name=$1
    local build_number=$2
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^version:.*/version: $version_name+$build_number/" "$PUBSPEC"
    else
        sed -i "s/^version:.*/version: $version_name+$build_number/" "$PUBSPEC"
    fi
}

get_msi_version() {
    local version_name
    local build_number
    local major minor patch
    local msi_build
    local msi_build_formatted
    version_name=$(get_version_name)
    build_number=$(get_version_code)

    # MSI ProductVersion should use 3 numeric parts (major.minor.build).
    # Encode pubspec patch/build-number into the third field to keep upgrade ordering:
    #   1.0.0+1 -> 1.0.0001
    #   1.0.0+2 -> 1.0.0002
    #   1.2.3+4 -> 1.2.3004
    IFS='.' read -r major minor patch <<< "$version_name"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    build_number=${build_number:-0}
    msi_build=$((patch * 1000 + build_number))

    if [ "$msi_build" -gt 65535 ]; then
        print_warning "MSI build component exceeded 65535; clamping for compatibility."
        msi_build=65535
    fi

    msi_build_formatted=$(printf "%04d" "$msi_build")
    echo "$major.$minor.$msi_build_formatted"
}

get_display_version() {
    local version_name
    local build_number
    local major minor patch
    version_name=$(get_version_name)
    build_number=$(get_version_code)
    IFS='.' read -r major minor patch <<< "$version_name"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    build_number=${build_number:-0}
    echo "$major.$patch.$minor.$build_number"
}

get_msix_version() {
    local version_name
    local build_number
    local major minor patch
    version_name=$(get_version_name)
    build_number=$(get_version_code)
    IFS='.' read -r major minor patch <<< "$version_name"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    build_number=${build_number:-0}
    echo "$major.$minor.$patch.$build_number"
}

# Show main menu
show_menu() {
    clear
    print_header
    echo ""
    echo -e "${GREEN}Current Version:${NC} $(get_version)"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📦 BUILD TARGETS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo "  1) Windows Portable (ZIP)"
    echo "  2) Windows MSI Installer"
    echo "  3) Windows MSIX Package"
    echo "  4) Android APK"
    echo "  5) Android AAB"
    echo "  6) Linux"
    echo "  7) macOS"
    echo "  8) iOS"
    echo "  9) Build All Platforms"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🔧 DEVELOPMENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo " 10) Clean Build Artifacts"
    echo " 11) Deep Clean (Remove all build files)"
    echo " 12) Install Dependencies"
    echo " 13) Run Tests"
    echo " 14) Analyze Code"
    echo " 15) Format Code"
    echo " 16) Flutter Doctor"
    echo " 17) Check Build Tools (WiX, MSIX, Inno Setup)"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}🚀 RELEASE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo " 18) Create Patch Release (x.x.X)"
    echo " 19) Create Minor Release (x.X.0)"
    echo " 20) Create Major Release (X.0.0)"
    echo " 21) Bump Build Number Only"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo "  0) Exit"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -n "Select option: "
}

# Clean build artifacts
clean_build() {
    print_info "Cleaning build artifacts..."
    cd "$PROJECT_DIR"
    flutter clean
    
    # Remove CMake cache to avoid generator conflicts
    print_info "Removing CMake cache..."
    rm -rf build/windows/CMakeCache.txt 2>/dev/null || true
    rm -rf build/windows/CMakeFiles 2>/dev/null || true
    rm -rf build/windows/.cmake 2>/dev/null || true
    
    # Remove additional directories if not locked
    print_info "Removing additional build directories..."
    rm -rf .dart_tool 2>/dev/null || true
    rm -rf windows/flutter/ephemeral 2>/dev/null || true
    rm -rf linux/flutter/ephemeral 2>/dev/null || true
    rm -rf macos/Flutter/ephemeral 2>/dev/null || true
    
    cd ..
    print_success "Clean completed!"
}

# Deep clean (more thorough)
deep_clean() {
    print_info "Performing deep clean..."
    cd "$PROJECT_DIR"
    
    flutter clean
    
    # Remove CMake cache completely
    print_info "Removing CMake cache..."
    rm -rf build/windows 2>/dev/null || true
    rm -rf build/linux 2>/dev/null || true
    rm -rf build/macos 2>/dev/null || true
    
    # Remove all build artifacts (ignore errors if files are locked)
    print_info "Removing all build artifacts..."
    rm -rf .dart_tool 2>/dev/null || true
    rm -rf .flutter-plugins 2>/dev/null || true
    rm -rf .flutter-plugins-dependencies 2>/dev/null || true
    rm -rf .packages 2>/dev/null || true
    
    # Remove platform-specific ephemeral folders
    rm -rf windows/flutter/ephemeral 2>/dev/null || true
    rm -rf linux/flutter/ephemeral 2>/dev/null || true
    rm -rf macos/Flutter/ephemeral 2>/dev/null || true
    rm -rf ios/.symlinks 2>/dev/null || true
    rm -rf ios/Flutter/Flutter.framework 2>/dev/null || true
    rm -rf ios/Flutter/Flutter.podspec 2>/dev/null || true
    
    cd ..
    print_success "Deep clean completed!"
    print_warning "Some files may be locked by running processes"
    print_info "Run 'Install Dependencies' before building"
}

# Install dependencies
install_deps() {
    print_info "Installing dependencies..."
    cd "$PROJECT_DIR"
    flutter pub get
    cd ..
    print_success "Dependencies installed!"
}

# Build Windows Portable (with auto-retry on first failure)
build_windows_portable() {
    print_info "Building Windows Portable..."
    
    # Force clean to ensure reproducible Windows builds.
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    
    # Fix pdfx plugin CMake compatibility issue
    local PDFX_CMAKE="windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/CMakeLists.txt"
    local PDFX_TEMPLATE="windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows/DownloadProject.CMakeLists.cmake.in"
    
    if [ -f "$PDFX_CMAKE" ] || [ -f "$PDFX_TEMPLATE" ]; then
        print_info "Patching pdfx plugin CMake configuration..."
        
        # Update main CMakeLists.txt
        if [ -f "$PDFX_CMAKE" ]; then
            sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.14)/g' "$PDFX_CMAKE" 2>/dev/null || true
        fi
        
        # Update DownloadProject template (this is the critical one!)
        if [ -f "$PDFX_TEMPLATE" ]; then
            sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.14)/g' "$PDFX_TEMPLATE" 2>/dev/null || true
        fi
    fi
    
    # Fix VS BuildTools/Community conflict on Windows
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Ensure VS Community 2022 takes precedence
        export VSINSTALLDIR="C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\"
        export VCToolsInstallDir="C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\"
        
        # Force CMake to use Visual Studio 2022 (not 2019)
        export CMAKE_GENERATOR="Visual Studio 17 2022"
        export CMAKE_GENERATOR_PLATFORM="x64"
    fi
    
    # Try build - if it fails with CMake/VS error, retry once
    print_info "Starting Flutter build..."
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    if ! flutter build windows --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE" 2>&1 | tee /tmp/flutter_build.log; then
        # Check if it's the known CMake/VS race condition error
        if grep -q "MSB3073\|CMake.*failed\|Visual Studio" /tmp/flutter_build.log 2>/dev/null; then
            print_warning "First build failed (known CMake race condition)"
            print_info "Retrying build automatically..."
            sleep 2
            flutter build windows --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
        else
            # Different error, don't retry
            cd ..
            return 1
        fi
    fi
    
    if [ $? -eq 0 ]; then
        print_info "Creating ZIP package..."
        local PORTABLE_DIR="$BUILD_DIR/windows/portable"
        mkdir -p "$PORTABLE_DIR"
        
        local RELEASE_DIR="$BUILD_DIR/windows/x64/runner/Release"
        local OUTPUT_ZIP="$PORTABLE_DIR/CBFileHub-Portable.zip"

        if ! verify_windows_release_bundle "$RELEASE_DIR"; then
            cd ..
            return 1
        fi

        if command -v zip &> /dev/null; then
            (
                cd "$RELEASE_DIR"
                zip -r "$OUTPUT_ZIP" ./*
            )
        elif command -v 7z &> /dev/null; then
            (
                cd "$RELEASE_DIR"
                7z a -tzip "$OUTPUT_ZIP" ./*
            )
        elif command -v powershell.exe &> /dev/null; then
            local RELEASE_DIR_WIN="$RELEASE_DIR"
            local OUTPUT_ZIP_WIN="$OUTPUT_ZIP"
            if command -v cygpath &> /dev/null; then
                RELEASE_DIR_WIN=$(cygpath -w "$RELEASE_DIR")
                OUTPUT_ZIP_WIN=$(cygpath -w "$OUTPUT_ZIP")
            fi
            powershell.exe -NoProfile -Command "Compress-Archive -Path '$RELEASE_DIR_WIN\\*' -DestinationPath '$OUTPUT_ZIP_WIN' -Force"
        else
            print_warning "No ZIP tool found. Files available at: $RELEASE_DIR"
            cd ..
            return 0
        fi
        
        print_success "Windows Portable build completed!"
        print_info "Output: $OUTPUT_ZIP"
    else
        print_error "Windows build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build Windows EXE
build_windows_exe() {
    print_info "Building Windows EXE Installer..."

    local ISCC=""
    local ISCC_WIN=""

    if command -v iscc.exe &> /dev/null; then
        ISCC="iscc.exe"
        ISCC_WIN="iscc.exe"
    elif command -v iscc &> /dev/null; then
        ISCC="iscc"
        ISCC_WIN="iscc"
    elif [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
        ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
    elif [ -f "/c/Program Files (x86)/Inno Setup 5/ISCC.exe" ]; then
        ISCC="/c/Program Files (x86)/Inno Setup 5/ISCC.exe"
    else
        print_error "Inno Setup not found!"
        print_info "Install from: https://jrsoftware.org/isdl.php"
        print_info "Or add to PATH: C:\\Program Files (x86)\\Inno Setup 6"
        return 1
    fi

    if [ -z "$ISCC_WIN" ]; then
        if command -v cygpath &> /dev/null; then
            ISCC_WIN=$(cygpath -w "$ISCC")
        else
            ISCC_WIN="$ISCC"
        fi
    fi

    print_info "Found Inno Setup: $ISCC_WIN"

    build_windows_portable

    local VERSION_NAME
    VERSION_NAME=$(get_version_name)
    local INSTALLER_SCRIPT="$REPO_DIR/installer/windows/installer.iss"
    local INSTALLER_SCRIPT_WIN="$INSTALLER_SCRIPT"

    if command -v cygpath &> /dev/null; then
        INSTALLER_SCRIPT_WIN=$(cygpath -w "$INSTALLER_SCRIPT")
    fi

    local iscc_ps
    local define_ps
    local installer_ps
    iscc_ps=$(escape_powershell_single_quotes "$ISCC_WIN")
    define_ps=$(escape_powershell_single_quotes "/DMyAppVersion=$VERSION_NAME")
    installer_ps=$(escape_powershell_single_quotes "$INSTALLER_SCRIPT_WIN")

    print_info "Creating EXE installer..."
    if command -v powershell.exe &> /dev/null; then
        powershell.exe -NoProfile -Command "& { & '$iscc_ps' '$define_ps' '$installer_ps'; if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE } }"
    else
        MSYS2_ARG_CONV_EXCL="/D*" "$ISCC" "/DMyAppVersion=$VERSION_NAME" "$INSTALLER_SCRIPT"
    fi

    if [ $? -eq 0 ]; then
        print_success "Windows EXE Installer created!"
        print_info "Output: $BUILD_DIR/windows/installer/CBFileHub-Setup.exe"
    else
        print_error "EXE installer creation failed!"
        return 1
    fi
}

# Build Windows MSI
build_windows_msi() {
    print_info "Building Windows MSI Installer..."
    
    # Check for WiX - v4+ uses wix.exe, v3 uses candle.exe/light.exe
    local WIX_CMD=""
    local WIX_VERSION=""
    
    # Check for WiX v4+ (wix.exe)
    if command -v wix.exe &> /dev/null; then
        WIX_CMD="wix.exe"
        WIX_VERSION="v4+"
    elif command -v wix &> /dev/null; then
        WIX_CMD="wix"
        WIX_VERSION="v4+"
    elif [ -f "/c/Program Files/WiX Toolset v4.0.5/bin/wix.exe" ]; then
        WIX_CMD="/c/Program Files/WiX Toolset v4.0.5/bin/wix.exe"
        WIX_VERSION="v4+"
    elif [ -f "/c/Program Files/WiX Toolset v4.0/bin/wix.exe" ]; then
        WIX_CMD="/c/Program Files/WiX Toolset v4.0/bin/wix.exe"
        WIX_VERSION="v4+"
    elif [ -f "/c/Program Files/WiX Toolset v7.0/bin/wix.exe" ]; then
        WIX_CMD="/c/Program Files/WiX Toolset v7.0/bin/wix.exe"
        WIX_VERSION="v7"
    elif [ -f "/c/Program Files/WiX Toolset v5.0/bin/wix.exe" ]; then
        WIX_CMD="/c/Program Files/WiX Toolset v5.0/bin/wix.exe"
        WIX_VERSION="v5"
    # Check for WiX v3 (candle.exe/light.exe)
    elif command -v candle.exe &> /dev/null; then
        WIX_CMD="candle"
        WIX_VERSION="v3"
    elif [ -f "/c/Program Files (x86)/WiX Toolset v3.14/bin/candle.exe" ]; then
        WIX_CMD="/c/Program Files (x86)/WiX Toolset v3.14/bin"
        WIX_VERSION="v3"
    elif [ -f "/c/Program Files (x86)/WiX Toolset v3.11/bin/candle.exe" ]; then
        WIX_CMD="/c/Program Files (x86)/WiX Toolset v3.11/bin"
        WIX_VERSION="v3"
    else
        print_error "WiX Toolset not found!"
        print_info "Install from: https://wixtoolset.org/releases/"
        print_info "Or add to PATH: C:\\Program Files\\WiX Toolset v7.0\\bin"
        return 1
    fi
    
    print_info "Found WiX $WIX_VERSION: $WIX_CMD"

    if [ "$WIX_VERSION" != "v3" ]; then
        print_info "Ensuring WiX UI extension is available..."
        "$WIX_CMD" extension add -g WixToolset.UI.wixext/4.0.5 >/dev/null 2>&1 || true
    fi

    build_windows_portable
    local VERSION_DISPLAY
    VERSION_DISPLAY=$(get_display_version)
    local VERSION_MSI
    VERSION_MSI=$(get_msi_version)
    
    print_info "Creating MSI installer..."
    local BUILD_PATH="$PROJECT_DIR/build/windows/x64/runner/Release"
    local INSTALLER_DIR="$REPO_DIR/installer/windows"
    local OUTPUT_DIR="$PROJECT_DIR/build/windows/installer"
    local HARVEST_WXS="$OUTPUT_DIR/generated-files.wxs"
    
    mkdir -p "$OUTPUT_DIR"

    if ! verify_windows_release_bundle "$BUILD_PATH"; then
        return 1
    fi

    if ! generate_wix_harvest_fragment "$BUILD_PATH" "$HARVEST_WXS"; then
        return 1
    fi
    
    # Convert paths for Windows if needed
    local BUILD_PATH_WIN="$BUILD_PATH"
    local OUTPUT_DIR_WIN="$OUTPUT_DIR"
    local INSTALLER_DIR_WIN="$INSTALLER_DIR"
    local HARVEST_WXS_WIN="$HARVEST_WXS"
    
    if command -v cygpath &> /dev/null; then
        BUILD_PATH_WIN=$(cygpath -w "$BUILD_PATH")
        OUTPUT_DIR_WIN=$(cygpath -w "$OUTPUT_DIR")
        INSTALLER_DIR_WIN=$(cygpath -w "$INSTALLER_DIR")
        HARVEST_WXS_WIN=$(cygpath -w "$HARVEST_WXS")
    fi
    
    if [ "$WIX_VERSION" = "v3" ]; then
        # WiX v3: Use candle.exe and light.exe
        print_info "Using WiX v3 (candle/light)..."
        if [ "$WIX_CMD" = "candle" ]; then
            candle.exe -dSourceDir="$BUILD_PATH_WIN" -dProductVersion="$VERSION_MSI" -dProductDisplayVersion="$VERSION_DISPLAY" -out "$OUTPUT_DIR_WIN\\installer.wixobj" "$INSTALLER_DIR_WIN\\installer.wxs"
            candle.exe -out "$OUTPUT_DIR_WIN\\generated-files.wixobj" "$HARVEST_WXS_WIN"
            light.exe -out "$OUTPUT_DIR_WIN\\CBFileHub-Setup.msi" "$OUTPUT_DIR_WIN\\installer.wixobj" "$OUTPUT_DIR_WIN\\generated-files.wixobj" -ext WixUIExtension -sval
        else
            "$WIX_CMD/candle.exe" -dSourceDir="$BUILD_PATH_WIN" -dProductVersion="$VERSION_MSI" -dProductDisplayVersion="$VERSION_DISPLAY" -out "$OUTPUT_DIR_WIN\\installer.wixobj" "$INSTALLER_DIR_WIN\\installer.wxs"
            "$WIX_CMD/candle.exe" -out "$OUTPUT_DIR_WIN\\generated-files.wixobj" "$HARVEST_WXS_WIN"
            "$WIX_CMD/light.exe" -out "$OUTPUT_DIR_WIN\\CBFileHub-Setup.msi" "$OUTPUT_DIR_WIN\\installer.wixobj" "$OUTPUT_DIR_WIN\\generated-files.wixobj" -ext WixUIExtension -sval
        fi
    else
        # WiX v4+: Use wix.exe build command
        # Syntax: wix build [options] source.wxs -o output.msi
        # -d defines preprocessor variables (like -dSourceDir)
        print_info "Using WiX $WIX_VERSION (wix build)..."
        "$WIX_CMD" eula accept wix7 >/dev/null 2>&1 || true
        "$WIX_CMD" build "$INSTALLER_DIR_WIN\\installer.wxs" "$HARVEST_WXS_WIN" -d "SourceDir=$BUILD_PATH_WIN" -d "ProductVersion=$VERSION_MSI" -d "ProductDisplayVersion=$VERSION_DISPLAY" -ext WixToolset.UI.wixext -o "$OUTPUT_DIR_WIN\\CBFileHub-Setup.msi"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Windows MSI Installer created!"
        print_info "Output: $OUTPUT_DIR/CBFileHub-Setup.msi"
    else
        print_error "MSI installer creation failed!"
        return 1
    fi
}

# Build Windows MSIX
build_windows_msix() {
    print_info "Building Windows MSIX Package..."

    build_windows_portable

    local VERSION_NAME
    local VERSION_MSIX
    local OUTPUT_DIR
    local OUTPUT_DIR_WIN
    local CERT_PATH="${MSIX_CERT_PATH:-}"
    local CERT_PATH_FOR_CHECK="${MSIX_CERT_PATH:-}"
    local CERT_PASSWORD="${MSIX_CERT_PASSWORD:-}"
    local PUBLISHER="${MSIX_PUBLISHER:-}"
    VERSION_NAME=$(get_version_name)
    VERSION_MSIX=$(get_msix_version)
    OUTPUT_DIR="$BUILD_DIR/windows/msix"
    OUTPUT_DIR_WIN="$OUTPUT_DIR"

    mkdir -p "$OUTPUT_DIR"

    if command -v cygpath &> /dev/null; then
        OUTPUT_DIR_WIN=$(cygpath -w "$OUTPUT_DIR")
        if [ -n "$CERT_PATH_FOR_CHECK" ] && [ ! -f "$CERT_PATH_FOR_CHECK" ]; then
            CERT_PATH_FOR_CHECK=$(cygpath -u "$CERT_PATH_FOR_CHECK" 2>/dev/null || echo "$CERT_PATH_FOR_CHECK")
        fi
        if [ -n "$CERT_PATH" ] && [ -f "$CERT_PATH" ]; then
            CERT_PATH=$(cygpath -w "$CERT_PATH" 2>/dev/null || echo "$CERT_PATH")
        fi
    fi

    if [ "${MSIX_REQUIRE_SIGNING:-false}" = "true" ]; then
        if [ -z "$CERT_PATH" ] || [ -z "$CERT_PASSWORD" ]; then
            print_error "MSIX signing is required but certificate env vars are missing."
            print_info "Required: MSIX_CERT_PATH, MSIX_CERT_PASSWORD"
            return 1
        fi
    fi

    cd "$PROJECT_DIR"
    print_info "Creating MSIX package..."
    local msix_cmd=(
        dart run msix:create
        --release
        --install-certificate false
        --version "$VERSION_MSIX"
        --output-path "$OUTPUT_DIR_WIN"
        --output-name "CBFileManager-$VERSION_NAME"
    )

    if [ -n "$CERT_PATH" ]; then
        if [ ! -f "$CERT_PATH_FOR_CHECK" ]; then
            print_error "MSIX certificate file not found: $CERT_PATH"
            cd ..
            return 1
        fi
        msix_cmd+=(--certificate-path "$CERT_PATH")
    fi

    if [ -n "$CERT_PASSWORD" ]; then
        msix_cmd+=(--certificate-password "$CERT_PASSWORD")
    fi

    if [ -n "$PUBLISHER" ]; then
        msix_cmd+=(--publisher "$PUBLISHER")
    fi

    "${msix_cmd[@]}"

    if [ $? -eq 0 ]; then
        print_success "Windows MSIX Package created!"
        print_info "Output: $OUTPUT_DIR/CBFileManager-$VERSION_NAME.msix"
    else
        print_error "MSIX package creation failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build Android APK
build_android_apk() {
    print_info "Building Android APK..."
    
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    flutter build apk --release --split-per-abi --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
    
    if [ $? -eq 0 ]; then
        print_success "Android APK build completed!"
        print_info "Output: $BUILD_DIR/app/outputs/flutter-apk/"
    else
        print_error "Android APK build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build Android AAB
build_android_aab() {
    print_info "Building Android AAB..."
    
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    flutter build appbundle --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
    
    if [ $? -eq 0 ]; then
        print_success "Android AAB build completed!"
        print_info "Output: $BUILD_DIR/app/outputs/bundle/release/"
    else
        print_error "Android AAB build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build Linux
build_linux() {
    print_info "Building Linux..."
    
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    flutter build linux --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
    
    if [ $? -eq 0 ]; then
        print_info "Creating tar.gz package..."
        mkdir -p "$BUILD_DIR/linux/portable"
        cd "$BUILD_DIR/linux/x64/release"
        tar -czf "../portable/CBFileHub-Linux.tar.gz" bundle/
        cd ../../../../..
        
        print_success "Linux build completed!"
        print_info "Output: $BUILD_DIR/linux/portable/CBFileHub-Linux.tar.gz"
    else
        print_error "Linux build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build macOS
build_macos() {
    print_info "Building macOS..."
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "macOS builds can only be done on macOS!"
        return 1
    fi
    
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    flutter build macos --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
    
    if [ $? -eq 0 ]; then
        print_info "Creating ZIP package..."
        mkdir -p "$BUILD_DIR/macos/portable"
        cd "$BUILD_DIR/macos/Build/Products/Release"
        zip -r "../../../portable/CBFileHub-macOS.zip" cb_file_hub.app
        cd ../.../../../../.
        
        print_success "macOS build completed!"
        print_info "Output: $BUILD_DIR/macos/portable/CBFileHub-macOS.zip"
    else
        print_error "macOS build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build iOS
build_ios() {
    print_info "Building iOS..."
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "iOS builds can only be done on macOS!"
        return 1
    fi
    
    clean_build
    install_deps
    
    cd "$PROJECT_DIR"
    local VERSION_NAME
    local VERSION_CODE
    VERSION_NAME=$(get_version_name)
    VERSION_CODE=$(get_version_code)
    flutter build ios --release --no-codesign --build-name "$VERSION_NAME" --build-number "$VERSION_CODE"
    
    if [ $? -eq 0 ]; then
        print_success "iOS build completed!"
        print_info "Output: $BUILD_DIR/ios/iphoneos/"
        print_warning "Note: You need to sign the app in Xcode before distribution"
    else
        print_error "iOS build failed!"
        cd ..
        return 1
    fi
    cd ..
}

# Build all platforms
build_all() {
    print_info "Building for all platforms..."
    
    local failed_builds=()
    
    build_windows_portable || failed_builds+=("Windows Portable")
    build_windows_msi || failed_builds+=("Windows MSI")
    build_windows_msix || failed_builds+=("Windows MSIX")
    build_android_apk || failed_builds+=("Android APK")
    build_android_aab || failed_builds+=("Android AAB")
    build_linux || failed_builds+=("Linux")
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        build_macos || failed_builds+=("macOS")
        build_ios || failed_builds+=("iOS")
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    if [ ${#failed_builds[@]} -eq 0 ]; then
        print_success "All builds completed successfully!"
    else
        print_warning "Some builds failed:"
        for build in "${failed_builds[@]}"; do
            echo "  - $build"
        done
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
}

# Run tests
run_tests() {
    print_info "Running tests..."
    cd "$PROJECT_DIR"
    flutter test
    cd ..
}

# Analyze code
analyze_code() {
    print_info "Analyzing code..."
    cd "$PROJECT_DIR"
    flutter analyze
    cd ..
}

# Format code
format_code() {
    print_info "Formatting code..."
    cd "$PROJECT_DIR"
    dart format .
    cd ..
    print_success "Code formatted!"
}

# Flutter doctor
flutter_doctor() {
    print_info "Running flutter doctor..."
    flutter doctor -v
}

# Check build tools
check_build_tools() {
    print_info "Checking build tools..."
    echo ""
    
    # Check Flutter
    echo -e "${BLUE}Flutter:${NC}"
    if command -v flutter &> /dev/null; then
        flutter --version | head -n 1
    else
        echo -e "${RED}Not found${NC}"
    fi
    echo ""
    
    # Check WiX Toolset
    echo -e "${BLUE}WiX Toolset:${NC}"
    if command -v wix.exe &> /dev/null; then
        echo -e "${GREEN}Found in PATH (v4+)${NC}"
        wix.exe --version 2>&1 | head -n 1
    elif [ -f "/c/Program Files/WiX Toolset v7.0/bin/wix.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files\\WiX Toolset v7.0\\bin${NC}"
        echo -e "${YELLOW}Version: v7 (uses 'wix build' command)${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    elif [ -f "/c/Program Files/WiX Toolset v5.0/bin/wix.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files\\WiX Toolset v5.0\\bin${NC}"
        echo -e "${YELLOW}Version: v5 (uses 'wix build' command)${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    elif [ -f "/c/Program Files/WiX Toolset v4.0/bin/wix.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files\\WiX Toolset v4.0\\bin${NC}"
        echo -e "${YELLOW}Version: v4 (uses 'wix build' command)${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    elif command -v candle.exe &> /dev/null; then
        echo -e "${GREEN}Found in PATH (v3)${NC}"
        candle.exe -? 2>&1 | grep "version" | head -n 1
    elif [ -f "/c/Program Files (x86)/WiX Toolset v3.14/bin/candle.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files (x86)\\WiX Toolset v3.14\\bin${NC}"
        echo -e "${YELLOW}Version: v3 (uses 'candle/light' commands)${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    elif [ -f "/c/Program Files (x86)/WiX Toolset v3.11/bin/candle.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files (x86)\\WiX Toolset v3.11\\bin${NC}"
        echo -e "${YELLOW}Version: v3 (uses 'candle/light' commands)${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    else
        echo -e "${RED}Not found${NC}"
        echo "Install from: https://wixtoolset.org/releases/"
    fi
    echo ""

    # Check MSIX tooling
    echo -e "${BLUE}MSIX:${NC}"
    if command -v dart &> /dev/null; then
        echo -e "${GREEN}Dart SDK found${NC}"
        echo -e "${YELLOW}Run 'dart run msix:create' from the Flutter app directory after 'flutter pub get'.${NC}"
    else
        echo -e "${RED}Dart SDK not found${NC}"
    fi
    echo ""

    # Check Inno Setup
    echo -e "${BLUE}Inno Setup:${NC}"
    if command -v iscc.exe &> /dev/null; then
        echo -e "${GREEN}Found in PATH${NC}"
        iscc.exe /? 2>&1 | grep "Inno Setup" | head -n 1
    elif [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files (x86)\\Inno Setup 6${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    elif [ -f "/c/Program Files (x86)/Inno Setup 5/ISCC.exe" ]; then
        echo -e "${YELLOW}Found at: C:\\Program Files (x86)\\Inno Setup 5${NC}"
        echo -e "${YELLOW}Not in PATH. Add to PATH or script will use full path.${NC}"
    else
        echo -e "${RED}Not found${NC}"
        echo "Install from: https://jrsoftware.org/isdl.php"
    fi
    echo ""

    # Check Visual Studio
    echo -e "${BLUE}Visual Studio:${NC}"
    if [ -d "/c/Program Files/Microsoft Visual Studio/2022/Community" ]; then
        echo -e "${GREEN}VS 2022 Community found${NC}"
    fi
    if [ -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools" ]; then
        echo -e "${YELLOW}VS 2022 BuildTools found${NC}"
        echo -e "${YELLOW}Warning: Having both Community and BuildTools may cause conflicts${NC}"
    fi
    echo ""
    
    print_success "Build tools check completed!"
}

# Calculate next version
next_version() {
    local current
    current=$(get_version_name)
    local type=$1
    
    IFS='.' read -r major minor patch <<< "$current"
    
    case $type in
        "patch")
            patch=$((patch + 1))
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Update version in pubspec.yaml
update_version() {
    local new_version=$1
    local current_build
    current_build=$(get_version_code)
    set_version_line "$new_version" "$current_build"
}

bump_build_number() {
    local current_version
    local current_build
    current_version=$(get_version_name)
    current_build=$(get_version_code)
    current_build=$((current_build + 1))
    set_version_line "$current_version" "$current_build"
}

create_build() {
    local current_build
    current_build=$(get_version_code)
    current_build=$((current_build + 1))
    set_version_line "$(get_version_name)" "$current_build"

    git add "$PUBSPEC"
    git commit -m "chore: bump build number to $current_build"

    print_success "Bumped build number to $current_build"
}

# Create release
create_release() {
    local type=$1
    local new_version=$(next_version $type)
    
    print_info "Creating $type release: $new_version"
    
    # Update version
    update_version "$new_version"
    bump_build_number
    
    # Commit and tag
    git add "$PUBSPEC"
    git commit -m "chore: bump version to $new_version"
    git tag -a "v$new_version" -m "Release v$new_version"
    
    print_success "Created tag v$new_version"
    print_warning "Push with: git push origin main && git push origin v$new_version"
}

# Pause function
pause() {
    echo ""
    read -p "Press Enter to continue..."
}

# Main loop
main() {
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1) build_windows_portable; pause ;;
            2) build_windows_msi; pause ;;
            3) build_windows_msix; pause ;;
            4) build_android_apk; pause ;;
            5) build_android_aab; pause ;;
            6) build_linux; pause ;;
            7) build_macos; pause ;;
            8) build_ios; pause ;;
            9) build_all; pause ;;
            10) clean_build; pause ;;
            11) deep_clean; pause ;;
            12) install_deps; pause ;;
            13) run_tests; pause ;;
            14) analyze_code; pause ;;
            15) format_code; pause ;;
            16) flutter_doctor; pause ;;
            17) check_build_tools; pause ;;
            18) create_release "patch"; pause ;;
            19) create_release "minor"; pause ;;
            20) create_release "major"; pause ;;
            21) create_build; pause ;;
            0) 
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                pause
                ;;
        esac
    done
}

if [ $# -gt 0 ]; then
    case "$1" in
        windows-portable) build_windows_portable ;;
        windows-exe) build_windows_exe ;;
        windows-msi) build_windows_msi ;;
        windows-msix) build_windows_msix ;;
        android-apk) build_android_apk ;;
        android-aab) build_android_aab ;;
        linux) build_linux ;;
        macos) build_macos ;;
        ios) build_ios ;;
        all) build_all ;;
        clean) clean_build ;;
        deep-clean) deep_clean ;;
        install-deps) install_deps ;;
        test) run_tests ;;
        analyze) analyze_code ;;
        format) format_code ;;
        doctor) flutter_doctor ;;
        check-tools) check_build_tools ;;
        release-patch) create_release "patch" ;;
        release-minor) create_release "minor" ;;
        release-major) create_release "major" ;;
        build-number) create_build ;;
        *) 
            print_error "Invalid option: $1"
            exit 1
            ;;
    esac
    exit 0
fi

# Run main
main
