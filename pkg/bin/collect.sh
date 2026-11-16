#!/system/bin/sh
# EV6 로그 수집 (읽기 전용: 차의 어떤 설정도 바꾸지 않음). 동글 패키지의 Launch가 부른다: 결과는 <USB>/EV6_LOG_<부팅후초> 폴더.
# 동글이 깜빡이지 않을 때 USB를 꽂고 Launch: USB 장치 목록, 드라이버, wlan0, 동글 서비스가 살아 있는지, KP 핫스팟 로그,
# 커널 로그(dmesg), logcat을 모은다. 4.11: 모든 파일은 개인정보 필터(kr/common.sh scrub_file)를 거쳐 저장한다:
# 연락처·통화기록·재생곡·위치·전화번호·기기 이름·Wi-Fi 이름과 비밀번호 줄은 빼고, 블루투스/Wi-Fi 주소는 끝 2바이트만 남긴다.
export PATH=${KR_TEST_PATH:+$KR_TEST_PATH:}/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
U=${1:?usage: collect.sh <USB folder>}
# the privacy filter: without it nothing is collected (status.sh starts us in the package folder)
[ -f ./kr/common.sh ] && . ./kr/common.sh
command -v scrub_file >/dev/null 2>&1 || { echo "$(date) privacy filter (kr/common.sh) not found in $PWD: nothing collected" | tee "$U/EV6_LOG_FAILED.txt"; exit 1; }
W=${ROOT:-}/data/local/tmp/usbwifi_hotspot/collect.tmp; mkdir -p "${W%/*}" 2>/dev/null
sc() { scrub_file "$1" "$2" 2>> "$E"; }   # filtered copy
sx() { "$@" > "$W" 2>> "$E"; }            # command output to the work file, then sc "$W" <out>
read -r UP _ < /proc/uptime
UP=${UP%%.*}
O="$U/EV6_LOG_up$UP"
mkdir -p "$O" || { echo "USB에 쓸 수 없음"; exit 1; }
E="$O/00_errors.txt"
step() { echo "$(date) $*" >> "$O/00_steps.txt"; }
step "start (uptime ${UP}s)"
{
  echo "date: $(date)"; echo "uptime: $UP"
  echo "product: $(getprop ro.build.product)"
  echo "sys.kp.aa_ap=$(getprop sys.kp.aa_ap)  service.adb.tcp.port=$(getprop service.adb.tcp.port)  persist.sys.iap2.wifi=$(getprop persist.sys.iap2.wifi)"
  echo "wlan.driver.status=$(getprop wlan.driver.status)  wifi_on=$(settings get global wifi_on 2>/dev/null)"
  echo; echo "== /sys/class/net"
  for n in /sys/class/net/*; do
    i=; read -r i < "$n/ifindex" 2>/dev/null; s=; read -r s < "$n/operstate" 2>/dev/null
    drv=$(readlink "$n/device/driver" 2>/dev/null); echo "${n##*/} ifindex=$i state=$s driver=${drv##*/}"
  done
  echo; echo "== USB devices (vendor:product, interface drivers)"
  for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] || continue
    v=; p=; m=; read -r v < "$d/idVendor"; read -r p < "$d/idProduct"; read -r m < "$d/product" 2>/dev/null
    echo "${d##*/} $v:$p $m"
    for f in "$d"/*:*; do [ -d "$f" ] || continue; x=$(readlink "$f/driver" 2>/dev/null); echo "   ${f##*/} driver=${x##*/}"; done
  done
  echo; echo "== modules"; cat /proc/modules
  echo; echo "== 88x2bu srcversion: $(cat /sys/module/88x2bu/srcversion 2>/dev/null)  (bundled = 46A9CFB83C8F6E0C09E8AAC)"
  echo; echo "== chip mark: $(ls -l /data/hmgapi/public/wifi-chip 2>&1)"
  echo; echo "== our dongle service (dongle.sh) and KP processes"
  for f in /proc/[0-9]*/cmdline; do
    c=$(cat "$f" 2>/dev/null | while IFS= read -r l; do echo "$l"; done)
    case "$c" in *dongle.sh*|*hotspot.sh*|*hostapd*|*dnsmasq*|*wpa_supplicant*|*ev6.devadb*) p=${f#/proc/}; echo "${p%/cmdline}: $c" ;; esac
  done
} > "$W" 2>> "$E"; sc "$W" "$O/01_state.txt"
step "state done"
# 동글 서비스 로그와 NEMESIS 서비스 출력(스크립트 오류가 여기에 남음)
mkdir -p "$O/dongle" "$O/nemesis_logs"
for f in /data/local/tmp/usbwifi_hotspot/*; do
  [ -f "$f" ] || continue
  case "${f##*/}" in *.conf) continue ;; esac   # 예전 판의 hostapd 설정(비밀번호)은 가져오지 않음
  sc "$f" "$O/dongle/${f##*/}"
done
for d in /data/nemesis/logs/*; do
  [ -d "$d" ] || continue
  mkdir -p "$O/nemesis_logs/${d##*/}"
  for f in "$d"/*; do [ -f "$f" ] && sc "$f" "$O/nemesis_logs/${d##*/}/${f##*/}"; done
done
mkdir -p "$O/hmgapi"
for f in /data/hmgapi/*.log /data/hmgapi/logs/* /data/hmgapi/logs/*/*; do
  [ -f "$f" ] || continue
  g=${f#/data/hmgapi/}
  case $g in */*) mkdir -p "$O/hmgapi/${g%/*}" 2>/dev/null ;; esac
  sc "$f" "$O/hmgapi/$g"
done
step "logs copied"
# KP 작업 폴더(상태·진행 기록). hostapd 설정은 비밀번호와 SSID를 가린다
mkdir -p "$O/kp"
for f in /data/local/tmp/korea.projection/*; do
  [ -f "$f" ] || continue
  case "${f##*/}" in *.pid|*.txt|*.log|aa.why|nowlan*) sc "$f" "$O/kp/${f##*/}" ;; esac
done
if [ -f /data/misc/wifi/hostapd-kp.conf ]; then
  while IFS= read -r l; do case "$l" in wpa_passphrase=*|ssid=*) echo "${l%%=*}=(가림)" ;; *) echo "$l" ;; esac; done < /data/misc/wifi/hostapd-kp.conf > "$W"
  sc "$W" "$O/kp/hostapd-kp.conf.masked"
fi
for f in /data/local/tmp/korea-projection-*.txt; do [ -f "$f" ] && sc "$f" "$O/kp/${f##*/}"; done
step "kp done"
sx dmesg; sc "$W" "$O/02_dmesg.txt"
sx logcat -d -v threadtime; sc "$W" "$O/03_logcat.txt"
sx logcat -d -b system -v threadtime; sc "$W" "$O/04_logcat_system.txt"
rm -f "$W"
step "dmesg/logcat done"
sync
step "end"
am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "EV6 로그 수집 끝: USB를 빼도 됩니다" >/dev/null 2>&1
exit 0
