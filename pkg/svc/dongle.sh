#!/system/bin/sh
# usbwifi.hotspot v4 service: makes the T3U Nano dongle look like the car's own Wi-Fi so that Korea Projection
# (korea.projection, unmodified) runs the hotspot on it. This service runs NO hostapd and NO dnsmasq.
#  1. load the bundled 88x2bu driver as early as possible (before Android's USB host service sees the dongle: its usbfs
#     block then keeps the stock Android Auto service from probing the dongle as a phone)
#  2. mark "Wi-Fi chip present" for HMG-API / Korea Projection (only if nobody else did; removed at uninstall)
#  3. the dongle's interface (the one bound to the USB device, highest index) becomes wlan0, the name the stock
#     Android Auto app and Korea Projection use; again after every replug
# Never rmmod the driver (it can reboot the head unit). It goes away at the next restart.
export PATH=${KR_TEST_PATH:+$KR_TEST_PATH:}/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# the package folder: the installed copy first (works whatever the start folder and $0 look like), else relative to this file
_P=${ROOT:-}/data/nemesis/apps/usbwifi.hotspot
[ -d "$_P" ] || _P=${ROOT:-}/data/nemesis/packages/usbwifi.hotspot
if [ -d "$_P" ]; then cd "$_P"; else cd "${0%/*}/.." 2>/dev/null; fi
[ -f ./kr/common.sh ] || { echo "usbwifi.hotspot v4: package files not found (cwd $PWD)"; exit 1; }
. ./kr/common.sh
mkdir -p "$T" 2>/dev/null; chmod 1777 "$T" 2>/dev/null   # aa-keep (inside the AA app, not root) writes aakeep.log here
[ -f "$LOG" ] && mv -f "$LOG" "$T/daemon.prev.log" 2>/dev/null
echo $$ > "$T/dongle.pid"
vlog "start v4 (pid $$)"
trap 'vlog "stop"; rm -f "$T/dongle.pid"; exit 0' TERM INT HUP

loaded() { grep -q "^88x2bu " "$MODS" 2>/dev/null; }
loaded8851() { grep -q "^8851bu " "$MODS" 2>/dev/null; }
load_driver() {
    if loaded; then
        _sv=; read -r _sv < "$SRCV" 2>/dev/null
        if [ "$_sv" = "$DRV_SRCVERSION" ]; then vlog "driver: bundled 88x2bu already loaded"
        else vlog "driver: another 88x2bu is loaded (srcversion ${_sv:-?}): restart the head unit to use the bundled driver"; fi
        return 0
    fi
    insmod ./modules/88x2bu.ko $KO_ARGS 2>> "$LOG"
    _rc=$?
    vlog "driver: insmod bundled 88x2bu rc=$_rc"
    [ $_rc = 0 ]
}
mark_chip() {
    [ -f "$CHIP" ] && return 0
    [ -d "${ROOT:-}/data/hmgapi" ] || return 1          # HMG-API not installed (yet): try again later
    mkdir -p "${CHIP%/*}" 2>/dev/null
    if : > "$CHIP" 2>/dev/null; then
        chmod 644 "$CHIP" 2>/dev/null
        : > "$CHIP_OURS"
        vlog "marked Wi-Fi chip present ($CHIP) for HMG-API / Korea Projection"
        return 0
    fi
    vlog "FAIL: could not create $CHIP"
    return 1
}
# the dongle's interface: bound to a USB device (has device/driver), not wlan0, highest ifindex
dongle_if() {
    _best=; _bi=-1
    for _n in "$SYSNET"/rtwlan* "$SYSNET"/wlan[1-9]*; do
        [ -d "$_n" ] || continue
        [ -e "$_n/device/driver" ] || continue
        _i=; read -r _i < "$_n/ifindex" 2>/dev/null
        case $_i in ''|*[!0-9]*) continue ;; esac
        [ "$_i" -gt "$_bi" ] && { _bi=$_i; _best=${_n##*/}; }
    done
    echo "$_best"
}
name_wlan0() {
    [ -d "$SYSNET/wlan0" ] && return 0
    _d=$(dongle_if)
    [ -n "$_d" ] || return 1
    ip link set "$_d" down >/dev/null 2>&1
    if ip link set "$_d" name wlan0 >/dev/null 2>&1; then
        vlog "renamed $_d to wlan0"
        return 0
    fi
    ip link set "$_d" up >/dev/null 2>&1
    vlog "FAIL: could not rename $_d to wlan0"
    return 1
}

# any USB stick plugged in: copy our logs (and aa-keep's) to <stick>/usbwifi_hotspot_log once per plug-in.
# 2026-11-14: the stick came back with 0-byte files: copy only once the stick is really mounted (in /proc/mounts) and has
# settled for 3 s, write to a temp name, move, sync, and check the size; every result (or failure) is logged.
USBS=${USBS:-/storage/usb0 /storage/usb1 /storage/usb2}
usb_seen=
usb_first=
copy_n=0
mounted() { [ -f "$PROC/mounts" ] || return 0; grep -q " $1 " "$PROC/mounts" 2>/dev/null; }
copy_logs() {
    _now=
    for _u in $USBS; do
        [ -d "${ROOT:-}$_u" ] || continue
        mounted "$_u" || continue
        _now="$_now $_u"
        case " $usb_seen " in *" $_u "*) continue ;; esac
        _up=$(uptime_s)
        case " $usb_first " in
            *" $_u="*) _f0=${usb_first#*" $_u="}; _f0=${_f0%% *} ;;
            *) usb_first="$usb_first $_u=$_up "; _f0=$_up ;;
        esac
        [ $((_up - _f0)) -ge ${USB_SETTLE:-3} ] || { _now=${_now% $_u}; continue; }
        # 2026-11-14 17:27: on the stick, writing over the old files and renaming failed ("(write)", .tmp files left):
        # each copy now goes to a new folder usbwifi_hotspot_log/up<uptime>_<n> (new files only, no rename)
        _o="${ROOT:-}$_u/usbwifi_hotspot_log/up${_up}_$((copy_n + 1))"
        mkdir -p "$_o" 2>/dev/null || { vlog "FAIL: logs not copied: can't make $_o"; continue; }
        copy_n=$((copy_n + 1))
        _n=0; _bad=
        for _f in "$T"/*.log; do
            [ -f "$_f" ] || continue
            _b=${_f##*/}
            # 4.11: copies go through the privacy filter (kr/common.sh scrub_file); the filter's last line proves the write
            if scrub_file "$_f" "$_o/$_b" 2>/dev/null && grep -q "^== privacy filter" "$_o/$_b" 2>/dev/null; then _n=$((_n + 1))
            else _bad="$_bad $_b(write)"; fi
        done
        dmesg > "$T/dmesg.tmp" 2>/dev/null && scrub_file "$T/dmesg.tmp" "$_o/dmesg.txt" 2>/dev/null; rm -f "$T/dmesg.tmp"
        sync
        if [ -z "$_bad" ]; then vlog "logs copied to ${_o#${ROOT:-}} ($_n files)"
        else vlog "FAIL: logs copied to ${_o#${ROOT:-}} with problems:$_bad"; fi
    done
    usb_seen=$_now
    # forget the first-seen time of sticks that were pulled out
    _keep=
    for _w in $usb_first; do
        _wu=${_w%%=*}
        [ -d "${ROOT:-}$_wu" ] && _keep="$_keep $_w "
    done
    usb_first=$_keep
}

uptime_s() {
    _u=0
    [ -r "$PROC/uptime" ] && read -r _u _ < "$PROC/uptime"
    echo "${_u%%.*}"
}
# ---- Korea Projection helpers. KP re-checks the hotspot only every 30 s (its main loop is "sleep 30 & wait"), and its
# dnsmasq/hostapd are bound to the old wlan0 after a replug. We never edit KP: we only end its own processes (the ones
# KP itself restarts when it finds them dead) and end the sleep of its loop so it checks right away.
# $1 is a regex written with [.] so that the grep's own command line (which holds "[.]") never matches itself
# (2026-11-12 car log: without this every check saw "hostapd running" = the grep itself)
kp_pids() {   # pids whose command line contains $1
    for _f in $(grep -l "$1" "$PROC"/[0-9]*/cmdline 2>/dev/null); do
        _p=${_f#$PROC/}; echo "${_p%/cmdline}"
    done
}
kp_main() {   # the KP service shell: the hotspot.sh process whose parent is not hotspot.sh too
    _all=" "
    for _x in $(kp_pids "korea[.]projection/svc/hotspot[.]sh"); do _all="$_all$_x "; done
    for _p in $_all; do
        _pp=; read -r _a _b _c _pp _r < "$PROC/$_p/stat" 2>/dev/null || continue
        case "$_all" in *" $_pp "*) continue ;; esac
        echo "$_p"; return 0
    done
    return 1
}
kp_kick() {   # $1 = why
    _m=$(kp_main) || { vlog "kick ($1): the Korea Projection service was not found"; return 1; }
    _n=0
    # KP's waits ("sleep 10 & wait", "sleep 30 & wait") are children of KP's main shell. On this car (2026-11-13/14
    # process lists) they show as "(sh)", not "(sleep)": the shell runs sleep inside a forked copy of itself. Such a
    # waiting copy sits in the kernel's timer wait: "poll_schedule_timeout" on this car (2026-11-14 17:25 list: KP's
    # copies 2930, 3639, 4145, 4445 - a new one every 10 s), "nanosleep" elsewhere - and has no children. KP's
    # permission task (fix.pid) is never touched, nor any copy that waits on something else (KP's log readers: a pipe).
    _fx=; read -r _fx _fb < "$KPW/fix.pid" 2>/dev/null
    _par=" "
    for _d in "$PROC"/[0-9]*; do _pp=; read -r _a _b _c _pp _r < "$_d/stat" 2>/dev/null && _par="$_par$_pp "; done
    for _d in "$PROC"/[0-9]*; do
        _q=${_d#$PROC/}; _pp=; _b=
        read -r _a _b _c _pp _r < "$_d/stat" 2>/dev/null || continue
        [ "$_pp" = "$_m" ] || continue
        [ "$_q" = "$_fx" ] && continue
        case "$_b" in
            "(sleep)") ;;
            "(sh)")
                case "$_par" in *" $_q "*) continue ;; esac          # has children: not a plain wait
                _wc=; read -r _wc < "$_d/wchan" 2>/dev/null
                case "$_wc" in *nanosleep*|poll_schedule_timeout) ;; *) continue ;; esac ;;
            *) continue ;;
        esac
        kill "$_q" 2>/dev/null && _n=$((_n + 1))
    done
    vlog "kick ($1): KP service $_m checks now ($_n waits ended)"
    [ $_n -gt 0 ] && kick_ok_at=$(uptime_s)
    # 2026-11-13 car: every kick ended 0 waits. Every 20 s while that lasts, write which processes hang under KP
    # (name, state, parent) and KP's fix_perms pid, to see what KP's wait really is.
    if [ $_n = 0 ] && [ "$up" -ge "${kp_tree_next:-0}" ]; then
        kp_tree_next=$((up + 20))
        _fx=; read -r _fx _fb < "$KPW/fix.pid" 2>/dev/null
        _t=
        for _x in $(kp_pids "korea[.]projection/svc/hotspot[.]sh"); do
            _pp=; _st=; read -r _a _b _st _pp _r < "$PROC/$_x/stat" 2>/dev/null
            _t="$_t | KP$_x$_b/$_st parent=$_pp$( [ "$_x" = "$_fx" ] && echo ' (fix_perms)') kids:"
            for _d in "$PROC"/[0-9]*; do
                _pp=; _b=; _st=; read -r _a _b _st _pp _r < "$_d/stat" 2>/dev/null || continue
                [ "$_pp" = "$_x" ] && { _wc=; read -r _wc < "$_d/wchan" 2>/dev/null; _t="$_t ${_d#$PROC/}$_b/$_st/${_wc:-?}"; }
            done
        done
        vlog "kick ($1) found no wait: KP processes:$_t | main=$_m"
    fi
}
kp_stale() {   # after a replug KP's hostapd and dnsmasq sit on the dead wlan0: end them, KP starts new ones
    _k=0
    for _q in $(kp_pids "hostapd-kp[.]conf"); do kill "$_q" 2>/dev/null && _k=$((_k + 1)); done
    _dp=; _db=; _dc=
    read -r _dp _db < "$KPW/dnsmasq.pid" 2>/dev/null
    case $_dp in ''|*[!0-9]*) ;; *)
        read -r _a _dc _c < "$PROC/$_dp/stat" 2>/dev/null
        [ "$_dc" = "(dnsmasq)" ] && kill "$_dp" 2>/dev/null && _k=$((_k + 1)) ;;
    esac
    vlog "replug: $_k old KP hostapd/dnsmasq ended"
    stale_at=$(uptime_s)
}

# ---- "the dongle does not blink": the dongle only blinks while a hotspot runs on it. Two things can keep it dark,
# both handled here, both without touching /system or KP's files:
#  1. USB sees the dongle but no Wi-Fi interface appears (the driver did not take it): software replug (authorized 0 -> 1)
#  2. wlan0 is there but nobody starts the hotspot: start the same hostapd/dnsmasq KP would (same command lines, KP's
#     own pid file), so KP finds them running and adopts them. If the KP service is not running at all, also raise the
#     AA signal ourselves.
KPCONF=${KPCONF:-${ROOT:-}/data/misc/wifi/hostapd-kp.conf}
USBDEV=${USBDEV:-${ROOT:-}/sys/bus/usb/devices}
# 2026-11-13 car run: plug -> phone on AA took 36 s, ~25 s of it these waits (10 s hotspot, 10 s DHCP, 5 s AA signal);
# KP's own 30 s loop never acted first. Now: 2 s each, then we start KP's hostapd/dnsmasq and raise the AA signal.
RADIO_WAIT=${RADIO_WAIT:-2}
DHCP_WAIT=${DHCP_WAIT:-2}
AASIG_WAIT=${AASIG_WAIT:-2}
KPBK=${KPBK:-${ROOT:-}/data/nemesis/backup/korea.projection}
USB_WAIT=${USB_WAIT:-10}
AP_IP=192.168.43.1
DONGLE_IDS=" 0846:9055 0b05:1841 0b05:184c 0bda:b812 0bda:b82c 13b1:0043 13b1:0045 2001:331c 2001:331e 2001:331f 20f4:808a 2357:0115 2357:012d 2357:012e 2357:0138 7392:b822 7392:c822 "
dongle_usb() {   # the dongle's USB device folder, by vendor:product
    for _d in "$USBDEV"/*; do
        [ -f "$_d/idVendor" ] || continue
        _v=; _pr=; read -r _v < "$_d/idVendor"; read -r _pr < "$_d/idProduct"
        case "$DONGLE_IDS" in *" $_v:$_pr "*) echo "$_d"; return 0 ;; esac
    done
    return 1
}
present8851() {   # an RTL8851BU dongle is plugged in (by vendor:product)
    for _d in "$USBDEV"/*; do
        [ -f "$_d/idVendor" ] || continue
        _v=; _pr=; read -r _v < "$_d/idVendor"; read -r _pr < "$_d/idProduct"
        case "$ID8851" in *" $_v:$_pr "*) return 0 ;; esac
    done
    return 1
}
# 4.13 EXPERIMENTAL: load 8851bu.ko once per run when an RTL8851BU dongle is there (never for other dongles)
try8851=0
load_8851() {
    [ $try8851 = 0 ] || return 0
    loaded8851 && { try8851=1; return 0; }
    present8851 || return 0
    try8851=1
    if [ -f "$EXP8851_OFF" ]; then
        vlog "8851: RTL8851BU dongle found, experimental driver is switched off ($EXP8851_OFF); reinstall the package to try again"
        return 0
    fi
    [ -f ./modules/8851bu.ko ] || { vlog "FAIL: 8851: modules/8851bu.ko missing"; return 1; }
    echo "$(date) uptime $(uptime_s)s" > "$EXP8851_GUARD" 2>/dev/null; sync
    vlog "8851: RTL8851BU dongle found: loading the EXPERIMENTAL driver 8851bu (not tested with the real dongle)"
    insmod ./modules/8851bu.ko $KO8851_ARGS 2>> "$LOG"
    _rc=$?
    rm -f "$EXP8851_GUARD"; sync
    vlog "8851: insmod 8851bu rc=$_rc"
    [ $_rc = 0 ]
}
usb_reset() {   # $1 = device folder, $2 = why
    if echo 0 > "$1/authorized" 2>/dev/null; then
        sleep 2
        echo 1 > "$1/authorized" 2>/dev/null
        resets=$((resets + 1)); last_reset=$up
        vlog "usb: software replug #$resets of ${1##*/} ($2)"
    else
        vlog "usb: FAIL could not replug ${1##*/} ($2)"
    fi
}
usb_check() {   # case 1
    _d=$(dongle_usb) || { nb_since=0; return 0; }
    for _n in "$_d"/*:*/net; do [ -d "$_n" ] && { nb_since=0; resets=0; return 0; }; done
    [ $nb_since = 0 ] && { nb_since=$up; vlog "usb: dongle ${_d##*/} on USB, no Wi-Fi interface yet"; }
    [ $((up - nb_since)) -ge $USB_WAIT ] || return 0
    if [ $resets -lt 3 ] || [ $((up - last_reset)) -ge 120 ]; then usb_reset "$_d" "on USB but no Wi-Fi interface for $((up - nb_since))s"; nb_since=$up; fi
}
kp_dhcp_on() {
    _dp=; read -r _dp _db < "$KPW/dnsmasq.pid" 2>/dev/null
    case $_dp in ''|*[!0-9]*) return 1 ;; esac
    _dc=; read -r _a _dc _c < "$PROC/$_dp/stat" 2>/dev/null
    [ "$_dc" = "(dnsmasq)" ]
}
start_dhcp() {   # the same dnsmasq KP's up() starts, with KP's pid file (pid + boot id), so KP adopts it
    mkdir -p "$KPW" 2>/dev/null
    dnsmasq --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative --pid-file \
        --interface=wlan0 --bind-interfaces \
        --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 >/dev/null 2>&1 &
    echo "$! $(cat "$PROC/sys/kernel/random/boot_id" 2>/dev/null)" > "$KPW/dnsmasq.pid"
    vlog "radio watchdog: $1: started dnsmasq with KP's settings"
}
aa_allowed() {   # KP's own reasons to keep the AA signal off: AA switched off in KP, or the stock CarPlay AP path
    [ ! -f "$KPBK/aa-off" ] && [ ! -f "$KPBK/stockap.seen" ]
}
radio_check() {   # case 2
    [ -d "$SYSNET/wlan0" ] || { nr_since=0; dh_since=0; as_since=0; return 0; }
    [ -f "$KPCONF" ] || return 0          # KP has never set the hotspot up on this car: nothing to start
    if [ -n "$(kp_pids "hostapd-kp[.]conf")" ]; then
        nr_since=0
        if kp_dhcp_on; then dh_since=0
        else
            [ $dh_since = 0 ] && dh_since=$up
            if [ $((up - dh_since)) -ge $DHCP_WAIT ]; then
                start_dhcp "no DHCP on wlan0 for $((up - dh_since))s"
                dh_since=0
            fi
            return 0
        fi
        # hotspot and DHCP are up: the AA signal is what KP raises next (KP's aa_sig: hostapd + 192.168.43.1 on wlan0)
        if [ "$(getprop sys.kp.aa_ap)" != 1 ] && aa_allowed; then
            [ $as_since = 0 ] && as_since=$up
            if [ $((up - as_since)) -ge $AASIG_WAIT ] || ! kp_main >/dev/null; then
                ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
                setprop sys.kp.aa_ap 1
                if kp_main >/dev/null; then
                    vlog "radio watchdog: hotspot and DHCP up for $((up - as_since))s, KP has not raised the AA signal: set to 1 ourselves"
                else
                    vlog "radio watchdog: the KP service is not running: wireless AA signal set to 1 ourselves"
                fi
                as_since=0
            fi
        else
            as_since=0
        fi
        return 0
    fi
    [ $nr_since = 0 ] && nr_since=$up
    if [ "${in_grace:-0}" = 1 ] && [ $((up - ${kick_ok_at:--99})) -le 5 ]; then
        # KP answers our wake-ups: it is about to start its own hotspot (it would stop ours anyway, and an AA session
        # started on ours would drop) - wait for KP, at most 60 s from the plug-in
        [ "${grace_hold_told:-0}" = 0 ] && { grace_hold_told=1; vlog "radio watchdog: KP wakes up (its wait is ending): leaving the hotspot to KP"; }
        [ $((up - plug_up)) -lt 60 ] && return 0
    fi
    if [ "${kp_taking:-0}" = 1 ]; then
        [ "${take_since:-0}" = 0 ] && { take_since=$up; vlog "radio watchdog: KP is taking Wi-Fi over (its start after the wait): leaving the hotspot to KP for up to 30 s"; }
        [ $((up - take_since)) -lt 30 ] && return 0
    else
        take_since=0
    fi
    [ $((up - nr_since)) -ge $RADIO_WAIT ] || return 0
    radio_tries=$((radio_tries + 1))
    if [ $radio_tries -gt 3 ]; then
        _d=$(dongle_usb) && usb_reset "$_d" "hotspot would not stay up after 3 starts"
        radio_tries=0; nr_since=$up
        return 0
    fi
    ifconfig wlan0 $AP_IP netmask 255.255.255.0 up 2>/dev/null
    hostapd "$KPCONF" >/dev/null 2>&1 &
    our_hp=$!
    vlog "radio watchdog: no hotspot on wlan0 for $((up - nr_since))s: started hostapd with KP's settings (try $radio_tries)"
    kp_dhcp_on || start_dhcp "with the hotspot"
    dh_since=0
    nr_since=$up
}

# ---- KP's start-up wait: on a car without /system/bin/busybox (this one) KP waits up to 90 s for a stock CarPlay hotspot
# at every start ("순정 카플레이 AP를 최대 90초 기다림") before it touches wlan0. That is why the dongle stays dark for
# ~2 minutes after a restart (dmesg 2026-11-12: wlan0 ready at 11 s, first "NETDEV_UP" at 136 s). This car has no stock
# hotspot, so the wait is pointless: while KP's log says it is waiting and wlan0 is there, end its 10 s sleeps
# (each one counts 10 s of the 90).
KPLOG=${KPLOG:-${ROOT:-}/data/nemesis/logs/korea.projection/ap.log}
kp_in_grace() {
    # also sets kp_taking=1 while KP is between its start line ("시작 (", after the wait it stops the running hotspot,
    # turns Wi-Fi on and frees wlan0) and its own "hostapd 시작": our watchdog then leaves the hotspot to KP for a while
    kp_taking=0
    [ -f "$KPLOG" ] || return 1
    _n=0; _g=0; _s=0; _h=0
    while IFS= read -r _l; do
        _n=$((_n + 1))
        case "$_l" in
            *"순정 카플레이 AP를 최대"*) _g=$_n ;;
            *" 시작 ("*|*"다른 hostapd가 멈춤"*|*"순정 AP"*|*"다른 hostapd가 돌고 있음"*) _s=$_n ;;
            *"hostapd 시작"*|*"hostapd가 4초 안에 꺼짐"*) _h=$_n ;;
        esac
    done < "$KPLOG"
    [ $_s -gt $_h ] && [ $_s -gt $_g ] && kp_taking=1
    [ $_g -gt $_s ]
}
grace_told=0

# ---- detection logs (v4.6, to prove or disprove what we suspect before changing behaviour) -------------------------
# 1) Does KP stop the running hotspot when its 90 s boot wait ends (AA drop ~100 s after boot)? Log every hostapd that
#    ends while wlan0 stays, with how long it ran, who started it, KP's last log line and the AA signal; and the moment
#    KP's wait ends.
KPLAST=
kp_last_line() { KPLAST=; [ -f "$KPLOG" ] && while IFS= read -r _l; do KPLAST=$_l; done < "$KPLOG"; }
hp_pid=; hp_since=0; hp_by=; grace_was=0; hv_told=0; in_grace=0; tick_n=0; kp_taking=0; take_since=0
watch_hotspot() {
    _hp=; for _q in $(kp_pids "hostapd-kp[.]conf"); do _r=; read -r _a _r _c < "$PROC/$_q/stat" 2>/dev/null; [ "$_r" = "(hostapd)" ] && { _hp=$_q; break; }; done
    if [ "$_hp" != "$hp_pid" ]; then
        if [ -n "$hp_pid" ]; then
            kp_last_line
            _why=; [ $((up - ${stale_at:--99})) -le 3 ] && _why=" (ended by our replug cleanup: it sat on the unplugged dongle)"
            vlog "watch: hotspot hostapd $hp_pid (started by $hp_by) ENDED after $((up - hp_since))s$_why, wlan0 $( [ -d "$SYSNET/wlan0" ] && echo still-here || echo gone), AA signal $(getprop sys.kp.aa_ap), KP last: $KPLAST"
        fi
        if [ -n "$_hp" ]; then
            if [ "$_hp" = "${our_hp:-x}" ]; then hp_by=us; else hp_by=KP; fi
            vlog "watch: hotspot hostapd $_hp started by $hp_by (uptime ${up}s)"
            if [ $hv_told = 0 ]; then
                hv_told=1; _v=; _vn=0
                for _w in $(hostapd -v 2>&1); do _vn=$((_vn + 1)); [ $_vn -le 2 ] && _v="$_v $_w"; done
                _cf=; [ -f "$KPCONF" ] && while IFS= read -r _l; do case "$_l" in hw_mode=*|channel=*|ieee80211n=*|ieee80211ac=*|wmm_enabled=*|ht_capab=*|vht_*) _cf="$_cf $_l" ;; esac; done < "$KPCONF"
                _wm=" (no wmm_enabled line)"; case "$_cf" in *wmm_enabled=*) _wm= ;; esac
                vlog "watch: hostapd version:$_v | hotspot settings:$_cf$_wm"
            fi
            hp_since=$up
        fi
        hp_pid=$_hp
    fi
    # KP's log is read once per tick at most (first 10 min after boot, then every 10th tick)
    in_grace=0; tick_n=$((tick_n + 1))
    if [ "$up" -lt 600 ] || [ $((tick_n % 10)) = 0 ] || [ $grace_was = 1 ]; then kp_in_grace && in_grace=1; fi
    if [ $in_grace = 1 ]; then grace_was=1
    elif [ $grace_was = 1 ]; then
        grace_was=0; kp_last_line
        vlog "watch: KP's 90 s boot wait ENDED (uptime ${up}s), hotspot hostapd ${hp_pid:-none} by ${hp_by:-?}, AA signal $(getprop sys.kp.aa_ap), KP last: $KPLAST"
    fi
}

# 3) Which USB devices are plugged in: our dongles, dongles with the same chip that the driver does not know yet, and
#    other Wi-Fi dongles (chip guessed from the maker's default ID only) - once per device per plug-in.
SAME_CHIP_IDS=" 0bda:b81a 04ca:8602 056e:4011 0b05:1870 0b05:1874 0b05:19aa 0bda:2102 0e66:0025 20f4:805a 2357:0116 2357:0117 2c4e:0107 7392:d822 7392:e822 7392:f822 "
dev_seen=" "
usb_report() {
    _dnow=" "
    for _d in "$USBDEV"/*; do
        [ -f "$_d/idVendor" ] || continue
        case "${_d##*/}" in usb*|*:*) continue ;; esac
        _v=; _pr=; read -r _v < "$_d/idVendor"; read -r _pr < "$_d/idProduct"
        _k="${_d##*/}=$_v:$_pr"; _dnow="$_dnow$_k "
        case "$dev_seen" in *" $_k "*) continue ;; esac
        _cls=; for _i in "$_d"/*:*/bInterfaceClass; do [ -f "$_i" ] && { read -r _c < "$_i"; _cls="$_cls$_c "; }; done
        case "$_cls" in *08*|*09*) continue ;; esac          # USB stick, hub: not a dongle
        _nm=; _mf=; read -r _nm < "$_d/product" 2>/dev/null; read -r _mf < "$_d/manufacturer" 2>/dev/null
        case "$DONGLE_IDS$ID8851" in
            *" $_v:$_pr "*) case "$ID8851" in *" $_v:$_pr "*) _what="EXPERIMENTAL: RTL8851BU (AX900), driver 8851bu loaded for this chip only, not tested with the real dongle" ;; *) _what="supported (RTL88x2BU, in the driver's list)" ;; esac ;;
            *) case "$SAME_CHIP_IDS" in
                *" $_v:$_pr "*) _what="same chip RTL88x2BU but NOT in the driver's list (can be added without a new driver)" ;;
                *) case "$_v:$_pr" in
                    0bda:8812|0bda:881a|0bda:881b|0bda:881c) _what="other chip, probably RTL8812AU (needs another driver)" ;;
                    0bda:0811|0bda:0821|0bda:8822|0bda:a811) _what="other chip, probably RTL8811AU/8821AU (needs another driver)" ;;
                    0bda:c811|0bda:c820|0bda:c821|0bda:c82c) _what="other chip, probably RTL8821CU/8811CU (needs another driver)" ;;
                    0bda:1a2b) _what="a Realtek dongle in its CD-ROM (driver installer) mode; this package cannot switch it to Wi-Fi mode" ;;
                    0e8d:*) _what="other chip, MediaTek (needs another driver)" ;;
                    *) case "$_cls" in *ff*|*e0*) _what="unknown device with a vendor-specific interface (maybe a Wi-Fi dongle, chip unknown)" ;; *) _what="not a Wi-Fi dongle" ;; esac ;;
                   esac ;;
               esac ;;
        esac
        case "$_what" in "not a Wi-Fi dongle") ;; *) vlog "usb: ${_d##*/} $_v:$_pr \"$_mf $_nm\" interfaces[$_cls]: $_what" ;; esac
    done
    dev_seen=$_dnow
}

# 4) 4.10 (2026-11-15 15:24: Android Auto dropped for 3 s while driving and no log had the cause, the recorder was off):
#    aa-keep (inside the AA app) writes $T/drop.req the moment a connected Android Auto ends. Within a second we save
#    what the car's logs hold of that moment (logcat ring buffers reach back about a minute, so it can't wait for a USB
#    stick) to $T/drop_<date>.log, newest DROPS_KEEP kept; copy_logs then puts them on the stick like the other logs.
#    The Wi-Fi state of the last minute comes from a small ring of driver snapshots taken every 5 s (kept in memory).
DROPS_KEEP=${DROPS_KEEP:-8}
# 4.10 kept the ring in files under $T/wq: remove what an older version left
[ -d "$T/wq" ] && { rm -f "$T"/wq/* 2>/dev/null; rmdir "$T/wq" 2>/dev/null; }
WQ_N=12
wq_i=0; wq_at=-999
# 4.11.1: the ring lives in shell variables (wq_0 .. wq_11), not in files: no flash write every 5 s
wifi_sample() {
    [ $((up - wq_at)) -ge 5 ] || return 0
    wq_at=$up
    _any=
    for _d in "$PROC"/net/rtl88x2bu/* "$PROC"/net/rtl8851bu/*; do [ -f "$_d/all_sta_info" ] && _any=1; done
    [ -n "$_any" ] || return 0
    _v=$(
        echo "--- $(date) uptime ${up}s"
        for _d in "$PROC"/net/rtl88x2bu/* "$PROC"/net/rtl8851bu/*; do
            [ -f "$_d/all_sta_info" ] || continue
            echo "[${_d##*/}] rx_signal:"; cat "$_d/rx_signal" 2>/dev/null
            echo "[${_d##*/}] all_sta_info:"; cat "$_d/all_sta_info" 2>/dev/null
        done
        grep "wlan0:" "$PROC/net/dev" 2>/dev/null
    )
    eval "wq_$wq_i=\$_v"
    wq_i=$(( (wq_i + 1) % WQ_N ))
}
wifi_ring() {
    _k=0; _j=$wq_i
    while [ $_k -lt $WQ_N ]; do
        eval "_v=\${wq_$_j:-}"
        [ -n "$_v" ] && echo "$_v"
        _j=$(( (_j + 1) % WQ_N )); _k=$((_k + 1))
    done
}
# 4.11.1: daemon.log is capped while running: past LOG_MAX it becomes daemon.old.log (one old copy kept; at start the
# previous run's log is daemon.prev.log as before). All go to the stick.
LOG_MAX=${LOG_MAX:-262144}
trim_at=-999
log_trim() {
    [ $((up - trim_at)) -ge ${TRIM_EVERY:-60} ] || return 0
    trim_at=$up
    [ -f "$LOG" ] || return 0
    _sz=$(wc -c < "$LOG" 2>/dev/null); _sz=$((${_sz:-0} + 0))
    [ "$_sz" -gt "$LOG_MAX" ] || return 0
    mv -f "$LOG" "$T/daemon.old.log" 2>/dev/null && vlog "log: daemon.log reached ${_sz} bytes, the earlier part kept as daemon.old.log"
}
# the lines that usually tell why a session ended (stock AA app, Bluetooth, Wi-Fi, crashes, the dongle), at most 80
cause_lines() {
    _c=0
    grep -i -e pingTimeOut -e "Ping TimeOut" -e ByeBye -e BYEBYE -e rfcommDisconnect -e "Connection Error" \
        -e "Reading Loop fail" -e "accept failed" -e "FATAL EXCEPTION" -e "has died" -e "ANR in" -e am_crash -e am_anr \
        -e am_proc_died -e lowmemorykiller -e onDisconnected -e disconnectReason -e stopSession -e endSession \
        -e WifiStartResponse -e STATUS_WIFI -e isWifiApEnable -e STA-DISCONNECTED -e deauth -e disassoc \
        -e "USB disconnect" -e "surprise removal" -e gpm.finish -e "Connection closed" -e "session end" "$@" 2>/dev/null |
    while read -r _x; do
        _c=$((_c + 1)); [ $_c -le 80 ] && echo "$_x"
    done
}
drop_check() {
    [ -f "$T/drop.req" ] || return 0
    _why=; read -r _why < "$T/drop.req" 2>/dev/null
    rm -f "$T/drop.req"
    _f="$T/drop_$(date +%m%d_%H%M%S)"
    logcat -d -v threadtime -b main -b system -b events -b radio > "$_f.lc" 2>&1
    dmesg > "$_f.km" 2>/dev/null
    {
        echo "== Android Auto drop: ${_why:-?}"
        echo "== saved $(date), uptime $(uptime_s)s, by usbwifi.hotspot $(grep "^package-version=" "$APPS/NEMESIS.data" 2>/dev/null)"
        echo "== hotspot: wlan0 $([ -d "$SYSNET/wlan0" ] && echo present || echo MISSING), KP hostapd $(kp_pids "hostapd-kp[.]conf"), AA signal sys.kp.aa_ap=$(getprop sys.kp.aa_ap)"
        echo
        echo "== likely cause: lines of the logs below that usually tell why a session ended (oldest first)"
        cause_lines "$_f.lc"
        echo "-- kernel:"
        cause_lines "$_f.km"
        echo
        echo "== Wi-Fi from the dongle driver, the last minute (every 5 s, oldest first)"
        wifi_ring
        echo
        echo "== logcat (main, system, events, radio): about the last minute before the drop"
        cat "$_f.lc"
        echo
        echo "== kernel log"
        cat "$_f.km"
    } > "$_f.raw" 2>/dev/null
    # 4.11: only the privacy-filtered copy is kept
    scrub_file "$_f.raw" "$_f.log" 2>/dev/null
    rm -f "$_f.lc" "$_f.km" "$_f.raw"
    chmod 644 "$_f.log" 2>/dev/null
    vlog "drop: Android Auto ended (${_why:-?}): logs of that moment saved to ${_f##*/}.log ($(wc -c < "$_f.log" 2>/dev/null) bytes)"
    # keep the newest DROPS_KEEP (names sort by date)
    _n=0; for _x in "$T"/drop_*.log; do [ -f "$_x" ] && _n=$((_n + 1)); done
    for _x in "$T"/drop_*.log; do
        [ $_n -gt $DROPS_KEEP ] || break
        [ -f "$_x" ] && { rm -f "$_x"; _n=$((_n - 1)); }
    done
}

nb_since=0; resets=0; last_reset=0; nr_since=0; dh_since=0; as_since=0; radio_tries=0; had_wlan=0
drv_ok=0; chip_ok=0; was=; seen_up=0; plug_up=0; ev_host=0; ev_aa=0; kick2=0; tl_end=0
if kernel_ok; then
    load_driver && drv_ok=1
    # 4.13: a guard file left from the last run = the experimental 8851bu load never finished (the head unit restarted)
    if [ -f "$EXP8851_GUARD" ]; then
        mv -f "$EXP8851_GUARD" "$EXP8851_OFF" 2>/dev/null
        vlog "FAIL: 8851: the experimental RTL8851BU driver did not finish loading last time - the head unit restarted while loading? Switched off. Reinstall the package to try again."
    fi
else
    # 4.12: firmware other than the tested one, with another kernel: no driver, no chip mark (KP would wait for a
    # Wi-Fi that can't come); logs and USB copies still work
    drv_ok=no; chip_ok=no
    _k3=$(set -- $kv; echo "$1 $2 $3")
    vlog "FAIL: this firmware's kernel is not the one the bundled driver was built for ($KERNEL_WANT SMP PREEMPT): driver not loaded, Wi-Fi chip not marked. Kernel: $_k3"
fi
while true; do
    [ $drv_ok != 0 ] || { load_driver && drv_ok=1; }
    [ $chip_ok != 0 ] || { mark_chip && chip_ok=1; }
    [ $drv_ok = no ] || load_8851
    name_wlan0
    copy_logs
    if [ -d "$SYSNET/wlan0" ]; then now=wlan0; else now=none; fi
    up=$(uptime_s)
    if [ "$now" != "$was" ]; then
        if [ $now = wlan0 ]; then
            vlog "dongle present as wlan0 (uptime ${up}s)"
            plug_up=$up; ev_host=0; ev_aa=0; tl_end=$((up + 180)); nr_since=$up
            # a replug = wlan0 was here before in this run (2026-11-13: the AA signal had never come up before the dongle
            # was pulled, so the old "AA signal seen" rule missed the replug and KP's dead hostapd/dnsmasq stayed)
            if { [ $seen_up = 1 ] || [ $had_wlan = 1 ]; } && [ ! -f "$NOACCEL" ]; then
                kp_stale
                kp_kick replug
                kick2=$((up + 6))
            fi
            had_wlan=1
        else
            vlog "no dongle interface (dongle unplugged or not up yet)"
            [ "$(getprop sys.kp.aa_ap)" = 1 ] && { setprop sys.kp.aa_ap 0; vlog "dongle gone: wireless AA signal set to 0"; }
        fi
        was=$now
    fi
    # timeline of a plug-in (boot or replug): where do the seconds go?
    if [ $now = wlan0 ] && [ $ev_aa = 0 ] && [ "$up" -le "$tl_end" ]; then
        if [ $ev_host = 0 ] && [ -n "$(kp_pids "hostapd-kp[.]conf")" ]; then ev_host=1; vlog "timeline: KP hostapd running +$((up - plug_up))s after the dongle"; fi
        if [ "$(getprop sys.kp.aa_ap)" = 1 ]; then ev_aa=1; seen_up=1; vlog "timeline: wireless AA signal on +$((up - plug_up))s after the dongle"; fi
    fi
    watch_hotspot
    usb_report
    wifi_sample
    drop_check
    log_trim
    if [ ! -f "$NOACCEL" ]; then
        if [ $now = wlan0 ] && [ $in_grace = 1 ]; then
            [ $grace_told = 0 ] && { vlog "boot: KP is waiting up to 90 s for a stock hotspot this car does not have: ending the wait"; grace_told=1; }
            kp_kick boot-wait >/dev/null
        fi
        usb_check
        radio_check
        [ "$(getprop sys.kp.aa_ap)" = 1 ] && radio_tries=0
    fi
    if [ $kick2 != 0 ] && [ "$up" -ge "$kick2" ]; then
        kick2=0
        [ "$(getprop sys.kp.aa_ap)" = 1 ] || kp_kick replug-2
    fi
    sleep ${TICK:-1} &
    wait $!
    [ -n "${ONCE:-}" ] && break
done
exit 0
