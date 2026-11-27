#!/usr/bin/env bash
# Packages the .app inside an (unsigned) .xcarchive as an .ipa and checks it.
# Usage: scripts/package-unsigned-ipa.sh <archive.xcarchive> <output.ipa>
set -euo pipefail
ARCHIVE="$1"
OUTPUT="$2"
APP="$ARCHIVE/Products/Applications/OutfitSimulator.app"

[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }
[[ -d "$APP/ClothingParserModel.mlmodelc" ]] || { echo "error: clothing parser model missing from the app bundle" >&2; exit 1; }
if ls "$APP"/uitest-sample-* >/dev/null 2>&1; then
  echo "error: UI-test sample photos must not ship in Release" >&2; exit 1
fi
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist"
lipo -info "$APP/OutfitSimulator"

WORK="$(mktemp -d)"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
mkdir -p "$(dirname "$OUTPUT")"
OUT_ABS="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
(cd "$WORK" && zip -qry "$OUT_ABS" Payload)
rm -rf "$WORK"
unzip -l "$OUT_ABS" | tail -1
echo "Created $OUT_ABS"
