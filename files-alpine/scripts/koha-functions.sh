#!/bin/sh
# Alpine koha-functions override.
# Loads upstream helpers, then replaces daemon-dependent running checks.

set -eu

if [ -r /usr/share/koha/bin/koha-functions.sh ]; then
    . /usr/share/koha/bin/koha-functions.sh
else
    echo "[koha-functions-alpine] ERROR: /usr/share/koha/bin/koha-functions.sh not present" >&2
    exit 1
fi

_pid_is_live() {
    local pidfile="$1"

    [ -s "$pidfile" ] || return 1
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac

    kill -0 "$pid" 2>/dev/null
}

_running_by_pid_candidates() {
    local instancename="$1"
    local role="$2"

    for pidfile in \
        "/var/run/koha/${instancename}/${role}.pid" \
        "/var/run/koha/${instancename}/${instancename}-koha-${role}.pid"; do
        if _pid_is_live "$pidfile"; then
            return 0
        fi
    done

    return 1
}

_supports_ssd_test() {
    start-stop-daemon --help 2>&1 | grep -Eq -- '--test|-t'
}

is_sip_running()
{
    local instancename=$1

    if _running_by_pid_candidates "$instancename" sip; then
        return 0
    fi

    return 1
}

is_zebra_running()
{
    local instancename=$1

    if _running_by_pid_candidates "$instancename" zebra; then
        return 0
    fi

    return 1
}

is_indexer_running()
{
    local instancename=$1

    if _running_by_pid_candidates "$instancename" indexer; then
        return 0
    fi

    return 1
}

is_es_indexer_running()
{
    local instancename=$1

    if _running_by_pid_candidates "$instancename" es-indexer; then
        return 0
    fi

    return 1
}

is_worker_running()
{
    local instancename=$1
    local queue=$2
    local name pidfile

    name=$(get_worker_name "$instancename" "$queue")
    pidfile="/var/run/koha/${instancename}/${name}.pid"

    if _pid_is_live "$pidfile"; then
        return 0
    fi

    return 1
}

is_plack_running()
{
    local instancename=$1
    local pidfile="/var/run/koha/${instancename}/plack.pid"

    if command -v start-stop-daemon >/dev/null 2>&1 && _supports_ssd_test; then
        if start-stop-daemon --stop --test --pidfile "$pidfile" --user="$instancename-koha" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if _pid_is_live "$pidfile"; then
        return 0
    fi

    return 1
}

is_z3950_running()
{
    local instancename=$1
    local pidfile="/var/run/koha/${instancename}/z3950-responder.pid"

    if command -v start-stop-daemon >/dev/null 2>&1 && _supports_ssd_test; then
        if start-stop-daemon --stop --test --pidfile "$pidfile" --user="$instancename-koha" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if _pid_is_live "$pidfile"; then
        return 0
    fi

    return 1
}
