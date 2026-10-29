#!/bin/zsh
# Construit, signe, notarise et emballe d4vWheel pour la distribution.
#   CODESIGN_IDENTITY="Developer ID Application: Nom (ÉQUIPE)"   obligatoire pour distribuer
#   NOTARY_PROFILE=d4vwheel   profil créé par : xcrun notarytool store-credentials d4vwheel --apple-id … --team-id … --password …
# Résultat : dist/d4vWheel-<version>.zip et dist/d4vWheel-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CODESIGN_IDENTITY:?Définissez CODESIGN_IDENTITY (certificat Developer ID Application)}"

scripts/build-app.sh release
APP="build/d4vWheel.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist
ZIP="dist/d4vWheel-$VERSION.zip"
DMG="dist/d4vWheel-$VERSION.dmg"
rm -f "$ZIP" "$DMG"

codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
else
  echo "NOTARY_PROFILE non défini : pas de notarisation (Gatekeeper refusera l'appli chez les autres)."
fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "d4vWheel" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
echo "→ $ZIP"
echo "→ $DMG"
