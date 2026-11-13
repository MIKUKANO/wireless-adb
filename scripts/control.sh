#!/system/bin/sh
MODDIR=$(CDPATH='' cd -- "${0%/*}/.." && pwd) || exit 1
. "$MODDIR/scripts/common.sh"
[ "$(id -u)" = 0 ] || { echo '需要 root 管理器授权' >&2; exit 1; }
init_data || exit 1

status() {
    load_config || { echo '配置损坏，请重新保存' >&2; return 1; }
    address=$(wifi_ip)
    actual=$PORT
    [ "$MODE" != tls ] || actual=$(getprop service.adb.tls.port)
    active=off
    if [ "$ENABLED" = on ] && [ -n "$address" ] && [ "$(getprop init.svc.adbd)" = running ] &&
       valid_port "$actual" && listening "$actual"; then
        if [ "$MODE" = tls ] && [ "$(settings get global adb_wifi_enabled)" = 1 ]; then active=on; fi
        if [ "$MODE" = tcp ] && listening "$PORT" "$address"; then active=on; actual=$PORT; fi
    fi
    printf 'enabled=%s\nport=%s\nmode=%s\nnotify=%s\n' "$ENABLED" "$PORT" "$MODE" "$NOTIFY"
    printf 'active=%s\nip=%s\nactual_port=%s\nauth=%s\nreason=%s\n' \
        "$active" "$address" "$actual" "$(getprop ro.adb.secure)" "$(cat "$DATA/reason" 2>/dev/null)"
    printf 'notification=%s\n' "$(cat "$DATA/notification" 2>/dev/null)"
}

restore() {
    [ -f "$STATE" ] || return 0
    tcp='' listen='' tls=0
    while IFS='=' read -r key value; do
        case "$key" in tcp) tcp=$value;; listen) listen=$value;; tls) tls=$value;; esac
    done < "$STATE"
    case "$tls" in 0|1) ;; *) tls=0;; esac
    setprop service.adb.tcp.port "$tcp" && setprop service.adb.listen_addrs "$listen" &&
        settings put global adb_wifi_enabled "$tls" && stop adbd && start adbd || return 1
    rm -f "$STATE"
    event restored
}

case "${1:-}" in
    status) [ "$#" -eq 1 ] && status;;
    save)
        [ "$#" -eq 5 ] || exit 2
        ENABLED=$2 PORT=$3 MODE=$4 NOTIFY=$5
        validate || { echo '无效配置：检查端口与选项' >&2; exit 2; }
        lock && save_config;;
    apply)
        [ "$#" -eq 1 ] || exit 2
        lock || exit 1
        [ ! -f "$MODDIR/remove" ] && [ ! -f "$MODDIR/disable" ] || exit 1
        reconcile || exit 1
        load_config && notify_entry
        status;;
    pause)
        [ "$#" -eq 1 ] || exit 2
        lock || exit 1
        if ! load_config; then PORT=5555 MODE=tcp NOTIFY=on; fi
        capture_original || exit 1
        ENABLED=off
        save_config && reconcile && status;;
    restore)
        [ "$#" -eq 1 ] || exit 2
        lock && restore;;
    settings)
        [ "$#" -eq 1 ] || exit 2
        am start -a android.settings.WIRELESS_DEBUGGING_SETTINGS >/dev/null 2>&1 ||
            am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS;;
    doctor)
        [ "$#" -eq 1 ] || exit 2
        status || exit 1
        printf '\n--- 属性与监听（不包含密钥）---\n'
        printf 'adbd=%s\nlisten_addrs=%s\nAndroid SDK=%s\n' "$(getprop init.svc.adbd)" \
            "$(getprop service.adb.listen_addrs)" "$(getprop ro.build.version.sdk)"
        printf '\n--- 最近事件（已省略地址）---\n'
        tail -n 40 "$LOG" 2>/dev/null;;
    *) echo '用法: control.sh status|save|apply|pause|settings|doctor|restore' >&2; exit 2;;
esac
