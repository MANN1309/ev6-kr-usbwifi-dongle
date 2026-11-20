#!/system/bin/sh
# preuninstall (root): stop the service, remove the chip mark if we made it, keep the driver (no rmmod: it goes at
# the next restart), remove the HMG-API mod that came with it (4.9). On an update (new package staged) the mark and the mod stay.
export PATH=${KR_TEST_PATH:+$KR_TEST_PATH:}/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -f kr/log.sh ] && . kr/log.sh && hlog_begin preuninstall
. ./kr/common.sh
if [ -f "$T/dongle.pid" ]; then
    _p=; read -r _p < "$T/dongle.pid" 2>/dev/null
    case $_p in ''|*[!0-9]*) ;; *) grep -q dongle.sh "${ROOT:-}/proc/$_p/cmdline" 2>/dev/null && kill "$_p" 2>/dev/null ;; esac
    rm -f "$T/dongle.pid"
fi
for _u in /storage/usb0 /storage/usb1 /storage/usb2; do
    [ -d "${ROOT:-}$_u" ] || continue
    mkdir -p "${ROOT:-}$_u/HMGAPI-LOGS" 2>/dev/null
    cat "$LOG" > "${ROOT:-}$_u/HMGAPI-LOGS/usbwifi-v4-daemon.log" 2>/dev/null
done
STAGE=${ROOT:-}/data/local/tmp/nemesis/stage/usbwifi.hotspot
case $(cat "${ROOT:-}/proc/$PPID/cmdline" 2>/dev/null) in
    *uninstall*) ;;
    *) if grep -q "^id=usbwifi.hotspot\$" "$STAGE/NEMESIS.data" 2>/dev/null; then echo "update: chip mark kept"; exit 0; fi ;;
esac
# 4.9: the HMG-API mod that came with this package (wireless AA keep + plug-in notices)
_h=${ROOT:-}/system/bin/hmgapid
if [ -d "${ROOT:-}/data/hmgapi/mods/ev6-kr-aa-keep" ]; then
    if [ -x "$_h" ]; then
        "$_h" ping >/dev/null 2>&1 || "$_h" daemon >/dev/null 2>&1
        if "$_h" engine remove ev6-kr-aa-keep --from-nemesis; then
            "$_h" engine apply || echo "WARNING: the mod is removed from HMG-API, but apply reported a problem: open the HMG-API app and tap Apply changes"
            echo "removed the HMG-API mod ev6-kr-aa-keep (AA keep-connected, plug-in notices); restart the head unit"
        else
            echo "WARNING: HMG-API didn't remove ev6-kr-aa-keep (see above): remove it in the HMG-API app"
        fi
    else
        rm -rf "${ROOT:-}/data/hmgapi/mods/ev6-kr-aa-keep"
        echo "HMG-API isn't installed: removed ev6-kr-aa-keep from /data/hmgapi/mods"
    fi
fi
rm -f "$T/aakeep.log" "$T/aakeep.old.log" "$T/plugquiet.log" "$T/plugquiet.log.old"
if [ -f "$CHIP_OURS" ]; then
    rm -f "$CHIP" "$CHIP_OURS"
    echo "removed the Wi-Fi chip mark (HMG-API mods that need a Wi-Fi chip are off after the next restart)"
fi
rm -f "$EXP8851_OFF" "$EXP8851_GUARD"
rm -f "$LOG" "$T/daemon.prev.log" "$T/daemon.old.log"
rmdir "$T" 2>/dev/null
echo "removed. The dongle driver stays loaded until the next restart (never unloaded while running)."
exit 0
