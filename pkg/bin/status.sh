#!/system/bin/sh
# NEMESIS Launch: one-screen status
export PATH=${KR_TEST_PATH:+$KR_TEST_PATH:}/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# the package folder: the installed copy first (works whatever the start folder and $0 look like), else relative to this file
_P=${ROOT:-}/data/nemesis/apps/usbwifi.hotspot
[ -d "$_P" ] || _P=${ROOT:-}/data/nemesis/packages/usbwifi.hotspot
if [ -d "$_P" ]; then cd "$_P"; else cd "${0%/*}/.." 2>/dev/null; fi
[ -f ./kr/common.sh ] || { echo "usbwifi.hotspot v4: package files not found (cwd $PWD)"; exit 1; }
. ./kr/common.sh
_sv=; [ -r "$SRCV" ] && read -r _sv < "$SRCV"
case $_sv in "$DRV_SRCVERSION") d="bundled driver loaded" ;; "") d="driver NOT loaded" ;; *) d="old driver loaded (restart needed)" ;; esac
kernel_ok || d="driver NOT loaded: this firmware's kernel is not supported (needs $KERNEL_WANT)"
[ -d "$SYSNET/wlan0" ] && w="wlan0 present" || w="no wlan0 (dongle?)"
[ -f "$CHIP" ] && c="chip mark yes" || c="chip mark NO"
if grep -q "^8851bu " "$MODS" 2>/dev/null; then d="$d; RTL8851BU experimental driver loaded"
elif [ -f "$EXP8851_OFF" ]; then d="$d; RTL8851BU experimental driver switched off"; fi
echo "USB Wi-Fi v4: $d, $w, $c, hotspot signal sys.kp.aa_ap=$(getprop sys.kp.aa_ap)"
# 4.13.1: pressing Launch = copy the logs to the USB stick (only then; nothing is copied when a stick is plugged in).
# collect.sh runs in the background and shows the car's messages: copying... / done, you can pull the stick / failed.
_got=
for _u in $USBS; do
    [ -d "${ROOT:-}$_u" ] || continue
    usb_mounted "$_u" || continue
    sh ./bin/collect.sh "${ROOT:-}$_u" </dev/null >/dev/null 2>&1 &
    echo "로그를 복사하는 중... ($_u 의 EV6_LOG 폴더). '로그 복사를 완료하였습니다' 안내가 뜰 때까지 USB를 빼지 마세요"
    _got=1
    break
done
[ -n "$_got" ] || echo "USB가 꽂혀 있지 않아 로그를 복사하지 않았습니다 (로그가 필요하면 USB를 꽂고 다시 실행)"
exit 0
