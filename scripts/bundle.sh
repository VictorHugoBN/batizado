#!/bin/bash
#
# Assemble and ad-hoc sign the .app bundle from SwiftPM build products.
# Called by `make app`; every input comes from the environment.
#
#   APP_NAME   display and executable name          (Batizado)
#   BUNDLE_ID  reverse-DNS bundle identifier
#   VERSION    CFBundleShortVersionString
#   BIN_DIR    directory holding the built executables
#   APP_BUNDLE output path of the .app

set -euo pipefail

: "${APP_NAME:?}" "${BUNDLE_ID:?}" "${VERSION:?}" "${BIN_DIR:?}" "${APP_BUNDLE:?}"

GUARDIAN_NAME="${APP_NAME}Guardian"

case "$APP_BUNDLE" in
  *.app) ;;
  *) echo "bundle: APP_BUNDLE must end in .app, got '$APP_BUNDLE'" >&2; exit 1 ;;
esac

for exe in "$APP_NAME" "$GUARDIAN_NAME"; do
  if [ ! -x "$BIN_DIR/$exe" ]; then
    echo "bundle: missing executable $BIN_DIR/$exe (run 'make build' first)" >&2
    exit 1
  fi
done

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$GUARDIAN_NAME" "$APP_BUNDLE/Contents/MacOS/$GUARDIAN_NAME"

# LSUIElement keeps the app out of the Dock and the app switcher: it lives in the menu bar only.
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

# Ad-hoc signatures: there is no Developer ID. Sign the nested helper first, then seal the bundle.
codesign --force --sign - --identifier "$BUNDLE_ID.guardian" "$APP_BUNDLE/Contents/MacOS/$GUARDIAN_NAME"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "bundle: $APP_BUNDLE ($VERSION)"
