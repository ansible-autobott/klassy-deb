#!/usr/bin/env bash
#
# Compile klassy from /src and emit a .deb into /out.
# Runs inside the per-release builder image (see docker/Dockerfile).
#
# Inputs (environment):
#   QT_MAJOR        5 or 6            (which Qt/KF stack to build)
#   DEB_SUITE       e.g. trixie       (Debian codename; version suffix + metadata)
#   PKGREV          default: 1        (Debian packaging revision)
#   PKG_NAME        default: klassy
#   PKG_VERSION     default: read from CMakeLists.txt PROJECT_VERSION (the klassy version)
#   DEB_MAINTAINER  default: klassy-deb <nobody@localhost>
# Mounts:
#   /src  klassy source (read-only)
#   /out  destination directory for the .deb
#
# The .deb version is  <klassy-version>-<PKGREV>[~<suite>]  e.g. 6.7.2-1~sid.
set -euo pipefail

QT_MAJOR="${QT_MAJOR:-6}"
PKG_NAME="${PKG_NAME:-klassy}"
DEB_SUITE="${DEB_SUITE:-}"
PKGREV="${PKGREV:-1}"
DEB_MAINTAINER="${DEB_MAINTAINER:-}"
[ -n "$DEB_MAINTAINER" ] || DEB_MAINTAINER="klassy-deb <nobody@localhost>"

SRC="/src"
OUT="/out"
BUILD="/tmp/build"
STAGE="/tmp/stage"

if [ "$QT_MAJOR" = "5" ]; then
    QT_FLAGS=(-DBUILD_QT5=ON -DBUILD_QT6=OFF)
else
    QT_FLAGS=(-DBUILD_QT5=OFF -DBUILD_QT6=ON)
fi

# Resolve the upstream (klassy) version: explicit env wins, else CMakeLists PROJECT_VERSION.
VERSION="${PKG_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(grep -oP 'set\(PROJECT_VERSION\s+"\K[0-9][0-9.]*' "$SRC/CMakeLists.txt" | head -n1 || true)"
fi
VERSION="${VERSION:-0.0.0}"
ARCH="$(dpkg --print-architecture)"

# Debian version: <upstream>-<packaging revision>[~<suite>], e.g. 6.7.2-1~sid.
if [ -n "$DEB_SUITE" ]; then
    DEB_VERSION="${VERSION}-${PKGREV}~${DEB_SUITE}"
else
    DEB_VERSION="${VERSION}-${PKGREV}"
fi

echo ">> building ${PKG_NAME} ${DEB_VERSION} (Qt${QT_MAJOR}) for ${ARCH}"

rm -rf "$BUILD" "$STAGE"

# Out-of-source build; /src stays read-only.
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
    "${QT_FLAGS[@]}"

cmake --build "$BUILD" -j"$(nproc)"
DESTDIR="$STAGE" cmake --install "$BUILD"

# Assemble Debian control metadata.
mkdir -p "$STAGE/DEBIAN"
INSTALLED_KB="$(du -ks --exclude=DEBIAN "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: ${DEB_MAINTAINER}
Installed-Size: ${INSTALLED_KB}
Section: kde
Priority: optional
Homepage: https://github.com/paulmcauley/klassy
Description: Klassy window decoration and application style for KDE Plasma
 Klassy offers highly customizable theming for the KDE Plasma desktop.
 Built for Debian ${DEB_SUITE:-unknown} against the Qt${QT_MAJOR} stack.
EOF

mkdir -p "$OUT"
DEB="${OUT}/${PKG_NAME}_${DEB_VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo ">> wrote ${DEB}"
dpkg-deb --info "$DEB" | sed 's/^/   /'
