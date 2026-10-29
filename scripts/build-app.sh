#!/bin/zsh
# Assemble build/d4vWheel.app à partir du paquet Swift (pas besoin d'Xcode).
# Signature : ad hoc par défaut ; avec CODESIGN_IDENTITY="Developer ID Application: …", signature distribuable
# (runtime durci + entitlements), à notariser ensuite avec scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"

if [[ ! -f Packaging/d4vWheel.icns ]]; then
  swift scripts/make-icon.swift Packaging/d4vWheel.iconset
  iconutil -c icns Packaging/d4vWheel.iconset -o Packaging/d4vWheel.icns
  rm -rf Packaging/d4vWheel.iconset
fi

APP="build/d4vWheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/d4vWheel" "$APP/Contents/MacOS/d4vWheel"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/d4vWheel.icns "$APP/Contents/Resources/d4vWheel.icns"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --entitlements Packaging/d4vWheel.entitlements \
    --sign "$CODESIGN_IDENTITY" "$APP"
  echo "Signé : $CODESIGN_IDENTITY"
else
  codesign --force --sign - --entitlements Packaging/d4vWheel.entitlements "$APP" >/dev/null 2>&1 || true
  echo "Signature ad hoc (CODESIGN_IDENTITY non défini)"
fi
echo "→ $APP"
