#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE="macos_skia"
APP_NAME="DSH Desktop"
BUNDLE_ID="dev.moui.dsh-desktop"
OUTPUT_DIR="dist/macos"
VERSION="0.1.0"
BUILD_VERSION="1"
SKIP_BUILD=false
RELEASE=false

usage() {
  printf 'Usage: %s [--package <moon-package>] [--name <app-name>] [--bundle-id <id>] [--version <semver>] [--build-version <build>] [--output <dir>] [--release] [--no-build]\n' "$0"
  printf '\n'
  printf 'Builds a native macOS package and wraps the executable in a .app bundle.\n'
  printf 'Example: %s --package macos_skia --name "DSH Desktop" --bundle-id dev.moui.dsh-desktop --version 0.1.0 --release\n' "$0"
}

xml_text() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="${2:?missing value}"; shift 2 ;;
    --name) APP_NAME="${2:?missing value}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:?missing value}"; shift 2 ;;
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
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_EXE="$MACOS_DIR/$PACKAGE_LEAF"

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
  printf 'Hint: moon build native outputs to _build/native/<profile>/build/<package>/<leaf>.exe\n' >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXE_PATH" "$APP_EXE"
chmod +x "$APP_EXE"

PLIST_EXECUTABLE="$(xml_text "$PACKAGE_LEAF")"
PLIST_BUNDLE_ID="$(xml_text "$BUNDLE_ID")"
PLIST_APP_NAME="$(xml_text "$APP_NAME")"
PLIST_VERSION="$(xml_text "$VERSION")"
PLIST_BUILD_VERSION="$(xml_text "$BUILD_VERSION")"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PLIST_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$PLIST_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$PLIST_APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$PLIST_APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$PLIST_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$PLIST_BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSRequiresAquaSystemAppearance</key>
  <false/>
</dict>
</plist>
EOF

# Optional: copy README / LICENSE into Resources for completeness
if [ -f "README.md" ]; then
  cp README.md "$RESOURCES_DIR/" || true
fi
if [ -f "LICENSE" ]; then
  cp LICENSE "$RESOURCES_DIR/" || true
fi

printf '==> Wrote %s\n' "$APP_DIR"
printf '    Executable: %s\n' "$APP_EXE"
printf '    Bundle ID : %s\n' "$BUNDLE_ID"
printf '    Version   : %s (%s)\n' "$VERSION" "$BUILD_VERSION"

# Create distributables if on macOS
DMG_PATH="dist/DSH-Desktop-${VERSION}-macOS.dmg"
ZIP_PATH="dist/DSH-Desktop-${VERSION}-macOS.zip"

# Ensure dist exists
mkdir -p "$(dirname "$DMG_PATH")"

# Create .dmg via hdiutil if available (macOS only)
if command -v hdiutil >/dev/null 2>&1; then
  printf '==> Creating DMG %s\n' "$DMG_PATH"
  rm -f "$DMG_PATH"
  # Use a temporary dmg directory to control volume name
  hdiutil create -volname "$APP_NAME" -srcfolder "$OUTPUT_DIR" -ov -format UDZO "$DMG_PATH" || {
    printf 'hdiutil create failed, skipping DMG\n' >&2
  }
  if [ -f "$DMG_PATH" ]; then
    printf '==> DMG ready: %s (%.1f MB)\n' "$DMG_PATH" "$(du -m "$DMG_PATH" | cut -f1)"
  fi
else
  printf 'hdiutil not available, skipping DMG (Linux/Windows)\n'
fi

# Create ZIP (use ditto on macOS for resource-fork safety, zip elsewhere)
printf '==> Creating ZIP %s\n' "$ZIP_PATH"
rm -f "$ZIP_PATH"
if command -v ditto >/dev/null 2>&1 && [ "$(uname)" = "Darwin" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
else
  # Fallback: zip the .app directory
  if command -v zip >/dev/null 2>&1; then
    (cd "$OUTPUT_DIR" && zip -r -q "../$(basename "$ZIP_PATH")" "$(basename "$APP_DIR")")
    # Move if we zipped from inside OUTPUT_DIR
    if [ ! -f "$ZIP_PATH" ] && [ -f "$OUTPUT_DIR/../$(basename "$ZIP_PATH")" ]; then
      mv "$OUTPUT_DIR/../$(basename "$ZIP_PATH")" "$ZIP_PATH"
    fi
  else
    printf 'zip not available, skipping ZIP\n' >&2
  fi
fi
if [ -f "$ZIP_PATH" ]; then
  printf '==> ZIP ready: %s (%.1f MB)\n' "$ZIP_PATH" "$(du -m "$ZIP_PATH" | cut -f1)"
fi

printf '==> macOS packaging complete\n'
printf '    App : %s\n' "$APP_DIR"
[ -f "$DMG_PATH" ] && printf '    DMG : %s\n' "$DMG_PATH"
[ -f "$ZIP_PATH" ] && printf '    ZIP : %s\n' "$ZIP_PATH"
