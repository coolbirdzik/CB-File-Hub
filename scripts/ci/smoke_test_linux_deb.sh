#!/usr/bin/env bash
# Installs a CB File Hub .deb on the current (fresh) Debian/Ubuntu image and
# fails when apt cannot satisfy Depends or any bundled ELF file still has an
# unresolved shared library. Run as root, e.g. in a debian:12 container.
#
# Usage: scripts/ci/smoke_test_linux_deb.sh <package.deb>
set -euo pipefail

DEB=$(readlink -f "$1")
APP_DIR=/opt/cb-file-hub

export DEBIAN_FRONTEND=noninteractive
apt-get update
# apt resolves Depends from the archive; a wrong soname fails here.
apt-get install -y --no-install-recommends "$DEB"

. /etc/os-release
echo "==> Installed on $PRETTY_NAME"
test -x "$APP_DIR/cb-file-hub"
test "$(readlink -f /usr/bin/cb-file-hub)" = "$APP_DIR/cb-file-hub"
test -f /usr/share/applications/com.cb.cbfilehub.desktop

missing=0
while IFS= read -r -d '' elf; do
  if ! head -c 4 "$elf" | grep -q $'\x7fELF'; then continue; fi
  # Plugins resolve libflutter_linux_gtk.so through the executable's RUNPATH
  # at run time; give ldd the same directory. -r also binds every symbol, so a
  # glibc symbol (versioned or GLIBC_PRIVATE) missing on this distro shows up;
  # other undefined symbols can be satisfied by the executable at run time.
  unresolved=$(LD_LIBRARY_PATH="$APP_DIR/lib" ldd -r "$elf" 2>&1 |
    grep -E 'not found|undefined symbol: .*GLIBC' || true)
  if [ -n "$unresolved" ]; then
    echo "::error::$elf has unresolved libraries:"
    echo "$unresolved"
    missing=1
  fi
done < <(find "$APP_DIR" -type f \( -name 'cb-file-hub' -o -name '*.so*' \) -print0)

if [ "$missing" -ne 0 ]; then
  exit 1
fi
echo "==> All bundled ELF files resolve their shared libraries."
