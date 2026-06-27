#!/usr/bin/env bash
# Build a distributable MoneyDate.app and a money-date.dmg.
#
# Signed/notarized path (warning-free for friends), if available:
#   1. Create a "Developer ID Application" cert (Xcode > Settings > Accounts >
#      Manage Certificates > + > Developer ID Application), then either let this
#      script auto-detect it or pass SIGN_IDENTITY="Developer ID Application: ...".
#   2. One-time notary credential setup:
#        xcrun notarytool store-credentials money-date \
#          --apple-id you@example.com --team-id <TEAMID> --password <app-specific-pw>
#      then run with NOTARY_PROFILE=money-date.
# Without a Developer ID cert it ad-hoc signs (runs, but Gatekeeper warns; allow
# via System Settings > Privacy & Security > "Open Anyway", or
# xattr -dr com.apple.quarantine /Applications/MoneyDate.app).
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

# 3. Sign. Prefer a Developer ID Application cert (hardened runtime, for
#    notarization); fall back to ad-hoc so the arm64 binary at least launches.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict "$APP" && echo "Developer ID signature OK"
else
    echo "No 'Developer ID Application' cert found — ad-hoc signing (Gatekeeper will warn)."
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP" && echo "ad-hoc signature OK"
fi

# 4. Build the DMG from a staging folder (app + drag-to-Applications symlink).
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "money-date" -srcfolder "$STAGE" -ov -format UDZO "$DIST/money-date.dmg" >/dev/null
rm -rf "$STAGE"

# 5. Notarize + staple the DMG (only with a Developer ID cert + notary profile).
if [ -n "$SIGN_IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DIST/money-date.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DIST/money-date.dmg"
    echo "Notarized + stapled."
else
    echo "Skipped notarization (need a Developer ID cert and NOTARY_PROFILE set)."
fi

echo "Built: $DIST/money-date.dmg"
