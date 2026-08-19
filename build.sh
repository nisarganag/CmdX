#!/bin/bash
set -euo pipefail

APP_NAME="CmdX"
BUNDLE_ID="com.nisarganag.cmdx"
VERSION="1.0.0"
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

rm -rf "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# --arch a --arch b needs Xcode's XCBuild, which is not installed. Build each
# slice separately and lipo them together instead.
echo "==> Building arm64"
swift build -c release --triple "arm64-apple-macosx$MIN_MACOS"
echo "==> Building x86_64"
swift build -c release --triple "x86_64-apple-macosx$MIN_MACOS"

echo "==> Creating universal binary"
lipo -create \
    "$ROOT/.build/arm64-apple-macosx/release/CmdXApp" \
    "$ROOT/.build/x86_64-apple-macosx/release/CmdXApp" \
    -output "$CONTENTS/MacOS/$APP_NAME"

echo "==> Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>$MIN_MACOS</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Rendering icon"
swift "$ROOT/Tools/makeicon.swift" "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Built $APP"

echo "==> Creating disk image"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO -quiet \
    "$DIST/$APP_NAME.dmg"
rm -rf "$STAGE"

echo ""
echo "==> Done"
echo "    App: $APP"
echo "    DMG: $DIST/$APP_NAME.dmg"
