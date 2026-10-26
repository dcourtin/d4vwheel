#!/bin/zsh
# Assemble build/Roue.app à partir du paquet Swift (pas besoin d'Xcode).
# Signature : ad hoc par défaut ; avec CODESIGN_IDENTITY="Developer ID Application: …", signature distribuable
# (runtime durci + entitlements), à notariser ensuite avec scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"

if [[ ! -f Packaging/Roue.icns ]]; then
  swift scripts/make-icon.swift Packaging/Roue.iconset
  iconutil -c icns Packaging/Roue.iconset -o Packaging/Roue.icns
  rm -rf Packaging/Roue.iconset
fi

APP="build/Roue.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Roue" "$APP/Contents/MacOS/Roue"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/Roue.icns "$APP/Contents/Resources/Roue.icns"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --entitlements Packaging/Roue.entitlements \
    --sign "$CODESIGN_IDENTITY" "$APP"
  echo "Signé : $CODESIGN_IDENTITY"
else
  codesign --force --sign - --entitlements Packaging/Roue.entitlements "$APP" >/dev/null 2>&1 || true
  echo "Signature ad hoc (CODESIGN_IDENTITY non défini)"
fi
echo "→ $APP"
