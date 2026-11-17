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
echo "USB Wi-Fi v4: $d, $w, $c, hotspot signal sys.kp.aa_ap=$(getprop sys.kp.aa_ap)"
# a USB stick is plugged in: save a full log bundle there (in the background; a toast says when it is done)
for _u in ${USBS:-/storage/usb0 /storage/usb1 /storage/usb2}; do
    [ -d "${ROOT:-}$_u" ] || continue
    sh ./bin/collect.sh "${ROOT:-}$_u" </dev/null >/dev/null 2>&1 &
    echo "로그를 USB($_u)의 EV6_LOG 폴더에 저장 중 (약 1분, 끝나면 안내가 뜹니다)"
    break
done
exit 0
