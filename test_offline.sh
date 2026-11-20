#!/bin/bash
# Off-car test of pkg/ (fake root, fake ip/insmod/getprop/log): syntax, driver load, chip mark, wlan0 naming, replug,
# install/uninstall/update. bash test_offline.sh
B=$(cd "$(dirname "$0")" && pwd); P=$B/pkg
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
echo "== 0 syntax"
for f in svc/dongle.sh scripts/post.sh scripts/preun.sh bin/status.sh bin/collect.sh kr/common.sh kr/log.sh kr/modgate.sh; do
  for sh in dash ksh bash; do command -v $sh >/dev/null || continue; ok "$sh -n $f" "$sh -n $P/$f"; done
  ok "no forbidden tools in $f" "! grep -v '^[[:space:]]*#' $P/$f | grep -Eq '(^|[|;&(\`]|\$\()[[:space:]]*(od|tail|head|tr|printf|md5sum|dirname|basename)( |\$)'"
done
mkbin() {
  mkdir -p "$W/bin"
  cat > "$W/bin/ip" <<'X'
#!/bin/bash
# ip link set <if> down|up|name <new>
[ "$1 $2" = "link set" ] || exit 0
if [ "$4" = name ]; then [ -e "$SYSNET/$5" ] && exit 1; mv "$SYSNET/$3" "$SYSNET/$5"; echo "$3->$5" >> "$ROOT/ip.calls"; fi
exit 0
X
  cat > "$W/bin/insmod" <<'X'
#!/bin/bash
echo "$*" >> "$ROOT/insmod.calls"; [ -n "$INSMOD_FAIL" ] && exit 1
case "$1" in *8851bu.ko) [ -n "$INSMOD8851_FAIL" ] && exit 1; echo "8851bu 5000000 0 - Live 0x0" >> "$MODS"; exit 0 ;; esac
echo "88x2bu 2722628 0 - Live 0x0" >> "$MODS"; mkdir -p "$ROOT/sys/module/88x2bu"; echo 46A9CFB83C8F6E0C09E8AAC > "$SRCV"; exit 0
X
  printf '#!/bin/bash\ncat "$ROOT/props/$1" 2>/dev/null; exit 0\n' > "$W/bin/getprop"
  printf '#!/bin/bash\nmkdir -p "$ROOT/props"; echo "$2" > "$ROOT/props/$1"\n' > "$W/bin/setprop"; printf '#!/bin/bash\nexit 0\n' > "$W/bin/log"
  chmod +x "$W/bin/"*
}
newcar() {
  export ROOT=$W/$1; rm -rf "$ROOT"; mkdir -p "$ROOT/proc" "$ROOT/sys/class/net" "$ROOT/data/hmgapi" "$ROOT/storage/usb0" "$ROOT/data/nemesis/apps"
  export HLOG_ROOT=$ROOT HLOG_USB_DIRS=$ROOT/storage/usb0
  : > "$ROOT/proc/modules"; export SYSNET=$ROOT/sys/class/net MODS=$ROOT/proc/modules SRCV=$ROOT/sys/module/88x2bu/srcversion
  cp -R "$P" "$ROOT/data/nemesis/apps/usbwifi.hotspot"; A=$ROOT/data/nemesis/apps/usbwifi.hotspot
}
netif() { mkdir -p "$SYSNET/$1"; echo $2 > "$SYSNET/$1/ifindex"; [ "$3" = usb ] && mkdir -p "$SYSNET/$1/device/driver"; true; }
runsvc() { (cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/storage/usb0 USB_SETTLE=0 ONCE=1 TICK=0 timeout 20 sh svc/dongle.sh); }
mkbin
echo "== 1 fresh: driver, chip mark, placeholder ignored, real dongle -> wlan0"
newcar t1; netif rtwlan0 10; netif rtwlan1 12 usb; runsvc
ok "insmod with KR + usbfs block" "grep -q 'rtw_country_code=KR.*rtw_usbfs_block=1' $ROOT/insmod.calls"
ok "chip mark made, ours" "[ -f $ROOT/data/hmgapi/public/wifi-chip ] && [ -f $ROOT/data/nemesis/usbwifi-v4.chip-ours ]"
ok "rtwlan1 (usb) renamed, placeholder kept" "[ -d $SYSNET/wlan0 ] && [ -d $SYSNET/rtwlan0 ] && [ ! -d $SYSNET/rtwlan1 ]"
ok "log says present" "grep -q 'dongle present as wlan0' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
ok "logs copied to USB once" "[ -s \$(ls $ROOT/storage/usb0/usbwifi_hotspot_log/up*/daemon.log | head -1) ] && [ \$(grep -c 'logs copied' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log) = 1 ]"
ok "status.sh runs from any folder and reports" "out=\$(cd / && KR_TEST_PATH=$W/bin:\$PATH sh $A/bin/status.sh 2>&1); echo \"\$out\" | grep -q 'bundled driver loaded, wlan0 present, chip mark yes'"
ok "status.sh also with relative start" "out=\$(cd $A/bin && KR_TEST_PATH=$W/bin:\$PATH sh status.sh 2>&1); echo \"\$out\" | grep -q 'wlan0 present'"
echo "== 2 no dongle yet: only placeholder, nothing renamed"
newcar t2; netif rtwlan0 10; runsvc
ok "placeholder not renamed" "[ ! -d $SYSNET/wlan0 ] && [ -d $SYSNET/rtwlan0 ]"
ok "logged no dongle" "grep -q 'no dongle interface' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
echo "== 3 replug: new interface gets wlan0 again"
rm -rf "$SYSNET/wlan0"; netif rtwlan2 14 usb; runsvc
ok "rtwlan2 -> wlan0" "[ -d $SYSNET/wlan0 ] && grep -q 'rtwlan2->wlan0' $ROOT/ip.calls"
echo "== 4 chip already marked by HMG-API (real chip): not ours, kept at uninstall"
newcar t4; mkdir -p $ROOT/data/hmgapi/public; : > $ROOT/data/hmgapi/public/wifi-chip; runsvc
ok "not marked as ours" "[ ! -f $ROOT/data/nemesis/usbwifi-v4.chip-ours ]"
(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/preun.sh >/dev/null 2>&1)
ok "foreign mark kept" "[ -f $ROOT/data/hmgapi/public/wifi-chip ]"
echo "== 5 old driver loaded: no insmod, restart advice"
newcar t5; echo "88x2bu 1 0 - Live" > $MODS; mkdir -p $ROOT/sys/module/88x2bu; echo A8402F29F362DF030025EE3 > $SRCV
out=$(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/post.sh 2>&1); runsvc
ok "post says restart" "echo \"\$out\" | grep -q RESTART"
ok "no insmod over old driver" "[ ! -f $ROOT/insmod.calls ]"
ok "daemon log says restart" "grep -q 'restart the head unit' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
echo "== 6 uninstall: mark removed, no rmmod, logs to USB"
newcar t6; netif rtwlan1 12 usb; runsvc
(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/preun.sh >/dev/null 2>&1); rc=$?
ok "preun rc 0" "[ $rc = 0 ]"
ok "chip mark removed" "[ ! -f $ROOT/data/hmgapi/public/wifi-chip ] && [ ! -f $ROOT/data/nemesis/usbwifi-v4.chip-ours ]"
ok "daemon log on USB" "[ -s $ROOT/storage/usb0/HMGAPI-LOGS/usbwifi-v4-daemon.log ]"
ok "install log on USB" "grep -q 'preuninstall exit rc=0' $ROOT/storage/usb0/HMGAPI-LOGS/usbwifi-v4.log"
ok "no rmmod anywhere" "! cat $P/svc/*.sh $P/scripts/*.sh | grep -v '^[[:space:]]*#' | grep -q 'rmmod '"
echo "== 7 update: mark kept"
newcar t7; runsvc; mkdir -p $ROOT/data/local/tmp/nemesis/stage/usbwifi.hotspot; cp $P/NEMESIS.data $ROOT/data/local/tmp/nemesis/stage/usbwifi.hotspot/
(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/preun.sh >/dev/null 2>&1)
ok "update keeps mark" "[ -f $ROOT/data/hmgapi/public/wifi-chip ]"
echo "== 8 HMG-API missing: no mark, insmod fails logged"
newcar t8; rm -rf $ROOT/data/hmgapi; INSMOD_FAIL=1 runsvc
ok "no mark without HMG-API" "[ ! -e $ROOT/data/hmgapi/public/wifi-chip ]"
ok "insmod failure logged" "grep -q 'insmod bundled 88x2bu rc=1' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
echo "== 9 replug: stale KP processes ended, KP woken at once, AA signal dropped while the dongle is gone, timeline logged"
newcar t9r; netif rtwlan1 12 usb; mkdir -p "$ROOT/props" "$ROOT/data/local/tmp/korea.projection"; echo 0 > "$ROOT/props/sys.kp.aa_ap"; echo "100.0 0.0" > "$ROOT/proc/uptime"
fake() { mkdir -p "$ROOT/proc/$1"; printf '%s' "$2" > "$ROOT/proc/$1/cmdline"; echo "$1 ($3) S $4 0 0 0" > "$ROOT/proc/$1/stat"; }
sleep 300 & KPMAIN=$!; sleep 300 & KPSUB=$!; sleep 300 & KPCH=$!; sleep 300 & SUBCH=$!; sleep 300 & OTHER=$!; sleep 300 & HOST=$!; sleep 300 & DNS=$!
fake $KPMAIN "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh 1
fake $KPSUB "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh $KPMAIN
fake $KPCH "sleep 30" sleep $KPMAIN
fake $SUBCH "sleep 5" sleep $KPSUB
fake $OTHER "sleep 30" sleep 999
fake $HOST "hostapd /data/misc/wifi/hostapd-kp.conf" hostapd 1
fake $DNS "dnsmasq --keep-in-foreground" dnsmasq 1; echo "$DNS bootid" > "$ROOT/data/local/tmp/korea.projection/dnsmasq.pid"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
sleep 1.2
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
echo 1 > "$ROOT/props/sys.kp.aa_ap"; echo "108.0 0.0" > "$ROOT/proc/uptime"; sleep 1.2
ok "timeline: hostapd and the AA signal seen after the plug-in" "grep -q 'timeline: KP hostapd running' $LOGF && grep -q 'timeline: wireless AA signal on' $LOGF"
ok "first plug-in (boot): no replug recovery, nothing ended" "! grep -q 'replug' $LOGF && kill -0 $HOST && kill -0 $DNS && kill -0 $KPCH"
rm -rf "$SYSNET/wlan0" "$SYSNET/rtwlan0"; sleep 1.2
ok "dongle gone: AA signal set to 0, logged" "[ \"\$(cat $ROOT/props/sys.kp.aa_ap)\" = 0 ] && grep -q 'dongle gone: wireless AA signal set to 0' $LOGF"
echo "120.0 0.0" > "$ROOT/proc/uptime"; netif rtwlan2 14 usb; sleep 1.5
ok "replug: KP hostapd and dnsmasq ended" "! kill -0 $HOST 2>/dev/null && ! kill -0 $DNS 2>/dev/null"
ok "replug: the sleep of KP's main loop ended (KP checks at once)" "! kill -0 $KPCH 2>/dev/null && grep -q 'kick (replug): KP service $KPMAIN checks now (1 waits ended)' $LOGF"
ok "replug: other sleeps untouched (a subshell's, an unrelated one)" "kill -0 $SUBCH && kill -0 $OTHER && kill -0 $KPMAIN && kill -0 $KPSUB"
sleep 300 & KPCH2=$!; fake $KPCH2 "sleep 30" sleep $KPMAIN; echo 0 > "$ROOT/props/sys.kp.aa_ap"; echo "127.0 0.0" > "$ROOT/proc/uptime"; sleep 1.5
ok "6 s later, still no AA signal: woken once more" "! kill -0 $KPCH2 2>/dev/null && grep -q 'kick (replug-2)' $LOGF"
echo "== 10 accelerator off by a flag file"
touch "$ROOT/data/nemesis/usbwifi-v4.noaccel"; sleep 300 & KPCH3=$!; fake $KPCH3 "sleep 30" sleep $KPMAIN; echo 1 > "$ROOT/props/sys.kp.aa_ap"; sleep 1.2
rm -rf "$SYSNET/wlan0"; sleep 1.2; netif rtwlan3 16 usb; sleep 1.5
ok "no-accel flag: replug leaves KP alone" "kill -0 $KPCH3 2>/dev/null"
kill $SVC $KPMAIN $KPSUB $KPCH $SUBCH $OTHER $HOST $DNS $KPCH2 $KPCH3 2>/dev/null; wait 2>/dev/null
echo "== 11 radio watchdog: wlan0 but no hotspot -> start KP's hostapd/dnsmasq; KP service absent -> AA signal"
cat > "$W/bin/hostapd" <<'X'
#!/bin/bash
[ "$1" = -v ] && { echo "hostapd v2.1-devel" >&2; echo "User space daemon" >&2; exit 1; }
mkdir -p "$ROOT/proc/$$"; printf 'hostapd %s' "$1" > "$ROOT/proc/$$/cmdline"; echo "$$ (hostapd) S 1 0" > "$ROOT/proc/$$/stat"; echo "$*" >> "$ROOT/hostapd.calls"; exec sleep 300
X
cat > "$W/bin/dnsmasq" <<'X'
#!/bin/bash
mkdir -p "$ROOT/proc/$$"; printf 'dnsmasq' > "$ROOT/proc/$$/cmdline"; echo "$$ (dnsmasq) S 1 0" > "$ROOT/proc/$$/stat"; echo "$*" >> "$ROOT/dnsmasq.calls"; exec sleep 300
X
printf '#!/bin/bash\necho "$*" >> "$ROOT/ifconfig.calls"\n' > "$W/bin/ifconfig"; chmod +x "$W/bin/hostapd" "$W/bin/dnsmasq" "$W/bin/ifconfig"
newcar t11; netif rtwlan1 12 usb; mkdir -p "$ROOT/props" "$ROOT/data/misc/wifi"; echo 'interface=wlan0' > "$ROOT/data/misc/wifi/hostapd-kp.conf"; echo "100.0 0.0" > "$ROOT/proc/uptime"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
sleep 1; ok "not before 2 s" "[ ! -f $ROOT/hostapd.calls ]"
echo "103.0 0.0" > "$ROOT/proc/uptime"; sleep 2.2
ok "after 2 s: wlan0 address set and hostapd started with KP's file" "grep -q 'wlan0 192.168.43.1 netmask 255.255.255.0 up' $ROOT/ifconfig.calls && grep -q 'hostapd-kp.conf' $ROOT/hostapd.calls && grep -q 'radio watchdog: no hotspot' $LOGF"
ok "only once while it runs" "[ \$(wc -l < $ROOT/hostapd.calls) = 1 ]"
ok "dnsmasq started together with the hotspot (no 10 s wait), KP's pid file" "grep -q 'interface=wlan0' $ROOT/dnsmasq.calls && [ -s $ROOT/data/local/tmp/korea.projection/dnsmasq.pid ]"
echo "104.0 0.0" > "$ROOT/proc/uptime"; sleep 0.8
ok "KP service not running: AA signal set by us" "[ \"\$(cat $ROOT/props/sys.kp.aa_ap)\" = 1 ] && grep -q 'set to 1 ourselves' $LOGF"
kill $SVC 2>/dev/null; for f in "$ROOT"/proc/[0-9]*; do kill ${f##*/} 2>/dev/null; done; wait 2>/dev/null
newcar t11b; netif rtwlan1 12 usb; echo "100.0 0.0" > "$ROOT/proc/uptime"; rm -f "$ROOT/hostapd.calls"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
sleep 0.6; echo "150.0 0.0" > "$ROOT/proc/uptime"; sleep 1
ok "KP never set up on this car (no hostapd-kp.conf): nothing started" "[ ! -f $ROOT/hostapd.calls ]"
kill $SVC 2>/dev/null; wait 2>/dev/null
echo "== 12 USB sees the dongle but no Wi-Fi interface -> software replug"
newcar t12; mkdir -p "$ROOT/sys/bus/usb/devices/1-1" "$ROOT/sys/bus/usb/devices/2-1"; echo 2357 > "$ROOT/sys/bus/usb/devices/1-1/idVendor"; echo 012e > "$ROOT/sys/bus/usb/devices/1-1/idProduct"; echo 1 > "$ROOT/sys/bus/usb/devices/1-1/authorized"
echo 1d6b > "$ROOT/sys/bus/usb/devices/2-1/idVendor"; echo 0002 > "$ROOT/sys/bus/usb/devices/2-1/idProduct"; echo 1 > "$ROOT/sys/bus/usb/devices/2-1/authorized"; echo "200.0 0.0" > "$ROOT/proc/uptime"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
sleep 1; ok "noticed: on USB, no interface yet" "grep -q 'usb: dongle 1-1 on USB, no Wi-Fi interface yet' $LOGF && ! grep -q 'software replug' $LOGF"
echo "211.0 0.0" > "$ROOT/proc/uptime"; sleep 3.2
ok "after 10 s: software replug of the dongle only" "grep -q 'usb: software replug #1 of 1-1' $LOGF && [ \"\$(cat $ROOT/sys/bus/usb/devices/1-1/authorized)\" = 1 ] && ! grep -q ' 2-1 ' $LOGF"
mkdir -p "$ROOT/sys/bus/usb/devices/1-1/1-1:1.0/net/rtwlan1"; echo "230.0 0.0" > "$ROOT/proc/uptime"; sleep 1
ok "interface appeared: no more replugs" "[ \$(grep -c 'software replug' $LOGF) = 1 ]"
kill $SVC 2>/dev/null; wait 2>/dev/null
echo "== 16 KP running but slow: hotspot + DHCP up and no AA signal for 2 s -> we raise it (not when AA is off in KP)"
newcar t16; netif rtwlan1 12 usb; mkdir -p "$ROOT/props" "$ROOT/data/misc/wifi" "$ROOT/data/local/tmp/korea.projection"; echo 'interface=wlan0' > "$ROOT/data/misc/wifi/hostapd-kp.conf"; echo 0 > "$ROOT/props/sys.kp.aa_ap"; echo "100.0 0.0" > "$ROOT/proc/uptime"
sleep 300 & KPM=$!; sleep 300 & H16=$!; sleep 300 & D16=$!
fake $KPM "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh 1; fake $H16 "hostapd /data/misc/wifi/hostapd-kp.conf" hostapd 1; fake $D16 "dnsmasq --keep-in-foreground" dnsmasq 1
echo "$D16 bootid" > "$ROOT/data/local/tmp/korea.projection/dnsmasq.pid"
mkdir -p "$ROOT/data/nemesis/backup/korea.projection"; touch "$ROOT/data/nemesis/backup/korea.projection/aa-off"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
sleep 0.8; echo "110.0 0.0" > "$ROOT/proc/uptime"; sleep 0.8
ok "AA switched off in KP: signal left alone" "[ \"\$(cat $ROOT/props/sys.kp.aa_ap)\" = 0 ]"
rm -f "$ROOT/data/nemesis/backup/korea.projection/aa-off"; sleep 0.6; echo "113.0 0.0" > "$ROOT/proc/uptime"; sleep 0.8
ok "2 s without KP raising it: AA signal set by us, logged" "[ \"\$(cat $ROOT/props/sys.kp.aa_ap)\" = 1 ] && grep -q 'KP has not raised the AA signal: set to 1 ourselves' $LOGF"
echo "== 17 replug before the AA signal ever came up: still treated as a replug"
echo 0 > "$ROOT/props/sys.kp.aa_ap"; rm -rf "$ROOT/sys/class/net/wlan0"; sleep 0.8
echo "130.0 0.0" > "$ROOT/proc/uptime"; netif rtwlan2 14 usb; sleep 1.2
ok "old KP hostapd/dnsmasq ended at the replug" "! kill -0 $H16 2>/dev/null && ! kill -0 $D16 2>/dev/null && grep -q 'replug: 2 old KP' $LOGF"
kill $SVC $KPM 2>/dev/null; for f in "$ROOT"/proc/[0-9]*; do kill ${f##*/} 2>/dev/null; done; wait 2>/dev/null
echo "== 15 the grep's own command line never counts as hostapd/KP"
newcar t15; netif rtwlan1 12 usb; mkdir -p "$ROOT/props" "$ROOT/data/misc/wifi"; echo 'interface=wlan0' > "$ROOT/data/misc/wifi/hostapd-kp.conf"; echo "100.0 0.0" > "$ROOT/proc/uptime"; rm -f "$ROOT/hostapd.calls"
fake 4242 'grep -l hostapd-kp[.]conf /proc/1/cmdline' grep 1; fake 4243 'grep -l korea[.]projection/svc/hotspot[.]sh' grep 1
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
sleep 0.8; echo "111.0 0.0" > "$ROOT/proc/uptime"; sleep 1.2; LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
ok "a grep process is not taken for hostapd: the watchdog starts the real one after 2 s" "grep -q 'hostapd-kp.conf' $ROOT/hostapd.calls && ! grep -q 'KP hostapd running +0s' $LOGF"
ok "log folder writable for aa-keep (1777)" "stat -f %p $ROOT/data/local/tmp/usbwifi_hotspot | grep -q 1777$"
kill $SVC 2>/dev/null; for f in "$ROOT"/proc/[0-9]*; do kill ${f##*/} 2>/dev/null; done; wait 2>/dev/null
echo "== 14 boot: KP's 90 s wait for a stock hotspot is ended while wlan0 is there"
newcar t14; netif rtwlan1 12 usb; mkdir -p "$ROOT/data/nemesis/logs/korea.projection" "$ROOT/props"; echo "100.0 0.0" > "$ROOT/proc/uptime"
printf '11-12 19:00:01 시작 (CVEV.KOR...): softap.conf\n11-12 20:00:05 순정 카플레이 AP를 최대 90초 기다림(busybox 없는 내비)\n' > "$ROOT/data/nemesis/logs/korea.projection/ap.log"
sleep 300 & GM=$!; sleep 300 & GC=$!; fake $GM "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh 1; fake $GC "sleep 10" sleep $GM
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
sleep 1.2; LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
ok "waiting KP: its sleep ended, logged once" "! kill -0 $GC 2>/dev/null && [ \$(grep -c 'ending the wait' $LOGF) = 1 ]"
echo "11-12 20:00:20 시작 (CVEV.KOR...): softap.conf" >> "$ROOT/data/nemesis/logs/korea.projection/ap.log"; sleep 300 & GC2=$!; fake $GC2 "sleep 30" sleep $GM; sleep 1
ok "after KP's start line: its sleeps are left alone" "kill -0 $GC2"
kill $SVC $GM $GC2 2>/dev/null; wait 2>/dev/null
echo "== 18 detection logs: KP's wait ends, a running hotspot ends while wlan0 stays, kick finds no wait, USB dongles"
newcar t18; netif rtwlan1 12 usb; mkdir -p "$ROOT/data/nemesis/logs/korea.projection" "$ROOT/props" "$ROOT/data/misc/wifi" "$ROOT/data/local/tmp/korea.projection"; echo "20.0 0.0" > "$ROOT/proc/uptime"
printf 'interface=wlan0\nchannel=149\nhw_mode=a\nieee80211n=1\nht_capab=[HT40+]\n' > "$ROOT/data/misc/wifi/hostapd-kp.conf"; echo 1 > "$ROOT/props/sys.kp.aa_ap"
printf '11-13 18:25:49 순정 카플레이 AP를 최대 90초 기다림(busybox 없는 내비)\n' > "$ROOT/data/nemesis/logs/korea.projection/ap.log"
sleep 300 & KM=$!; sleep 300 & KF=$!; sleep 300 & HK=$!
fake $KM "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh 1; fake $KF "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh $KM
echo "$KF bootid" > "$ROOT/data/local/tmp/korea.projection/fix.pid"; fake $HK "hostapd /data/misc/wifi/hostapd-kp.conf" hostapd 1
D=$ROOT/sys/bus/usb/devices; mkdir -p "$D/4-1/4-1:1.0" "$D/1-3/1-3:1.0" "$D/1-4/1-4:1.0"
echo 0bda > "$D/4-1/idVendor"; echo b81a > "$D/4-1/idProduct"; echo ff > "$D/4-1/4-1:1.0/bInterfaceClass"; echo "802.11ac NIC" > "$D/4-1/product"
echo 0bda > "$D/1-3/idVendor"; echo c811 > "$D/1-3/idProduct"; echo ff > "$D/1-3/1-3:1.0/bInterfaceClass"
echo 0781 > "$D/1-4/idVendor"; echo 5581 > "$D/1-4/idProduct"; echo 08 > "$D/1-4/1-4:1.0/bInterfaceClass"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log; sleep 1.2
ok "hotspot seen with its starter, hostapd version and settings (no wmm line noted)" "grep -q 'watch: hotspot hostapd $HK started by KP' $LOGF && grep -q 'hostapd version: hostapd v2.1-devel' $LOGF && grep -q 'channel=149.*(no wmm_enabled line)' $LOGF"
ok "kick found no wait: KP processes listed with fix_perms marked" "grep -q 'found no wait: KP processes:.*KP$KF(sh)/S parent=$KM (fix_perms)' $LOGF"
ok "USB: same chip not in the driver list / other chip / stick ignored" "grep -q 'usb: 4-1 0bda:b81a .*same chip RTL88x2BU but NOT in the driver' $LOGF && grep -q 'usb: 1-3 0bda:c811 .*RTL8821CU' $LOGF && ! grep -q '0781:5581' $LOGF"
ok "each USB device reported once" "[ \$(grep -c 'usb: 4-1 0bda:b81a' $LOGF) = 1 ]"
echo "11-13 18:27:19 시작 (CVEV.KOR...): softap.conf" >> "$ROOT/data/nemesis/logs/korea.projection/ap.log"; sleep 0.8
ok "KP's boot wait end logged with the hotspot's state" "grep -q \"watch: KP's 90 s boot wait ENDED.*hostapd $HK by KP, AA signal 1, KP last: 11-13 18:27:19 시작\" $LOGF"
kill $HK; rm -rf "$ROOT/proc/$HK"; sleep 0.8
ok "hotspot ended while wlan0 stayed: logged with run time, AA signal, KP's last line" "grep -q 'watch: hotspot hostapd $HK (started by KP) ENDED after .*wlan0 still-here, AA signal 1, KP last: 11-13 18:27:19' $LOGF"
kill $SVC $KM $KF 2>/dev/null; for f in "$ROOT"/proc/[0-9]*; do kill ${f##*/} 2>/dev/null; done; wait 2>/dev/null
echo "== 19 log copy waits until the stick is really mounted, checks sizes"
newcar t19; netif rtwlan1 12 usb; mkdir -p "$ROOT/data/local/tmp/usbwifi_hotspot"; echo "line from before" > "$ROOT/data/local/tmp/usbwifi_hotspot/aakeep.log"
echo "/dev/block/vold/179:1 /storage/sdcard vfat rw 0 0" > "$ROOT/proc/mounts"; runsvc >/dev/null 2>&1; LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log
ok "stick folder there but not mounted: nothing copied" "! grep -q 'logs copied' $LOGF && [ ! -d $ROOT/storage/usb0/usbwifi_hotspot_log ]"
echo "/dev/block/vold/8:1 /storage/usb0 exfat rw 0 0" >> "$ROOT/proc/mounts"; runsvc >/dev/null 2>&1
ok "mounted: copied with a file count, sizes checked, no temp files left" "grep -q 'logs copied to /storage/usb0/usbwifi_hotspot_log/up[0-9]*_1 ([0-9]* files)' $LOGF && grep -q 'line from before' $ROOT/storage/usb0/usbwifi_hotspot_log/up*_1/aakeep.log && ! ls $ROOT/storage/usb0/usbwifi_hotspot_log/.*.tmp >/dev/null 2>&1"
echo "== 20 this car: KP's waits run as a forked shell (sh) in nanosleep - ended; its permission task and log readers kept"
newcar t20; netif rtwlan1 12 usb; mkdir -p "$ROOT/data/nemesis/logs/korea.projection" "$ROOT/props" "$ROOT/data/local/tmp/korea.projection" "$ROOT/data/misc/wifi"; echo "20.0 0.0" > "$ROOT/proc/uptime"
echo 'interface=wlan0' > "$ROOT/data/misc/wifi/hostapd-kp.conf"
printf '11-14 15:20:40 시작 (CVEV): softap.conf\n11-14 15:20:41 hostapd 시작\n11-14 15:20:49 순정 카플레이 AP를 최대 90초 기다림(busybox 없는 내비)\n' > "$ROOT/data/nemesis/logs/korea.projection/ap.log"
sleep 300 & M=$!; sleep 300 & S1=$!; sleep 300 & FX=$!; sleep 300 & RD=$!; sleep 300 & PR=$!; sleep 300 & PC=$!
fake $M "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh 1
for p in $S1 $FX $RD $PR; do fake $p "sh /data/nemesis/apps/korea.projection/svc/hotspot.sh" sh $M; done
fake $PC "logcat -v threadtime" logcat $PR; echo poll_schedule_timeout > "$ROOT/proc/$PR/wchan"
echo poll_schedule_timeout > "$ROOT/proc/$S1/wchan"; echo poll_schedule_timeout > "$ROOT/proc/$FX/wchan"; echo pipe_wait > "$ROOT/proc/$RD/wchan"
echo "$FX bootid" > "$ROOT/data/local/tmp/korea.projection/fix.pid"
( cd "$A" && KR_TEST_PATH=$W/bin:$PATH USBS=/nonexistent TICK=0.2 sh svc/dongle.sh >/dev/null 2>&1 ) & SVC=$!
LOGF=$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log; sleep 1.2
ok "KP's sleeping shell ended (1 wait ended)" "! kill -0 $S1 2>/dev/null && grep -q 'kick (boot-wait): KP service $M checks now (1 waits ended)' $LOGF"
ok "permission task (fix.pid), log reader (pipe wait) and a shell with children kept" "kill -0 $FX && kill -0 $RD && kill -0 $PR"
ok "KP answers the wake-up: our watchdog leaves the hotspot to KP" "grep -q 'KP wakes up' $LOGF && [ ! -f $ROOT/hostapd.calls ]"
printf '11-14 15:21:20 시작 (CVEV): softap.conf\n' >> "$ROOT/data/nemesis/logs/korea.projection/ap.log"; rm -f "$ROOT/hostapd.calls"; echo "30.0 0.0" > "$ROOT/proc/uptime"; sleep 1.2
ok "KP taking Wi-Fi over after its wait: our watchdog holds off (no hostapd start), logged" "[ ! -f $ROOT/hostapd.calls ] && grep -q 'KP is taking Wi-Fi over' $LOGF"
printf '11-14 15:21:40 hostapd 시작\n' >> "$ROOT/data/nemesis/logs/korea.projection/ap.log"; echo "40.0 0.0" > "$ROOT/proc/uptime"; sleep 1.2
ok "after KP's own hostapd line: the watchdog works again" "[ -f $ROOT/hostapd.calls ]"
kill $SVC $M $FX $RD $PR $PC 2>/dev/null; for f in "$ROOT"/proc/[0-9]*; do kill ${f##*/} 2>/dev/null; done; wait 2>/dev/null
echo "== 21 4.9/4.10: the HMG-API mod inside (AA keep + plug-in notices): install, update, uninstall, refusals"
JW=$W/java; mkdir -p "$JW"; M=$B/hmgapi_mod
javac --release 8 -nowarn -d "$JW" "$M/src/hmgapi/mods/aakeep/Ladder.java" "$M/test/LadderTest.java" 2>&1
jout=$(java -cp "$JW" hmgapi.mods.aakeep.LadderTest 2>&1); echo "$jout" | grep -v '^PASS'
ok "AA keep recovery steps: all checks pass" "echo \"\$jout\" | grep -q 'failed 0'"
javac --release 8 -nowarn -d "$JW" -cp "$HOME/Library/Android/sdk/platforms/android-35/android.jar" "$M"/stubs/hmgapi/hook/*.java "$M/src/hmgapi/mods/aakeep/PlugQuiet.java" "$M/test/PlugQuietTest.java" 2>&1
jout=$(java -cp "$JW" hmgapi.mods.aakeep.PlugQuietTest 2>&1); echo "$jout" | grep -v '^PASS'
ok "plug-in notice decisions: all checks pass" "echo \"\$jout\" | grep -q 'failed 0'"
ok "mod package inside the dongle package" "[ -f $P/mod/package.zip ] && [ \"\$(cat $P/mod/id)\" = ev6-kr-aa-keep ]"
ok "mod ids = driver ids (17)" "[ \$(strings $P/modules/88x2bu.ko | grep -c '^alias=usb:v') = 17 ]"
printf '#!/bin/bash\n[ -f "$1" ] || exit 1; echo "$(/sbin/md5 -q "$1") $1"\n' > "$W/bin/md5"; chmod +x "$W/bin/md5"
modcar() {
  newcar $1; mkdir -p "$ROOT/system/bin" "$ROOT/system/app" "$ROOT/system/framework" "$ROOT/props"
  echo 110 > "$ROOT/props/ro.product.opt.stepofspec"
  echo gpm > "$ROOT/system/app/HKMC_GPM.odex"; echo svc > "$ROOT/system/framework/services.odex"
  { echo "$(md5 -q $ROOT/system/app/HKMC_GPM.odex) /system/app/HKMC_GPM.odex"; echo "$(md5 -q $ROOT/system/framework/services.odex) /system/framework/services.odex"; } > "$A/kr/modexpect.txt"
  cat > "$ROOT/system/bin/hmgapid" <<'X'
#!/bin/bash
D=$ROOT/data/hmgapi; echo "$*" >> "$ROOT/hmgapid.calls"
case "$1 $2" in
 "engine install") [ "$MOCK_INSTALL" = fail ] && { echo "install refused"; exit 1; }; mkdir -p $D/mods/ev6-kr-aa-keep; exit 0 ;;
 "engine apply") [ "$MOCK_APPLY" = fail ] && { echo "apply problem"; exit 1; }; echo "applied"; exit 0 ;;
 "engine remove") rm -rf $D/mods/$3; exit 0 ;;
esac
exit 0
X
  chmod +x "$ROOT/system/bin/hmgapid"
}
post() { (cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/post.sh 2>&1); }
modcar t21; out=$(post); rc=$?
ok "install: rc 0, mod installed and applied" "[ $rc = 0 ] && [ -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ] && grep -q 'engine install .*mod/package.zip --from-nemesis' $ROOT/hmgapid.calls && grep -q 'engine apply' $ROOT/hmgapid.calls"
ok "install says what it added" "echo \"\$out\" | grep -q 'plug-in notices hidden'"
mkdir -p "$ROOT/data/nemesis/apps/hmgapi.ev6-kr-aa-keep/scripts"; echo 'engine remove ev6-kr-aa-keep' > "$ROOT/data/nemesis/apps/hmgapi.ev6-kr-aa-keep/scripts/preuninstall.sh"
out=$(post)
ok "old separate package: its uninstall made harmless" "grep -q 'now part of usbwifi.hotspot' $ROOT/data/nemesis/apps/hmgapi.ev6-kr-aa-keep/scripts/preuninstall.sh && (cd $ROOT/data/nemesis/apps/hmgapi.ev6-kr-aa-keep && sh scripts/preuninstall.sh >/dev/null) && [ -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ]"
mkdir -p "$ROOT/data/local/tmp/nemesis/stage/usbwifi.hotspot"; cp "$A/NEMESIS.data" "$ROOT/data/local/tmp/nemesis/stage/usbwifi.hotspot/"
(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/preun.sh >/dev/null 2>&1)
ok "update: mod stays" "[ -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ]"
rm -rf "$ROOT/data/local/tmp/nemesis/stage"; echo x > "$ROOT/data/local/tmp/usbwifi_hotspot/plugquiet.log"
(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/preun.sh >/dev/null 2>&1); rc=$?
ok "uninstall: mod removed, its logs removed" "[ $rc = 0 ] && [ ! -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ] && grep -q 'engine remove ev6-kr-aa-keep' $ROOT/hmgapid.calls && [ ! -f $ROOT/data/local/tmp/usbwifi_hotspot/plugquiet.log ]"
modcar t22; echo changed >> "$ROOT/system/framework/services.odex"; out=$(post); rc=$?
ok "other services.odex: mod not installed, dongle still installs (rc 0), logged" "[ $rc = 0 ] && [ ! -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ] && grep -q 'services.odex md5' $ROOT/data/hmgapi/usbwifi-v4.log && grep -q 'NOT installed' $ROOT/storage/usb0/HMGAPI-LOGS/usbwifi-v4.log"
modcar t23; rm -f "$ROOT/system/bin/hmgapid"; out=$(post); rc=$?
ok "no HMG-API: dongle installs, mod warned" "[ $rc = 0 ] && echo \"\$out\" | grep -q 'NOT installed'"
modcar t24; out=$(MOCK_APPLY=fail post); rc=$?
ok "apply fails on a new install: mod taken out, dongle installs" "[ $rc = 0 ] && [ ! -d $ROOT/data/hmgapi/mods/ev6-kr-aa-keep ] && echo \"\$out\" | grep -q 'taken out again'"
modcar t25; out=$(MOCK_INSTALL=fail post); rc=$?
ok "HMG-API refuses: logged, dongle installs" "[ $rc = 0 ] && echo \"\$out\" | grep -q 'didn.t install the mod'"
echo "== 22 4.10: an Android Auto drop (aa-keep writes drop.req): the logs of that moment saved at once, newest 8 kept, copied"
printf '#!/bin/bash\necho "11-15 15:24:57.100  1000  1100 I AAProjection: GalConnectionSession : Wireless << AA Ping TimeOut!!"\necho "11-15 15:24:50.000  1000  1100 I SplitScreen: song tick"\n' > "$W/bin/logcat"
printf '#!/bin/bash\necho "<6>[  620.1] rtl88x2bu 4-1:1.0: something"\n' > "$W/bin/dmesg"; chmod +x "$W/bin/logcat" "$W/bin/dmesg"
newcar t26; netif rtwlan1 12 usb; Q=$ROOT/proc/net/rtl88x2bu/wlan0; mkdir -p "$Q"; echo "rssi:-35" > "$Q/rx_signal"; echo "sta 02:00:00:00:aa:01 tx_rate 433" > "$Q/all_sta_info"
TD=$ROOT/data/local/tmp/usbwifi_hotspot; mkdir -p "$TD"; echo "11-15 15:24:59 DROP: Android Auto ended while connected (status 6 -> 0, mode 0) after 578 s" > "$TD/drop.req"
runsvc >/dev/null 2>&1; DF=$(ls $TD/drop_*.log 2>/dev/null | head -1)
ok "drop file saved, request taken" "[ -s \"$DF\" ] && [ ! -f $TD/drop.req ] && grep -q 'drop: Android Auto ended.*saved to drop_' $TD/daemon.log"
ok "drop file: why, likely cause (Ping TimeOut picked out), Wi-Fi of the last minute, logcat, kernel" "grep -q '== Android Auto drop: 11-15 15:24:59 DROP' \"$DF\" && sed -n '/likely cause/,/Wi-Fi from/p' \"$DF\" | grep -q 'Ping TimeOut' && ! sed -n '/likely cause/,/Wi-Fi from/p' \"$DF\" | grep -q 'song tick' && grep -q 'tx_rate 433' \"$DF\" && grep -q 'rtl88x2bu 4-1' \"$DF\""
ok "no temp files left" "! ls $TD/drop_*.lc $TD/drop_*.km $TD/drop_*.raw >/dev/null 2>&1"
ok "4.11 privacy: song line left out, address shows only its last 2 bytes, filter line at the end" "! grep -q 'song tick' \"$DF\" && ! grep -q '02:00:00:00:aa:01' \"$DF\" && grep -q 'xx:xx:xx:xx:aa:01 tx_rate 433' \"$DF\" && grep -q '^== privacy filter (usbwifi.hotspot): 1 lines' \"$DF\""
for i in 1 2 3 4 5 6 7 8 9; do echo old > "$TD/drop_0101_00000$i.log"; done; echo "again" > "$TD/drop.req"
runsvc >/dev/null 2>&1; runsvc >/dev/null 2>&1
ok "newest 8 kept (oldest removed, the new ones there)" "[ \$(ls $TD/drop_*.log | wc -l) -eq 8 ] && [ ! -f $TD/drop_0101_000001.log ] && [ -f \"$DF\" ]"
ok "drop files go to the USB stick with the other logs" "ls $ROOT/storage/usb0/usbwifi_hotspot_log/up*/\$(basename \"$DF\") >/dev/null 2>&1"
ok "no request: nothing saved" "n=\$(ls $TD/drop_*.log | wc -l); runsvc >/dev/null 2>&1; [ \$(ls $TD/drop_*.log | wc -l) = \$n ]"
rm -f "$W/bin/logcat" "$W/bin/dmesg"
echo "== 23 4.11 privacy filter: USB copies and the Launch bundle carry no personal data"
newcar t23; netif rtwlan1 12 usb; TD=$ROOT/data/local/tmp/usbwifi_hotspot; mkdir -p "$TD" "$ROOT/storage/usb0"
{ echo "aa-keep: phone 0A:1B:2C:3D:12:E4 on Bluetooth"; echo "BluetoothContactsProvider: add Hong"; echo "CoNA: tel 010-1234-5678"; echo "keep: step 1 START"; } > "$TD/aakeep.log"
echo "/dev/block/vold/8:1 /storage/usb0 exfat rw 0 0" > "$ROOT/proc/mounts"; runsvc >/dev/null 2>&1; runsvc >/dev/null 2>&1
CF=$(ls $ROOT/storage/usb0/usbwifi_hotspot_log/up*/aakeep.log 2>/dev/null | head -1)
ok "USB copy: contacts and phone number lines left out, address masked, other lines kept" "[ -f \"$CF\" ] && ! grep -q -e Hong -e 010-1234 -e 0A:1B:2C:3D:12:E4 \"$CF\" && grep -q 'phone xx:xx:xx:xx:12:E4 on Bluetooth' \"$CF\" && grep -q 'keep: step 1 START' \"$CF\" && grep -q 'privacy filter.*: 2 lines' \"$CF\""
ok "USB copy logged as copied (no write problem)" "grep -q 'logs copied to /storage/usb0/usbwifi_hotspot_log/up' $TD/daemon.log && ! grep -q 'FAIL: logs copied' $TD/daemon.log"
printf '#!/bin/bash\necho "11-16 10:00:00.000 1 2 I BTA_BT_PLAYER_MANAGER: artist=A title=B"\necho "11-16 10:00:01.000 1 2 I HKMC_GPM: status 6 phone 0A:1B:2C:3D:12:E4"\n' > "$W/bin/logcat"; chmod +x "$W/bin/logcat"
out=$(cd "$A" && ROOT=$ROOT KR_TEST_PATH=$W/bin:$PATH USBS=/storage/usb0 sh bin/collect.sh "$ROOT/storage/usb0" 2>&1); LB=$(ls -d $ROOT/storage/usb0/EV6_LOG_up* 2>/dev/null | head -1)
ok "Launch bundle: logcat filtered (song gone, address masked, GPM kept)" "[ -f \"$LB/03_logcat.txt\" ] && ! grep -q artist \"$LB/03_logcat.txt\" && grep -q 'status 6 phone xx:xx:xx:xx:12:E4' \"$LB/03_logcat.txt\" && grep -q '^== privacy filter' \"$LB/01_state.txt\""
rm -f "$W/bin/logcat"; mkdir -p "$W/nokr/bin"; cp "$A/bin/collect.sh" "$W/nokr/bin/"; mkdir -p "$ROOT/storage/usb1"
(cd "$W/nokr" && ROOT=$ROOT KR_TEST_PATH=$W/bin:$PATH sh bin/collect.sh "$ROOT/storage/usb1" >/dev/null 2>&1)
ok "no filter found: nothing collected, the reason written to the stick" "[ -f $ROOT/storage/usb1/EV6_LOG_FAILED.txt ] && ! ls -d $ROOT/storage/usb1/EV6_LOG_up* >/dev/null 2>&1"
echo "== 24 4.11.1 lighter logging: Wi-Fi snapshots in memory (no files), daemon.log capped"
newcar t24; netif rtwlan1 12 usb; Q=$ROOT/proc/net/rtl88x2bu/wlan0; mkdir -p "$Q"; echo "rssi:-40" > "$Q/rx_signal"; echo "sta 02:00:00:00:bb:02 tx_rate 866" > "$Q/all_sta_info"
TD=$ROOT/data/local/tmp/usbwifi_hotspot; mkdir -p "$TD/wq"; echo old > "$TD/wq/0"; echo "11-16 DROP: test" > "$TD/drop.req"
runsvc >/dev/null 2>&1; DF=$(ls $TD/drop_*.log 2>/dev/null | head -1)
ok "Wi-Fi snapshot reaches the drop log from memory, no snapshot files, old 4.10 folder removed" "grep -q 'xx:xx:xx:xx:bb:02 tx_rate 866' \"$DF\" && [ ! -d $TD/wq ]"
export LOG_MAX=100; runsvc >/dev/null 2>&1; unset LOG_MAX
ok "daemon.log past LOG_MAX while running: earlier part kept as daemon.old.log, new daemon.log small and says so" "[ -s $TD/daemon.old.log ] && grep -q 'reached [0-9]* bytes, the earlier part kept as daemon.old.log' $TD/daemon.log && [ \$(wc -c < $TD/daemon.log) -lt 200 ]"
echo "== 25 4.12 other EV6 KR firmware: the driver loads only on its own kernel"
newcar t25; echo "Linux version 3.18.24-tcc (b@h) (gcc version 4.7 (GCC) ) #1 SMP PREEMPT Wed Jan 1 2025" > "$ROOT/proc/version"; runsvc >/dev/null 2>&1
ok "car's kernel: driver loaded as before" "[ -f $ROOT/insmod.calls ] && ! grep -q 'FAIL: this firmware' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
newcar t25b; echo "Linux version 4.14.98-tcc (b@h) (gcc version 6.3 (GCC) ) #1 SMP PREEMPT Wed Jan 1 2025" > "$ROOT/proc/version"
out=$(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/post.sh 2>&1); runsvc >/dev/null 2>&1; runsvc >/dev/null 2>&1
ok "other kernel: no insmod, no chip mark, reason logged with the kernel version" "[ ! -f $ROOT/insmod.calls ] && [ ! -f $ROOT/data/hmgapi/public/wifi-chip ] && grep -q 'FAIL: this firmware.*Kernel: Linux version 4.14.98-tcc' $ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"
ok "other kernel: install warns, status says so" "echo \"\$out\" | grep -q 'driver will NOT load' && (cd $A && KR_TEST_PATH=$W/bin:\$PATH USBS=/none sh bin/status.sh) | grep -q 'kernel is not supported'"
ok "descriptor: any EV6 KR firmware (CVEV.KOR*)" "grep -q '^os=\"CVEV.KOR[*]\"' $P/NEMESIS.data"
echo "== 26 4.13 EXPERIMENTAL RTL8851BU: loaded only for that chip, boot guard, switch-off flag"
fake8851() { mkdir -p "$ROOT/sys/bus/usb/devices/1-2"; echo 0bda > "$ROOT/sys/bus/usb/devices/1-2/idVendor"; echo b851 > "$ROOT/sys/bus/usb/devices/1-2/idProduct"; }
L26() { echo "$ROOT/data/local/tmp/usbwifi_hotspot/daemon.log"; }
newcar t26a; netif rtwlan1 12 usb; runsvc >/dev/null 2>&1
ok "no RTL8851BU plugged in: 8851bu never loaded (T3U cars unchanged)" "! grep -q 8851bu $ROOT/insmod.calls"
newcar t26b; fake8851; runsvc >/dev/null 2>&1
ok "RTL8851BU plugged in: 8851bu loaded with KR + usbfs block, guard removed, logged" "grep -q '8851bu.ko .*rtw_country_code=KR.*rtw_usbfs_block=1' $ROOT/insmod.calls && [ ! -f $ROOT/data/nemesis/usbwifi-v4.8851.loading ] && grep -q '8851: insmod 8851bu rc=0' \$(L26)"
ok "usb report names it experimental" "grep -q 'usb: 1-2 0bda:b851.*EXPERIMENTAL: RTL8851BU' \$(L26)"
ok "88x2bu still loaded as before" "grep -q '88x2bu.ko' $ROOT/insmod.calls"
newcar t26c; fake8851; echo "11-20 uptime 9s" > "$ROOT/data/nemesis/usbwifi-v4.8851.loading"; runsvc >/dev/null 2>&1
ok "guard left by an unfinished load: switched off, not loaded again, reason logged" "[ -f $ROOT/data/nemesis/usbwifi-v4.8851.off ] && ! grep -q 8851bu $ROOT/insmod.calls && grep -q 'did not finish loading last time' \$(L26)"
runsvc >/dev/null 2>&1
ok "switched off: next start says so, still not loaded" "! grep -q 8851bu $ROOT/insmod.calls && grep -q 'experimental driver is switched off' \$(L26)"
out=$(cd "$A" && KR_TEST_PATH=$W/bin:$PATH sh scripts/post.sh 2>&1)
ok "reinstall switches it on again" "[ ! -f $ROOT/data/nemesis/usbwifi-v4.8851.off ] && echo \"\$out\" | grep -q 'switched on again'"
newcar t26d; fake8851; export INSMOD8851_FAIL=1; runsvc >/dev/null 2>&1; unset INSMOD8851_FAIL
ok "8851bu insmod fails: logged, guard removed, 88x2bu side unaffected" "grep -q '8851: insmod 8851bu rc=1' \$(L26) && [ ! -f $ROOT/data/nemesis/usbwifi-v4.8851.loading ] && grep -q 'driver: insmod bundled 88x2bu rc=0' \$(L26)"
newcar t26e; fake8851; echo "Linux version 4.14.98-tcc (b@h) (gcc) #1 SMP PREEMPT x" > "$ROOT/proc/version"; runsvc >/dev/null 2>&1
ok "other kernel: 8851bu not loaded either" "[ ! -f $ROOT/insmod.calls ]"
req=$(sed -n 's/^REQUIRED_PARAMS="${REQUIRED_PARAMS:-\(.*\)}"$/\1/p' $P/source/driver8851/inner-build.sh); args=$(. $P/kr/common.sh; for a in $KO8851_ARGS; do echo "${a%%=*}"; done)
miss=; for a in $args; do case " $req " in *" $a "*) ;; *) miss="$miss $a" ;; esac; done
ok "every 8851bu insmod option is checked by the driver build (unknown options make insmod fail)" "[ -n \"$req\" ] && [ -z \"$miss\" ]"
echo "== 13 Launch with a USB stick: status + log bundle on the stick"
newcar t13; mkdir -p "$ROOT/storage/usb0"
out=$(cd "$A" && ROOT=$ROOT KR_TEST_PATH=$W/bin:$PATH USBS=/storage/usb0 sh bin/status.sh 2>&1); sleep 2
ok "status line + saving message" "echo \"\$out\" | grep -q 'USB Wi-Fi v4' && echo \"\$out\" | grep -q 'EV6_LOG'"
ok "bundle folder with the state file on the stick" "ls -d $ROOT/storage/usb0/EV6_LOG_up* >/dev/null 2>&1 && [ -f \$(ls -d $ROOT/storage/usb0/EV6_LOG_up* | head -1)/01_state.txt ]"
echo; echo "passed $pass, failed $fail"; [ $fail = 0 ]
