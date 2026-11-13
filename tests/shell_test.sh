#!/bin/sh
# Behavioral tests use command doubles, never Android system services.
set -eu
ROOT=$(CDPATH='' cd -- "${0%/*}/.." && pwd)
. "$ROOT/scripts/common.sh"
SANDBOX=$(mktemp -d)
DATA="$SANDBOX/wadb"
CONFIG="$SANDBOX/config"
STATE="$DATA/original"
LOG="$DATA/events.log"
mkdir -p "$DATA"
# Keep small test fixtures for inspection; caller owns temporary directory cleanup.
echo "test fixtures: $SANDBOX"
TCP=-1 ADDRS='' TLS=0 AUTH=1 WIFI=on RUNNING=running STARTS=0 NOW=1000
SOCKETS="$SANDBOX/sockets"
: > "$SOCKETS"
getprop() {
    case "$1" in
        wifi.interface) echo wlan0;; ro.adb.secure) echo "$AUTH";;
        service.adb.tcp.port) echo "$TCP";; service.adb.listen_addrs) echo "$ADDRS";;
        service.adb.tls.port) [ "$TLS" = 1 ] && echo 37001 || echo -1;;
        init.svc.adbd) echo "$RUNNING";;
    esac
}
setprop() {
    case "$1" in service.adb.tcp.port) TCP=$2;; service.adb.listen_addrs) ADDRS=$2;; *) return 1;; esac
}
settings() {
    if [ "$1" = get ]; then echo "$TLS"; else TLS=$4; fi
}
ip() {
    [ "$WIFI" = on ] && echo '3: wlan0 inet 192.168.1.8/24 scope global wlan0' || return 0
}
ss() { cat "$SOCKETS"; }
stop() { RUNNING=stopped; : > "$SOCKETS"; }
start() {
    STARTS=$((STARTS + 1)); RUNNING=running
    echo "LISTEN 0 4 ${ADDRS#tcp:} *:*" > "$SOCKETS"
}
sleep() { :; }
date() { if [ "$1" = +%s ]; then echo "$NOW"; else command date "$@"; fi; }
ok() { printf 'PASS %s\n' "$1"; }

load_config
[ "$ENABLED" = off ]
ok 'fresh installs are opt-in without background polling'
for port in 1024 5555 65535; do valid_port "$port"; done
for port in 0 1023 65536 05555 '5555;id' '1e4' -1; do
    if valid_port "$port"; then echo "unexpected valid port $port"; exit 1; fi
done
ok 'shell validation rejects malformed ports'
ENABLED=on
save_config
[ "$(wc -l < "$CONFIG")" -eq 4 ]
ok 'atomic save writes real newlines'
reconcile
[ "$TCP:$ADDRS:$STARTS" = '5555:tcp:192.168.1.8:5555:1' ]
grep -q active_tcp "$DATA/reason"
ok 'TCP binds only the current Wi-Fi IPv4 address'
reconcile
[ "$STARTS" -eq 1 ]
ok 'healthy sessions are not periodically restarted'
TCP=-1
reconcile
[ "$STARTS" -eq 1 ]
ok 'changed properties alone do not disrupt a healthy listener'
WIFI=off
reconcile
[ "$ADDRS:$TLS" = 'tcp:127.0.0.1:5555:0' ]
grep -q waiting_wifi "$DATA/reason"
ok 'manual apply after Wi-Fi loss closes the remote TCP binding'
WIFI=on NOW=1040
reconcile
grep -q active_tcp "$DATA/reason"
ok 'manual apply after Wi-Fi return restores service'
AUTH=0
if reconcile; then echo 'unsafe auth accepted'; exit 1; fi
[ "$ADDRS" = tcp:127.0.0.1:5555 ]
ok 'unverified authentication fails closed'
AUTH=1
printf 'enabled=on\nport=5555;touch /tmp/wadb-injected\n' > "$CONFIG"
if reconcile; then echo 'injected config accepted'; exit 1; fi
grep -q invalid_config "$DATA/reason"
ok 'malicious configuration is parsed as data and rejected'
ENABLED=on PORT=5555 MODE=tcp NOTIFY=off
save_config
NOW=1100
reconcile
ENABLED=off
save_config
reconcile
grep -q disabled "$DATA/reason"
[ "$ADDRS" = tcp:127.0.0.1:5555 ]
ok 'manual switch-off is honored even immediately after a restart'
ENABLED=on MODE=tls NOW=1200
save_config
echo 'LISTEN 0 4 *:37001 *:*' >> "$SOCKETS"
reconcile
[ "$TLS" = 1 ]
ok 'native TLS is requested through the system setting'
printf 'enabled=on\nport=5555' > "$CONFIG"
load_config
[ "$PORT" = 5555 ]
ok 'configuration without a trailing newline still loads'
NOTIFY=off
notify_entry
[ "$(cat "$DATA/notification")" = off ]
ok 'disabled notification is explicitly recorded'
NOTIFY=on
cmd() { echo 'No activity found'; }
notify_entry
[ "$(cat "$DATA/notification")" = unsupported ]
ok 'unknown manager is not guessed or silently reported as supported'
cmd() {
    if [ "$1" = package ]; then echo 'com.sukisu.ultra/.ui.MainActivity';
    else printf '%s\n' "$@" > "$SANDBOX/notification-args"; fi
}
notify_entry
[ "$(cat "$DATA/notification")" = requested ]
[ "$(tail -n 3 "$SANDBOX/notification-args" | head -n 1)" = 'ksu://webui?id=wireless-adb' ]
[ "$(tail -n 2 "$SANDBOX/notification-args" | head -n 1)" = wadb ]
ok 'notification intent consumes its URI before the notification tag'
cmd() { if [ "$1" = package ]; then echo 'com.sukisu.ultra/.ui.MainActivity'; else return 1; fi; }
notify_entry
[ "$(cat "$DATA/notification")" = failed ]
ok 'notification posting failure is recorded without pretending success'
# Model an OEM daemon that ignores service.adb.listen_addrs and binds a wildcard.
start() {
    RUNNING=running
    echo 'LISTEN 0 4 *:5555 *:*' > "$SOCKETS"
}
stop adbd
if reconcile; then echo 'unsupported wildcard binding accepted'; exit 1; fi
[ "$RUNNING" = stopped ]
grep -q binding_unsupported "$DATA/reason"
ok 'unsupported OEM binding fails closed instead of exposing a wildcard listener'
echo 'Shell behavioral tests passed (Android commands mocked)'
