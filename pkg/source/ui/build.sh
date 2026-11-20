#!/bin/bash
# 완료 창(ev6.usbwifi.Done) 빌드: javac (Java 8) -> d8 (min API 19) -> ../../bin/done.jar (classes.dex 하나)
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; OUT="$H/../../bin/done.jar"
SDK="$HOME/Library/Android/sdk"; AJ="$SDK/platforms/android-35/android.jar"; D8="$SDK/build-tools/36.0.0/d8"
W=$(mktemp -d); mkdir -p "$W/cls" "$W/dex"
javac --release 8 -Xlint:-options -nowarn -d "$W/cls" -cp "$AJ" $(find "$H/ev6" -name '*.java')
"$D8" --min-api 19 --release --lib "$AJ" --output "$W/dex" $(find "$W/cls" -name '*.class')
rm -f "$OUT"; (cd "$W/dex" && zip -X -q "$OUT" classes.dex); rm -rf "$W"
echo "built $OUT"
