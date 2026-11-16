#!/bin/sh
# 설치 USB 묶음(zip) 만들기. 사용: sh usb/만들기.sh <usbwifi.hotspot.zip> <출력폴더>
set -e
PKG="$1"; OUT="$2"; [ -f "$PKG" ] && [ -d "$OUT" ] || { echo "usage: $0 <usbwifi.hotspot.zip> <out_dir>"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(sed -n 's/^package-version=//p' "$ROOT/pkg/NEMESIS.data")
NAME="EV6-dongle-USB-v$VER"
W=$(mktemp -d); D="$W/$NAME"
mkdir -p "$D/packages" "$D/설명서"
cp "$ROOT/usb/NEMESIS.data" "$ROOT/usb/먼저_읽어주세요.txt" "$D/"
cp "$PKG" "$D/packages/usbwifi.hotspot.zip"
cp "$ROOT/DISCLAIMER.md"        "$D/설명서/1_면책고지.txt"
cp "$ROOT/docs/설치와연결.md"   "$D/설명서/2_설치와연결.txt"
cp "$ROOT/docs/지원동글.md"     "$D/설명서/3_지원동글.txt"
cp "$ROOT/NOTICE.md"            "$D/설명서/4_라이선스와출처.txt"
cp "$ROOT/CHANGELOG.md"         "$D/설명서/5_변경기록.txt"
cp "$ROOT/LICENSE"              "$D/설명서/LICENSE_AGPL-3.0.txt"
cp "$ROOT/ADDITIONAL-TERMS.md"   "$D/설명서/6_포크와상업이용.txt"
rm -f "$OUT/$NAME.zip"
# 한글 파일 이름: NFC + UTF-8 표시(윈도우에서 깨지지 않게)
python3 -I - "$W" "$NAME" "$OUT/$NAME.zip" <<'PY'
import os,sys,zipfile,unicodedata as u
w,n,o=sys.argv[1:4]
with zipfile.ZipFile(o,'w',zipfile.ZIP_DEFLATED) as z:
    for r,ds,fs in os.walk(os.path.join(w,n)):
        ds.sort()
        for f in sorted(fs):
            if f=='.DS_Store': continue
            a=os.path.join(r,f); z.write(a,u.normalize('NFC',os.path.relpath(a,w)))
PY
case "$W" in */tmp.*) rm -r "${W:?}/$NAME" && rmdir "$W";; esac; echo "$OUT/$NAME.zip"
