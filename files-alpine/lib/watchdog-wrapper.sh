#!/bin/bash
# watchdog-wrapper.sh - keeps container alive and restarts plack/worker
INSTANCE="${1:-kohadev}"
INTERVAL="${2:-30}"
echo "[watchdog] Service watchdog started (instance=${INSTANCE}, plack=yes, worker=yes, interval=${INTERVAL}s)"

trap 'echo "[watchdog] Shutdown signal received; stopping services..."; koha-plack --stop '"${INSTANCE}"' 2>/dev/null || true; koha-worker --stop '"${INSTANCE}"' 2>/dev/null || true; httpd -k stop 2>/dev/null || true; exit 0' TERM INT

while true; do
  if command -v koha-plack >/dev/null 2>&1; then
    koha-plack --status "${INSTANCE}" >/dev/null 2>&1 || { echo "[watchdog] koha-plack is down; restarting..."; koha-plack --start "${INSTANCE}" 2>/dev/null || true; }
  fi
  if command -v koha-worker >/dev/null 2>&1; then
    koha-worker --status "${INSTANCE}" >/dev/null 2>&1 || { echo "[watchdog] koha-worker is down; restarting..."; koha-worker --start "${INSTANCE}" 2>/dev/null || true; }
  fi
  # Also ensure apache still up
  pgrep httpd >/dev/null 2>&1 || { echo "[watchdog] apache is down; restarting..."; httpd -k start 2>/dev/null || true; }
  sleep "${INTERVAL}"
done
