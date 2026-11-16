# USB Wi-Fi dongle v4: install/uninstall log, sourced by the NEMESIS scripts (cwd = the package).
# hlog_begin <name>: from here on every line the script prints (and its exit code) is also
# written, at exit, to /data/hmgapi/usbwifi-v4.log and to HMGAPI-LOGS/usbwifi-v4.log on every USB stick
# that is plugged in (the install stick itself), so a failed install can be diagnosed from
# that stick. Output still reaches NEMESIS as before. Never changes the script's exit code.
# HLOG_ROOT prefixes the paths (off-car tests only).
hlog_begin() {
    HLOG_NAME=$1
    HLOG_TMP=${HLOG_ROOT:-}/data/local/tmp/usbwifi-v4-$1.$$
    mkdir -p "${HLOG_ROOT:-}/data/local/tmp" 2>/dev/null
    # if the log file can't be made, run without logging: a failed redirect of exec would end the script
    ( : > "$HLOG_TMP" ) 2>/dev/null || return 0
    exec 3>&1 4>&2
    exec >"$HLOG_TMP" 2>&1
    trap hlog_end EXIT
    echo "$(date) $1 start, cwd=$PWD"
}
hlog_end() {
    _rc=$?
    trap - EXIT
    echo "$(date) $HLOG_NAME exit rc=$_rc"
    exec 1>&3 2>&4
    [ -f "$HLOG_TMP" ] && cat "$HLOG_TMP"
    for _d in "${HLOG_ROOT:-}/data/hmgapi" ${HLOG_USB_DIRS:-/storage/usb0 /storage/usb1 /storage/usb2}; do
        case $_d in */data/hmgapi) _f=$_d/usbwifi-v4.log ;; *) [ -d "$_d" ] || continue; _f=$_d/HMGAPI-LOGS/usbwifi-v4.log; mkdir -p "$_d/HMGAPI-LOGS" 2>/dev/null ;; esac
        [ -d "${_f%/*}" ] || continue
        { echo "=== $HLOG_NAME"; cat "$HLOG_TMP"; } >> "$_f" 2>/dev/null
    done
    rm -f "$HLOG_TMP"
    sync 2>/dev/null
    exit $_rc
}
