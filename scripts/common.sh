#!/system/bin/sh
# Configuration is data, never sourced or evaluated.
PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/magisk:$PATH
export PATH
umask 077
DATA=/data/adb/wadb
CONFIG=/data/adb/wadb_config
STATE="$DATA/original"
LOG="$DATA/events.log"

init_data() {
    [ ! -L "$DATA" ] && [ ! -L "$CONFIG" ] || return 1
    mkdir -p "$DATA" && chmod 700 "$DATA"
}

valid_port() {
    case "$1" in ''|*[!0-9]*|0*) return 1;; esac
    [ ${#1} -le 5 ] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}

validate() {
    case "$ENABLED:$NOTIFY" in on:on|on:off|off:on|off:off) ;; *) return 1;; esac
    case "$MODE" in tcp|tls) ;; *) return 1;; esac
    valid_port "$PORT"
}

load_config() {
    ENABLED=off PORT=5555 MODE=tcp NOTIFY=on
    if [ -f "$CONFIG" ]; then
        [ "$(wc -c < "$CONFIG")" -le 2048 ] || return 1
        while IFS='=' read -r key value || [ -n "$key" ]; do
            case "$key" in
                enabled) ENABLED=$value;; port) PORT=$value;; mode) MODE=$value;;
                notify) NOTIFY=$value;;
                debug_menu|'') ;; *) return 1;;
            esac
        done < "$CONFIG"
    fi
    validate
}

save_config() {
    validate || return 1
    tmp=$(mktemp "${CONFIG%/*}/.wadb_config.XXXXXX") || return 1
    printf 'enabled=%s\nport=%s\nmode=%s\nnotify=%s\n' \
        "$ENABLED" "$PORT" "$MODE" "$NOTIFY" > "$tmp" &&
        chmod 600 "$tmp" && mv -f "$tmp" "$CONFIG"
    rc=$?
    [ "$rc" -eq 0 ] || rm -f "$tmp"
    return "$rc"
}

lock() {
    if ! mkdir "$DATA/control.lock" 2>/dev/null; then
        pid=$(cat "$DATA/control.lock/pid" 2>/dev/null)
        case "$pid" in ''|*[!0-9]*) echo '操作正在进行，请稍后重试' >&2; return 1;; esac
        if kill -0 "$pid" 2>/dev/null; then echo '操作正在进行，请稍后重试' >&2; return 1; fi
        rm -f "$DATA/control.lock/pid"
        rmdir "$DATA/control.lock" 2>/dev/null && mkdir "$DATA/control.lock" || return 1
    fi
    echo $$ > "$DATA/control.lock/pid"
    trap 'rm -f "$DATA/control.lock/pid"; rmdir "$DATA/control.lock" 2>/dev/null' EXIT
    trap 'exit 1' HUP INT TERM
}

event() {
    previous=$(cat "$DATA/reason" 2>/dev/null || :)
    [ "$previous" = "$1" ] && return 0
    tmp=$(mktemp "$DATA/.reason.XXXXXX") || return 1
    printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$DATA/reason" || return 1
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 16384 ]; then
        tail -n 60 "$LOG" > "$DATA/.events.tmp" && mv -f "$DATA/.events.tmp" "$LOG"
    fi
    # No IP addresses, keys, serials or hostnames in the event log.
    printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$1" >> "$LOG"
}

wifi_ip() {
    iface=$(getprop wifi.interface)
    [ -n "$iface" ] || iface=wlan0
    case "$iface" in *[!a-zA-Z0-9_.-]*) return 1;; esac
    ip -o -4 addr show dev "$iface" scope global 2>/dev/null |
        awk '{split($4,a,"/"); print a[1]; exit}'
}

listening() {
    valid_port "$1" || return 1
    ss -lnt 2>/dev/null | awk -v p=":$1" -v host="${2:-}" '
        /LISTEN/ { for(i=1;i<=NF;i++) if ((host == "" && $i ~ (p "$")) || (host != "" && $i == host p)) found=1 }
        END { exit !found }'
}

remote_listener() {
    valid_port "$1" || return 1
    ss -lnt 2>/dev/null | awk -v p=":$1" '
        /LISTEN/ { for(i=1;i<=NF;i++) if ($i ~ (p "$") && $i !~ /^127\./ && $i !~ /^\[?::1\]?:/) found=1 }
        END { exit !found }'
}

capture_original() {
    [ -f "$STATE" ] && return 0
    tmp=$(mktemp "$DATA/.original.XXXXXX") || return 1
    printf 'tcp=%s\nlisten=%s\ntls=%s\n' "$(getprop service.adb.tcp.port)" \
        "$(getprop service.adb.listen_addrs)" "$(settings get global adb_wifi_enabled)" > "$tmp" &&
        mv -f "$tmp" "$STATE"
}

restart_adbd() {
    stop adbd && start adbd || return 1
    sleep 1
}

close_tcp() {
    # -1 alone can still trigger the default TCP port without USB on some builds.
    old_port=$(getprop service.adb.tcp.port)
    if [ "$(getprop service.adb.listen_addrs)" != 'tcp:127.0.0.1:5555' ] ||
       [ "$(getprop service.adb.tcp.port)" != '-1' ] || ! listening 5555 127.0.0.1; then
        setprop service.adb.tcp.port -1 &&
            setprop service.adb.listen_addrs tcp:127.0.0.1:5555 && restart_adbd || return 1
    fi
    # Refuse an OEM daemon which ignores listen_addrs. Never label a wildcard socket closed.
    if remote_listener 5555 || remote_listener "$PORT" || remote_listener "$old_port"; then
        stop adbd
        event binding_unsupported
        return 1
    fi
}

notify_entry() {
    tmp=$(mktemp "$DATA/.notification.XXXXXX") || return 1
    if [ "$NOTIFY" != on ]; then
        printf 'off\n' > "$tmp"
        mv -f "$tmp" "$DATA/notification"
        return 0
    fi
    component=$(cmd package resolve-activity --brief --user 0 -a android.intent.action.VIEW \
        -d 'ksu://webui?id=wireless-adb' 2>/dev/null | tail -n 1)
    case "$component" in
        me.weishu.kernelsu/*|com.sukisu.ultra/*|com.rifsxd.ksunext/*)
            if cmd notification post -t '无线 ADB · 管理入口' \
                -c activity -a android.intent.action.VIEW -n "$component" \
                'ksu://webui?id=wireless-adb' wadb '点击管理连接与授权；地址仅在管理页显示。' >/dev/null 2>&1; then
                printf 'requested\n' > "$tmp"
            else printf 'failed\n' > "$tmp"; fi;;
        *) printf 'unsupported\n' > "$tmp";;
    esac
    mv -f "$tmp" "$DATA/notification"
}

reconcile() {
    if ! load_config; then
        if [ -f "$STATE" ]; then
            close_tcp
            settings put global adb_wifi_enabled 0
        fi
        event invalid_config
        return 1
    fi
    if [ "$ENABLED" != on ]; then
        if [ -f "$STATE" ]; then
            close_tcp || { event close_failed; return 1; }
            [ "$(settings get global adb_wifi_enabled)" = 0 ] || settings put global adb_wifi_enabled 0 || return 1
        fi
        event disabled
        return 0
    fi
    capture_original || return 1
    if [ "$(getprop ro.adb.secure)" != 1 ]; then
        close_tcp
        settings put global adb_wifi_enabled 0
        event auth_unverified
        return 1
    fi
    address=$(wifi_ip)
    if [ -z "$address" ]; then
        close_tcp || { event close_failed; return 1; }
        [ "$(settings get global adb_wifi_enabled)" = 0 ] || settings put global adb_wifi_enabled 0 || return 1
        event waiting_wifi
        return 0
    fi
    if [ "$MODE" = tls ]; then
        close_tcp || { event close_failed; return 1; }
        [ "$(settings get global adb_wifi_enabled)" = 1 ] || settings put global adb_wifi_enabled 1 || return 1
        tlsport=$(getprop service.adb.tls.port)
        if valid_port "$tlsport" && listening "$tlsport"; then event active_tls; else event waiting_tls; fi
    else
        [ "$(settings get global adb_wifi_enabled)" = 0 ] || settings put global adb_wifi_enabled 0 || return 1
        target="tcp:$address:$PORT"
        # A property changed by the OS is not by itself grounds to disrupt a live session.
        if listening "$PORT" "$address" && [ "$(getprop init.svc.adbd)" = running ]; then
            event active_tcp
            return 0
        fi
        if [ "$(getprop service.adb.listen_addrs)" != "$target" ] ||
           [ "$(getprop service.adb.tcp.port)" != "$PORT" ] ||
           [ "$(getprop init.svc.adbd)" != running ] || ! listening "$PORT" "$address"; then
            setprop service.adb.listen_addrs "$target" && setprop service.adb.tcp.port "$PORT" &&
                restart_adbd || { event restart_failed; return 1; }
        fi
        if listening "$PORT" "$address"; then
            event active_tcp
        else
            close_tcp || return 1
            event binding_unsupported
            return 1
        fi
    fi
}
