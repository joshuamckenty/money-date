#!/usr/bin/env bash
# Build a distributable MoneyDate.app and a money-date.dmg.
#
# The app is ad-hoc signed (required for the arm64 binary to launch at all) but
# NOT Developer-ID signed or notarized — friends will hit a Gatekeeper warning
# and must allow it via System Settings > Privacy & Security > "Open Anyway"
# (or: xattr -dr com.apple.quarantine /Applications/MoneyDate.app). To ship
# warning-free you'd need a paid Apple Developer ID cert + notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
APP_NAME="MoneyDate"
DIST="dist"
APP="$DIST/$APP_NAME.app"

# 1. Build (also compiles the Dopamine effect shaders into each bundle's metallib).
./scripts/build.sh "$CONFIG"
BIN=".build/$CONFIG/$APP_NAME"

# 2. Assemble the .app bundle.
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# SPM resource bundles (with the compiled metallibs) -> Contents/Resources, where
# Bundle.module resolves them inside an app bundle.
cp -R ".build/$CONFIG"/*.bundle "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>money-date</string>
    <key>CFBundleDisplayName</key><string>money-date</string>
    <key>CFBundleIdentifier</key><string>com.joshuamckenty.money-date</string>
    <key>CFBundleExecutable</key><string>MoneyDate</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Joshua McKenty</string>
</dict>
</plist>
PLIST

# 3. Ad-hoc sign (so the binary launches on Apple Silicon).
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "ad-hoc signature OK"

# 4. Build the DMG from a staging folder (app + drag-to-Applications symlink).
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "money-date" -srcfolder "$STAGE" -ov -format UDZO "$DIST/money-date.dmg" >/dev/null
rm -rf "$STAGE"

echo "Built: $DIST/money-date.dmg"
