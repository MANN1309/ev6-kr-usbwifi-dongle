#!/bin/sh
# 설치 USB 묶음(zip) 만들기. 사용: sh usb/만들기.sh [--pre] <usbwifi.hotspot.zip> <출력폴더>
#   --pre: 시험판(Pre-release). 목록 이름에 "beta"가 붙는다. 없으면 안정판.
# 버전과 날짜는 손으로 쓰지 않는다: 넣는 패키지 zip 안의 NEMESIS.data(package-version)와 오늘 날짜로
# usb/NEMESIS.data, usb/먼저_읽어주세요.txt 의 {{VER}} {{DATE}} 를 채운다. 끝나면 usb/릴리스_검사.py 가 묶음을 검사하고,
# 하나라도 틀리면 묶음을 지우고 멈춘다 (예전 버전 문구, 서명, 설명 길이, 숨김 파일, 안정판의 실험 드라이버 등).
set -e
KIND=stable; [ "$1" = "--pre" ] && { KIND=pre; shift; }
PKG="$1"; OUT="$2"; [ -f "$PKG" ] && [ -d "$OUT" ] || { echo "usage: $0 [--pre] <usbwifi.hotspot.zip> <out_dir>"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(unzip -p "$PKG" NEMESIS.data | sed -n 's/^package-version=//p' | tr -d '\r')
[ -n "$VER" ] || { echo "no package-version in $PKG"; exit 1; }
LVER=$VER; [ $KIND = pre ] && LVER="$VER beta"
TODAY=$(date +%Y-%m-%d)
NAME="EV6-dongle-USB-v$VER"
W=$(mktemp -d); D="$W/$NAME"
mkdir -p "$D/packages" "$D/설명서"
for f in NEMESIS.data 먼저_읽어주세요.txt; do
    sed -e "s/{{VER}}/$VER/g" -e "s/(KR v$VER)/(KR v$LVER)/g" -e "s/{{DATE}}/$TODAY/g" "$ROOT/usb/$f" > "$D/$f"
done
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
case "$W" in */tmp.*) rm -r "${W:?}/$NAME" && rmdir "$W";; esac
if ! python3 -I "$ROOT/usb/릴리스_검사.py" --$KIND "$OUT/$NAME.zip"; then
    rm -f "$OUT/$NAME.zip"; echo "릴리스 검사 실패: 묶음을 지웠습니다 ($OUT/$NAME.zip)"; exit 1
fi
echo "$OUT/$NAME.zip"
