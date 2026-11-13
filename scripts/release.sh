#!/bin/zsh
# Builds a signed, notarized EdgeMeter.dmg for distribution outside the App Store.
#
#   scripts/release.sh                  # universal Release build → sign → DMG → notarize → staple
#   scripts/release.sh --skip-notarize  # everything except notarization (for testing)
#
# Needs: the "Developer ID Application: Erik Rill (25ZPKD8P86)" certificate in the keychain and a
# notarytool profile named "edgemeter" (xcrun notarytool store-credentials edgemeter …).
set -euo pipefail

TEAM_ID="25ZPKD8P86"
IDENTITY="Developer ID Application: Erik Rill (${TEAM_ID})"
NOTARY_PROFILE="edgemeter"
ROOT="${0:A:h:h}"
OUT="${ROOT}/build/release"
NOTARIZE=1
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=0

cd "${ROOT}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/EdgeMeter/Info.plist)
DMG="${OUT}/EdgeMeter-${VERSION}.dmg"
echo "==> EdgeMeter ${VERSION}"

rm -rf "${OUT}"
mkdir -p "${OUT}"
xcodegen generate --quiet

echo "==> Archive (Release, universal, Developer ID)"
xcodebuild archive \
    -project EdgeMeter.xcodeproj -scheme EdgeMeter -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${OUT}/EdgeMeter.xcarchive" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${IDENTITY}" DEVELOPMENT_TEAM="${TEAM_ID}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -quiet

APP="${OUT}/EdgeMeter.app"
cp -R "${OUT}/EdgeMeter.xcarchive/Products/Applications/EdgeMeter.app" "${APP}"

echo "==> Verify app"
codesign --verify --deep --strict --verbose=1 "${APP}"
SIGNATURE=$(codesign -dvv "${APP}" 2>&1)
for required in "Authority=${IDENTITY}" "(runtime)" "Timestamp="; do
    [[ "${SIGNATURE}" == *"${required}"* ]] || { echo "error: signature lacks ${required}" >&2; exit 1; }
done
echo "    signed by ${IDENTITY}, hardened runtime, timestamp"
echo "    architectures: $(lipo -archs "${APP}/Contents/MacOS/EdgeMeter")"

echo "==> DMG"
STAGE="${OUT}/dmg"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
hdiutil create -quiet -volname "EdgeMeter ${VERSION}" -srcfolder "${STAGE}" -fs HFS+ -format UDZO "${DMG}"
codesign --sign "${IDENTITY}" --timestamp "${DMG}"

if (( NOTARIZE )); then
    echo "==> Notarize (takes a few minutes)"
    xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG}"
    echo "==> Gatekeeper check"
    spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
else
    echo "==> Skipped notarization"
fi

echo "==> Done: ${DMG}"
