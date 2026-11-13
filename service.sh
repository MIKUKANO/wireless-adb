#!/system/bin/sh
MODDIR=${0%/*}
# One-shot boot task only. No daemon, interval, watchdog or network polling.
tries=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 150 ] || exit 1
    sleep 2
done
[ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || exit 0
/system/bin/sh "$MODDIR/scripts/control.sh" apply
