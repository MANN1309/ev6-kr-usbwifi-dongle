#!/system/bin/sh
# postinstall (root, cwd = the installed package): checks; the service does the driver work at start.
# 4.9: also installs (or updates) the HMG-API mod inside this package, ev6-kr-aa-keep 1.3 (4.10) = wireless AA keep-connected
# + the two dongle plug-in notices hidden. If that part can't be done the dongle still installs (WARNING, logged).
export PATH=${KR_TEST_PATH:+$KR_TEST_PATH:}/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -f kr/log.sh ] && . kr/log.sh && hlog_begin postinstall
. ./kr/common.sh
[ -f modules/88x2bu.ko ] && [ -f svc/dongle.sh ] || { echo "FAIL: package files missing"; exit 1; }
chmod 755 svc/dongle.sh bin/status.sh 2>/dev/null
mkdir -p "$T" 2>/dev/null; chmod 1777 "$T" 2>/dev/null
if grep -q "^88x2bu " "$MODS" 2>/dev/null; then
    _sv=; read -r _sv < "$SRCV" 2>/dev/null
    [ "$_sv" = "$DRV_SRCVERSION" ] || echo "the previous dongle driver is still loaded: RESTART the head unit so the new driver and wlan0 are used"
fi
[ -d "${ROOT:-}/data/hmgapi" ] || echo "WARNING: HMG-API isn't installed: Korea Projection needs it"

MODID=ev6-kr-aa-keep
OLDPKG=hmgapi.$MODID
mod_install() {
    _h=${ROOT:-}/system/bin/hmgapid
    [ -f mod/package.zip ] || { echo "WARNING: mod/package.zip missing"; return 1; }
    [ -x "$_h" ] || { echo "WARNING: HMG-API isn't installed (install it, then this package again)"; return 1; }
    . ./kr/modgate.sh
    mod_gate || return 1
    "$_h" ping >/dev/null 2>&1 || "$_h" daemon >/dev/null 2>&1
    _new=yes
    [ -d "${ROOT:-}/data/hmgapi/mods/$MODID" ] && _new=no
    if ! "$_h" engine install "$PWD/mod/package.zip" --from-nemesis; then
        echo "WARNING: HMG-API didn't install the mod (see above)"
        return 1
    fi
    if ! _r=$("$_h" engine apply 2>&1); then
        echo "$_r"
        if [ $_new = yes ]; then
            "$_h" engine remove "$MODID" --from-nemesis >/dev/null 2>&1
            "$_h" engine apply >/dev/null 2>&1
            echo "WARNING: HMG-API couldn't apply the mod (see above), so it was taken out again"
        else
            echo "WARNING: the mod update is in HMG-API, but it couldn't apply it (see above): open the HMG-API app and tap Apply changes"
        fi
        return 1
    fi
    echo "$_r"
    return 0
}
if mod_install; then
    echo "HMG-API mod $MODID 1.3 installed with the dongle: AA keep-connected, the two plug-in notices hidden, logs saved at each AA drop (restart the head unit)"
else
    echo "WARNING: AA keep-connected and the plug-in notice hiding are NOT installed (the dongle itself works)"
fi
# the old separate package of the same mod: removing it in NEMESIS Manager must not take the mod away any more
for _o in "${ROOT:-}/data/nemesis/apps/$OLDPKG" "${ROOT:-}/data/nemesis/packages/$OLDPKG"; do
    [ -f "$_o/scripts/preuninstall.sh" ] || continue
    grep -q "now part of usbwifi.hotspot" "$_o/scripts/preuninstall.sh" 2>/dev/null && continue
    {
        echo "#!/system/bin/sh"
        echo "# replaced by usbwifi.hotspot 4.9: the mod $MODID is now part of usbwifi.hotspot"
        echo "echo \"$MODID is now part of usbwifi.hotspot: removing this old entry leaves the mod in place\""
        echo "exit 0"
    } > "$_o/scripts/preuninstall.sh" 2>/dev/null && echo "old package $OLDPKG: its uninstall no longer removes the mod (you can delete it in NEMESIS Manager)"
done
[ -d "${ROOT:-}/data/hmgapi/mods/ev6kr-usbquiet" ] && echo "NOTE: the old test mod ev6kr-usbquiet is installed; it is not needed any more (delete hmgapi.ev6kr-usbquiet in NEMESIS Manager)"
echo "installed. This package runs no hotspot itself: install Korea Projection (korea.projection) for that, then restart."
exit 0
