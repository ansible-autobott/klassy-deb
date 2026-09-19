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
#   DEB_MAINTAINER  default: Andres Bott <contact@andresbott.com>
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
[ -n "$DEB_MAINTAINER" ] || DEB_MAINTAINER="Andres Bott <contact@andresbott.com>"

SRC="/src"
OUT="/out"
BUILD="/tmp/build"
# The staging root lives at <PKGROOT>/debian/<package>, the layout dpkg-shlibdeps
# expects for a package being built: anywhere else it warns that the binaries
# "should already be installed in their package's directory", and it looks for
# debian/shlibs.local relative to PKGROOT.
PKGROOT="/tmp/pkg"
STAGE="$PKGROOT/debian/$PKG_NAME"

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

rm -rf "$BUILD" "$PKGROOT"
mkdir -p "$STAGE"

# Out-of-source build; /src stays read-only.
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
    "${QT_FLAGS[@]}"

cmake --build "$BUILD" -j"$(nproc)"
DESTDIR="$STAGE" cmake --install "$BUILD"

# Runtime dependencies: resolved with dpkg-shlibdeps rather than hand-maintained,
# so every release gets the Depends of the exact Qt/KF stack it was compiled
# against (that stack differs per suite, which is the whole point of this repo).
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"

# Must exist *before* dpkg-shlibdeps runs: it locates the package root by walking
# up from each binary until it finds a DEBIAN/ directory, and without it every
# object is reported as "should already be installed in their package's directory"
# and treated as living outside the package.
mkdir -p "$STAGE/DEBIAN"

# shlibs.local covers klassy's *own* shared library (libklassycommon<qt>.so.N):
# no installed package provides it, and without an entry dpkg-shlibdeps aborts
# with "no dependency information found". Derived from the staged SONAMEs so it
# holds for both the Qt5 (…common5) and Qt6 (…common6) builds.
: > "$PKGROOT/debian/shlibs.local"
while IFS= read -r lib; do
    soname="$(readelf -d "$lib" 2>/dev/null | grep -oP 'SONAME.*\[\K[^]]+' || true)"
    [ -n "$soname" ] || continue
    echo "${soname%%.so*} ${soname##*.so.} ${PKG_NAME} (>= ${VERSION})" \
        >> "$PKGROOT/debian/shlibs.local"
done < <(find "$STAGE" -type f -name '*.so.*')

# Minimal control stanza for dpkg-shlibdeps (it reads the package name from here).
cat > "$PKGROOT/debian/control" <<EOF
Source: ${PKG_NAME}

Package: ${PKG_NAME}
Architecture: any
EOF

# Everything ELF in the staging tree: the settings binary, the private library
# and the style / decoration / KCM plugins.
ELFS=()
while IFS= read -r f; do
    readelf -h "$f" >/dev/null 2>&1 && ELFS+=("$f")
done < <(find "$STAGE" -type f -not -path "$STAGE/DEBIAN/*")
[ "${#ELFS[@]}" -gt 0 ] || { echo "!! no ELF objects staged — build produced nothing" >&2; exit 1; }

# -l points at the staged lib dir so the private library can be inspected there;
# -O prints to stdout instead of writing debian/substvars.
DEPENDS="$(cd "$PKGROOT" && dpkg-shlibdeps -O -dDepends -l"$STAGE/usr/lib/$MULTIARCH" "${ELFS[@]}")"
DEPENDS="${DEPENDS#shlibs:Depends=}"
# Drop the self-dependency that shlibs.local produces for klassy's own library.
DEPENDS="$(printf '%s\n' "$DEPENDS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
    | grep -vE "^${PKG_NAME}( |\$)" | paste -sd, - | sed 's/,/, /g')"
[ -n "$DEPENDS" ] || { echo "!! dpkg-shlibdeps produced no dependencies" >&2; exit 1; }

echo ">> Depends: ${DEPENDS}"

# Assemble Debian control metadata.
INSTALLED_KB="$(du -ks --exclude=DEBIAN "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: ${DEB_MAINTAINER}
Installed-Size: ${INSTALLED_KB}
Section: kde
Priority: optional
Depends: ${DEPENDS}
Recommends: kwin-wayland | kwin-x11, systemsettings
Suggests: plasma-desktop
Homepage: https://github.com/paulmcauley/klassy
Description: Klassy window decoration and application style for KDE Plasma
 Klassy offers highly customizable theming for the KDE Plasma desktop.
 Built for Debian ${DEB_SUITE:-unknown} against the Qt${QT_MAJOR} stack.
 .
 Unofficial build packaged by ${DEB_MAINTAINER}; not affiliated with upstream.
EOF

mkdir -p "$OUT"
# The FILENAME replaces '~' with '.'; the control Version above keeps the tilde,
# which is the part that matters (apt needs it to rank 6.7.2-1~sid *below* a
# later 6.7.2-1). This is NOT cosmetic: GitHub rewrites '~' to '.' in release
# asset names — verified by upload, klassy_6.7.2-1~sid_amd64.deb is stored as
# klassy_6.7.2-1.sid_amd64.deb — and debian-repo records its download URL from
# this filename, so emitting the tilde here would 404 every publish. Doing the
# same substitution up front keeps the local name and the asset name identical.
# The pooled filename is canonicalized from the control fields by the repo, so
# all that is required here is that <arch> stays the trailing component.
DEB="${OUT}/${PKG_NAME}_${DEB_VERSION//\~/.}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo ">> wrote ${DEB}"
dpkg-deb --info "$DEB" | sed 's/^/   /'
