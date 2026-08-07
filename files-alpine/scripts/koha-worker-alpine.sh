#!/bin/sh
# Alpine-native koha-worker
set -eu
ACTION="${1:-status}"
INSTANCE="${2:-kohadev}"
RUN_DIR="/var/run/koha/${INSTANCE}"
LOG_DIR="/var/log/koha/${INSTANCE}"
PIDFILE="${RUN_DIR}/worker.pid"
mkdir -p "${RUN_DIR}" "${LOG_DIR}"
export PERL5LIB="/opt/koha-perl/lib/perl5:/kohadevbox/koha/lib:/kohadevbox/koha"
export KOHA_CONF="/etc/koha/sites/${INSTANCE}/koha-conf.xml"
[ -f "$KOHA_CONF" ] || export KOHA_CONF="/kohadevbox/koha/etc/koha-conf.xml"

is_running() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null || true)
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null
}

case "$ACTION" in
  --start|--restart)
    if is_running; then echo "[worker] already running $(cat $PIDFILE)"; exit 0; fi
    echo "[worker] Starting worker for $INSTANCE"
    # Koha worker script is misc/worker/worker.pl or bin/worker
    WORKER=""
    for w in "/kohadevbox/koha/misc/worker/worker.pl" "/kohadevbox/koha/bin/koha-worker.pl" "/kohadevbox/koha/misc/worker.pl"; do
      [ -f "$w" ] && WORKER="$w" && break
    done
    if [ -z "$WORKER" ]; then
      echo "[worker] No worker script found, skipping" >&2
      touch "$PIDFILE"
      echo $$ > "$PIDFILE"
      exit 0
    fi
    nohup perl "$WORKER" --daemon --pidfile "$PIDFILE" >> "${LOG_DIR}/worker.log" 2>&1 &
    sleep 2
    ;;
  --stop)
    if [ -f "$PIDFILE" ]; then kill $(cat "$PIDFILE") 2>/dev/null || true; rm -f "$PIDFILE"; fi
    pkill -f "worker.*$INSTANCE" 2>/dev/null || true
    ;;
  --status)
    if is_running; then echo "[worker] running pid $(cat $PIDFILE)"; exit 0; else echo "[worker] not running"; exit 1; fi
    ;;
  --enable|--disable) echo "[worker] $ACTION $INSTANCE (noop on Alpine)";;
  *) echo "Usage: $0 {--start|--stop|--status}"; exit 1;;
esac
