#!/bin/sh
# Renders docs/screenshot-light.png and docs/screenshot-dark.png from the real app views.
# The capture app has its own bundle ID, so your saved mix and volumes stay untouched.
# It plays Rain, Fire and Stream with the audio engine muted.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/screenshot/Soundscape Screenshot.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$ROOT/docs"
swiftc -O -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
  "$ROOT"/Soundscape/Channel.swift "$ROOT"/Soundscape/Mixer.swift \
  "$ROOT"/Soundscape/MixerView.swift "$ROOT"/Soundscape/Sound.swift "$ROOT"/Soundscape/Unzip.swift \
  "$ROOT"/scripts/screenshot.swift -o "$APP/Contents/MacOS/Screenshot"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.soundscape.screenshot</string>
  <key>CFBundleName</key>
  <string>Soundscape</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
open -n "$APP" --args "$ROOT/docs" -AppleLocale en_US -AppleLanguages '(en)'
sleep 1
while pgrep -f "Soundscape Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done
ls -la "$ROOT"/docs/screenshot-*.png
