#!/bin/zsh
# Lance les tests (Swift Testing). Sans Xcode, les Command Line Tools rangent Testing.framework hors des chemins
# par défaut de SwiftPM : on les lui indique.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT="$(xcode-select -p)"
F="$CLT/Library/Developer/Frameworks"
L="$CLT/Library/Developer/usr/lib"
if [[ -d "$F" ]]; then
  swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
else
  swift test "$@"   # Xcode complet : rien à ajouter
fi
