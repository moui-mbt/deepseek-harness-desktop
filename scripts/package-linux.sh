#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE="linux_skia"
APP_NAME="DSH Desktop"
OUTPUT_DIR="dist/linux"
VERSION="0.1.0"
BUILD_VERSION="1"
SKIP_BUILD=false
RELEASE=false

usage() {
  printf 'Usage: %s [--package <moon-package>] [--name <app-name>] [--version <semver>] [--build-version <build>] [--output <dir>] [--release] [--no-build]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="${2:?missing value}"; shift 2 ;;
    --name) APP_NAME="${2:?missing value}"; shift 2 ;;
    --version) VERSION="${2:?missing value}"; shift 2 ;;
    --build-version) BUILD_VERSION="${2:?missing value}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:?missing value}"; shift 2 ;;
    --release) RELEASE=true; shift ;;
    --no-build) SKIP_BUILD=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

PACKAGE_LEAF="$(basename "$PACKAGE")"
BUILD_PROFILE="debug"
if [ "$RELEASE" = true ]; then
  BUILD_PROFILE="release"
fi
EXE_PATH="_build/native/$BUILD_PROFILE/build/$PACKAGE/$PACKAGE_LEAF.exe"

if [ "$SKIP_BUILD" = false ]; then
  printf '==> Building %s (%s)\n' "$PACKAGE" "$BUILD_PROFILE"
  if [ "$RELEASE" = true ]; then
    moon build "$PACKAGE" --target native --release
  else
    moon build "$PACKAGE" --target native
  fi
fi

if [ ! -f "$EXE_PATH" ]; then
  printf 'Built executable not found: %s\n' "$EXE_PATH" >&2
  exit 1
fi

# Portable folder
PORTABLE_DIR="$OUTPUT_DIR/${APP_NAME}-linux-x64"
rm -rf "$PORTABLE_DIR"
mkdir -p "$PORTABLE_DIR"

cp "$EXE_PATH" "$PORTABLE_DIR/dsh-desktop"
chmod +x "$PORTABLE_DIR/dsh-desktop"

# Wrapper script to set env if needed
cat > "$PORTABLE_DIR/run.sh" <<'EOS'
#!/usr/bin/env sh
set -eu
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$DIR/dsh-desktop" "$@"
EOS
chmod +x "$PORTABLE_DIR/run.sh"

# Metadata
cat > "$PORTABLE_DIR/README.txt" <<EOF
$APP_NAME $VERSION ($BUILD_VERSION)
Linux x64 portable build

Run:
  ./dsh-desktop
or
  ./run.sh

Requirements:
  - WebKitGTK 4.1 (libwebkit2gtk-4.1-0)
  - libsoup 3
  - Wayland or X11

Built with MoonBit + MoUI Skia.
EOF
if [ -f "README.md" ]; then cp README.md "$PORTABLE_DIR/" || true; fi
if [ -f "LICENSE" ]; then cp LICENSE "$PORTABLE_DIR/" || true; fi

# Desktop entry
cat > "$PORTABLE_DIR/dsh-desktop.desktop" <<EOF
[Desktop Entry]
Name=$APP_NAME
Comment=DeepSeek Harness Desktop
Exec=./dsh-desktop
Icon=dsh-desktop
Type=Application
Categories=Utility;Development;
StartupWMClass=dsh-desktop
EOF

printf '==> Wrote %s\n' "$PORTABLE_DIR"

# Tarball
TARBALL="dist/DSH-Desktop-${VERSION}-linux-x64.tar.gz"
mkdir -p "$(dirname "$TARBALL")"
printf '==> Creating tarball %s\n' "$TARBALL"
tar -czf "$TARBALL" -C "$OUTPUT_DIR" "$(basename "$PORTABLE_DIR")"
printf '==> Tarball ready: %s (%.1f MB)\n' "$TARBALL" "$(du -m "$TARBALL" | cut -f1)"

# Debian package (optional, requires dpkg-deb)
DEB_DIR="dist/deb"
if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_STAGING="$DEB_DIR/staging"
  DEB_NAME="dsh-desktop_${VERSION}-${BUILD_VERSION}_amd64.deb"
  DEB_PATH="dist/$DEB_NAME"
  printf '==> Creating deb %s\n' "$DEB_PATH"
  rm -rf "$DEB_STAGING"
  mkdir -p "$DEB_STAGING/DEBIAN" "$DEB_STAGING/usr/bin" "$DEB_STAGING/usr/share/applications" "$DEB_STAGING/usr/share/doc/dsh-desktop"
  cp "$PORTABLE_DIR/dsh-desktop" "$DEB_STAGING/usr/bin/dsh-desktop"
  cp "$PORTABLE_DIR/dsh-desktop.desktop" "$DEB_STAGING/usr/share/applications/"
  if [ -f "LICENSE" ]; then cp LICENSE "$DEB_STAGING/usr/share/doc/dsh-desktop/copyright" || true; fi
  cat > "$DEB_STAGING/DEBIAN/control" <<EOF
Package: dsh-desktop
Version: ${VERSION}-${BUILD_VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: MoUI <noreply@wzzc.dev>
Description: DeepSeek Harness Desktop - MoUI native shell for DSH
 Native desktop shell embedding DSH and Chat via system WebView.
Depends: libwebkit2gtk-4.1-0, libsoup-3.0-0, libharfbuzz0b, libfontconfig1
EOF
  cat > "$DEB_STAGING/DEBIAN/postinst" <<'EOS'
#!/bin/sh
set -e
update-desktop-database >/dev/null 2>&1 || true
exit 0
EOS
  chmod 0755 "$DEB_STAGING/DEBIAN/postinst"
  dpkg-deb --build "$DEB_STAGING" "$DEB_PATH" >/dev/null
  printf '==> Deb ready: %s (%.1f MB)\n' "$DEB_PATH" "$(du -m "$DEB_PATH" | cut -f1)"
else
  printf 'dpkg-deb not available, skipping deb\n'
fi

printf '==> Linux packaging complete\n'
