#!/bin/bash
# 안정판(Latest) 패키지 zip 만들기: pkg/ 그대로에서 RTL8851BU 실험 드라이버만 뺀다 (그 드라이버는 시험판에만).
#   빠지는 것: modules/8851bu.ko, source/driver8851/, NOTICE.txt의 8851 문단, 설명의 "EXPERIMENTAL RTL8851BU" 문장.
#   코드는 같다: 8851bu.ko가 없으면 서비스가 "this build has no RTL8851BU driver"라고만 기록하고 넘어간다.
# 사용: bash 안정판_만들기.sh <출력 zip>
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; OUT="${1:?usage: 안정판_만들기.sh <out.zip>}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp -R "$H/pkg" "$W/pkg"; find "$W/pkg" -name .DS_Store -delete
rm -f "$W/pkg/modules/8851bu.ko"; rm -rf "$W/pkg/source/driver8851"
python3 -I - "$W/pkg" <<'PY'
import sys,os,re
p=sys.argv[1]
n=os.path.join(p,'NOTICE.txt'); L=open(n,encoding='utf-8').read().split('\n'); out=[]; skip=False
for l in L:
    if l.startswith('modules/8851bu.ko'): skip=True
    if not skip: out.append(l)
    if skip and 'source/driver8851/.' in l: skip=False
assert not any('8851' in l for l in out), 'NOTICE still names 8851'
open(n,'w',encoding='utf-8').write('\n'.join(out))
m=os.path.join(p,'NEMESIS.data'); s=open(m,encoding='utf-8').read()
s2=s.replace(' EXPERIMENTAL RTL8851BU driver, untested.','')
assert s2!=s and '8851' not in s2, 'descriptor still names 8851'
open(m,'w',encoding='utf-8').write(s2)
PY
rm -f "$OUT"; (cd "$W/pkg" && zip -q -X -D -r "$OUT" . )
N="$H/../../02_네메시스_설치/원본_다운로드/NEMESIS_적용파일/01_NEMESIS/src/Sources/native"; C="$H/../../00_공통기준/NEMESIS_설명파일_검사기"
cc -I"$N" -o "$W/check" "$C/check.c" "$N/ini.c" "$N/meta.c" 2>/dev/null && "$W/check" "$W/pkg/NEMESIS.data"
echo "stable zip: $OUT ($(unzip -l "$OUT" | grep -c 8851) entries naming 8851)"
