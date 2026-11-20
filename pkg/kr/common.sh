# usbwifi.hotspot v4 (KR, for Korea Projection): shared settings. Every path can be moved with ROOT (off-car tests).
# Shell rules for this head unit: no od/tail/head/tr/printf/md5sum/wc (Android 4.4 toolbox, no busybox); must pass dash/ksh/bash -n.
APPS=${ROOT:-}/data/nemesis/apps/usbwifi.hotspot
[ -d "$APPS" ] || APPS=${ROOT:-}/data/nemesis/packages/usbwifi.hotspot
T=${ROOT:-}/data/local/tmp/usbwifi_hotspot          # logs (aa-keep writes aakeep.log here too)
LOG=$T/daemon.log
SYSNET=${SYSNET:-${ROOT:-}/sys/class/net}
MODS=${MODS:-${ROOT:-}/proc/modules}
SRCV=${SRCV:-${ROOT:-}/sys/module/88x2bu/srcversion}
# the bundled 88x2bu build (GPL-2.0, source in source/driver): blocks usbfs while bound, survives a surprise unplug
DRV_SRCVERSION=46A9CFB83C8F6E0C09E8AAC
# 4.12: the bundled driver was built for this kernel (car: "Linux version 3.18.24-tcc (...) #1 SMP PREEMPT ...").
# Other EV6 KR firmware may install now; on a different kernel the driver is not loaded at all (no crash risk).
KERNEL_WANT=3.18.24-tcc
kernel_ok() {
    kv=; read -r kv < "$PROC/version" 2>/dev/null
    [ -n "$kv" ] || return 0        # no /proc/version (off-car): insmod's own version check still applies
    case "$kv" in *" $KERNEL_WANT "*"SMP PREEMPT"*) return 0 ;; esac
    return 1
}
# 4.13 EXPERIMENTAL: RTL8851BU (AX900) dongles, driver modules/8851bu.ko (GPL-2.0, source in source/driver8851).
# Not tested with the real dongle. Loaded only when one of these USB IDs is plugged in; a boot guard turns it off
# if a load ever did not finish (head unit restarted while loading). Make EXP8851_OFF to switch it off by hand.
ID8851=" 0bda:b851 3625:010b 7392:e611 "
# power save (IPS/LPS) is off in this build: CONFIG_RTW_IPS/LPS are not set, so the defaults are PS_OP_MODE_DISABLED
KO8851_ARGS='ifname=rtwlan%d if2name=rtwlan%d rtw_country_code=KR rtw_en_napi=0 rtw_en_gro=0 rtw_usbfs_block=1'
EXP8851_OFF=${ROOT:-}/data/nemesis/usbwifi-v4.8851.off
EXP8851_GUARD=${ROOT:-}/data/nemesis/usbwifi-v4.8851.loading
KO_ARGS='ifname=rtwlan%d if2name=rtwlan%d rtw_country_code=KR rtw_power_mgnt=0 rtw_ips_mode=0 rtw_enusbss=0 rtw_en_napi=0 rtw_en_gro=0 rtw_usbfs_block=1'
PROC=${PROC:-${ROOT:-}/proc}
KPW=${KPW:-${ROOT:-}/data/local/tmp/korea.projection}          # Korea Projection's work folder (dnsmasq.pid, ap.log)
NOACCEL=${NOACCEL:-${ROOT:-}/data/nemesis/usbwifi-v4.noaccel}   # make this file to switch the replug accelerator off
# HMG-API and Korea Projection both read this file as "this car has a Wi-Fi chip" (hmgapi.wifi)
CHIP=${ROOT:-}/data/hmgapi/public/wifi-chip
CHIP_OURS=${ROOT:-}/data/nemesis/usbwifi-v4.chip-ours
# also to logcat (tag USBWifiHotspot, shown by the Mac signal monitor)
vlog() { echo "$(date) $*" >> "$LOG" 2>/dev/null; log -t USBWifiHotspot "v4: $*" 2>/dev/null; }

# 4.11 privacy filter for every log that can leave the car (USB copies, drop logs, Launch log bundle).
# Lines from sources that carry personal data are left out (contacts, call log, phonebook, messages, songs and
# artists, location, connected-car service, phone/SIM ids, device names, Wi-Fi names and passwords, phone numbers);
# Bluetooth/Wi-Fi addresses keep only their last 2 bytes (xx:xx:xx:xx:12:E4), enough to tell devices apart.
# scrub_file <in> <out>: writes the filtered copy and a last line saying how many lines were left out.
priv_drop() {
    grep -v -i -e Contacts -e Pbap -e phonebook -e vcard -e CallLog -e SmsProvider -e SmsMessage -e MmsService -e msisdn \
        -e artist -e album -e title= -e metadata -e PLAYER_MANAGER -e SplitScreen -e AvrcpController -e nowplaying \
        -e CoNA -e Mqtt -e System.out -e VoiceMemo -e AdvancedLauncher -e RILJ -e DataCall -e onDataStateChanged \
        -e imei -e imsi -e iccid -e serialno -e android_id -e latitude -e longitude -e GpsLocation -e LocationManager -e LocationProvider -e lat= -e lon= -e geo: \
        -e " name=" -e mName -e deviceName -e friendlyName -e "device name" -e alias -e ssid -e passphrase -e psk= -e password \
        -e "+82" -e "01[016789]-[0-9][0-9][0-9]" -e "3[3-8][.][0-9][0-9][0-9][0-9].*1[23][0-9][.][0-9][0-9][0-9][0-9]" "$1" 2>/dev/null
}
# 4.13.1: the car has no wc (2026-11-20 logs: "( bytes)", filter counts always 0): count lines with grep
lines_of() { _lc=$(grep -c "" "$1" 2>/dev/null); echo "${_lc:-0}"; }
# a USB stick is really mounted there (the /storage/usbN folders exist without a stick)
usb_mounted() { [ -f "$PROC/mounts" ] || return 0; grep -q " $1 " "$PROC/mounts" 2>/dev/null; }
USBS=${USBS:-/storage/usb0 /storage/usb1 /storage/usb2}
scrub_file() {
    _sa=0; [ -f "$1" ] && _sa=$(lines_of "$1")
    priv_drop "$1" | while IFS= read -r _sl; do
        case "$_sl" in
            *[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]*)
                _sl=${_sl//[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:/xx:xx:xx:xx:} ;;
        esac
        echo "$_sl"
    done > "$2"
    _sr=$?
    _sb=$(lines_of "$2")
    echo "== privacy filter (usbwifi.hotspot): $((${_sa:-0} - ${_sb:-0})) lines with personal data left out, addresses show only the last 2 bytes" >> "$2"
    return $_sr
}
