#!/usr/bin/env bash
# Packages a `flutter build linux` bundle as a Debian package (.deb) for
# Debian, Ubuntu and their derivatives.
#
# Usage: scripts/package_linux_deb.sh <bundle-dir> <version> <output.deb>
#
# Layout: the bundle goes to /opt/cb-file-hub, /usr/bin/cb-file-hub links to
# its executable, plus a desktop entry and hicolor icons named after the GTK
# application id so docks match the running window.
#
# Depends is computed with dpkg-shlibdeps from the libraries the bundle really
# links, so a package built on Ubuntu 22.04 (libmpv1) and one built on
# Debian 12 (libmpv2) each ask for the right libmpv. Without dpkg-shlibdeps a
# conservative static list is used.
#
# Environment overrides: DEB_ARCH (default from uname -m), DEB_MAINTAINER.
set -euo pipefail

die() {
    echo "package_linux_deb: $*" >&2
    exit 1
}

[ $# -eq 3 ] || die "usage: $0 <bundle-dir> <version> <output.deb>"
BUNDLE_DIR=$1
VERSION=${2#v}
OUTPUT=$3

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PACKAGE=cb-file-hub
APP_ID=com.cb.cbfilehub
BINARY_NAME="cb-file-hub"
INSTALL_DIR=/opt/$PACKAGE
ICON_PNG="$REPO_DIR/cb_file_manager/assets/images/logo512.png"
ICON_SVG="$REPO_DIR/cb_file_manager/assets/images/logo.svg"
MAINTAINER=${DEB_MAINTAINER:-"CB File Hub <ngtanhung41@gmail.com>"}
HOMEPAGE="https://github.com/coolbirdzik/CB-File-Hub"

[ -x "$BUNDLE_DIR/$BINARY_NAME" ] || die "no executable '$BINARY_NAME' in $BUNDLE_DIR"
command -v dpkg-deb >/dev/null || die "dpkg-deb is required"
# Debian policy: upstream version starts with a digit.
[[ "$VERSION" =~ ^[0-9][A-Za-z0-9.+~-]*$ ]] || die "invalid Debian version '$VERSION'"

if [ -n "${DEB_ARCH:-}" ]; then
    ARCH=$DEB_ARCH
else
    case "$(uname -m)" in
        x86_64 | amd64) ARCH=amd64 ;;
        aarch64 | arm64) ARCH=arm64 ;;
        *) die "unsupported architecture $(uname -m); set DEB_ARCH" ;;
    esac
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/root"

mkdir -p \
    "$ROOT$INSTALL_DIR" \
    "$ROOT/usr/bin" \
    "$ROOT/usr/share/applications" \
    "$ROOT/usr/share/icons/hicolor/512x512/apps" \
    "$ROOT/DEBIAN"
cp -a "$BUNDLE_DIR/." "$ROOT$INSTALL_DIR/"
ln -s "$INSTALL_DIR/$BINARY_NAME" "$ROOT/usr/bin/$PACKAGE"

install -m 644 "$ICON_PNG" "$ROOT/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
if [ -f "$ICON_SVG" ]; then
    mkdir -p "$ROOT/usr/share/icons/hicolor/scalable/apps"
    install -m 644 "$ICON_SVG" "$ROOT/usr/share/icons/hicolor/scalable/apps/$APP_ID.svg"
fi

# Exec uses the /usr/bin link to the bundled executable.
cat >"$ROOT/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CB File Hub
GenericName=File Manager
Comment=Browse, tag and manage local and network files
Exec=$PACKAGE
Icon=$APP_ID
Terminal=false
Categories=Utility;FileManager;
Keywords=files;tags;smb;ftp;webdav;cleaner;
StartupWMClass=$APP_ID
EOF

# Normalise permissions: bundle files may come from a restrictive umask.
chmod -R u+rwX,go+rX,go-w "$ROOT"
chmod 755 "$ROOT$INSTALL_DIR/$BINARY_NAME"

FALLBACK_DEPENDS="libc6, libgtk-3-0 | libgtk-3-0t64, libglib2.0-0 | libglib2.0-0t64, libmpv2 | libmpv1, libepoxy0, libsecret-1-0, libstdc++6"
DEPENDS=""
if command -v dpkg-shlibdeps >/dev/null; then
    mkdir -p "$STAGE/debian"
    printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" \
        >"$STAGE/debian/control"
    ELF_FILES=("$ROOT$INSTALL_DIR/$BINARY_NAME")
    while IFS= read -r -d '' lib; do
        ELF_FILES+=("$lib")
    done < <(find "$ROOT$INSTALL_DIR/lib" -type f -name '*.so*' -print0)
    # Bundled libraries are found through -l and have no package; only the
    # system libraries they and the executable link become dependencies.
    if SHLIBS="$(cd "$STAGE" && dpkg-shlibdeps -O --ignore-missing-info \
        -l"$ROOT$INSTALL_DIR/lib" "${ELF_FILES[@]/#/-e}" 2>"$STAGE/shlibdeps.log")"; then
        DEPENDS="${SHLIBS#shlibs:Depends=}"
    else
        echo "package_linux_deb: dpkg-shlibdeps failed, using fallback Depends" >&2
        cat "$STAGE/shlibdeps.log" >&2 || true
    fi

    # A file using GLIBC_PRIVATE symbols makes dpkg-shlibdeps pin the build
    # host's exact glibc (`libc6 (<< 2.37)` on Debian 12), so the package would
    # not install on any newer distro. Name those files in the log, then drop
    # upper bounds: a prebuilt app bundle must accept newer libraries. The
    # smoke test (scripts/ci/smoke_test_linux_deb.sh) resolves every symbol on
    # newer distros, so a private symbol that really disappeared still fails.
    if command -v objdump >/dev/null; then
        for elf in "${ELF_FILES[@]}"; do
            private="$(objdump -T "$elf" 2>/dev/null |
                awk '/GLIBC_PRIVATE/ {print $NF}' | sort -u | tr '\n' ' ')"
            if [ -n "$private" ]; then
                echo "package_linux_deb: warning: ${elf#"$ROOT"} uses GLIBC_PRIVATE symbols: $private" >&2
            fi
        done
    fi
    if [ -n "$DEPENDS" ]; then
        stripped="$(printf '%s\n' "$DEPENDS" | tr ',' '\n' | sed 's/^ *//; s/ *$//' |
            { grep -Ev '\(<<? ' || true; } | paste -sd ',' - | sed 's/,/, /g')"
        if [ "$stripped" != "$DEPENDS" ]; then
            echo "package_linux_deb: dropped upper-bound dependencies from: $DEPENDS" >&2
        fi
        DEPENDS=$stripped
    fi
fi
[ -n "$DEPENDS" ] || DEPENDS=$FALLBACK_DEPENDS

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)"

cat >"$ROOT/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_SIZE
Depends: $DEPENDS
Recommends: libglib2.0-bin | trash-cli, aria2
Section: utils
Priority: optional
Homepage: $HOMEPAGE
Description: File manager with tags, network shares and media tools
 CB File Hub browses local folders and SMB, FTP and WebDAV shares, tags
 files, previews media and cleans regenerable developer caches.
 .
 Trash moves use gio (libglib2.0-bin) or trash-cli. Torrent downloads use
 an installed aria2c.
EOF

mkdir -p "$(dirname "$OUTPUT")"
# xz instead of the zstd default of newer dpkg, so older dpkg can read it.
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUTPUT" >/dev/null
echo "package_linux_deb: built $OUTPUT"
echo "Depends: $DEPENDS"
