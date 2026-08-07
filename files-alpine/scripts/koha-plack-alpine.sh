#!/bin/sh
# /usr/local/bin/koha-plack - Alpine-native fully functional
# Replaces Debian koha-plack which requires apache2ctl, xmlstarlet, daemon(), start-stop-daemon --status
set -eu

INSTANCE="${2:-${KOHA_INSTANCE:-kohadev}}"
ACTION="${1:-status}"

BASE_DIR="/kohadevbox/koha"
ETC_DIR="/etc/koha/sites/${INSTANCE}"
CONF="${ETC_DIR}/koha-conf.xml"
[ -f "$CONF" ] || CONF="/kohadevbox/koha/etc/koha-conf.xml"
[ -f "$CONF" ] || CONF="/etc/koha/koha-conf.xml"

RUN_DIR="/var/run/koha/${INSTANCE}"
LOG_DIR="/var/log/koha/${INSTANCE}"
PID_OPAC="${RUN_DIR}/plack-opac.pid"
PID_INTRA="${RUN_DIR}/plack-intra.pid"
PID_API="${RUN_DIR}/plack-api.pid"

mkdir -p "${RUN_DIR}" "${LOG_DIR}" "${ETC_DIR}"
chown kohadev:kohadev "${RUN_DIR}" "${LOG_DIR}" 2>/dev/null || true

# Find PSGI files (Koha 24.11 layout)
find_psgi() {
    local type="$1"
    # Try common locations
    for p in \
        "${BASE_DIR}/$type/$type.psgi" \
        "${BASE_DIR}/opac/opac.psgi" \
        "${BASE_DIR}/intranet/intranet.psgi" \
        "${BASE_DIR}/api/v1/app.psgi" \
        "${BASE_DIR}/api/v1/app.pl" \
        "${BASE_DIR}/plack/$type.psgi" \
        "${BASE_DIR}/$type.psgi" \
        "${BASE_DIR}/etc/$type.psgi" \
        "/usr/share/koha/$type/$type.psgi"; do
        if [ -f "$p" ]; then echo "$p"; return 0; fi
    done
    # fallback find
    find "${BASE_DIR}" -maxdepth 4 -name "*${type}*.psgi" 2>/dev/null | head -1
}

PSGI_OPAC=$(find_psgi opac)
PSGI_INTRA=$(find_psgi intranet)
[ -n "$PSGI_INTRA" ] || PSGI_INTRA=$(find_psgi staff)
PSGI_API=$(find_psgi api)
[ -n "$PSGI_API" ] || PSGI_API=$(find "${BASE_DIR}" -name "app.psgi" -o -name "app.pl" | head -1)

# If still not found, use generic plack.psgi that Koha provides
if [ -z "$PSGI_OPAC" ] && [ -f "${BASE_DIR}/opac/psgi/opac.psgi" ]; then PSGI_OPAC="${BASE_DIR}/opac/psgi/opac.psgi"; fi
if [ -z "$PSGI_OPAC" ] && [ -f "${BASE_DIR}/plack.psgi" ]; then PSGI_OPAC="${BASE_DIR}/plack.psgi"; fi
if [ -z "$PSGI_INTRA" ]; then PSGI_INTRA="$PSGI_OPAC"; fi

export PERL5LIB="/opt/koha-perl/lib/perl5:${BASE_DIR}/lib:${BASE_DIR}"
export KOHA_CONF="${CONF}"
export KOHA_HOME="${BASE_DIR}"

is_running() {
    local pidfile="$1"
    [ -f "$pidfile" ] || return 1
    local pid=$(cat "$pidfile" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null
}

start_one() {
    local name="$1"
    local port="$2"
    local psgi="$3"
    local pidfile="$4"
    if [ ! -f "$psgi" ]; then
        echo "[koha-plack-alpine] SKIP $name: PSGI not found ($psgi)" >&2
        return 0
    fi
    if is_running "$pidfile"; then
        echo "[koha-plack-alpine] $name already running ($(cat $pidfile))"
        return 0
    fi
    echo "[koha-plack-alpine] Starting $name on :$port with $psgi"
    # Use plackup with Starman if available
    local server="Starman"
    /opt/koha-perl/bin/plackup --version 2>&1 | grep -q Starman || server="Standalone"
    # Try starman via plackup
    nohup /opt/koha-perl/bin/plackup -E deployment -s "$server" --workers 2 --port "$port" --pid "$pidfile" --access-log "${LOG_DIR}/plack-${name}-access.log" --error-log "${LOG_DIR}/plack-${name}-error.log" "$psgi" >> "${LOG_DIR}/plack.log" 2>&1 &
    sleep 2
    if is_running "$pidfile"; then
        echo "[koha-plack-alpine] $name started pid $(cat $pidfile)"
    else
        echo "[koha-plack-alpine] WARNING $name failed to start, see ${LOG_DIR}/plack-${name}-error.log" >&2
        cat "${LOG_DIR}/plack-${name}-error.log" 2>/dev/null | tail -30 >&2 || true
    fi
}

stop_one() {
    local pidfile="$1"
    local name="$2"
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$pid" ]; then
            echo "[koha-plack-alpine] Stopping $name pid $pid"
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$pidfile"
    fi
}

case "$ACTION" in
    --enable|--enable-opac|--enable-intranet)
        # Create enable flag and ensure koha-conf.xml has plack enabled
        touch "${ETC_DIR}/plack_enabled"
        if command -v xmlstarlet >/dev/null 2>&1 && [ -f "$CONF" ]; then
            xmlstarlet ed -L -u "//config/plack/enable" -v 1 "$CONF" 2>/dev/null || true
            xmlstarlet ed -L -u "//config/plack/opac_port" -v 5000 "$CONF" 2>/dev/null || true
            xmlstarlet ed -L -u "//config/plack/intra_port" -v 5001 "$CONF" 2>/dev/null || true
        fi
        echo "[koha-plack-alpine] Enabled plack for $INSTANCE"
        ;;
    --disable)
        rm -f "${ETC_DIR}/plack_enabled"
        echo "[koha-plack-alpine] Disabled plack for $INSTANCE"
        ;;
    --start|--restart)
        if [ "$ACTION" = "--restart" ]; then
            stop_one "$PID_OPAC" "opac"
            stop_one "$PID_INTRA" "intra"
            stop_one "$PID_API" "api"
            sleep 1
        fi
        # Determine ports from env or defaults
        OPAC_PORT=${KOHA_OPAC_PLACK_PORT:-5000}
        INTRA_PORT=${KOHA_INTRANET_PLACK_PORT:-5001}
        # If koha-conf has ports, try to extract
        if [ -f "$CONF" ] && command -v xmlstarlet >/dev/null 2>&1; then
            OPAC_PORT=$(xmlstarlet sel -t -v "//config/plack/opac_port" "$CONF" 2>/dev/null || echo "$OPAC_PORT")
            INTRA_PORT=$(xmlstarlet sel -t -v "//config/plack/intra_port" "$CONF" 2>/dev/null || echo "$INTRA_PORT")
        fi
        start_one "opac" "$OPAC_PORT" "$PSGI_OPAC" "$PID_OPAC"
        # Intranet - if same psgi, use different port but same file with different env
        if [ "$PSGI_INTRA" != "$PSGI_OPAC" ] || [ "$OPAC_PORT" != "$INTRA_PORT" ]; then
            # If same file, still start second instance on different port
            start_one "intranet" "$INTRA_PORT" "$PSGI_INTRA" "$PID_INTRA"
        fi
        # API on 5002 if exists and different
        if [ -n "$PSGI_API" ] && [ "$PSGI_API" != "$PSGI_OPAC" ] && [ "$PSGI_API" != "$PSGI_INTRA" ]; then
            start_one "api" "5002" "$PSGI_API" "$PID_API"
        fi
        ;;
    --stop)
        stop_one "$PID_OPAC" "opac"
        stop_one "$PID_INTRA" "intranet"
        stop_one "$PID_API" "api"
        pkill -f "plackup.*$INSTANCE" 2>/dev/null || true
        ;;
    --status|--status-opac|--status-intranet)
        ok=0
        if is_running "$PID_OPAC"; then echo "[koha-plack-alpine] OPAC running pid $(cat $PID_OPAC) port 5000"; else echo "[koha-plack-alpine] OPAC not running"; ok=1; fi
        if is_running "$PID_INTRA"; then echo "[koha-plack-alpine] Intranet running pid $(cat $PID_INTRA) port 5001"; else echo "[koha-plack-alpine] Intranet not running (may share OPAC)"; fi
        # Check listening
        ss -tln 2>/dev/null | grep -E "5000|5001" || netstat -tln 2>/dev/null | grep -E "5000|5001" || true
        exit $ok
        ;;
    *)
        echo "Usage: $0 {--enable|--disable|--start|--stop|--restart|--status} instance"
        exit 1
        ;;
esac
