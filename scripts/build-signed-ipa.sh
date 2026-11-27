#!/usr/bin/env bash
# Builds a signed .ipa when signing material is available (CI secrets or env).
#
# Required environment:
#   IOS_CERTIFICATE_P12       base64 of a .p12 with the signing certificate + key
#   IOS_CERTIFICATE_PASSWORD  password of the .p12
#   IOS_PROVISIONING_PROFILE  base64 of the .mobileprovision
#   IOS_TEAM_ID               Apple Developer team ID
# Optional:
#   IOS_BUNDLE_ID             bundle identifier matching the profile (default: from the profile)
#   IOS_EXPORT_METHOD         release-testing | debugging | app-store-connect | enterprise (default: release-testing)
#
# Usage: scripts/build-signed-ipa.sh <output.ipa>
set -euo pipefail
OUTPUT="$1"
: "${IOS_CERTIFICATE_P12:?}" "${IOS_CERTIFICATE_PASSWORD:?}" "${IOS_PROVISIONING_PROFILE:?}" "${IOS_TEAM_ID:?}"
METHOD="${IOS_EXPORT_METHOD:-release-testing}"
case "$METHOD" in
  debugging|development) IDENTITY="Apple Development" ;;
  *) IDENTITY="Apple Distribution" ;;
esac
WORK="$(mktemp -d)"
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "$IOS_CERTIFICATE_P12" | base64 --decode > "$WORK/cert.p12"
echo "$IOS_PROVISIONING_PROFILE" | base64 --decode > "$WORK/profile.mobileprovision"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/cert.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$WORK/profile.plist")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$WORK/profile.plist")
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$WORK/profile.plist")
BUNDLE_ID="${IOS_BUNDLE_ID:-${APP_ID#*.}}"
if [[ "$BUNDLE_ID" == *"*"* ]]; then
  echo "error: wildcard profile; set IOS_BUNDLE_ID" >&2
  exit 1
fi
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$WORK/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

xcodebuild archive \
  -project OutfitSimulator.xcodeproj -scheme OutfitSimulator -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Signed.xcarchive" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$IOS_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN"

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$IOS_TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE_ID</key><string>$PROFILE_UUID</string></dict>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$WORK/Signed.xcarchive" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist"
mkdir -p "$(dirname "$OUTPUT")"
cp "$WORK/export/"*.ipa "$OUTPUT"
echo "Signed IPA ($METHOD, profile \"$PROFILE_NAME\"): $OUTPUT"
