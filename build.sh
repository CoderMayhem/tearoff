#!/bin/bash
# Builds Tearoff.app into dist/.
#
#   ./build.sh              build only
#   ./build.sh --install    build, then replace /Applications/Tearoff.app and launch it
#
# TEAROFF_VERSION overrides the version stamped into the bundle (CI sets it from the git tag).
set -euo pipefail

cd "$(dirname "$0")"

APP="dist/Tearoff.app"
BUNDLE_ID="io.github.codermayhem.tearoff"
VERSION="${TEAROFF_VERSION:-1.0.0}"

echo "→ building Tearoff $VERSION"
swift build -c release

echo "→ rendering icon"
rm -rf build/AppIcon.iconset
if swift tools/makeicon.swift build/AppIcon.iconset >/dev/null 2>&1 &&
   iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns 2>/dev/null; then
    ICON_BUILT=1
else
    echo "  ! icon generation failed — bundling without one"
    ICON_BUILT=0
fi

echo "→ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Tearoff" "$APP/Contents/MacOS/Tearoff"
[[ "$ICON_BUILT" == "1" ]] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tearoff</string>
    <key>CFBundleDisplayName</key><string>Tearoff</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Tearoff</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright 2026 Naman Mishra. Apache License 2.0.</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "  ! ad-hoc signing failed; the bundle will still run locally"
}

if [[ "${1:-}" == "--install" ]]; then
    echo "→ installing to /Applications"
    pkill -x Tearoff 2>/dev/null || true
    sleep 0.4
    rm -rf /Applications/Tearoff.app
    cp -R "$APP" /Applications/Tearoff.app
    open /Applications/Tearoff.app
    echo "✓ Tearoff is running — look for the stacked-pages icon in your menu bar."
else
    echo "✓ built $APP   (run ./build.sh --install to put it in /Applications)"
fi
