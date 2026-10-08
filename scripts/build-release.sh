#!/bin/sh
# Builds a universal (Apple silicon and Intel) Tranquillity Maker.app, signs it with Flavio's
# Developer ID when that certificate is in the keychain (ad-hoc everywhere else),
# notarizes and staples when Developer ID signed, checks the signature survives zipping,
# and writes dist/Tranquillity Maker-<version>.zip.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/Tranquillity Maker.app"
ZIP="$ROOT/dist/Tranquillity Maker-$VERSION.zip"
CHECK=$(mktemp -d)
ENT=$(mktemp)
EMPTY_ENT=$(mktemp)
trap 'rm -rf "$CHECK" "$ENT" "$EMPTY_ENT"' EXIT
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict/></plist>' >"$EMPTY_ENT"

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project Soundscape.xcodeproj -target Soundscape -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/Tranquillity Maker" -verify_arch arm64 x86_64

IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  SIGNATURE="Developer ID"

  if codesign -d --entitlements - --xml "$APP" 2>/dev/null >"$ENT"; then
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$ENT" >/dev/null 2>&1 || true
  else
    cp "$EMPTY_ENT" "$ENT"
  fi
  HAS_ENT=
  if grep -q '<key>' "$ENT" 2>/dev/null; then
    HAS_ENT=1
  fi
  if [ -z "$HAS_ENT" ]; then
    BIN_ENT="$EMPTY_ENT"
  else
    BIN_ENT="$ENT"
  fi

  MACHO_SORTED=$(mktemp)
  trap 'rm -rf "$CHECK" "$ENT" "$EMPTY_ENT" "$MACHO_SORTED"' EXIT
  find "$APP" -type f -print | while read -r path; do
    case $(file -b "$path") in
      Mach-O*) depth=$(echo "$path" | tr -cd '/' | wc -c | tr -d ' ')
        printf '%s %s\n' "$depth" "$path" ;;
    esac
  done | sort -rn -k1,1 >"$MACHO_SORTED"
  while read -r _ path; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
      --entitlements "$BIN_ENT" "$path"
  done <"$MACHO_SORTED"
  if [ -n "$HAS_ENT" ]; then
    APP_ENT="$ENT"
  else
    APP_ENT="$EMPTY_ENT"
  fi
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$APP_ENT" "$APP"

  codesign --verify --strict "$APP"
else
  SIGNATURE="ad-hoc"
  codesign --verify --deep --strict "$APP"
fi

if [ "$SIGNATURE" = "Developer ID" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

if [ "$SIGNATURE" = "Developer ID" ]; then
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  status=$(printf '%s' "$result" | plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    printf '%s\n' "$result" >&2
    submission_id=$(printf '%s' "$result" | plutil -extract id raw -o - -)
    xcrun notarytool log "$submission_id" --keychain-profile notary >&2
    exit 1
  fi

  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Tranquillity Maker.app"
rm -rf "$CHECK"

echo "Built $ZIP ($SIGNATURE signed)"
echo "$ZIP"
shasum -a 256 "$ZIP"
