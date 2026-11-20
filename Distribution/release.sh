#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
: "${TEKMOR_SIGN_IDENTITY:?Set the Developer ID Application signing identity.}"
: "${TEKMOR_NOTARY_PROFILE:?Set the notarytool keychain profile.}"
if [[ "$TEKMOR_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "A Developer ID Application identity is required." >&2
    exit 1
fi

release_dir="$repo_root/.build/release"
mkdir -p "$release_dir"

notary=(--keychain-profile "$TEKMOR_NOTARY_PROFILE")
if [[ -n "${TEKMOR_NOTARY_KEYCHAIN:-}" ]]; then
    notary+=(--keychain "$TEKMOR_NOTARY_KEYCHAIN")
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/disk"
xcodebuild -project Tekmor.xcodeproj -scheme Tekmor -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$release_dir/xcode" \
    -disableAutomaticPackageResolution -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
app="$work/disk/Tekmor.app"
ditto "$release_dir/xcode/Build/Products/Release/Tekmor.app" "$app"
codesign --force --options runtime --timestamp --sign "$TEKMOR_SIGN_IDENTITY" "$app"
codesign --verify --strict --verbose=2 "$app"

ln -s /Applications "$work/disk/Applications"
dmg="$release_dir/Tekmor-0.1.0-arm64.dmg"
hdiutil create -ov -volname Tekmor -srcfolder "$work/disk" -format UDZO "$dmg"
codesign --force --timestamp --sign "$TEKMOR_SIGN_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" "${notary[@]}" --wait --output-format json > "$release_dir/dmg-notarization.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$release_dir/dmg-notarization.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
(
    cd "$release_dir"
    shasum -a 256 Tekmor-0.1.0-arm64.dmg > SHA256SUMS.txt
)
printf 'Release candidate: %s\n' "$release_dir"
