#!/bin/sh
# Builds a universal (Apple silicon and Intel) Soundscape.app with an ad-hoc signature,
# checks the signature survives zipping, and writes dist/Soundscape-<version>.zip.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/Soundscape.app"
ZIP="$ROOT/dist/Soundscape-$VERSION.zip"
CHECK=$(mktemp -d)

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project Soundscape.xcodeproj -target Soundscape -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/Soundscape" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/Soundscape.app"
rm -rf "$CHECK"

echo "$ZIP"
shasum -a 256 "$ZIP"
